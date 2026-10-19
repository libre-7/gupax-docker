#!/usr/bin/env python3
"""Cross-surface runtime contract checks for gupax-docker.

The project ships the same runtime contract in four places: Dockerfile,
docker-compose.yml, templates/gupax-docker.xml, and the CI smoke test. Each
file reads as correct on its own, so drift is only visible when they are
compared. This script is the comparison (#GUP-02/03/07/09/10/17/19/21).

Run locally:  python3 .github/scripts/verify-runtime-contract.py
Exit:         0 = all checks pass, 1 = at least one failure
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

failures: list[str] = []
passes: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        passes.append(name)
        print(f"PASS: {name}")
    else:
        failures.append(f"{name}: {detail}" if detail else name)
        print(f"FAIL: {name}" + (f" — {detail}" if detail else ""))


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


compose = text("docker-compose.yml")
template = text("templates/gupax-docker.xml")
dockerfile = text("Dockerfile")
start = text("start.sh")
healthcheck = text("healthcheck.sh")
pr_tests = text(".github/workflows/pr-tests.yml")

# --------------------------------------------------------------------------
# GUP-02 — every user-facing variable is interpolated from .env
# --------------------------------------------------------------------------
for var, default in [
    ("TOR_ENABLED", "false"),
    ("TOR_EXPOSE_RPC", "false"),
    ("PUID", "999"),
    ("PGID", "999"),
    ("VNC_AUTH_TOKEN", ""),
    ("MONERO_RPC_RESTRICTED", "true"),
    ("SCREEN_RESOLUTION", "1920x1080x24"),
]:
    needle = f'${{{var}:-{default}}}'
    check(
        f"compose interpolates {var}",
        needle in compose,
        f"expected {needle} in the environment mapping",
    )

# A hard-coded list item would re-introduce the inert-.env bug.
check(
    "compose has no hard-coded TOR_ENABLED/PUID list entries",
    not re.search(r"^\s*-\s*(TOR_ENABLED|PUID|PGID|VNC_AUTH_TOKEN)=", compose, re.M),
    "literal environment list entries win over .env",
)

# --------------------------------------------------------------------------
# GUP-03 — no unauthenticated VNC published by default
# --------------------------------------------------------------------------
vnc = re.search(
    r'<Config Name="VNC" Target="5900" Type="Port" Default="([^"]*)"', template
)
check("template VNC port defaults to unpublished", bool(vnc) and vnc.group(1) == "",
      "Default must be empty so Unraid does not publish 5900")

check(
    "x11vnc binds loopback when no token is set",
    re.search(r"-nopw[^\n]*-localhost", start) is not None,
    "the no-auth branch must use -nopw -localhost",
)

# --------------------------------------------------------------------------
# GUP-07 / GUP-17 — init + stop timeout in both runtime surfaces
# --------------------------------------------------------------------------
check("compose sets init: true", re.search(r"^\s*init:\s*true\s*$", compose, re.M) is not None)
check("template passes --init", "--init" in template)
check("compose stop_grace_period is 30s", "stop_grace_period: 30s" in compose)
check("template passes --stop-timeout=30", "--stop-timeout=30" in template)

# --------------------------------------------------------------------------
# GUP-09 — capability profile identical in compose, template and CI
# --------------------------------------------------------------------------
compose_caps = set(
    re.findall(r"^\s*-\s*(SETUID|SETGID|DAC_OVERRIDE|FOWNER|CHOWN)\s*$", compose, re.M)
)
template_caps = set(re.findall(r"--cap-add=([A-Z_]+)", template))
ci_caps = set(re.findall(r"--cap-add=([A-Z_]+)", pr_tests))

check("compose cap set is the documented five", compose_caps == {
    "SETUID", "SETGID", "DAC_OVERRIDE", "FOWNER", "CHOWN"}, str(sorted(compose_caps)))
check("template cap set matches compose", template_caps == compose_caps,
      f"template={sorted(template_caps)} compose={sorted(compose_caps)}")
check("CI smoke test cap set matches compose", ci_caps == compose_caps,
      f"ci={sorted(ci_caps)} compose={sorted(compose_caps)}")
check("compose drops ALL capabilities", bool(re.search(r"cap_drop:\s*\n\s*-\s*ALL", compose)))
check("CI smoke test drops ALL capabilities", "--cap-drop=ALL" in pr_tests)

# --------------------------------------------------------------------------
# GUP-10 — one builder only; a second push workflow reintroduces digest drift
# --------------------------------------------------------------------------
builders = sorted(
    p.name for p in (ROOT / ".github/workflows").glob("*.yml")
    if "docker/build-push-action" in p.read_text(encoding="utf-8")
    and re.search(r"^\s*push:\s*true\s*$", p.read_text(encoding="utf-8"), re.M)
)
check("exactly one workflow publishes images", len(builders) == 1, f"found {builders}")

# --------------------------------------------------------------------------
# GUP-19 — OCI provenance labels
# --------------------------------------------------------------------------
check("Dockerfile licence is SPDX GPL-3.0-or-later",
      'org.opencontainers.image.licenses="GPL-3.0-or-later"' in dockerfile)
check("Dockerfile has revision label", "org.opencontainers.image.revision=" in dockerfile)
check("Dockerfile has created label", "org.opencontainers.image.created=" in dockerfile)

# --------------------------------------------------------------------------
# GUP-21 — internal probe timeout below Docker's probe timeout
# --------------------------------------------------------------------------
internal = re.search(r"urlopen\([^\n]*timeout=(\d+)", healthcheck)
docker_timeout = re.search(r"--timeout=(\d+)s", dockerfile)
check("healthcheck internal timeout is parseable", internal is not None)
check("Docker HEALTHCHECK timeout is parseable", docker_timeout is not None)
if internal and docker_timeout:
    check("healthcheck internal timeout < Docker probe timeout",
          int(internal.group(1)) < int(docker_timeout.group(1)),
          f"internal={internal.group(1)}s docker={docker_timeout.group(1)}s")

# --------------------------------------------------------------------------
# Template variable coverage — every env var start.sh reads must be settable
# --------------------------------------------------------------------------
for var in ["TOR_ENABLED", "TOR_EXPOSE_RPC", "VNC_AUTH_TOKEN", "PUID", "PGID",
            "MONERO_RPC_RESTRICTED", "SCREEN_RESOLUTION"]:
    check(f"template exposes {var}", f'Target="{var}"' in template)

# --------------------------------------------------------------------------
print()
print(f"RESULT: {len(passes)} passed, {len(failures)} failed")
if failures:
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)
sys.exit(0)
