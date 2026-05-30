<img src="https://raw.githubusercontent.com/gupax-io/gupax/main/assets/images/banner.png" width="600">

[![Build Status](https://img.shields.io/github/actions/workflow/status/libre-7/Gupax-docker/docker-publish.yml?branch=main&style=flat-square&logo=github&label=build)](https://github.com/libre-7/Gupax-docker/actions)
[![Docker Hub Build](https://img.shields.io/github/actions/workflow/status/libre-7/Gupax-docker/docker-hub-push.yml?branch=main&style=flat-square&logo=docker&label=dockerhub)](https://github.com/libre-7/Gupax-docker/actions/workflows/docker-hub-push.yml)
[![License](https://img.shields.io/github/license/libre-7/Gupax-docker?style=flat-square&color=blue)](https://github.com/libre-7/Gupax-docker/blob/main/LICENSE)
[![Docker Hub](https://img.shields.io/docker/pulls/libre7/gupax-docker?style=flat-square&color=blue&logo=docker)](https://hub.docker.com/r/libre7/gupax-docker)
[![Image Size](https://img.shields.io/docker/image-size/libre7/gupax-docker/latest?style=flat-square&logo=docker&color=blueviolet)](https://hub.docker.com/r/libre7/gupax-docker)

> Docker packaging for [Gupax](https://github.com/hinto-janai/gupax) — the GUI that unites [P2Pool](https://github.com/SChernykh/p2pool) and [XMRig](https://github.com/xmrig/xmrig) for easy, decentralized Monero mining. Optional built-in **🧅 Tor hidden service** for private transaction relay.

**Self-contained with noVNC** — access the Gupax GUI directly from your web browser. No X11 server or additional setup needed.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🌐 **Browser Access** | noVNC web interface — just open `http://localhost:6080` |
| 🖥️ Gupax GUI | Full graphical interface for P2Pool + XMRig mining |
| 🔗 Decentralized mining | P2Pool provides trustless, decentralized Monero mining |
| 💾 Persistent config | Gupax settings persist across container restarts |
| 🔄 Auto-restart | Container restarts automatically on failure |
| 📊 Mining dashboard | Real-time hashrate, shares, payouts, and node status |
| 🔧 XMRig proxy | Built-in proxy for connecting external miners |
| 🧅 Tor hidden service | Optional — expose your node as a `.onion` for private transactions |

---

## 📋 Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)
- A Monero wallet address (for mining payouts)
- A web browser (any modern browser)

---

## 🚀 Quick Start

### Option 1: Docker Compose (recommended)

```bash
# 1. Clone the repository
git clone https://github.com/libre-7/Gupax-docker.git
cd Gupax-docker

# 2. Copy and edit environment file
cp .env.example .env

# 3. Start the container
docker compose up -d

# 4. Open your browser
open http://localhost:6080
```

```bash
# Pull and run
docker run -d \
  --name gupax \
  -p 6080:6080 \
  -p 3333:3333 \
  -p 37889:37889 \
  -p 18080:18080 \
  -p 18081:18081 \
  -v gupax-data:/home/miner/.local/share/gupax \
  -v gupax-state:/home/miner/.local/state/gupax \
  -v gupax-monero:/home/miner/.bitmonero \
  libre7/gupax-docker:latest

# Open browser
open http://localhost:6080
```

Click **Connect** on the noVNC page — no password required by default.

---


## 🧅 Tor (Optional)

When `TOR_ENABLED=true`, the container starts a Tor daemon with a **SOCKS5 proxy** on `127.0.0.1:9050` and a **hidden service** that exposes your Monero node as a `.onion` address:

See the [Ports table](#ports) in Configuration for all Tor-related ports (`18081`, `18084`, `18086`). In short:

| Port | Service |
|------|---------|
| `<onion>:18081` | Wallet RPC — connect wallets over Tor (restricted, read-only) |
| `<onion>:18084` | P2P inbound — other Tor peers relay transactions here |

The container uses **tx-only mode** — P2P blockchain sync stays on clearnet; only wallet-originated transactions are routed through Tor. This keeps bandwidth through Tor negligible (~2 KB per transaction) while still protecting transaction privacy.

### Why not sync blocks over Tor?

**Bandwidth — the ethical concern.** A synced Monero node pushes hundreds of GB to multiple TB per month through its P2P connections. The Tor network consists of ~7,000 volunteer-run relays provisioned for web browsing and messaging — low-bandwidth, bursty traffic. Monero P2P is the opposite: sustained, high-throughput, always-on. Pushing full node sync through Tor degrades the network for everyone else, analogous to torrenting over Tor.

**Monero's own design acknowledges this.** From official docs:
> *Monerod does not support synchronizing the blockchain over onion or I2P hidden services.*
> *anonymous-inbound is not for blockchain sync!*

**What `--tx-proxy` gives you instead.** Only wallet-originated transactions (~2 KB) route through Tor. Your ISP sees you running a Monero node on clearnet, but individual transaction origins are hidden behind Tor circuits. Combined with `--anonymous-inbound`, transactions enter and leave your node through Tor while bulk sync stays efficient on clearnet.

> **Note:** If you need full-P2P-over-Tor (e.g., ISP blocks Monero traffic entirely), you can add `--proxy 127.0.0.1:9050` manually in Gupax's Node → Arguments. This works but will consume significant Tor network bandwidth — please reduce rate limits with `--limit-rate-up` and `--limit-rate-down` if you do this.

### Step-by-Step: Configuring monerod to Use Tor

**1. Find your `.onion` address in the container logs**

```bash
docker logs gupax 2>&1 | grep -A5 "Monero .onion"
```

You'll see output like:

```
[+] Monero .onion: dqwj5fyc4xfjnlswv2b4xjayxo2enr5sjgwjlimlvgeejkudo6msmqqd.onion
    │ Wallet RPC:   dqwj5fyc...onion:18081
    │ P2P inbound:  dqwj5fyc...onion:18084
    │
    │ Connect wallets over Tor:
    │   monero-wallet-cli --proxy 127.0.0.1:9050 \
    │     --daemon-address dqwj5fyc...onion:18081 \
    │     --trusted-daemon
    │
    │ Mobile wallets (Cake, Monerujo): add .onion as remote node.
    │ RPC is restricted — read-only wallet operations, no admin access.

[+] Recommended monerod arguments (Gupax → Node → Arguments):
    --restricted-rpc
    --tx-proxy=tor,127.0.0.1:9050
    --anonymous-inbound=dqwj5fyc...onion:18084,127.0.0.1:18086,40
```

**2. Open the Gupax web UI** at `http://your-server:6080`

**3. Go to the Node tab** and switch from **Simple** to **Advanced** mode to reveal the **"Start options:"** text box

> **Note:** If you don't see the **Node** tab, open **Settings** → **Tabs**, check **Node**, and click **Save**.

**4. ⚠️ Fix the `--data-dir` path first.** Gupax's default is the relative path `.bitmonero`, which does not resolve correctly in this Docker setup. In the Start options box, locate `--data-dir` and change it to the absolute path:

```
--data-dir /home/miner/.bitmonero
```

> **Why this matters:** Every time you click "Reset to Advanced options" or switch between Simple/Advanced modes, Gupax resets `--data-dir` back to `.bitmonero`. If left as the relative path, monerod will fail to find the blockchain and exit immediately. You must manually correct this each time the options are reset.

**5. Paste the four Tor arguments** from the log output (after the `--data-dir` fix):

```
--restricted-rpc --tx-proxy=tor,127.0.0.1:9050 --anonymous-inbound=dqwj5fyc...onion:18084,127.0.0.1:18086,40
```

The complete Start options line should look like:

```
--data-dir /home/miner/.bitmonero --zmq-pub tcp://127.0.0.1:18083 --rpc-bind-ip 127.0.0.1 --rpc-bind-port 18081 --out-peers 8 --in-peers 16 --log-level 0 --sync-pruned-blocks --enable-dns-blocklist --disable-dns-checkpoints --prune-blockchain --restricted-rpc --tx-proxy=tor,127.0.0.1:9050 --anonymous-inbound=dqwj5fyc...onion:18084,127.0.0.1:18086,40
```

**6. Click Save** (Gupax does not auto-save — if you skip this, the arguments are lost on restart)

**7. Click Start** to launch monerod with Tor

**8. ⚠️ Fix P2Pool's ZMQ port.** Gupax has a known bug where it copies the RPC port (`18081`) into P2Pool's `--zmq-port` argument. ZMQ is a different protocol on a different port (`18083`, set by `--zmq-pub tcp://127.0.0.1:18083` on monerod). If `--zmq-port 18081` is left as-is, P2Pool won't receive real-time block notifications from monerod.

Open the **P2Pool tab** → **Advanced** mode → **Arguments**, and change:
```
--zmq-port 18081
```
to:
```
--zmq-port 18083
```
Then click **Save**.

### Keeping the Same .onion Across Restarts

Mount the `gupax-tor` volume (enabled by default in `docker-compose.yml`) to persist the hidden service private key at `/home/miner/.tor/hs_monerod/hs_ed25519_secret_key`. As long as that file survives, your `.onion` address stays the same across container recreations.

### Connecting a Wallet via Tor

Once monerod is running, you can connect any Monero wallet through the same `.onion` address over the wallet RPC port (`18081`).

**With a Monero wallet:**
1. Go to wallet settings / nodes
2. Add a remote node: `<onion>:18081` (e.g. `dqwj5fyc...onion:18081`)
3. The wallet syncs and submits transactions entirely through Tor

**With `monero-wallet-cli`:**
```bash
monero-wallet-cli --daemon-address <onion>:18081 --proxy 127.0.0.1:9050
```

> **How it works:** The hidden service maps `:18081` directly to monerod's JSON-RPC at `127.0.0.1:18081`. Wallet sync (`get_blocks.bin`) and transaction submission (`send_raw_transaction`) both flow through this port. Transaction broadcast from monerod to the network uses `--tx-proxy=tor,...` to route through SOCKS5.

---
## 🖥️ Unraid Setup

This section covers installing and running Gupax-docker on Unraid.

### Prerequisites

- A running Unraid server (v6.12+)
- The [Community Applications](https://forums.unraid.net/topic/38582-plug-in-community-applications/) plugin installed

### Installing via Community Applications (Recommended)

1. Open the **Apps** tab in your Unraid web UI
2. Search for **"gupax"** or **"monero mining"**
3. Click **Install**
4. Set **SCREEN_RESOLUTION** if needed (default: `1920x1080x24`)
5. Click **Apply** and wait for the container to start

### Manual Install (if not yet in Community Applications)

If Gupax-docker is not yet in the Community Applications store, you can install it manually by dropping the template XML onto your Unraid USB flash drive.

1. Download the template and place it on the flash drive:
   ```bash
   # From Unraid terminal, or mount the flash drive on another machine and copy it:
   wget -O /boot/config/plugins/dockerMan/templates-user/my-gupax-docker.xml \
     https://raw.githubusercontent.com/libre-7/gupax-docker/main/templates/gupax-docker.xml
   ```
2. Go to the **Docker** tab in your Unraid web UI
3. Click **Add Container**
4. Select **"my-gupax-docker"** from the **Template** dropdown
5. Review the settings — adjust **SCREEN_RESOLUTION** if needed (default: `1920x1080x24`)
6. Click **Apply**

### Accessing the GUI

Once the container is running:

1. Open your browser and go to:
   ```
   http://your-unraid-ip:6080
   ```
2. Click **Connect** on the noVNC page — no password required
3. The Gupax GUI will appear

### Setting Your Wallet Address

Inside the Gupax GUI:

1. If you do not see a **Node** tab, go to **Settings** → **Tabs** and check **Node** → **Save**
2. Go to the **Node** tab and enter your Monero wallet address in the **Wallet Address** field
3. Save the settings

> **Note:** Gupax v2.0.0+ hides the Node tab by default. You must enable it manually. The wallet address is set inside the Gupax GUI itself — it is **not** a Docker environment variable or template field.

### Ports on Unraid

See the [Ports table](#ports) in Configuration for a complete list. The Unraid template maps `6080`, `3333`, `37889`, `18080`, and `18081` by default. Port `5900` (VNC) is available but disabled by default — only enable it if you have set `VNC_AUTH_TOKEN`.

### Using Your Own Blockchain on Unraid

If you have an existing Monero blockchain on your Unraid server:

1. In the template, map your blockchain directory to `/home/miner/.bitmonero` as a volume
2. Start the container once to ensure the path is created
3. In the Gupax GUI, go to the **Node tab** and set the database path to:
   ```
   /home/miner/.bitmonero
   ```

---

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TOR_ENABLED` | No | `false` | Enable Tor daemon with SOCKS5 proxy + hidden service for monerod |
| `VNC_AUTH_TOKEN` | No | *(none)* | Set to require a password on the noVNC/VNC interface |
| `PUID` | No | *(auto)* | UID to run Gupax as — auto-detected from `gupax-data` volume owner |
| `PGID` | No | *(auto)* | GID to run Gupax as — auto-detected from `gupax-data` volume owner |
| `MONERO_RPC_RESTRICTED` | No | `true` | Restrict monerod RPC to view-only commands |
| `MONERO_DATA_PATH` | No | `gupax-monero` | Path (volume name or host path) for Monero blockchain data |
| `SCREEN_RESOLUTION` | No | `1920x1080x24` | Resolution for the virtual X display (WxHxD format) |

> **Note:** `GUPAX_VERSION` and `GUPAX_SHA256` are managed automatically by the CI workflow — no manual configuration needed. The Docker image is always built with the latest detected upstream Gupax version.

### Ports

| Port | Service | Category | Map | Description |
|---|---|---|---|---|
| `6080` | noVNC | Access | ✅ **Yes** | Web UI — open in your browser |
| `5900` | VNC | Access | ⚠️ **Optional** | Direct VNC (only needed if `VNC_AUTH_TOKEN` is set) |
| `3333` | P2Pool | Mining | ✅ **Yes** | Stratum — external miners connect here |
| `37889` | P2Pool | Mining | ✅ **Yes** | P2P — p2pool peer connections |
| `18080` | monerod | Node | ✅ **Yes** | P2P network — connects to other Monero nodes |
| `18081` | monerod | Node | ✅ **Yes** | RPC — JSON-RPC API for Gupax and wallets |
| `18083` | monerod | Node | — | ZMQ pub — block notifications for P2Pool (loopback only, `--zmq-pub` flag) |
| `18084` | Tor HS | Tor | — | Hidden service virtual port (Tor routes this internally) |
| `18086` | monerod | Tor | — | `--anonymous-inbound` bind target (Tor routes this internally) |


### Volumes

| Volume | Path | Description |
|---|---|---|
| `gupax-data` | `/home/miner/.local/share/gupax` | Downloaded Gupax binaries (P2Pool, XMRig, monerod) |
| `gupax-state` | `/home/miner/.local/state/gupax` | Gupax configuration and session state |
| `gupax-monero` (or host path) | `/home/miner/.bitmonero` | Monero blockchain data |
| `gupax-tor` | `/home/miner/.tor` | Persistent `.onion` address and Tor data |

### Using an Existing Blockchain

If you have an existing Monero blockchain directory, you can mount it directly.

First start the container to create the volume:

```bash
docker compose up -d
```

Then in the Gupax GUI, go to the **Node tab** and set the database path to:
```
/home/miner/.bitmonero
```

Alternatively, pre-populate the volume before starting:

```bash
# Copy your blockchain to the volume
docker run --rm -v gupax-monero:/data -v /path/to/your/blockchain:/source alpine cp -r /source /data/

# Or use a host directory directly in docker-compose.yml:
# volumes:
#   - /path/to/your/blockchain:/home/miner/.bitmonero
```

#### Ownership Requirements for Existing Blockchain Files

If you mount an existing blockchain from a host directory (not a fresh Docker volume), the container must have **read and write** permission to those files. The container runs Gupax as the user owning the `gupax-data` volume — auto-detected at startup or set via `PUID`/`PGID`.

If the container UID does not match the blockchain file owner, monerod will fail immediately:

```
Node | Stopped ... Uptime was: [1s], Exit status: [Failed]
```

**To check and fix ownership:**

```bash
# 1. Find the container's expected UID/GID
#    Check PUID/PGID env vars in docker-compose.yml or Unraid template.
#    Default on Unraid: 99:100 (nobody:users)

# 2. Check current ownership of your blockchain files
ls -ln /path/to/your/blockchain/lmdb/data.mdb

# 3. Change ownership to match the container (example for Unraid: 99:100)
chown -R 99:100 /path/to/your/blockchain
```

> **⚠️ Unraid FUSE caveat:** If your blockchain is on a **user share** path like `/mnt/user/appdata/...`, `chown` will appear to succeed but have **no effect** — Unraid's FUSE overlay filesystem (shfs) silently ignores ownership changes. Use the **direct disk or cache path** instead:
>
> ```bash
> # Correct — bypasses FUSE:
> chown -R 99:100 /mnt/cache/appdata/gupax/monero
> # or
> chown -R 99:100 /mnt/disk1/appdata/gupax/monero
> ```
>
> Verify from inside the container after changing ownership:
> ```bash
> docker exec gupax stat /home/miner/.bitmonero/lmdb/data.mdb | grep Uid
> # Should show: Uid: (99/nobody) — not 999/miner
> ```

> **Tip:** If you're unsure which UID the container uses, check the startup logs:
> ```
> [*] Running Gupax as UID:99 GID:100
> ```
> Then run `chown -R <UID>:<GID> /path/to/your/blockchain` to match.

---

## 🔐 Security Notes

- The noVNC interface has **no password by default** — set `VNC_AUTH_TOKEN` to enable authentication
- Only expose port 6080 to trusted networks
- For production use, consider adding authentication at the network level

### Unraid FUSE Filesystems (Important)

Unraid uses FUSE (fuse.shfs) for its `appdata` shares, which silently ignores
`chown`. The container detects this at startup and applies **world-writable**
permissions (`chmod a+rwX`) on the Gupax data volume so the container can
write files regardless of the host user ID.

**What this means:** Any process on your Unraid host — or any other
container — can read and write files in `/mnt/user/appdata/gupax/`.
This includes:

- **Mining binaries** (P2Pool, XMRig, monerod) — could be replaced with a
  trojaned version by a compromised container
- **Gupax config** (wallet, node settings) — could be read or modified
- **Tor hidden service keys** — the keys are restricted to root in the
  container, but if you mount their parent directory from a host path on
  a FUSE share, the same world-writable concerns apply

**Mitigations:**
- Keep your Unraid host secure — don't run untrusted containers
- Consider mounting `appdata` from a non-FUSE location (e.g., an SSD cache
  pool with `btrfs` or `xfs`) if security is a concern
- This is a fundamental Unraid limitation, not specific to Gupax-docker —
  any Docker container on Unraid with persistent volumes faces the same
  trade-off

---

## 🐛 Troubleshooting

### Gupax appears blank or black in the browser

Try refreshing the page and waiting 10-20 seconds for Gupax to fully initialize. If the issue persists, restart the container:

```bash
docker compose restart
```

### Connection refused on port 6080

Make sure the container is running:

```bash
docker compose logs
docker compose ps
```

### Container keeps restarting

Check the logs:

```bash
docker compose logs
```

### P2Pool spamming `empty response` / `EBADF` errors

**Symptoms:** Log fills with:
```
JSONRPCRequest uv_poll_start returned error EBADF
P2Pool get_info RPC request to host 127.0.0.1:RPC 18081:ZMQ 18083 failed: Error (empty response)
```

**Root cause:** Gupax v2.0.0+ hides the **Node** tab by default. If the Node was never enabled, **monerod is not running** — but P2Pool (and possibly XMRig/xmrig-proxy) still tries to connect to `127.0.0.1:18081`, producing endless RPC failures.

**Fix:**

1. In the Gupax GUI → **Settings** → **Tabs** → check **Node** → **Save**
2. Go to the **Node** tab → ensure **Node Type** is `Local` and **Port** is `18081`
3. In **Arguments**, add:
   ```bash
   --zmq-pub tcp://127.0.0.1:18083
   ```
   (If you use Tor, also append the Tor args from the container startup banner.)
4. Click **Save**, then **Start**
5. Wait for the Node status to go green (30–120s), then verify P2Pool stops erroring

**Note for auto-start users:** If you previously had Node set to auto-start but the tab was hidden after a config reset or Gupax upgrade, the auto-start setting may also be reset. You must re-enable both the tab visibility AND the auto-start toggle on the Node tab.

---

## 🔗 Official Resources

- [Gupax](https://github.com/hinto-janai/gupax) — The GUI unifying P2Pool & XMRig
- [P2Pool](https://github.com/SChernykh/p2pool) — Decentralized Monero mining pool
- [XMRig](https://github.com/xmrig/xmrig) — High-performance Monero miner
- [Monero](https://www.getmonero.org/) — Private, decentralized cryptocurrency
- [noVNC](https://github.com/novnc/noVNC) — HTML5 VNC client

---

## ⚠️ Disclaimer

**Mining cryptocurrency consumes significant electricity and may not be profitable depending on your hardware, electricity costs, and market conditions.** This project is provided as-is for educational and convenience purposes. Always do your own research before investing in mining hardware or cryptocurrency. The maintainers of this repository are not responsible for any financial losses.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

Gupax, P2Pool, and XMRig are each licensed under their respective licenses — see the official repositories linked above.