#!/bin/bash
# =============================================================================
# Tests for .github/scripts/detect-gupax-version.sh
#
# Runs the real script against fixture JSON through GUPAX_RELEASES_FILE, so the
# selection rules and the newer-non-semver warning (#GUP-22) are pinned without
# network access.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -e
set -o pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/detect-gupax-version.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

# --- fixture 1: newest semver wins, asset resolved from assets[] -------------
cat > "$WORK/semver.json" <<'JSON'
[
  {"tag_name":"v2.0.2","prerelease":false,"published_at":"2026-09-01T00:00:00Z",
   "assets":[{"name":"gupax-v2.0.2-linux-x64.tar.gz"}]},
  {"tag_name":"v2.0.1","prerelease":false,"published_at":"2026-05-01T00:00:00Z",
   "assets":[{"name":"gupax-v2.0.1-linux-x64.tar.gz"}]}
]
JSON
(
    cd "$WORK"
    GUPAX_RELEASES_FILE="$WORK/semver.json" bash "$SCRIPT" >out.log 2>err.log
)
status=$?
grep -q '^VERSION=v2.0.2$' "$WORK/release.env"
report $? "newest semver release selected"
grep -q '^GUPAX_ASSET=gupax-v2.0.2-linux-x64.tar.gz$' "$WORK/release.env"
report $? "asset filename resolved from assets[]"
rc=1
[ "$status" -eq 0 ] && rc=0
report $rc "semver fixture exits 0"

# --- fixture 2: newer non-semver release must warn, not be silent ------------
cat > "$WORK/nonsemver.json" <<'JSON'
[
  {"tag_name":"critical_update_p2pool","prerelease":false,"published_at":"2026-10-01T00:00:00Z",
   "assets":[{"name":"gupax-v2.0.1-linux-x64.tar.gz"}]},
  {"tag_name":"v2.0.1","prerelease":false,"published_at":"2026-05-01T00:00:00Z",
   "assets":[{"name":"gupax-v2.0.1-linux-x64.tar.gz"}]}
]
JSON
(
    cd "$WORK"
    GUPAX_RELEASES_FILE="$WORK/nonsemver.json" bash "$SCRIPT" >out2.log 2>err2.log
)
status=$?
grep -q '^VERSION=v2.0.1$' "$WORK/release.env"
report $? "non-semver release is not selected"
grep -q 'Upstream release skipped' "$WORK/err2.log"
report $? "newer non-semver release emits a warning"
grep -q 'critical_update_p2pool' "$WORK/err2.log"
report $? "warning names the skipped tag"
rc=1
[ "$status" -eq 0 ] && rc=0
report $rc "non-semver fixture still builds with the semver release"

# --- fixture 3: no semver release is a hard failure --------------------------
cat > "$WORK/none.json" <<'JSON'
[
  {"tag_name":"nightly","prerelease":false,"published_at":"2026-10-01T00:00:00Z",
   "assets":[{"name":"gupax-nightly-linux-x64.tar.gz"}]}
]
JSON
set +e
(
    cd "$WORK"
    GUPAX_RELEASES_FILE="$WORK/none.json" bash "$SCRIPT" >out3.log 2>err3.log
)
status=$?
set -e
[ "$status" -ne 0 ]
report $? "no semver release exits non-zero"
grep -q 'no non-prerelease semver release' "$WORK/err3.log"
report $? "no semver release explains why"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
