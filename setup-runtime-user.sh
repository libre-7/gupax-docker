#!/bin/bash
# =============================================================================
# Gupax-docker — runtime user/group setup
#
# Resolves the UID/GID that Gupax will run as and guarantees that:
#   1. the `gupax` group exists (used for group-owned volume permissions), and
#   2. the runtime principal exists in /etc/passwd and is a member of `gupax`.
#
# Why this is a separate script (#GUP-01): the previous inline block only ran
# when `getent passwd "$PUID"` failed. The image's default user is `miner` at
# UID 999, so on every documented default path (compose pins PUID=999, the
# fresh-volume fallback is 999) the block was skipped entirely and no `gupax`
# group was ever created. A second bug hit custom IDs: `useradd -g "$PGID"`
# fails when that GID has no group entry (the common 1000:1000 case).
#
# This script is idempotent: start.sh calls it once per container start, and
# the CI matrix test calls it directly for 999/999, 99/100 and 1000/1000.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -e
set -o pipefail

# Default to the image's `miner` account rather than a literal UID: the
# Dockerfile creates it with `useradd -r`, so the number is not contractual.
PUID=${PUID:-$(id -u miner 2>/dev/null || echo 999)}
PGID=${PGID:-$(id -g miner 2>/dev/null || echo 999)}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

# Numeric and non-root. `gosu` accepts arbitrary numeric IDs, but an empty or
# malformed value silently becomes UID 0 in some code paths — refuse it here.
case "$PUID" in
    '' | *[!0-9]*) die "PUID must be a positive integer (got '$PUID')" ;;
esac
case "$PGID" in
    '' | *[!0-9]*) die "PGID must be a positive integer (got '$PGID')" ;;
esac
[ "$PUID" -ge 1 ] || die "PUID must be >= 1 (refusing to run the mining stack as root)"
[ "$PGID" -ge 1 ] || die "PGID must be >= 1"

# The group always exists, on every path. Volume permissions on FUSE mounts
# are granted through it (see the FUSE branch in start.sh).
groupadd -f gupax 2>/dev/null || true
getent group gupax >/dev/null 2>&1 || die "could not create the gupax group"

# `|| true`: getent exits 2 when the ID is absent, and pipefail+set -e would
# abort here before the creation branch below ever runs.
RUN_AS_USER=$(getent passwd "$PUID" | cut -d: -f1 || true)

if [ -z "$RUN_AS_USER" ]; then
    # Resolve the primary group. `useradd -g "$PGID"` requires an existing
    # group entry; when the host GID is not present in the image, create one.
    RUN_AS_GROUP=$(getent group "$PGID" | cut -d: -f1 || true)
    if [ -z "$RUN_AS_GROUP" ]; then
        groupadd -g "$PGID" gupax-run 2>/dev/null || true
        RUN_AS_GROUP=$(getent group "$PGID" | cut -d: -f1 || true)
        [ -n "$RUN_AS_GROUP" ] || die "could not create a group for GID $PGID"
    fi

    # Reuse the `gupax` name only when it is free. Restarting an existing
    # container with a *different* PUID must not resolve back to the old
    # account (and its old UID).
    NEW_USER=gupax
    if getent passwd gupax >/dev/null 2>&1; then
        NEW_USER="gupax-$PUID"
    fi

    if useradd -o -M -u "$PUID" -g "$RUN_AS_GROUP" -d /home/miner \
        -s /bin/bash "$NEW_USER" 2>/dev/null; then
        RUN_AS_USER=$NEW_USER
    else
        # Read-only /etc or missing shadow tooling. Write both databases: a
        # passwd entry alone has no shadow entry and breaks account lookups.
        if ! grep -q "^${NEW_USER}:" /etc/passwd 2>/dev/null; then
            echo "${NEW_USER}:x:$PUID:$PGID:Docker user:/home/miner:/bin/bash" >>/etc/passwd
        fi
        if [ -w /etc/shadow ] && ! grep -q "^${NEW_USER}:" /etc/shadow 2>/dev/null; then
            echo "${NEW_USER}:*:19000:0:99999:7:::" >>/etc/shadow
        fi
        RUN_AS_USER=$NEW_USER
        echo "[!] useradd failed — wrote /etc/passwd and /etc/shadow directly" >&2
    fi
fi

# The default path (UID 999 = miner) and Unraid's 99 both already have a
# passwd entry, so membership must be granted unconditionally.
usermod -a -G gupax "$RUN_AS_USER" 2>/dev/null || true
if ! id -nG "$RUN_AS_USER" 2>/dev/null | tr ' ' '\n' | grep -qx gupax; then
    die "user '$RUN_AS_USER' (UID $PUID) is not a member of the gupax group"
fi

echo "[+] Runtime user: $RUN_AS_USER (UID $PUID, GID $PGID), member of gupax"
