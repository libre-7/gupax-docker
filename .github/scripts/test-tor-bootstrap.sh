#!/bin/bash
# =============================================================================
# Tests for tor-bootstrap-check.sh (#GUP-06)
#
# A fake Tor ControlPort speaks just enough of the protocol to exercise the
# probe without a Tor daemon or a container:
#   - PROGRESS=100        -> exit 0
#   - PROGRESS=50         -> exit 1
#   - bad authentication  -> exit 1
#   - missing cookie      -> exit 1
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -e
set -o pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CHECK="$ROOT/tor-bootstrap-check.sh"
WORK=$(mktemp -d)
SERVER_PID=""
trap 'rm -rf "$WORK"; [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true' EXIT

pass=0
fail=0
report() {
    if [ "$1" -eq 0 ]; then
        echo "PASS: $2"
        pass=$((pass + 1))
    else
        echo "FAIL: $2"
        fail=$((fail + 1))
    fi
}

cat > "$WORK/fake_tor.py" <<'PY'
import socket
import sys

mode, portfile = sys.argv[1], sys.argv[2]
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(1)
srv.settimeout(10)
with open(portfile, "w", encoding="utf-8") as fh:
    fh.write(str(srv.getsockname()[1]))

try:
    conn, _ = srv.accept()
except socket.timeout:
    sys.exit(0)
stream = conn.makefile("rwb")

line = stream.readline()
if line.startswith(b"AUTHENTICATE "):
    if mode == "badauth":
        stream.write(b"515 Authentication failed\r\n")
        stream.flush()
        conn.close()
        sys.exit(0)
    stream.write(b"250 OK\r\n")
    stream.flush()

line = stream.readline()
if line.startswith(b"GETINFO status/bootstrap-phase"):
    progress = 100 if mode == "100" else 50
    stream.write(
        (
            f'250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS={progress} '
            f'TAG=test SUMMARY="test circuit"\r\n'
        ).encode()
    )
    stream.write(b"250 OK\r\n")
    stream.flush()

conn.close()
PY

run_case() {
    mode=$1
    name=$2
    portfile="$WORK/port-$mode"
    rm -f "$portfile"
    python3 "$WORK/fake_tor.py" "$mode" "$portfile" &
    SERVER_PID=$!
    for _ in $(seq 1 50); do
        [ -s "$portfile" ] && break
        sleep 0.1
    done
    if [ ! -s "$portfile" ]; then
        echo "FAIL: fake Tor server did not publish a port ($name)"
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
        CASE_RC=99
        return 0
    fi
    port=$(cat "$portfile")
    if timeout 15 "$CHECK" 127.0.0.1 "$port" "$WORK/cookie" >"$WORK/$mode.out" 2>&1; then
        CASE_RC=0
    else
        CASE_RC=$?
    fi
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    echo "--- $mode (exit $CASE_RC) ---"
    cat "$WORK/$mode.out"
    return 0
}

printf '0123456789abcdef0123456789abcdef' > "$WORK/cookie"

set +e
run_case 100 "bootstrapped"
report $((CASE_RC == 0 ? 0 : 1)) "PROGRESS=100 exits 0"
grep -q '100% — circuit ready' "$WORK/100.out"
report $? "PROGRESS=100 is reported as ready"

run_case 50 "partial"
report $((CASE_RC != 0 ? 0 : 1)) "PROGRESS=50 exits non-zero"
grep -q '50%' "$WORK/50.out"
report $? "partial bootstrap reports its progress"

run_case badauth "badauth"
report $((CASE_RC != 0 ? 0 : 1)) "authentication failure exits non-zero"
grep -q 'authentication failed' "$WORK/badauth.out"
report $? "authentication failure is explained"

"$CHECK" 127.0.0.1 1 "$WORK/does-not-exist" >"$WORK/nocookie.out" 2>&1
rc=$?
set -e
report $((rc != 0 ? 0 : 1)) "missing cookie exits non-zero"
grep -q 'cannot read control cookie' "$WORK/nocookie.out"
report $? "missing cookie is explained"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
