#!/usr/bin/env python3
"""
Sync the repository README to Docker Hub's `full_description` (#73 / M5).

Why this exists
---------------
Docker Hub's repository page and the GitHub README are two separate
artifacts. Nothing propagates between them: the README casing fix from
#68 / L1 landed in the repository but the published page kept serving
pre-fix text for over a month, and #68 / L5 (Docker Hub description
drift) was listed in the review and never actioned. A one-time manual
PATCH would fix today's drift and guarantee the next one, so the sync
runs in CI on every push to main instead.

Docker Hub API notes (see the project skill's docker-hub-api reference):
  * The v2 API requires a JWT, not the PAT itself. Log in at
    /v2/users/login/ to exchange the token for a short-lived JWT.
  * `full_description` stores raw Markdown. Docker Hub renders tables,
    code blocks and headings, so the README is sent verbatim — no
    stripping.
  * The repository model has NO `license` key for community accounts, so
    PATCHing one is silently ignored. The license is conveyed by the
    README's badge and License section; the authoritative copy is the
    Dockerfile's OCI label. Do not add it here.

Usage:
    DOCKERHUB_USERNAME=… DOCKERHUB_TOKEN=… python3 sync-docker-hub-description.py

Exit codes:
    0  synced, or already identical (no-op)
    1  failure — the caller decides whether that is fatal
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

NAMESPACE = "libre7"
REPO = "gupax-docker"
GITHUB_REPO = "libre-7/gupax-docker"
DH_URL = f"https://hub.docker.com/v2/repositories/{NAMESPACE}/{REPO}/"
LOGIN_URL = "https://hub.docker.com/v2/users/login/"
GH_README_URL = f"https://api.github.com/repos/{GITHUB_REPO}/readme"


def die(msg, detail=None):
    print(f"ERROR: {msg}", file=sys.stderr)
    if detail:
        print(detail, file=sys.stderr)
    sys.exit(1)


def fetch_readme(token):
    """Return the README markdown, preferring the checked-out file."""
    # In CI the repo is already checked out; use it so the sync publishes
    # exactly what was just committed (no extra API call, no base64 dance).
    if os.path.isfile("README.md"):
        with open("README.md", encoding="utf-8") as fh:
            return fh.read()

    # Fallback for running outside a checkout.
    req = urllib.request.Request(
        GH_README_URL, headers={"Accept": "application/vnd.github.v3.raw"}
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.URLError as exc:
        die("could not fetch README", str(exc))
    try:
        return base64.b64decode(raw).decode("utf-8")
    except Exception:  # already-decoded raw response
        return raw.decode("utf-8")


def login(username, token):
    body = json.dumps({"username": username, "password": token}).encode()
    req = urllib.request.Request(
        LOGIN_URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())["token"]
    except urllib.error.HTTPError as exc:
        die(
            f"Docker Hub login failed (HTTP {exc.code})",
            exc.read().decode("utf-8", "replace")[:300],
        )
    except urllib.error.URLError as exc:
        die("Docker Hub login request failed", str(exc))


def get_current(jwt):
    req = urllib.request.Request(DH_URL, headers={"Authorization": f"Bearer {jwt}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.URLError as exc:
        die("could not read current Docker Hub description", str(exc))


def patch_description(jwt, markdown):
    body = json.dumps({"full_description": markdown}).encode()
    req = urllib.request.Request(
        DH_URL,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {jwt}"},
        method="PATCH",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        die(
            f"Docker Hub PATCH failed (HTTP {exc.code})",
            exc.read().decode("utf-8", "replace")[:300],
        )
    except urllib.error.URLError as exc:
        die("Docker Hub PATCH request failed", str(exc))


def main():
    username = os.environ.get("DOCKERHUB_USERNAME")
    token = os.environ.get("DOCKERHUB_TOKEN")
    if not username or not token:
        die("DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must be set")

    markdown = fetch_readme(token)
    jwt = login(username, token)
    current = get_current(jwt).get("full_description") or ""

    if current.strip() == markdown.strip():
        print("Docker Hub description already in sync — no change needed")
        return 0

    print(
        f"Description drift detected: Docker Hub has {len(current)} chars, "
        f"README has {len(markdown)} chars — syncing"
    )
    status = patch_description(jwt, markdown)
    print(f"Docker Hub description synced (HTTP {status}, {len(markdown)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
