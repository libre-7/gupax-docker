#!/bin/bash
# =============================================================================
# Tests for setup-runtime-user.sh (#GUP-01)
#
# These run WITHOUT root and WITHOUT Docker by putting fake `getent`,
# `groupadd`, `useradd`, `usermod` and `id` binaries first on PATH. They
# exercise the script's branching (which is where the bug lived), not the
# kernel's useradd: the container-level matrix in pr-tests.yml covers the real
# tools.
#
# Regression: with PUID=999 (the image default, `miner`), the old inline block
# was skipped entirely because the UID already existed — no `gupax` group was
# created, so XMRig's `pkexec` wrapper could not prove membership.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# =============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/setup-runtime-user.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
report() {
    if [ "$1" -eq 0 ]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2"
        fail=$((fail + 1))
    fi
}

# Assertions must not run a bare failing command under `set -e`.
check_grep() {
    if grep -q "$1" "$2"; then report 0 "$3"; else report 1 "$3"; fi
}
check_member() {
    if PATH="$BIN:$PATH" id -nG "$1" | tr ' ' '\n' | grep -qx gupax; then
        report 0 "$2"
    else
        report 1 "$2"
    fi
}

# --- fake toolchain ----------------------------------------------------------
BIN="$WORK/bin"
DB="$WORK/db"
mkdir -p "$BIN" "$DB"
export FAKE_DB="$DB"
: >"$DB/passwd"
: >"$DB/group"
: >"$DB/members"

cat >"$BIN/getent" <<'FAKE'
#!/bin/bash
case "$1" in
passwd)
    while IFS=: read -r name uid gid _; do
        if [ "$name" = "$2" ] || [ "$uid" = "$2" ]; then
            printf '%s:x:%s:%s:test:/home/miner:/bin/bash\n' "$name" "$uid" "$gid"
            exit 0
        fi
    done <"$FAKE_DB/passwd"
    exit 2
    ;;
group)
    while IFS=: read -r name gid; do
        if [ "$name" = "$2" ] || [ "$gid" = "$2" ]; then
            printf '%s:x:%s:\n' "$name" "$gid"
            exit 0
        fi
    done <"$FAKE_DB/group"
    exit 2
    ;;
esac
exit 2
FAKE

cat >"$BIN/groupadd" <<'FAKE'
#!/bin/bash
force=0
gid=""
name=""
while [ $# -gt 0 ]; do
    case "$1" in
    -f) force=1; shift ;;
    -g) gid="$2"; shift 2 ;;
    -*) shift ;;
    *) name="$1"; shift ;;
    esac
done
if grep -q "^${name}:" "$FAKE_DB/group" 2>/dev/null; then
    [ "$force" -eq 1 ] && exit 0
    exit 9
fi
[ -n "$gid" ] || gid=$((2000 + $(wc -l <"$FAKE_DB/group")))
echo "${name}:${gid}" >>"$FAKE_DB/group"
FAKE

cat >"$BIN/useradd" <<'FAKE'
#!/bin/bash
uid=""
gid=""
name=""
while [ $# -gt 0 ]; do
    case "$1" in
    -o | -M) shift ;;
    -u) uid="$2"; shift 2 ;;
    -g) gid="$2"; shift 2 ;;
    -d | -s) shift 2 ;;
    *) name="$1"; shift ;;
    esac
done
# Real useradd refuses a -g that has no group entry: reproduce that.
getent group "$gid" >/dev/null 2>&1 || exit 6
getent passwd "$name" >/dev/null 2>&1 && exit 9
echo "${name}:${uid}:${gid}:test" >>"$FAKE_DB/passwd"
FAKE

cat >"$BIN/usermod" <<'FAKE'
#!/bin/bash
while [ $# -gt 0 ]; do
    case "$1" in
    -a) shift ;;
    -G) grp="$2"; shift 2 ;;
    *) user="$1"; shift ;;
    esac
done
grep -qx "${user}:${grp}" "$FAKE_DB/members" 2>/dev/null ||
    echo "${user}:${grp}" >>"$FAKE_DB/members"
FAKE

cat >"$BIN/id" <<'FAKE'
#!/bin/bash
[ "$1" = "-nG" ] || exit 1
user="$2"
entry=$(getent passwd "$user") || exit 1
gid=$(echo "$entry" | cut -d: -f3)
out=$(getent group "$gid" | cut -d: -f1)
while IFS=: read -r u g; do
    [ "$u" = "$user" ] && out="$out $g"
done <"$FAKE_DB/members"
echo "$out"
FAKE

chmod +x "$BIN"/*

reset_db() {
    printf 'root:0:0:root\nminer:999:999:miner\nnobody:99:100:nobody\n' >"$DB/passwd"
    printf 'root:0\nminer:999\nusers:100\nnogroup:65534\n' >"$DB/group"
    : >"$DB/members"
}

run_setup() {
    PATH="$BIN:$PATH" PUID="$1" PGID="$2" bash "$SCRIPT" >"$WORK/out.log" 2>&1
}

# --- 1. default 999 (the regression) ----------------------------------------
reset_db
if run_setup 999 999; then
    check_grep '^\[+\] Runtime user: miner' "$WORK/out.log" \
        "999/999 resolves to the existing miner user"
    check_member miner "999/999: miner is a member of gupax"
else
    report 1 "999/999 setup exits 0"
fi

# --- 2. Unraid 99/100 --------------------------------------------------------
reset_db
if run_setup 99 100; then
    check_member nobody "99/100: nobody is a member of gupax"
else
    report 1 "99/100 setup exits 0"
fi

# --- 3. custom 1000/1000 (no passwd or group entry) --------------------------
reset_db
if run_setup 1000 1000; then
    check_member gupax "1000/1000: user created and joined gupax"
    check_grep '^gupax-run:1000' "$DB/group" \
        "1000/1000: missing primary group was created"
else
    report 1 "1000/1000 setup exits 0"
fi

# --- 4. restart with a changed PUID must not reuse the old account -----------
reset_db
echo 'gupax:1000:1000:test' >>"$DB/passwd"
if run_setup 1001 1001; then
    check_member gupax-1001 \
        "changed PUID creates gupax-1001 (not the stale gupax account)"
else
    report 1 "changed PUID setup exits 0"
fi

# --- 5. invalid input fails closed ------------------------------------------
reset_db
if run_setup notanumber 999; then
    report 1 "non-numeric PUID is rejected"
else
    report 0 "non-numeric PUID is rejected"
fi

reset_db
if run_setup 0 999; then
    report 1 "PUID 0 (root) is rejected"
else
    report 0 "PUID 0 (root) is rejected"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "RESULT: all runtime-user tests passed"
    exit 0
fi
echo "RESULT: $fail test(s) failed"
exit 1
