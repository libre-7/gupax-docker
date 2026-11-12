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
# GITHUB_TOKEN: used as Bearer auth for the GitHub API to avoid
# unauthenticated rate limits on shared CI runner IPs. Both registry
# workflows export secrets.GITHUB_TOKEN to the step that calls this script
# (see #73 / M4 — it was documented but never wired, so the branch below
# never executed in CI). Falls back to anonymous access when unset, which
# is only appropriate for local runs.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2024-2026  libre-7
# =============================================================================
set -euo pipefail

API_URL="https://api.github.com/repos/gupax-io/gupax/releases"

# The token is passed as a header read from stdin, never on the command line:
# curl's argv is world-readable in /proc/<pid>/cmdline, and this project's own
# rule is that secrets do not go there. GitHub tokens are [A-Za-z0-9_], so the
# header needs no further escaping.
gh_api() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" \
            | curl -fsSL -H @- "$1"
    else
        curl -fsSL "$1"
    fi
}

# Fail fast on API errors instead of half-parsing a rate-limit page.
# per_page=100: every upstream release in one request, so old releases can
# never crowd the newest semver tag off the first page.
#
# GUPAX_RELEASES_FILE is a test seam: .github/scripts/test-detect-version.sh
# feeds fixture JSON through it, so the selection and warning logic is pinned
# without hitting the network (#GUP-22).
if [ -n "${GUPAX_RELEASES_FILE:-}" ]; then
    RESPONSE=$(cat "$GUPAX_RELEASES_FILE") || {
        echo "ERROR: could not read GUPAX_RELEASES_FILE=$GUPAX_RELEASES_FILE" >&2
        exit 1
    }
else
    RESPONSE=$(gh_api "${API_URL}?per_page=100") || {
        echo "ERROR: GitHub API request failed" >&2
        exit 1
    }
fi

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
        chosen = (rel, linux_asset)
        break

if not chosen:
    sys.stderr.write(
        "ERROR: no non-prerelease semver release has a linux-x64 tarball asset\n")
    sys.exit(1)

rel, asset = chosen
tag = rel["tag_name"]

# #GUP-22: a newer release under a non-semver tag is deliberately skipped
# (the #68/C1 fix), but skipping it silently reintroduces the class of bug
# where a real upstream fix never reaches the image. Emit a GitHub annotation
# and a plain warning so the condition is visible in the Actions summary.
chosen_published = rel.get("published_at") or ""
newer_nonsemver = sorted(
    (
        r for r in releases
        if not r.get("prerelease")
        and not semver.match(r.get("tag_name", ""))
        and (r.get("published_at") or "") > chosen_published
    ),
    key=lambda r: r.get("published_at") or "",
)
for skipped in newer_nonsemver:
    sys.stderr.write(
        f"::warning title=Upstream release skipped::"
        f"{skipped.get('tag_name')} was published after {tag} but is not a "
        f"semver tag. The image keeps {tag}; check whether it contains a "
        f"security fix.\n"
    )

print(f"VERSION={tag}")
print(f"GUPAX_ASSET={asset}")
PYEOF

# shellcheck disable=SC1091
. ./release.env
echo "Detected Gupax version: $VERSION"
echo "Linux asset: $GUPAX_ASSET"
