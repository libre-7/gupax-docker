#!/usr/bin/env bash
# =============================================================================
# Detect Gupax upstream release for image tagging.
#
# Problem this solves (#68 / C1): upstream published a non-semver tag
# ("critical_update_p2pool") as the newest release. Blindly feeding that
# tag_name into the Dockerfile constructed a 404 asset URL and froze both
# registries for months. This script instead:
#   1. Picks the newest NON-prerelease release whose tag matches
#      ^v[0-9]+\.[0-9]+\.[0-9]+$ (semver "v" tags only).
#   2. Resolves the actual Linux x64 tarball filename from that release's
#      assets[] — never constructs one from the tag name.
#   3. Fails loudly (exit 1) if no semver release has a matching asset,
#      so a broken upstream state can never silently produce garbage tags.
#
# Output: ./release.env containing VERSION and GUPAX_ASSET.
# The calling workflow step sources this file and exports to GITHUB_ENV.
# Consumed by docker-publish.yml and docker-hub-push.yml (kept in lockstep).
#
# GITHUB_TOKEN (optional): used as Bearer auth for the GitHub API to avoid
# unauthenticated rate limits on shared CI runner IPs. Falls back to
# anonymous access when unset (e.g. local runs).
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -euo pipefail

API_URL="https://api.github.com/repos/gupax-io/gupax/releases"
AUTH_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

# Fail fast on API errors instead of half-parsing a rate-limit page.
# per_page=100: every upstream release in one request, so old releases can
# never crowd the newest semver tag off the first page.
RESPONSE=$(curl -fsSL "${AUTH_ARGS[@]}" "${API_URL}?per_page=100") || {
    echo "ERROR: GitHub API request failed" >&2
    exit 1
}

# The API response can exceed the per-argument size limit (128 KiB on Linux),
# so it is passed via a temp file instead of argv.
JSON_FILE=$(mktemp)
trap 'rm -f "$JSON_FILE"' EXIT
printf '%s' "$RESPONSE" > "$JSON_FILE"

# Newest non-prerelease semver release with a Linux x64 tarball asset.
python3 - "$JSON_FILE" <<'PYEOF' > release.env
import json, sys, re

try:
    with open(sys.argv[1]) as f:
        releases = json.load(f)
except json.JSONDecodeError as e:
    sys.stderr.write(f"ERROR: GitHub API response was not valid JSON: {e}\n")
    sys.exit(1)

if not isinstance(releases, list):
    # e.g. an API error object such as {"message": "API rate limit exceeded"}
    sys.stderr.write(
        "ERROR: GitHub API did not return a release list (rate limited or "
        f"API change): {str(releases)[:200]}\n")
    sys.exit(1)

semver = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
candidates = [
    r for r in releases
    if not r.get("prerelease") and semver.match(r.get("tag_name", ""))
]
if not candidates:
    sys.stderr.write(
        "ERROR: no non-prerelease semver release found in the first 100 releases\n")
    sys.exit(1)

# /releases is newest-first per GitHub docs, but do not rely on API ordering:
# sort by published_at ourselves (descending) so the newest wins deterministically.
candidates.sort(key=lambda r: r.get("published_at") or "", reverse=True)

chosen = None
for rel in candidates:
    linux_asset = next(
        (a["name"] for a in rel.get("assets", [])
         if re.search(r"linux-x64.*\.tar\.gz$", a.get("name", ""))),
        None,
    )
    if linux_asset:
        chosen = (rel["tag_name"], linux_asset)
        break

if not chosen:
    sys.stderr.write(
        "ERROR: no non-prerelease semver release has a linux-x64 tarball asset\n")
    sys.exit(1)

tag, asset = chosen
print(f"VERSION={tag}")
print(f"GUPAX_ASSET={asset}")
PYEOF

# shellcheck disable=SC1091
. ./release.env
echo "Detected Gupax version: $VERSION"
echo "Linux asset: $GUPAX_ASSET"
