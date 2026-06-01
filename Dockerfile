# =============================================================================
# Gupax-docker — Dockerfile
# Gupax GUI for P2Pool + XMRig Monero mining
# Self-contained with noVNC — access via web browser at http://localhost:6080
#
# Standalone approach — only Gupax GUI is bundled.
# P2Pool, XMRig, monerod, and xmrig-proxy are downloaded at runtime by Gupax
# and persisted in /home/miner/.local/share/gupax via the gupax-share volume.
# =============================================================================

FROM ubuntu:22.04@sha256:4fff072216d2d3d6accc8bc09b57c33e474edd726f3f65fbadbb05647ab15fa5

# Use bash with pipefail for all RUN commands so that failures in piped
# commands are not silently ignored (e.g., grep | awk producing empty output).
# The default /bin/sh (dash) does not support pipefail.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Prevent interactive tzdata prompt from blocking the build
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Xvfb display for headless GUI
ENV DISPLAY=:1

# VNC password — set VNC_AUTH_TOKEN to require auth; leave empty for no auth
ENV VNC_AUTH_TOKEN=

# Install base tools needed for adding the Tor Project apt repo
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*

# Tor: use Tor Project's official apt repo to get Tor 0.4.8.x instead of
# Ubuntu 22.04's stale 0.4.6.10 which lacks FlowCtrl=2 and Relay=4 protocol
# support.  Without this, Tor will eventually be rejected from the network.
RUN curl -fsSL https://deb.torproject.org/torproject.org/pool/main/d/deb.torproject.org-keyring/deb.torproject.org-keyring_2025.08.08_all.deb \
    -o /tmp/tor-keyring.deb \
    && dpkg -i /tmp/tor-keyring.deb && rm /tmp/tor-keyring.deb \
    && echo "deb [arch=$(dpkg --print-architecture)] https://deb.torproject.org/torproject.org jammy main" \
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
    libasound2 \
    libpulse0 \
    ca-certificates \
    curl \
    libxkbcommon-x11-0 \
    python3 \
    zenity \
    tor \
    netcat-openbsd \
    gosu \
    openbox \
    dbus-x11 \
    dbus \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    x11-apps \
    xinput \
    sudo \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates \
    && groupadd -r miner \
    && useradd -r -g miner -m -d /home/miner miner

# Allow passwordless sudo for XMRig — Gupax on Linux spawns XMRig via pkexec
# which is unavailable in Docker; we provide a pkexec→sudo wrapper instead.
# Restrict to %gupax group (created by start.sh's useradd for the gosu-dropped
# UID) rather than ALL, to limit the writable-volume sudo escalation surface.
RUN echo "%gupax ALL=(ALL) NOPASSWD: /home/miner/.local/share/gupax/xmrig/xmrig" > /etc/sudoers.d/gupax-xmrig \
    && chmod 0440 /etc/sudoers.d/gupax-xmrig

# Provide a pkexec wrapper that delegates to sudo (no PolicyKit agent in container)
RUN printf '#!/bin/sh\nexec sudo "$@"\n' > /usr/local/bin/pkexec \
    && chmod +x /usr/local/bin/pkexec

# =============================================================================
# Install standalone Gupax (Gupax GUI only — binaries downloaded at runtime)
# Gupax downloads P2Pool, XMRig, monerod, and xmrig-proxy internally.
# Downloaded binaries are persisted in /home/miner/.local/share/gupax
# via a named volume (gupax-share) so they survive container restarts.
# =============================================================================

WORKDIR /tmp/install

# Build argument: Gupax version to install (default: v2.0.1).
# Override at build time: --build-arg GUPAX_VERSION=v2.0.2
# For reproducibility, the SHA256 is fetched from upstream SHA256SUMS
# at build time — the image build fails if verification fails.
ARG GUPAX_VERSION=v2.0.1
ARG BUILD_DATE=unknown
RUN TARBALL="gupax-${GUPAX_VERSION}-linux-x64.tar.gz" \
    && echo "[*] Downloading Gupax ${GUPAX_VERSION}..." \
    && curl -fsSL "https://github.com/gupax-io/gupax/releases/download/${GUPAX_VERSION}/${TARBALL}" -o "${TARBALL}" \
    && curl -fsSL "https://github.com/gupax-io/gupax/releases/download/${GUPAX_VERSION}/SHA256SUMS" -o SHA256SUMS \
    && grep "${TARBALL}" SHA256SUMS | awk '{print $1 "  " $2}' > "${TARBALL}.sha256" \
    && sha256sum --check "${TARBALL}.sha256" \
    && tar -xzf "${TARBALL}" \
    && mkdir -p /usr/local/bin/gupax \
    && mv "gupax-${GUPAX_VERSION}-linux-x64/gupax" /usr/local/bin/gupax/gupax \
    && chmod +x /usr/local/bin/gupax/gupax \
    && ln -s /usr/local/bin/gupax/gupax /usr/local/bin/gupax-bin \
    && rm -rf "${TARBALL}" "${TARBALL}.sha256" SHA256SUMS "gupax-${GUPAX_VERSION}-linux-x64" /tmp/install

# Labels
LABEL org.opencontainers.image.title="gupax-docker" \
      org.opencontainers.image.description="noVNC-enabled Docker image for Gupax — GUI for P2Pool + XMRig Monero mining with optional Tor" \
      org.opencontainers.image.vendor="libre-7" \
      org.opencontainers.image.url="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.source="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.documentation="https://github.com/libre-7/gupax-docker" \
      org.opencontainers.image.version="${GUPAX_VERSION}-${BUILD_DATE}" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.icon="https://raw.githubusercontent.com/gupax-io/gupax/main/assets/images/icons/icon.png" \
      maintainer="libre-7" \
      description="Gupax — GUI for P2Pool + XMRig Monero mining in Docker (noVNC enabled, standalone binaries + optional Tor)" \
      gupax.version="${GUPAX_VERSION}"


# Create index.html redirect at build time (avoids any runtime permission issues)
RUN echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=vnc.html"></head><body><a href="vnc.html">Click to connect</a></body></html>' > /usr/share/novnc/index.html

# Copy startup script and healthcheck
COPY start.sh /usr/local/bin/start.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/healthcheck.sh
EXPOSE 6080 5900
EXPOSE 3333 37889 18080 18081
# Internal-only ports (documented for debugging — not mapped to host)
EXPOSE 18083 18084 18086 9050

# Pre-create .bitmonero directory with miner ownership.
# No .bitmonero symlink needed — monerod resolves its data directory via $HOME
# (/home/miner) which start.sh passes through gosu to the gupax process.
RUN mkdir -p /home/miner/.bitmonero && chown miner:miner /home/miner/.bitmonero

# Container starts as root so start.sh can fix volume permissions.
# start.sh drops to the miner user via gosu before launching Gupax.
WORKDIR /home/miner

# Health check — verifies noVNC web interface + Tor (if enabled)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
