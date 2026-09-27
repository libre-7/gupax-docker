#!/bin/bash
# =============================================================================
# Gupax-docker Health Check
# Verifies noVNC is reachable and Tor (if enabled) is healthy.
# Called by Docker HEALTHCHECK every 30s.
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================

set -e
set -o pipefail

# noVNC — always required. This probes websockify's static file server,
# which is NOT sufficient on its own: it keeps serving index.html after
# x11vnc dies, leaving a "healthy" container with a black GUI. The VNC
# probe below is what actually catches a dead VNC stack.
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:6080/', timeout=5)" 2>/dev/null; then
    echo "FAIL: noVNC not responding on port 6080"
    exit 1
fi

# VNC — the real GUI path (websockify proxies WebSocket connections here).
# Without this probe a dead x11vnc goes undetected (M1).
if ! nc -z 127.0.0.1 5900 2>/dev/null; then
    echo "FAIL: VNC server (127.0.0.1:5900) not responding — GUI is dead"
    exit 1
fi

# x11vnc process — catches a half-dead state where the port is held open
# by a defunct/hung process rather than a working VNC server.
if ! pgrep -x x11vnc > /dev/null 2>&1; then
    echo "FAIL: x11vnc process not running"
    exit 1
fi

# Gupax — the container's purpose. start.sh waits on the Gupax PID, so if
# Gupax has died the container is already on its way out; report it.
if ! pgrep -f gupax/gupax > /dev/null 2>&1; then
    echo "FAIL: Gupax process not running"
    exit 1
fi

# Tor — only checked when enabled at startup
if [ -f /home/miner/.tor/tor_enabled ]; then
    if ! nc -z 127.0.0.1 9050 2>/dev/null; then
        echo "FAIL: Tor SOCKS proxy (127.0.0.1:9050) not responding — daemon may have died"
        exit 1
    fi
fi

exit 0
