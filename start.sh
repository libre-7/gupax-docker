#!/bin/bash
# =============================================================================
# Gupax-docker Startup Script
# Starts Xvfb → openbox → x11vnc → websockify → Gupax
# Optional Tor daemon for monerod-over-Tor (TOR_ENABLED=true)
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================

set -e
set -o pipefail

# Cleanup function — stops all background processes gracefully
cleanup() {
    echo ""
    echo "[*] Shutting down..."
    echo "[*] Stopping Gupax..."
    kill $GUPAX_PID 2>/dev/null || true
    wait $GUPAX_PID 2>/dev/null || true
    echo "[*] Stopping xdg-desktop-portal..."
    kill $PORTAL_PID 2>/dev/null || true
    wait $PORTAL_PID 2>/dev/null || true
    echo "[*] Stopping D-Bus session..."
    kill $DBUS_SESSION_BUS_PID 2>/dev/null || true
    wait $DBUS_SESSION_BUS_PID 2>/dev/null || true
    echo "[*] Stopping websockify..."
    kill $WEBSOCKIFY_PID 2>/dev/null || true
    wait $WEBSOCKIFY_PID 2>/dev/null || true
    echo "[*] Stopping x11vnc..."
    kill $X11VNC_PID 2>/dev/null || true
    wait $X11VNC_PID 2>/dev/null || true
    # Belt-and-suspenders: remove the password temp file on shutdown
    # in case it wasn't cleaned up during startup (e.g., container was killed
    # before the startup-time rm could execute).
    [ -n "$X11VNC_PASSFILE" ] && rm -f "$X11VNC_PASSFILE"
    echo "[*] Stopping openbox..."
    kill $OPENBOX_PID 2>/dev/null || true
    wait $OPENBOX_PID 2>/dev/null || true
    echo "[*] Stopping Tor..."
    kill $TOR_PID 2>/dev/null || true
    wait $TOR_PID 2>/dev/null || true
    echo "[*] Stopping Xvfb..."
    kill $XVFB_PID 2>/dev/null || true
    wait $XVFB_PID 2>/dev/null || true
    echo "[+] Shutdown complete"
}

# Register signal handlers for graceful shutdown
trap cleanup SIGTERM SIGINT SIGQUIT

echo "============================================="
echo "  Gupax-docker — Starting noVNC + Gupax"
echo "============================================="
echo ""
echo "  noVNC:  http://localhost:6080"
echo "  VNC:    localhost:5900"
echo ""
if [ "${TOR_ENABLED:-false}" = "true" ]; then
    echo "  Tor:    ENABLED — tx-only mode (SOCKS5 127.0.0.1:9050)"
    echo "  Note:   P2P sync stays on clearnet. Only transactions use Tor."
    if [ "${MONERO_RPC_RESTRICTED:-true}" = "true" ]; then
        RPC_STATUS="restricted"
    else
        RPC_STATUS="UNRESTRICTED ⚠️"
    fi
    echo "  RPC:    ${RPC_STATUS}"
else
    echo "  Tor:    disabled (set TOR_ENABLED=true to enable)"
fi
echo "============================================="

# Fix volume permissions — container starts as root, no setpriv needed
echo "[*] Fixing data directory permissions..."

# Detect the user to run Gupax as, matching the data volume owner.
# Must happen early — chown below needs to target the correct UID/GID.
PUID=${PUID:-$(stat -c '%u' /home/miner/.local/share/gupax 2>/dev/null || echo "999")}
PGID=${PGID:-$(stat -c '%g' /home/miner/.local/share/gupax 2>/dev/null || echo "999")}

# Pre-create Gupax binary subdirectories on the persistent volume and symlink
# them into /usr/local/bin/gupax/ so Gupax downloads binaries to the volume,
# not to the root-owned, non-persistent image layer.
for dir in p2pool node xmrig xmrig-proxy; do
    mkdir -p /home/miner/.local/share/gupax/$dir
    ln -sfn /home/miner/.local/share/gupax/$dir /usr/local/bin/gupax/$dir
done

# Safety net: Unraid FUSE filesystems (fuse.shfs) silently ignore chown.
# Detect the filesystem type and apply relaxed permissions only when needed.
FS_TYPE=$(stat -f -c '%T' /home/miner/.local/share/gupax 2>/dev/null || echo "unknown")
# Make parent directories traversable (needed for any Docker volume).
chmod a+rx /home/miner /home/miner/.local /home/miner/.local/share 2>/dev/null || true

if [ "$FS_TYPE" = "fuse.shfs" ] || [ "$FS_TYPE" = "fuseblk" ]; then
    # Unraid FUSE: chown is silently ignored, so we resort to world-writable
    # permissions.  This is the only way to make the volume usable when the
    # gosu-dropped UID (e.g. 99) doesn't own the backing files.
    echo "[*] Detected FUSE filesystem ($FS_TYPE) — applying relaxed permissions"
    chmod -R a+rwX /home/miner/.local/share/gupax 2>/dev/null || true
    chmod a+rwX /home/miner/.bitmonero 2>/dev/null || true
else
    # Normal filesystem: chown actually works.
    # Target the gosu-dropped PUID/PGID (detected above), not the image-layer
    # 'miner' user, so Gupax can write as the correct UID.
    echo "[*] Non-FUSE filesystem ($FS_TYPE) — applying standard permissions for UID:$PUID GID:$PGID"
    chown -R "$PUID:$PGID" /home/miner/.local/share/gupax 2>/dev/null || true
    chmod -R u+rwX,go+rX /home/miner/.local/share/gupax 2>/dev/null || true
    chown "$PUID:$PGID" /home/miner/.bitmonero 2>/dev/null || true
    chmod u+rwX,go+rX /home/miner/.bitmonero 2>/dev/null || true
fi

# Display number for Xvfb
DISPLAY_NUM=:1
SCREEN_RESOLUTION=${SCREEN_RESOLUTION:-1920x1080x24}
# Validate format: must be WxHxD with positive integers
if ! echo "$SCREEN_RESOLUTION" | grep -qE '^[0-9]+x[0-9]+x[0-9]+$'; then
    echo "[!] Invalid SCREEN_RESOLUTION '$SCREEN_RESOLUTION' — using default 1920x1080x24"
    SCREEN_RESOLUTION="1920x1080x24"
fi

# ── Tor daemon (optional) ──────────────────────────────────────────────────
# Remove stale signal file from a previous run in case Tor is now disabled;
# the Tor block below re-creates it only if Tor actually starts successfully.
rm -f /home/miner/.tor/tor_enabled
if [ "${TOR_ENABLED:-false}" = "true" ]; then
    echo "[*] Tor is enabled — starting Tor daemon..."

    # Prepare Tor directories with restrictive permissions (required for HS)
    mkdir -p /home/miner/.tor
    chown root:root /home/miner/.tor
    chmod 700 /home/miner/.tor

    # Generate minimal torrc: SOCKS5 outbound proxy + hidden service for monerod
    # Single .onion exposes both P2P (18084) and RPC (18081) on different ports
    cat > /home/miner/.tor/torrc <<'TORRC'
SocksPort 127.0.0.1:9050
DataDirectory /home/miner/.tor
PidFile /home/miner/.tor/tor.pid
HiddenServiceDir /home/miner/.tor/hs_monerod
HiddenServicePort 18084 127.0.0.1:18086
HiddenServicePort 18081 127.0.0.1:18081
TORRC
    chmod 600 /home/miner/.tor/torrc

    /usr/sbin/tor --torrc-file /home/miner/.tor/torrc &
    TOR_PID=$!

    echo "[*] Waiting for Tor SOCKS proxy (127.0.0.1:9050) to be ready..."
    for i in $(seq 1 30); do
        if nc -z 127.0.0.1 9050 2>/dev/null; then
            echo "[+] Tor SOCKS proxy is ready (127.0.0.1:9050)"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "[!] WARNING: Tor SOCKS proxy did not become ready within 30s — continuing anyway"
        else
            sleep 1
        fi
    done

    # ── Hidden Service .onion address ───────────────────────────────────────
    echo "[*] Waiting for hidden service .onion address..."
    HS_HOSTNAME=""
    for i in $(seq 1 30); do
        if [ -f /home/miner/.tor/hs_monerod/hostname ]; then
            HS_HOSTNAME=$(tr -d '[:space:]' < /home/miner/.tor/hs_monerod/hostname 2>/dev/null)
            if [ -n "$HS_HOSTNAME" ]; then
                break
            fi
        fi
        if [ $i -eq 30 ]; then
            echo "[!] WARNING: Hidden service .onion address not generated in time"
        else
            sleep 1
        fi
    done

    if [ -n "$HS_HOSTNAME" ]; then
        echo "[+] Monero .onion: ${HS_HOSTNAME}"
        echo "    │ Wallet RPC:   ${HS_HOSTNAME}:18081"
        echo "    │ P2P inbound:  ${HS_HOSTNAME}:18084"
        echo "    │"
        echo "    │ Connect wallets over Tor:"
        echo "    │   monero-wallet-cli --proxy 127.0.0.1:9050 \\"
        echo "    │     --daemon-address ${HS_HOSTNAME}:18081 \\"
        echo "    │     --trusted-daemon"
        echo "    │"
        echo "    │ Mobile wallets (Cake, Monerujo): add .onion as remote node."
        echo "    │ RPC is restricted — read-only wallet operations, no admin access."
        echo ""
        HS_KEY="${HS_HOSTNAME}"
        echo "[+] Recommended monerod arguments (Gupax → Node → Arguments):"
        if [ "${MONERO_RPC_RESTRICTED:-true}" = "true" ]; then
            echo "    --restricted-rpc"
        fi
        # --rpc-login is not recommended here: Gupax's internal watchdog has
        # no RPC authentication support and will fail (HTTP 401), preventing
        # the Node tab from showing green and blocking P2Pool startup.
        # P2Pool v4.x also rejects --rpc-login=user:pass (= syntax).
        # Use --restricted-rpc for loopback-only RPC access (sufficient here).
        echo "    --tx-proxy=tor,127.0.0.1:9050"
        echo "    --anonymous-inbound=${HS_KEY}:18084,127.0.0.1:18086,40"
        # Persist for reference across container restarts
        echo "Monero .onion: ${HS_HOSTNAME}" > /home/miner/.tor/monerod_onion.txt
        echo "" >> /home/miner/.tor/monerod_onion.txt
        echo "Wallet RPC — connect wallets via Tor:" >> /home/miner/.tor/monerod_onion.txt
        echo "  ${HS_HOSTNAME}:18081" >> /home/miner/.tor/monerod_onion.txt
        echo "" >> /home/miner/.tor/monerod_onion.txt
        echo "Monerod arguments (Gupax → Node → Arguments):" >> /home/miner/.tor/monerod_onion.txt
        if [ "${MONERO_RPC_RESTRICTED:-true}" = "true" ]; then
            echo "  --restricted-rpc" >> /home/miner/.tor/monerod_onion.txt
        fi
        # --rpc-login omitted: Gupax watchdog has no auth support (HTTP 401).
        # --restricted-rpc is sufficient for loopback-only RPC access.
        echo "  --tx-proxy=tor,127.0.0.1:9050" >> /home/miner/.tor/monerod_onion.txt
        echo "  --anonymous-inbound=${HS_KEY}:18084,127.0.0.1:18086,40" >> /home/miner/.tor/monerod_onion.txt
    fi
    # Signal file so the Docker health check knows Tor was started —
    # healthcheck.sh verifies SOCKS proxy :9050 is still alive on each probe.
    touch /home/miner/.tor/tor_enabled
else
    TOR_PID=""
fi

# Remove stale X lock file and socket from previous runs
rm -f /tmp/.X${DISPLAY_NUM#*:}-lock /tmp/.X11-unix/X${DISPLAY_NUM#*:} 2>/dev/null

# Kill any stale Xvfb process still holding the display
for pid in $(pgrep -x Xvfb 2>/dev/null); do
    kill -9 $pid 2>/dev/null && echo "[*] Killed stale Xvfb (PID $pid)" || true
done

# Start Xvfb (virtual framebuffer)
echo "[*] Starting Xvfb on $DISPLAY_NUM..."
Xvfb $DISPLAY_NUM -screen 0 $SCREEN_RESOLUTION -nolisten tcp &
XVFB_PID=$!

# Wait for Xvfb to start
sleep 2

# Verify Xvfb is running
if ! kill -0 $XVFB_PID 2>/dev/null; then
    echo "[ERROR] Xvfb failed to start"
    exit 1
fi
echo "[+] Xvfb started on $DISPLAY_NUM"

# Start openbox (window manager — required for XI2 keyboard focus routing)
echo "[*] Starting openbox..."
openbox &>/dev/null &
OPENBOX_PID=$!
sleep 0.5
if ! kill -0 $OPENBOX_PID 2>/dev/null; then
    echo "[!] openbox failed, retrying..."
    sleep 1
    openbox &>/dev/null &
    OPENBOX_PID=$!
fi
echo "[+] openbox started (PID $OPENBOX_PID)"
sleep 1

# Configure keyboard layout for winit (Gupax's windowing library)
echo "[*] Configuring keyboard layout..."
setxkbmap us 2>/dev/null || echo "[!] setxkbmap failed (non-fatal)"

# Start x11vnc (VNC server sharing Xvfb)
echo "[*] Starting x11vnc on port 5900..."
# VNC authentication — use VNC_AUTH_TOKEN if set, otherwise disable auth.
# Uses -passwdfile instead of -passwd to avoid exposing the password in
# /proc/PID/cmdline and to handle passwords with spaces or special characters.
if [ -n "$VNC_AUTH_TOKEN" ]; then
    X11VNC_PASSFILE=$(mktemp)
    printf '%s' "$VNC_AUTH_TOKEN" > "$X11VNC_PASSFILE"
    echo "[*] VNC authentication: enabled (VNC_AUTH_TOKEN is set)"
    x11vnc -display $DISPLAY_NUM -forever -shared -rfbport 5900 \
        -passwdfile "$X11VNC_PASSFILE" -noxfixes -cursor arrow &
else
    echo "[*] VNC authentication: DISABLED (set VNC_AUTH_TOKEN to enable)"
    x11vnc -display $DISPLAY_NUM -forever -shared -rfbport 5900 \
        -nopw -noxfixes -cursor arrow &
fi
X11VNC_PID=$!
# x11vnc runs asynchronously (& above) — give it time to read the
# passwdfile before we remove it.  x11vnc opens the file once at startup;
# after that the credential doesn't need to sit in /tmp.
sleep 1
[ -n "$X11VNC_PASSFILE" ] && rm -f "$X11VNC_PASSFILE"

# Re-enable X autorepeat that x11vnc disables on client connect (run 3x as x11vnc recommends)
xset r on 2>/dev/null || true
sleep 0.5
xset r on 2>/dev/null || true
sleep 0.5
xset r on 2>/dev/null || true
sleep 1

# Verify x11vnc is running
if ! kill -0 $X11VNC_PID 2>/dev/null; then
    echo "[ERROR] x11vnc failed to start"
    kill $XVFB_PID 2>/dev/null
    exit 1
fi
echo "[+] x11vnc started on port 5900"

# Start noVNC
echo "[*] Starting noVNC on port 6080..."
websockify --web /usr/share/novnc 6080 localhost:5900 &
WEBSOCKIFY_PID=$!

# Re-enable X autorepeat after noVNC connects (x11vnc disables it on client connect)
sleep 2
xset r on 2>/dev/null || true

# Debug: show X keyboard state
echo "[D] Keyboard repeat setting:"
xset q 2>/dev/null | grep -A2 "Keyboard" || echo "[D] xset q failed"

echo "[D] X input devices:"
xinput list 2>/dev/null || echo "[D] xinput failed"

# Verify websockify is running
if ! kill -0 $WEBSOCKIFY_PID 2>/dev/null; then
    echo "[ERROR] websockify failed to start"
    kill $X11VNC_PID $XVFB_PID 2>/dev/null
    exit 1
fi
echo "[+] noVNC started on port 6080"
echo ""
echo "[*] noVNC web interface ready at http://localhost:6080"
echo "[*] Gupax GUI should appear automatically"
echo ""

# Start D-Bus session for file dialog support (zenity, xdg-desktop-portal, etc.)
echo "[*] Starting D-Bus session..."
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
echo "[+] D-Bus session started"

# Start xdg-desktop-portal (file picker backend for GTK/zenity)
echo "[*] Starting xdg-desktop-portal..."
/usr/libexec/xdg-desktop-portal &
PORTAL_PID=$!
echo "[+] xdg-desktop-portal started (PID $PORTAL_PID)"

# Start Gupax — runs as child of this script so cleanup() can manage it
echo "[*] Starting Gupax..."

# PUID/PGID were already detected (or overridden by env vars) during the
# permission-fix block above — no need to rediscover them.
#
# sudo requires the current UID to exist in both /etc/passwd and /etc/shadow.
# A raw 'echo' into passwd has no corresponding shadow entry, so sudo fails:
# "account validation failure, is your account locked?"
# useradd creates both entries properly and accepts the NOPASSWD sudoers rule.
#
# The Dockerfile sudoers rule uses %gupax (group-based).  On many systems
# (Unraid especially) PUID=99/PGID=100 maps to nobody:users / nobody:nogroup,
# so group GID 100 already belongs to a system group.  groupadd -f will
# silently skip the conflicting GID and assign a different numeric ID,
# meaning the new user is NOT a member of the gupax group and sudoers never
# matches.  To fix this we unconditionally add the user to gupax as a
# supplementary group after creation.
if ! getent passwd "$PUID" >/dev/null 2>&1; then
    groupadd -f gupax
    useradd -o -M -u "$PUID" -g "$PGID" -d /home/miner -s /bin/bash gupax 2>/dev/null || {
        # Fallback: useradd failed (e.g., read-only rootfs, no shadow).  At minimum get the
        # user into passwd so the container doesn't crash; XMRig may still fail but won't
        # bring down Gupax itself.
        echo "gupax:x:$PUID:$PGID:Docker user:/home/miner:/bin/bash" >> /etc/passwd
        echo "[!] useradd failed — fallback to /etc/passwd only (XMRig may not start)"
    }
    usermod -a -G gupax gupax 2>/dev/null || true
    echo "[*] Created gupax user (UID $PUID) for pkexec→sudo support"
fi

if command -v gosu >/dev/null 2>&1 && gosu "$PUID:$PGID" true 2>/dev/null; then
    echo "[*] Running Gupax as UID:$PUID GID:$PGID"
    gosu "$PUID:$PGID" env HOME=/home/miner /usr/local/bin/gupax/gupax &
    GUPAX_PID=$!
else
    echo "[*] gosu unavailable — running as current user (rootless Docker?)"
    HOME=/home/miner /usr/local/bin/gupax/gupax &
    GUPAX_PID=$!
fi
echo "[+] Gupax started (PID $GUPAX_PID)"

# Wait specifically for Gupax — other services dying should NOT kill the container.
echo "[*] All services running. Press Ctrl+C to stop."
echo ""
wait $GUPAX_PID
EXIT_CODE=$?

echo ""
echo "[*] Gupax exited (code: $EXIT_CODE)"
cleanup
exit $EXIT_CODE
