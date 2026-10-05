# Contributing to gupax-docker

Thanks for contributing! This document covers how to submit changes,
what gets tested, and the conventions in use.

## Quick start

1. Fork the repo and clone it
2. Create a branch: `fix/descriptive-name` or `feat/descriptive-name`
3. Make your changes
4. Push and open a PR against `main`

That's it. CI will lint your changes and run a smoke test automatically.

## What CI checks

Every PR runs through `pr-tests.yml`:

- **ShellCheck** — catches bugs in shell scripts
- **Hadolint** — Dockerfile best practices
- **YAML lint** — workflow and compose syntax
- **Smoke test** — builds the image and verifies the container starts
  with Gupax running and Tor operational

PRs that only touch docs (README, CHANGELOG, templates) still trigger CI
because linting and smoke testing are cheap and catch regressions.

## Commit messages

Use conventional commit prefixes:

```
fix: describe what was broken and how it's fixed
feat: describe the new capability
docs: documentation only
```

Reference issues in the body (`Refs #N`) rather than the subject line.
Use `Closes #N` only after the fix is confirmed on Unraid production.

## Branch naming

```
fix/env-var-naming-mismatch
feat/tor-health-check
docs/port-table-consolidation
```

Hyphens, lowercase, descriptive.

## Issue lifecycle

All issues follow this flow:

```
Investigate → Present findings → Get approval → Implement → VM test → Unraid test → Close
```

- **VM test** is a build/startup smoke test at `192.168.1.127`. It confirms
  the image builds and the container starts — not that everything works
  end-to-end.
- **Unraid test** is the final verification. The project maintainer runs the
  change on their Unraid production server before any issue is closed.
- **CI-only changes** (workflow files, lint configs) and **docs-only changes**
  skip Unraid testing.

Never close an issue based on a VM test alone. The user always tests on
Unraid first.

## Dockerfile conventions

- Base image is digest-pinned (`ubuntu:26.04@sha256:...`)
- All `RUN` commands use bash with `pipefail` (global `SHELL` directive)
- `apt-get install` always includes `--no-install-recommends` and cleanup
  in the same layer (`rm -rf /var/lib/apt/lists/*`)
- Tor is installed from the Tor Project apt repo, not Ubuntu's stale package
- The container starts as root so `start.sh` can fix volume permissions,
  then drops to the `miner` user via `gosu`

## Shell script conventions

- `#!/bin/bash` with `set -e` or `&&` chaining
- SPDX header: `# SPDX-License-Identifier: GPL-3.0-or-later`
- Graceful shutdown via `trap` + `cleanup` function
- No secrets in `/proc/PID/cmdline` (use `-passwdfile`, not `-passwd`)

## Version scheme

- Images are tagged `v{upstream-gupax}-{build-date}` (e.g. `v2.0.1-20260518`)
- The `v2.0.1` base tracks which Gupax is bundled
- The `-20260518` suffix differentiates container builds
- Moving tags (`:latest`, `:v2.0.1`, `:2.0.1`) always point to the latest build

## Registry flow

On merge to `main`, both registries are updated:

```
main commit → GHCR (ghcr.io/libre-7/gupax-docker)
            → Docker Hub (docker.io/libre7/gupax-docker)
```

Feature branches don't push to registries unless explicitly configured.

## Where to find things

| What | Where |
|------|-------|
| Dockerfile | `./Dockerfile` |
| Entrypoint | `./start.sh` |
| Health check | `./healthcheck.sh` |
| Compose config | `./docker-compose.yml` |
| CI workflows | `.github/workflows/` |
| Unraid template | `templates/gupax-docker.xml` |
| Release history | `CHANGELOG.md` |
| Roadmap | `TODO.md` |
| Security policy | `SECURITY.md` |
