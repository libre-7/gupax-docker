# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `:latest` (main branch) | ✅ |
| `v2.0.1-YYYYMMDD-<sha7>` (immutable build) | ✅ |
| `v2.0.1-YYYYMMDD` (date convenience tag) | ✅ — may be replaced by a same-day rebuild |
| `:<sha>` (commit-pinned) | ✅ |
| Feature branch tags | ⚠️ Unstable — development only |

Both registries receive the **same digest**: images are built once and pushed
to GHCR and Docker Hub in a single build. For an immutable reference use the
SHA-suffixed tag or the commit tag; the plain date tag can be replaced if the
same commit is rebuilt on the same day.

The `:latest` tag and date-stamped tags receive security fixes. Feature
branch tags are development snapshots and may not receive prompt updates.

## Reporting a Vulnerability

If you discover a security vulnerability in gupax-docker, please **do not**
open a public GitHub issue.

Please report it privately via GitHub Security Advisories:

1. Go to the [Security tab](https://github.com/libre-7/gupax-docker/security)
2. Click **Report a vulnerability**
3. Describe the issue with as much detail as possible

You can also email **libre7@proton.me** with the details.

### What to include

- A clear description of the vulnerability
- Steps to reproduce or a proof-of-concept
- Affected versions or configurations
- Potential impact to users

### What to expect

- **Acknowledgment:** Within 48 hours
- **Assessment:** Within 7 days — we'll evaluate severity and confirm whether
  it applies
- **Fix timeline:** Critical issues will be patched as quickly as possible,
  typically within 2–4 weeks depending on complexity
- **Disclosure:** We'll coordinate public disclosure with you. You'll be
  credited in the release notes unless you prefer to remain anonymous

### Out of scope

- Issues that require physical access to the host machine
- Vulnerabilities in upstream projects (Gupax, P2Pool, XMRig, monerod) —
  please report those to the respective projects directly
- Theoretical attacks that require the attacker to already have root on the
  Docker host

## Security-relevant Configuration

The following environment variables and settings directly affect the security
posture of the container:

| Setting | Effect |
|---------|--------|
| `VNC_AUTH_TOKEN` | Password for VNC/noVNC. VNC authentication uses a fixed 8-byte key, so only the **first 8 characters** are effective. Without it, x11vnc binds to loopback only; noVNC still works through the local proxy, but publishing 5900 does not expose the desktop. |
| `TOR_ENABLED=true` | Starts the Tor daemon and hidden service. It does **not** route traffic by itself: monerod must be started with `--tx-proxy=tor,127.0.0.1:9050`. P2P sync stays on clearnet. |
| `TOR_EXPOSE_RPC=true` | Publishes wallet RPC (`18081`) on the `.onion`. Off by default because monerod's RPC is unauthenticated unless you paste `--restricted-rpc` into Gupax. |
| `MONERO_RPC_RESTRICTED=true` | Adds `--restricted-rpc` to the **recommended** monerod arguments printed at startup. The container does not inject it — you still have to paste the arguments into Gupax → Node → Arguments and Save. With `false`, the startup banner warns that port 18081 is unauthenticated. |
| `--rpc-login` | Do **not** use with Gupax-managed monerod — incompatible. Use `--restricted-rpc` instead. |

The container runs with `cap_drop: [ALL]` and only adds back the minimum
capabilities needed (`SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`, `CHOWN`).

### Runtime user

Gupax is launched via `gosu` as a **non-root** user. Which UID depends on
configuration, and the difference matters:

| Configuration | Effective UID |
|---|---|
| Default (fresh volume, no `PUID` set) | `999` — the image's non-root `miner` user |
| `PUID`/`PGID` set explicitly | that value (compose defaults to `999`; the Unraid template defaults to `99`) |
| Pre-existing volume owned by another user | that volume owner's UID |

The container **starts as root** so `start.sh` can fix volume ownership before
dropping privileges. The Gupax process tree (Gupax, monerod, P2Pool, XMRig)
runs as the configured UID. A fresh Docker named volume mounts `root:root
0755`; `start.sh` treats a detected owner of `0` as "unset" and falls back to
`999` rather than running the mining stack as root. The CI smoke test mounts a
volume and asserts Gupax is non-root to keep that from regressing (see #73).

Privilege handling elsewhere:

- **Tor** runs as `debian-tor` when the `.tor` volume permits ownership
  changes. On a FUSE share that ignores `chown`, it falls back to root and
  logs a warning — the alternative would be Tor failing to start.
- **XMRig** runs unprivileged, as the same UID as Gupax. The image grants no
  sudo rule at all. XMRig's MSR optimisation requires root, but the binary is
  downloaded into a writable volume, so executing it as root would let any
  process able to write that volume run code as container root. That trade is
  deliberate; hugepages and mining still work.
- **Xvfb, x11vnc, websockify and the D-Bus/portal processes** run as root.
  They are local-only: Xvfb has no TCP listener (`-nolisten tcp`), x11vnc is
  password-protected or bound to loopback, and websockify exposes only the
  configured noVNC port.

### FUSE fallback and root execution

On Unraid's FUSE shares the container first tries group ownership
(`chgrp gupax`). If the mount ignores that too, it falls back to
world-writable permissions on the data volume. Binaries in that volume are
never executed as root, so the fallback is a data-integrity exposure, not a
container-root escalation.

On Unraid, the FUSE filesystem silently ignores `chown`, which is why the
group-first and world-writable fallbacks above exist. This is a fundamental
Unraid limitation documented in the README's Security Notes section.
