# ✅ Gupax-docker — Project Roadmap & TODO

## 🔴 Critical — App Won't Run Without These

- [x] **Working Dockerfile** — Gupax binary with Xvfb + x11vnc + noVNC
- [x] **noVNC web access** — Container accessible via browser at http://localhost:6080
- [x] **Wallet address configuration** — Set inside Gupax GUI (Node tab), not as Docker env var
- [x] **docker-compose.yml** — Working compose with Gupax, noVNC, and volumes
- [x] **README.md** — Clear documentation with Quick Start and troubleshooting

## 🟡 Important — Real-World Usability

- [x] **Blockchain volume** — Mount existing Monero blockchain at `/home/miner/.bitmonero`
- [x] **PR test pipeline** — Lint (shellcheck + hadolint + yamllint) + smoke test on PRs
- [x] **GHCR + Docker Hub CI** — Image builds pushed to both registries on merge to main
- [x] **Multi-arch builds** — Support `linux/arm64` if Gupax provides arm64 binary
- [x] **CONTRIBUTING.md** — How to submit PRs and report issues
- [ ] **X11 troubleshooting docs** — Expand troubleshooting for common noVNC issues
- [ ] **GitHub Releases** — Tagged releases with release notes

## 🟢 Nice to Have — Polish & Production Hardening

- [x] **Non-root user** — Runs as `miner` user for security
- [x] **Version pinning** — Gupax version pinned with SHA256 checksum verification
- [x] **Automatic restart** — `restart: unless-stopped` in compose
- [x] **VNC password** — Optional password protection for noVNC interface
- [ ] **Read-only root filesystem** — Mark image as `read_only: true` where possible
- [ ] **Monitoring integration** — Optional Prometheus metrics if Gupax exposes them

## 📝 Documentation & Community

- [x] **README.md** — Quick Start, noVNC setup, configuration, troubleshooting
- [x] **CHANGELOG.md** — Track changes per release

- [ ] **GitHub Issues templates** — Bug report and feature request templates

## 🧪 Testing & Validation

- [x] **Smoke test** — Verified container starts and noVNC is accessible at port 6080
- [x] **Browser test** — noVNC http://localhost:6080 validated via CI health check
- [x] **Restart test** — Verified Gupax config persists after container restart
- [x] **Tor test** — Verified hidden service + SOCKS proxy on Unraid
- [x] **Version upgrade test** — SHA256SUMS verification from upstream at build time

## 📌 Current Build Information

- **Version scheme:** `v{upstream-gupax}-{build-date}` (e.g. `v2.0.1-20260518`)
- **Gupax version:** Dynamically detected at build time — CI resolves latest upstream release
- **Build method:** Pre-built Gupax binary from upstream, verified via SHA256SUMS
- **Image size:** ~375 MB
- **Components:** Gupax + Xvfb + x11vnc + websockify + noVNC + Tor (optional)
- **Registries:** `ghcr.io/libre-7/gupax-docker` + `docker.io/libre7/gupax-docker`

> **Note:** This container uses noVNC for browser-based GUI access. No X11 server needed on the host.
