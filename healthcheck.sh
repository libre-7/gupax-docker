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

# NoVNC — always required
if ! python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:6080/', timeout=5)" 2>/dev/null; then
    echo "FAIL: noVNC not responding on port 6080"
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
