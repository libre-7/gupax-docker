# Unraid Docker Templates

This directory contains the Docker template XML file for installing **Gupax-docker** on [Unraid](https://unraid.net/) via the [Community Applications](https://forums.unraid.net/topic/38582-plug-in-community-applications/) plugin.

The image is published to both:
- **GitHub Container Registry**: [ghcr.io/libre-7/gupax-docker](https://github.com/libre-7/gupax-docker/pkgs/container/gupax-docker) — this is what the template pulls (`<Repository>`)
- **Docker Hub**: [libre7/gupax-docker](https://hub.docker.com/r/libre7/gupax-docker) — identical image, published in the same CI run

## How to Use

### Option 1: Community Applications (Recommended)

Once this template is merged into the [Unraid Docker Template Repository](https://github.com/selfhosters/unRAID-CA-templates), you can install Gupax-docker directly from the Unraid Apps tab:

1. Open **Apps** tab in Unraid
2. Search for **"gupax"** or **"monero mining"**
3. Click **Install**
4. Set SCREEN_RESOLUTION if needed (default: 1920x1080x24)
5. Click **Apply** and start mining!

### Option 2: Manual Installation

If the template is not yet in the Community Applications store, you can install it manually by placing the XML on your Unraid USB flash drive:

1. Download the template onto the flash drive:
   ```bash
   # From Unraid terminal:
   wget -O /boot/config/plugins/dockerMan/templates-user/my-gupax-docker.xml \
     https://raw.githubusercontent.com/libre-7/gupax-docker/main/templates/gupax-docker.xml
   ```
2. Go to the **Docker** tab in your Unraid web UI
3. Click **Add Container**
4. Select **"my-gupax-docker"** from the **Template** dropdown
5. Review settings (adjust SCREEN_RESOLUTION if needed) and click **Apply**

## Configuration

| Field | Required | Default | Description |
|---|---|---|---|
| `SCREEN_RESOLUTION` | No | `1920x1080x24` | Display resolution for Gupax GUI |

## Accessing the GUI

The container runs a **noVNC web interface** — no X11 or VNC client needed:

- Open your browser to: `http://<your-unraid-ip>:6080`
- Click **Connect** on the noVNC page — no password required by default
- The Gupax GUI will appear in your browser

## Ports

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

## Volumes

The template creates three persistent directories under `/mnt/user/appdata/gupax/`.

Unraid uses host directory paths; `docker compose` uses named volumes.
The data is the same — only the storage mechanism differs.

| Unraid directory | Container path | Compose named volume |
|------------------|----------------|---------------------|
| `share/` | `/home/miner/.local/share/gupax` | `gupax-data` |
| `monero/` | `/home/miner/.bitmonero` | `gupax-monero` |
| `tor/` | `/home/miner/.tor` | `gupax-tor` |

## Using an Existing Blockchain

If you already have a Monero blockchain synced:

1. Start the container once so the volume is created
2. Copy your blockchain to `/mnt/user/appdata/gupax/monero/`
3. In the Gupax GUI, go to the **Node tab** and set the database path to:
   ```
   /home/miner/.bitmonero
   ```

## Resource Limits

The template sets recommended limits of **4GB RAM** and **2 CPU cores**. Adjust these in the template if needed.

## Submitting to Community Applications

To have this template included in the official Unraid Community Applications store, submit a PR to:

- [selfhosters/unRAID-CA-templates](https://github.com/selfhosters/unRAID-CA-templates)

Include the template XML file and the repository URL in your PR.
