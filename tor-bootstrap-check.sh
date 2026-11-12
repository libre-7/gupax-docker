#!/bin/bash
# =============================================================================
# Gupax-docker — assert Tor has actually bootstrapped
#
# A listening SocksPort proves nothing: Tor opens :9050 before it has a single
# circuit. This talks to the ControlPort with cookie authentication and requires
# PROGRESS=100 in `GETINFO status/bootstrap-phase` (#GUP-06).
#
# Usage: tor-bootstrap-check.sh [host] [port] [cookie-file]
# Exit:  0 = fully bootstrapped, 1 = not bootstrapped / unreachable / auth error
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -e
set -o pipefail

HOST=${1:-127.0.0.1}
PORT=${2:-9051}
COOKIE=${3:-/home/miner/.tor/control_auth_cookie}

exec python3 - "$HOST" "$PORT" "$COOKIE" <<'PY'
import binascii
import re
import socket
import sys

host, port, cookie_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]

try:
    cookie = open(cookie_path, "rb").read()
except OSError as exc:
    print(f"tor-bootstrap: cannot read control cookie: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    # 3s, not 5s: Docker's HEALTHCHECK --timeout is 5s, and it starts its timer
    # before exec, so a 5s connect timeout would consume the whole budget and be
    # killed at its own deadline — losing the explanatory message (#review L18).
    sock = socket.create_connection((host, port), timeout=3)
except OSError as exc:
    print(f"tor-bootstrap: control port {host}:{port} unreachable: {exc}", file=sys.stderr)
    sys.exit(1)


def send(line):
    sock.sendall(line.encode() + b"\r\n")


def read_reply():
    """Read one Tor control reply, returning its lines.

    Continuation lines use '250-', the final line uses '250 '. A '+' data
    block is not used by the commands below.
    """
    buf = b""
    lines = []
    while True:
        while b"\r\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                raise IOError("control connection closed")
            buf += chunk
        line, buf = buf.split(b"\r\n", 1)
        lines.append(line)
        if len(line) >= 4 and line[3:4] == b" ":
            return lines
        if len(line) >= 4 and line[0:1] in (b"4", b"5"):
            return lines


try:
    send("AUTHENTICATE " + binascii.hexlify(cookie).decode())
    auth = read_reply()
    if not auth[-1].startswith(b"250"):
        print("tor-bootstrap: control authentication failed", file=sys.stderr)
        sys.exit(1)

    send("GETINFO status/bootstrap-phase")
    reply = read_reply()
except (OSError, IOError) as exc:
    print(f"tor-bootstrap: control protocol error: {exc}", file=sys.stderr)
    sys.exit(1)

text = b"\n".join(reply).decode("utf-8", "replace")
match = re.search(r"PROGRESS=(\d+)", text)
if not match:
    print(f"tor-bootstrap: no bootstrap progress in reply: {text}", file=sys.stderr)
    sys.exit(1)

progress = int(match.group(1))
if progress < 100:
    summary = re.search(r'SUMMARY="([^"]*)"', text)
    detail = summary.group(1) if summary else "in progress"
    print(f"tor-bootstrap: {progress}% — {detail}", file=sys.stderr)
    sys.exit(1)

print("tor-bootstrap: 100% — circuit ready")
sys.exit(0)
PY
