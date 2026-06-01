# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Versions follow the scheme `v{upstream-gupax}-{build-date}`. The base version
tracks which Gupax release is bundled; the date suffix differentiates container
builds. `v2.0.1` and `v2.0.1-YYYYMMDD` tags are Docker image tags — the
`v`-prefixed tag is a moving tag that always points to the latest build of that
upstream release.

## [v2.0.1-20260518] — 2026-05-18

### Changed

- **Version scheme** — Adopted `v{upstream}-{date}` convention. Version now
  tracks the bundled Gupax release with a date-stamped container build suffix.
  OCI labels (`image.version`, `gupax.version`) updated accordingly (#47).

### Fixed

- **CI build-args broken** (#48) — `GUPAX_VERSION` was arriving empty due to
  multiline YAML scalar not interpolating `${{ }}`. Both registries were
  silently falling back to the hardcoded v2.0.1 default. Fixed with
  comma-separated args + `env:` block pattern.
- **Registry divergence from `paths:` filter** (#48) — Docker Hub workflow had
  a `paths:` filter that skipped docs-only commits. Removed; both registries
  now share identical triggers.
- **Smoke test Gupax race condition** (#51) — Single-shot `pgrep` fired before
  `start.sh` reached Gupax launch (80% failure rate). Replaced with 15-attempt
  polling loop matching Tor/hidden-service probes.
- **Version tag asymmetry** (#53) — Docker Hub tagged `:v2.0.1`, GHCR tagged
  `:2.0.1`. Both now emit `:2.0.1` (stripped) and `:v2.0.1` (v-prefixed).

### Security

- **Hadolint warnings resolved** (#52) — `DL4006/SC3040` (pipefail in dash),
  `DL3009` (uncleaned apt lists), `SC2034` (dead variable). Added `SHELL` to
  bash with pipefail globally.
- **OCI labels corrected** (#52) — `image.source` case fixed
  (`Gupax-docker` → `gupax-docker`), stale `-standalone-tor` suffix removed.
- **Stale comment fixed** (#54) — `VNC_PASSWORD` → `VNC_AUTH_TOKEN` in
  `start.sh` comment (was correct in code, wrong in docs).

### Added

- **Date-stamped image tags** — Both registries now push a `v{version}-{date}`
  immutable tag in addition to the moving tags.

### Documentation

- Port tables consolidated into single master table in README and template
  README (#47).
- License restructured as canonical GPL-3.0 with separate NOTICE and SPDX
  headers.
- Docker Hub build status badge added to README.
- Unraid template docs updated for 6.10+ flash-drive install method.

---

## [2.3.0] — 2026-05-12

### Security

- Health check now monitors Tor SOCKS proxy when enabled (#9)
- Image provenance attestations + SBOM generated for GHCR and Docker Hub (#5)
- Documented FUSE world-writable permission trade-off on Unraid (#8)

### Fixed

- VNC_PASSWORD → VNC_AUTH_TOKEN env var mismatch in compose/template (#1)
- Dockerfile labels updated from deprecated w111a → libre-7 namespace (#2)
- Removed deprecated version: "3.8" from docker-compose.yml (#3)
- Docker Hub builds now pass correct GUPAX_VERSION as build-arg (#7)
- Removed deprecated transitional libgl1-mesa-glx package (#11)
- Replaced racy rm -rf /tmp/.X11-unix with targeted file removal (#10)

### Added

- MONERO_RPC_RESTRICTED surfaced in compose, Unraid template, and .env.example (#6)
- Dependabot configured for GitHub Actions version updates (#14)

---

## [2.2.0] — 2026-04-18

### Added
- **Blockchain volume support** — Mount existing Monero blockchain at `/home/miner/.bitmonero`
- **Unraid template** — Updated with noVNC WebUI (`http://[IP]:[PORT:6080]`) and blockchain volume

### Changed
- **Unraid template** — Renamed from old P2Pool+XMRig direct approach to Gupax GUI approach

---

## [2.1.0] — 2026-04-18

### Added
- **noVNC self-contained GUI** — Container now accessible via web browser at http://localhost:6080
- **Xvfb + x11vnc + websockify** — Virtual framebuffer and VNC-to-WebSocket proxy
- **start.sh** — Startup script orchestrating Xvfb → x11vnc → websockify → Gupax

### Changed
- **Image size** reduced from ~6.14 GB to ~375 MB
- **DISPLAY requirement removed** — Container is now self-contained, no X11 on host needed

### Removed
- P2Pool and XMRig binaries (Gupax manages these internally)

---

## [2.0.0] — 2026-04-18

### Breaking Changes

**Complete rewrite. The previous version managed P2Pool and XMRig directly. This version packages the Gupax GUI application.**

- **Removed** direct P2Pool and XMRig binaries from the container
- **Removed** custom entrypoint script that orchestrated P2Pool + XMRig
- **Removed** environment variables: `P2POOL_MINI`, `XMRIG_THREADS`, `MONERO_NODE`, `P2POOL_STRATUM_PORT`, `P2POOL_MONERO_PORT`
- **Removed** volumes: `gupax-p2pool`, `gupax-monero`
- **Removed** Unraid template (old version)
- **Changed** container behavior: Now runs Gupax GUI application

### Added
- **Gupax GUI** — Full graphical interface for P2Pool + XMRig mining
- **X11 requirement** — Container fails if DISPLAY is not set
- **X11 socket mount** — `/tmp/.X11-unix` mounted automatically
- **Gupax config volume** — `gupax-config:/home/miner/.local/state/gupax`
- **CHANGELOG.md** — This file

### Legacy Files

These files are from the old P2Pool+XMRig direct approach and are kept for reference:
- `entrypoint.sh.LEGACY_P2POOL_XMRIG`
- `.env.example.LEGACY_P2POOL_XMRIG`
- `scripts/get-checksums.sh.LEGACY`
- `templates/gupax-docker.xml.LEGACY_P2POOL_XMRIG`

---

## [1.0.0] — Previous

See git history for previous changes.
