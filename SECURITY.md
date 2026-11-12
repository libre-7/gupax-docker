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

### Runtime-downloaded miner binaries (not verified by this image)

The image verifies **Gupax** at build time. It does not verify the four
binaries Gupax fetches **after** the container starts, and it cannot: Gupax owns
version selection, the download, and its own update path.

| Binary | Downloaded from | Integrity data the upstream publishes |
|--------|-----------------|----------------------------------------|
| P2Pool | `github.com/SChernykh/p2pool` releases | `sha256sums.txt.asc` (GPG-signed) |
| XMRig | `github.com/xmrig/xmrig` releases | `SHA256SUMS` + `SHA256SUMS.sig` |
| xmrig-proxy | `github.com/xmrig/xmrig` releases | same as XMRig |
| monerod | `downloads.getmonero.org/cli/` | [`hashes.txt`](https://www.getmonero.org/downloads/hashes.txt) (PGP-signed) |

Gupax asks `api.github.com` for each project's latest release, downloads the
matching archive over TLS, extracts it into the `gupax-data` volume, and
executes it. Nothing in that path compares a hash, checks a signature, or
verifies a file size, and no checksum or signature file is fetched for these
downloads. (The `sha256`/`sha512`/`gpg` strings inside the binary belong to its
bundled TLS/crypto library and archive decompressor, not to a verification
step.)

#### What the image does verify

- **Gupax tarball** — the in-repo `gupax-checksums.txt` SHA256, plus upstream
  `SHA256SUMS` as a secondary, same-origin (corruption-only) check.
- **Tor package** — exact version pinned, and the apt origin recorded at build
  time so CI can assert it came from `deb.torproject.org`.
- **Tor keyring `.deb`** — SHA256 pinned in the Dockerfile.
- **TLS on every download** — protects the transfer, nothing more.

#### What this does and does not expose

- **It is not a privilege-escalation path.** These binaries run as the runtime
  UID, never as root (see above), so a tampered binary gains the same access the
  miner already has. It also adds no new local attacker: anyone who can write
  the `gupax-data` volume could already replace these files and have them
  executed as the runtime user.
- **It does expose you to a compromised upstream release.** A malicious
  release, a hijacked maintainer account, or TLS interception with a
  trusted certificate means arbitrary code running as your mining user, with
  access to the wallet and node settings stored in that volume. That is the same
  trust you extend to any `curl | sh`.
- TLS protects transit only. It does not make a malicious release safe.

#### Verifying by hand

This is a point-in-time check, not a one-time seal. Gupax replaces these
binaries whenever it decides a newer upstream release exists, so re-check after
any Gupax update. Run the verification on your host, not in the container.

Upstream checksum files cover the **release archive**, not the extracted
binary, so compare like with like: verify the archive, extract it yourself, then
compare the extracted binary's hash with the one running in the container.

```bash
# 1. Hash the binary that is actually executing in the container
docker exec gupax sha256sum /home/miner/.local/share/gupax/xmrig/xmrig

# 2. Fetch the same upstream release. The tag keeps the "v";
#    the asset name and the extracted directory do not.
VER=6.26.0                        # from `xmrig --version`
BASE=https://github.com/xmrig/xmrig/releases/download/v$VER
# -O applies per URL: one -O per download, or the second lands on stdout
curl -fsSLO "$BASE/SHA256SUMS"
curl -fsSLO "$BASE/SHA256SUMS.sig"
curl -fsSLO "$BASE/xmrig-$VER-linux-static-x64.tar.gz"

# 3. Import the project's signing key, then verify. Get the fingerprint from
#    XMRig's OWN repository documentation — never from the release page you are
#    checking, or the signature proves nothing. A missing key is a hard stop:
#    gpg exits non-zero with "Can't check signature: No public key".
gpg --recv-keys <signing-key-fingerprint-from-xmrig-docs>
gpg --verify SHA256SUMS.sig SHA256SUMS
grep "xmrig-$VER-linux-static-x64.tar.gz" SHA256SUMS | sha256sum -c -

# 4. Unpack and compare against step 1 — the two hashes must match
tar -xzf "xmrig-$VER-linux-static-x64.tar.gz"
sha256sum "xmrig-$VER/xmrig"
```

The other two projects publish different shapes, so the comparison step differs:

- **P2Pool** — `sha256sums.txt.asc` is clearsigned but uses `Name:` / `Size:` /
  `SHA256:` blocks, not `sha256sum` lines. Verify the signature, then pull the
  hash for the archive you downloaded:

  ```bash
  awk '/^Name: p2pool-<version>-linux-x64\.tar\.gz$/{f=1}
       f && /^SHA256:/{print $2; exit}' sha256sums.txt.asc
  ```

- **Monero** — `hashes.txt` is clearsigned and its body *is* plain `sha256sum`
  format, so `sha256sum -c` works after `gpg --verify hashes.txt`:

  ```bash
  grep 'monero-linux-x64-v<version>.tar.bz2' hashes.txt | sha256sum -c -
  ```

Use the signing key each project publishes from its own documentation. Do not
accept a key offered by the release page you are checking — that defeats the
purpose. The Monero `hashes.txt` is signed by the key for **binaryFate**;
XMRig and P2Pool name their release-signing key in their repositories. If
`gpg --verify` reports an unknown key, stop: it has not verified anything.

#### Reducing the exposure

- Restrict the container's egress to `github.com`, `api.github.com`,
  `objects.githubusercontent.com` and `downloads.getmonero.org`. A miner has no
  other reason to reach the internet.
- Keep the `gupax-data` volume writable only by the runtime UID. On Unraid the
  FUSE fallback below can widen that to world-writable.
- Treat a Gupax update as a reason to re-verify, not as evidence that the new
  binaries are trustworthy.

### FUSE fallback and root execution

On Unraid's FUSE shares the container first tries group ownership
(`chgrp gupax`). If the mount ignores that too, it falls back to
world-writable permissions on the data volume. Binaries in that volume are
never executed as root, so the fallback is a data-integrity exposure, not a
container-root escalation.

On Unraid, the FUSE filesystem silently ignores `chown`, which is why the
group-first and world-writable fallbacks above exist. This is a fundamental
Unraid limitation documented in the README's Security Notes section.
