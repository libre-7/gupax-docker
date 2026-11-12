# =============================================================================
# Gupax-docker — Dockerfile
# Gupax GUI for P2Pool + XMRig Monero mining
# Self-contained with noVNC — access via web browser at http://localhost:6080
#
# Standalone approach — only Gupax GUI is bundled.
# P2Pool, XMRig, monerod, and xmrig-proxy are downloaded at runtime by Gupax
# and persisted in /home/miner/.local/share/gupax via the gupax-data volume.
# =============================================================================

# Ubuntu 26.04 LTS ("resolute"). Migrated from 22.04, whose standard support
# ends April 2027 — see issue #84.
#
# Requires `libasound2t64` rather than `libasound2`: Ubuntu completed the
# 64-bit-time_t transition in 24.04, and there is NO package literally named
# `libasound2` in 24.04 or later. `libasound2t64` declares
# `Provides: libasound2`, so the virtual dependency is still satisfied and
# sound-using code keeps linking `libasound.so.2` unchanged.
#
# NOTE: Gupax's own binary (v2.0.1, ELF64 PIE) contains zero references to
# libasound or libpulse, so these two packages may be removable outright.
# They are kept here because GTK/zenity can pull audio transitively; removing
# them is tracked separately and should not be conflated with this bump.
FROM ubuntu:26.04@sha256:f144425ff09be612d6d9ad965196e9cdc23dae1f42110a8a11a3e9a8198759f7

# Use bash with pipefail for all RUN commands so that failures in piped
# commands are not silently ignored (e.g., grep | awk producing empty output).
# The default /bin/sh (dash) does not support pipefail.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Prevent interactive tzdata prompt from blocking the build
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Xvfb display for headless GUI
ENV DISPLAY=:1

# VNC password — set VNC_AUTH_TOKEN to require auth; leave empty for no auth.
# The value is a credential supplied at runtime, not a build-time secret; the
# hadolint DL3064 warning is acknowledged below rather than worked around
# because ENV is the only mechanism to declare it for docker run/compose users.
# hadolint ignore=DL3064
ENV VNC_AUTH_TOKEN=

# Install base tools needed for adding the Tor Project apt repo
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*

# Tor: use Tor Project's official apt repo so we get a current Tor (0.4.9.x)
# rather than the distro build. On 26.04 the archive ships 0.4.9.6 — good
# enough for the network, but this image still pins the Tor Project build so
# the binary is reproducible and provenance-checkable (#GUP-12/#GUP-16).
#
# The suite must track the base image: 22.04 needed `jammy`, 24.04+ needs
# `noble`/`resolute`. The repo is arch-keyed rather than suite-keyed, so a
# mismatch still resolves — it just silently mixes release cadences. Keep
# this line in sync with the FROM above.
#
# Both pinned values are deliberate bumps. When the Tor Project removes a
# version from the pool the build fails here (loudly) rather than drifting to
# whatever is current that day — see TODO.md for the refresh procedure.
#
# The two pins are INDEPENDENT. TOR_VERSION moves with each Tor release;
# TOR_KEYRING_SHA256 changes only when the Tor Project reissues the keyring
# package itself (2025.08.08 is current). Bumping the keyring hash alongside a
# Tor release will break the build — verify it against a freshly downloaded
# keyring .deb instead.
ARG TOR_VERSION=0.4.9.16-1~resolute+1
ARG TOR_KEYRING_SHA256=e5bd5c6442ead01e183838be611d6bdf04896ba299095fbb4dc5ab5fe8f19bf6
RUN curl -fsSL https://deb.torproject.org/torproject.org/pool/main/d/deb.torproject.org-keyring/deb.torproject.org-keyring_2025.08.08_all.deb \
    -o /tmp/tor-keyring.deb \
    && echo "${TOR_KEYRING_SHA256}  /tmp/tor-keyring.deb" | sha256sum --check --strict \
    && dpkg -i /tmp/tor-keyring.deb && rm /tmp/tor-keyring.deb \
    && echo "deb [arch=$(dpkg --print-architecture)] https://deb.torproject.org/torproject.org resolute main" \
    > /etc/apt/sources.list.d/tor.list \
    && apt-get update \
    && rm -rf /var/lib/apt/lists/*

# Install X11 (for Xvfb), VNC, noVNC, GUI file manager, and Gupax runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11-xserver-utils \
    x11vnc \
    novnc \
    websockify \
    libgl1 \
    libasound2t64 \
    libpulse0 \
    ca-certificates \
    curl \
    libxkbcommon-x11-0 \
    python3 \
    zenity \
    tor=${TOR_VERSION} \
    netcat-openbsd \
    gosu \
    openbox \
    dbus-x11 \
    dbus \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    x11-apps \
    xinput \
    xdotool \
    # Record where apt resolved tor from before the lists are deleted; the
    # installed version alone cannot prove provenance at runtime.
    && mkdir -p /usr/local/share/gupax-docker \
    && apt-cache policy tor > /usr/local/share/gupax-docker/tor-policy.txt \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates \
    && groupadd -r miner \
    && useradd -r -g miner -m -d /home/miner miner

# Gupax on Linux launches XMRig through pkexec. XMRig does not need root to
# mine: running as root only unlocks MSR writes, and the binary lives on a
# writable volume. A NOPASSWD sudo rule for that path — which this image
# shipped — let anything that could write the volume execute code as container
# root (#GUP-08). The wrapper therefore executes the target unchanged.
#
# MSR optimisation is deliberately given up: there is no way to execute a
# binary from a user-writable path as root without granting that escalation.
# See SECURITY.md.
RUN printf '#!/bin/sh\n# Gupax spawns XMRig via pkexec; run it unprivileged on purpose.\nexec "$@"\n' > /usr/local/bin/pkexec \
    && chmod +x /usr/local/bin/pkexec

# =============================================================================
# Install standalone Gupax (Gupax GUI only — binaries downloaded at runtime)
# Gupax downloads P2Pool, XMRig, monerod, and xmrig-proxy internally.
# Downloaded binaries are persisted in /home/miner/.local/share/gupax
# via a named volume (gupax-data) so they survive container restarts.
# =============================================================================

WORKDIR /tmp/install

# Build argument: Gupax version to install (default: v2.0.1).
# Override at build time: --build-arg GUPAX_VERSION=v2.0.2
# GUPAX_ASSET is the actual Linux x64 tarball filename from the chosen
# release (resolved by CI from the release's assets[] — see
# .github/scripts/detect-gupax-version.sh). Upstream has published
# releases whose tag differs from the asset name (e.g. tag
# "critical_update_p2pool" shipping gupax-v2.0.1-linux-x64.tar.gz), so
# the filename must never be constructed from the tag alone.
# For reproducibility the tarball must match the in-repo pin below; the
# upstream SHA256SUMS is also checked, but it is same-origin with the tarball
# and therefore only detects corruption, not a replaced release (#GUP-15).
ARG GUPAX_VERSION=v2.0.1
ARG GUPAX_ASSET=gupax-v2.0.1-linux-x64.tar.gz
ARG BUILD_DATE=unknown
# Optional per-build override. When empty, the hash is looked up in the
# in-repo pin file below; when neither has an entry the build warns and falls
# back to the upstream SHA256SUMS check (#GUP-15).
ARG GUPAX_SHA256=
# Extract with --strip-components=1 so the binary lands at
# /usr/local/bin/gupax/gupax regardless of the tarball's root directory name.
# The previous `mv gupax-${GUPAX_VERSION}-linux-x64/gupax` reconstructed that
# name from the release TAG, which breaks whenever the two disagree — exactly
# what happened upstream with the non-semver `critical_update_p2pool` tag (see
# #68 / C1). The asset name is already resolved from the release's assets[];
# the directory name should not be re-derived. See #73 (L3).
#
# Verification has two layers. The upstream SHA256SUMS check detects
# corruption/truncation; it cannot detect a replaced release because the sums
# come from the same origin. The in-repo gupax-checksums.txt pin is the
# trusted digest: a newer auto-detected release is allowed to build (with a
# loud warning) only until someone records its hash.
COPY gupax-checksums.txt /tmp/install/gupax-checksums.txt
RUN TARBALL="${GUPAX_ASSET}" \
    && echo "[*] Downloading Gupax ${GUPAX_VERSION} (${TARBALL})..." \
    && curl -fsSL "https://github.com/gupax-io/gupax/releases/download/${GUPAX_VERSION}/${TARBALL}" -o "${TARBALL}" \
    && curl -fsSL "https://github.com/gupax-io/gupax/releases/download/${GUPAX_VERSION}/SHA256SUMS" -o SHA256SUMS \
    && grep " ${TARBALL}$" SHA256SUMS | awk '{print $1 "  " $2}' > "${TARBALL}.sha256" \
    && sha256sum --check --strict "${TARBALL}.sha256" \
    && PINNED=$(awk -v v="${GUPAX_VERSION}" -v a="${TARBALL}" '$1 == v && $2 == a {print $3; exit}' gupax-checksums.txt) \
    && EXPECTED="${GUPAX_SHA256:-$PINNED}" \
    && if [ -n "$EXPECTED" ]; then \
           echo "[*] Verifying pinned SHA256 for ${GUPAX_VERSION}"; \
           echo "$EXPECTED  ${TARBALL}" | sha256sum --check --strict; \
       else \
           echo "[!] WARNING: no pinned SHA256 for ${GUPAX_VERSION}/${TARBALL}."; \
           echo "[!] Add it to gupax-checksums.txt — upstream sums alone are same-origin."; \
       fi \
    && mkdir -p /usr/local/bin/gupax \
    && tar -xzf "${TARBALL}" -C /usr/local/bin/gupax --strip-components=1 \
    && chmod +x /usr/local/bin/gupax/gupax \
    && ln -s /usr/local/bin/gupax/gupax /usr/local/bin/gupax-bin \
    && rm -rf "${TARBALL}" "${TARBALL}.sha256" SHA256SUMS /tmp/install

# Labels
# licenses uses the current SPDX expression (GPL-3.0 is deprecated); revision
# and created make registry-side provenance queries useful even without the
# attached BuildKit attestations (#GUP-19).
ARG GUPAX_REVISION=unknown
ARG BUILD_CREATED=unknown
LABEL org.opencontainers.image.title="gupax-docker" \
      org.opencontainers.image.description="noVNC-enabled Docker image for Gupax — GUI for P2Pool + XMRig Monero mining with optional Tor" \
      org.opencontainers.image.vendor="libre-7" \
      org.opencontainers.image.url="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.source="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.documentation="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.version="${GUPAX_VERSION}-${BUILD_DATE}" \
      org.opencontainers.image.revision="${GUPAX_REVISION}" \
      org.opencontainers.image.created="${BUILD_CREATED}" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.icon="https://raw.githubusercontent.com/gupax-io/gupax/main/assets/images/icons/icon.png" \
      description="Gupax — GUI for P2Pool + XMRig Monero mining in Docker (noVNC enabled, standalone binaries + optional Tor)" \
      gupax.version="${GUPAX_VERSION}"


# Create index.html redirect at build time (avoids any runtime permission issues)
RUN echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=vnc.html"></head><body><a href="vnc.html">Click to connect</a></body></html>' > /usr/share/novnc/index.html

# Copy runtime scripts. setup-runtime-user.sh must be present before start.sh
# runs; tor-bootstrap-check.sh is used by the HEALTHCHECK.
COPY start.sh healthcheck.sh setup-runtime-user.sh tor-bootstrap-check.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/healthcheck.sh \
    /usr/local/bin/setup-runtime-user.sh /usr/local/bin/tor-bootstrap-check.sh

# Licence text and attribution notice travel with the image. It redistributes
# Gupax (GPL-3.0-or-later), and the GPL requires the licence to accompany the
# distribution; `org.opencontainers.image.licenses` alone is metadata, not the
# licence. .dockerignore deliberately does not exclude these two files.
COPY LICENSE NOTICE /usr/share/doc/gupax-docker/

EXPOSE 6080 5900
EXPOSE 3333 37889 18080 18081
# Internal-only ports (documented for debugging — not mapped to host)
EXPOSE 18083 18084 18086 9050

# Pre-create .bitmonero directory with miner ownership.
# No .bitmonero symlink needed — monerod resolves its data directory via $HOME
# (/home/miner) which start.sh passes through gosu to the gupax process.
#
# NOTE: /home/miner/.local/share/gupax is deliberately NOT pre-created here.
# A fresh Docker named volume mounts root:root 0755 regardless, and
# pre-creating the path would only mask that. start.sh therefore treats a
# detected owner of 0 as "unset" and falls back to the miner user (999).
RUN mkdir -p /home/miner/.bitmonero && chown miner:miner /home/miner/.bitmonero

# Container starts as root so start.sh can fix volume permissions.
# start.sh drops to the miner user via gosu before launching Gupax.
WORKDIR /home/miner

# Health check — verifies noVNC + VNC + Gupax, plus Tor if enabled.
# Exec form (JSON array) avoids hadolint DL3025.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/start.sh"]
