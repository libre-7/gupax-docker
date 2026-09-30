# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `:latest` (main branch) | ✅ |
| Date-stamped tags (`v2.0.1-YYYYMMDD`) | ✅ |
| Feature branch tags | ⚠️ Unstable — development only |

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
| `VNC_AUTH_TOKEN` | Required for VNC access on port 5900. Without it, anyone on your network can control the Gupax GUI. |
| `TOR_ENABLED=true` | Routes transaction broadcasts through Tor for privacy. P2P sync stays on clearnet. |
| `MONERO_RPC_RESTRICTED=true` | Adds `--restricted-rpc` to the **recommended** monerod arguments printed at startup. The container does not inject it — you still have to paste the arguments into Gupax → Node → Arguments and Save. With `false`, the startup banner warns that port 18081 is unauthenticated. |
| `--rpc-login` | Do **not** use with Gupax-managed monerod — incompatible. Use `--restricted-rpc` instead. |

The container runs with `cap_drop: [ALL]` and only adds back the minimum
capabilities needed (`SETUID`, `SETGID`, `DAC_OVERRIDE`, `FOWNER`, `CHOWN`).
It runs as a non-root `miner` user at runtime.

On Unraid, the FUSE filesystem silently ignores `chown`, requiring a fallback
to world-writable permissions on persistent volumes. This is a fundamental
Unraid limitation documented in the README's Security Notes section.
