#!/bin/bash
# =============================================================================
# Gupax-docker Health Check
# Verifies noVNC, the X/VNC stack, Gupax liveness, and Tor bootstrap.
# Called by Docker HEALTHCHECK every 30s.
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================

set -e
set -o pipefail

DISPLAY_NUM=${DISPLAY:-:1}
export DISPLAY="$DISPLAY_NUM"

# noVNC — always required. This probes websockify's static file server,
# which is NOT sufficient on its own: it keeps serving index.html after
# x11vnc dies, leaving a "healthy" container with a black GUI.
#
# Internal timeout is 3s, strictly below Docker's 5s probe timeout (#GUP-21):
# Docker starts its timer before exec, so a 5s urllib timeout could consume
# the entire budget and be killed at its own deadline.
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:6080/', timeout=3)" 2>/dev/null; then
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

# X server — a dead Xvfb makes every GUI probe meaningless. `xset q` is a
# round-trip to the server, not a process check (#GUP-06).
if ! xset q > /dev/null 2>&1; then
    echo "FAIL: X server on $DISPLAY_NUM is not responding"
    exit 1
fi

# Gupax process — the container's purpose. start.sh waits on the Gupax PID, so
# if Gupax has died the container is already on its way out; report it.
GUPAX_PIDS=$(pgrep -f gupax/gupax 2>/dev/null || true)
if [ -z "$GUPAX_PIDS" ]; then
    echo "FAIL: Gupax process not running"
    exit 1
fi

# A SIGSTOPped or zombie Gupax still has a PID and (for STOP) a window. Read
# the process state so "hung" is distinguishable from "running" (#GUP-06).
for pid in $GUPAX_PIDS; do
    state=$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || echo "?")
    case "$state" in
        T | t)
            echo "FAIL: Gupax PID $pid is stopped (state $state)"
            exit 1
            ;;
        Z)
            echo "FAIL: Gupax PID $pid is a zombie"
            exit 1
            ;;
    esac
done

# Gupax window — proves the process has a live X client, not just a PID.
# (A deadlocked event loop can still hold a window; the X probe above plus the
# process-state check cover the cheaper failure modes.)
if [ -z "$(xdotool search --name Gupax 2>/dev/null)" ]; then
    echo "FAIL: no Gupax window on $DISPLAY_NUM"
    exit 1
fi

# Tor — only checked when enabled at startup.
if [ -f /home/miner/.tor/tor_enabled ]; then
    if ! nc -z 127.0.0.1 9050 2>/dev/null; then
        echo "FAIL: Tor SOCKS proxy (127.0.0.1:9050) not responding — daemon may have died"
        exit 1
    fi
    # A listening SocksPort exists at 0% bootstrap. Require a real circuit.
    if ! /usr/local/bin/tor-bootstrap-check.sh 127.0.0.1 9051 \
        /home/miner/.tor/control_auth_cookie; then
        echo "FAIL: Tor has not completed bootstrap"
        exit 1
    fi
fi

exit 0
