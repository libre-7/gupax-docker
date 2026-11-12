# ✅ Gupax-docker — Project Roadmap & TODO

## 🔴 Critical — App Won't Run Without These

- [x] **Working Dockerfile** — Gupax binary with Xvfb + x11vnc + noVNC
- [x] **noVNC web access** — Container accessible via browser at http://localhost:6080
- [x] **Wallet address configuration** — Set inside Gupax GUI (P2Pool tab), not as Docker env var
- [x] **docker-compose.yml** — Working compose with Gupax, noVNC, and volumes
- [x] **README.md** — Clear documentation with Quick Start and troubleshooting

## 🟡 Important — Real-World Usability

- [x] **Blockchain volume** — Mount existing Monero blockchain at `/home/miner/.bitmonero`
- [x] **PR test pipeline** — Lint (shellcheck + hadolint + yamllint) + smoke test on PRs
- [x] **GHCR + Docker Hub CI** — One build pushed to both registries on merge to main (same digest)
- [ ] **Multi-arch builds** — `linux/arm64` not yet supported: Gupax ships no arm64 Linux binary. The release build is `linux/amd64` only (tracked in #61)
- [x] **CONTRIBUTING.md** — How to submit PRs and report issues
- [x] **X11 troubleshooting docs** — Blank/black-screen, refused port, and restart-loop sections expanded; covers health-probe interpretation, `SCREEN_RESOLUTION` validation/fallback, stale X locks, missing window manager, and framebuffer size
- [x] **GitHub Releases** — Tagged releases with release notes
- [x] **Base image migration** — Migrated `ubuntu:22.04` → `ubuntu:26.04` LTS ("resolute"); 22.04 standard support ends April 2027. Required renaming `libasound2` → `libasound2t64` (no package named `libasound2` exists in 24.04+; the t64 package `Provides: libasound2`) and moving the Tor apt suite `jammy` → `resolute`; Tor is now pinned to the Tor Project build. Closes #84
- [ ] **Drop the audio packages** — Gupax's binary (v2.0.1 ELF64 PIE) contains zero references to `libasound`/`libpulse`, so `libasound2t64` and `libpulse0` may be removable outright. Kept in the 26.04 migration because GTK/zenity can pull audio transitively — verify separately
- [x] **Issue templates** — Bug + feature forms, blank issues disabled, contact links for security advisories and upstream Gupax/Monero
- [ ] **Tor pin refresh** — Two **independent** pins in the Dockerfile: `tor=<version>` (moves with each Tor release) and the keyring `.deb` SHA256 (changes only when the keyring package is reissued — currently `2025.08.08`). Dependabot covers neither, so each must be bumped by hand when the Tor Project removes the pinned version from the pool or reissues the keyring. When a version disappears, read `dists/resolute/main/binary-amd64/Packages` for what replaced it; do **not** bump the keyring hash in the same commit unless the keyring `.deb` itself changed.

## 🟢 Nice to Have — Polish & Production Hardening

- [x] **Non-root user** — Gupax runs as a non-root user via `gosu` (default UID 999; `PUID`/`PGID` override). CI asserts this on every PR.
- [x] **Version pinning** — The Gupax tarball is verified against an in-repo SHA256 pin (`gupax-checksums.txt`); the upstream SHA256SUMS is a secondary, same-origin check. ⚠️ The P2Pool/XMRig/monerod binaries Gupax downloads at **runtime** are not checksum-verified by this image.
- [x] **Restart on exit** — `restart: unless-stopped` in compose. It acts on exit only: a hung GUI (container `Up`, health `unhealthy`) is reported by the health check, not auto-restarted
- [x] **VNC password** — Optional password protection for noVNC interface
- [ ] **Read-only root filesystem** — Mark image as `read_only: true` where possible
- [ ] **Monitoring integration** — Optional Prometheus metrics if Gupax exposes them

## 📝 Documentation & Community

- [x] **README.md** — Quick Start, noVNC setup, configuration, troubleshooting
- [x] **CHANGELOG.md** — Track changes per release

## 🧪 Testing & Validation

- [x] **Smoke test** — Verified container starts and noVNC is accessible at port 6080
- [x] **Browser test** — noVNC http://localhost:6080 validated via CI health check
- [x] **Restart test** — Verified Gupax config persists after container restart
- [x] **Tor test** — Verified hidden service + SOCKS proxy on Unraid
- [x] **Version upgrade test** — SHA256SUMS verification from upstream at build time

## 📌 Current Build Information

- **Version scheme:** `v{upstream-gupax}-{build-date}` (e.g. `v2.0.1-20260928` — the date is the build day, not a fixed value)
- **Gupax version:** Dynamically detected at build time — CI resolves latest upstream release
- **Build method:** Pre-built Gupax binary from upstream, verified via SHA256SUMS
- **Image size:** ~375 MB
- **Components:** Gupax + Xvfb + x11vnc + websockify + noVNC + Tor (optional)
- **Registries:** `ghcr.io/libre-7/gupax-docker` + `docker.io/libre7/gupax-docker`

> **Note:** This container uses noVNC for browser-based GUI access. No X11 server needed on the host.
