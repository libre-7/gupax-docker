# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Versions follow the scheme `v{upstream-gupax}-{build-date}`. The base version
tracks which Gupax release is bundled; the date suffix differentiates container
builds. `v2.0.1` and `v2.0.1-YYYYMMDD` tags are Docker image tags — the
`v`-prefixed tag is a moving tag that always points to the latest build of that
upstream release. `v2.0.1-YYYYMMDD-<sha7>` adds the commit and is the immutable
reference; a same-day rebuild can replace the plain date tag.

## [Unreleased] — 2026-11-11

### Fixed

- **The image could not build: the pinned Tor release was removed upstream**
  (review C1) — `TOR_VERSION` pinned `0.4.9.14-1~resolute+1`, which the Tor
  Project has dropped from the `resolute` pool; the suite now offers only
  `0.4.9.16-1~resolute+1`. `apt-get install tor=<pin>` therefore failed and
  every build aborted at that layer. Bumped to the version in the pool.
- **The Tor version was pinned in two places** (review M3) — `pr-tests.yml`
  compared the container's Tor against a hardcoded `0.4.9.14`, so bumping the
  Dockerfile alone left CI red. The assertion now reads `ARG TOR_VERSION` from
  the Dockerfile, making the pin single-source.
- **Teardown hung when a stop arrived during startup** (review H1) — `cleanup()`
  waited on six services with `wait "$VAR"`. When a PID variable was still
  unset (a SIGTERM during the up-to-75s Tor bootstrap, or before
  Xvfb/websockify/portal started), the empty expansion turned that into a bare
  `wait`, which waits for **every** child of the script — so teardown blocked on
  a live service, burned the full `stop_grace_period`, and the container was
  SIGKILLed and recorded as 137, which reads exactly like an OOM kill. All six
  teardowns now run through `stop_pid`, which returns immediately on an empty
  PID.
- **A graceful stop was recorded as exit 143 and tore down twice** (review M1) —
  the signal trap ran `cleanup`, then the main path ran it again and exited
  with 143, so every `docker stop` looked like a crash and printed a duplicate
  shutdown sequence. `cleanup` is now idempotent, and the signal path exits 0
  with an explicit `Received SIGTERM` line; Gupax's own exit code still
  propagates when it dies by itself. The README's description of the log order
  was inverted and is corrected (review L4). A second signal arriving during
  teardown is now ignored rather than aborting the first one halfway.
- **The GitHub token was visible in `curl`'s argv** (review L9) — the release
  detector passed `Authorization: Bearer …` as a command-line argument, which is
  world-readable in `/proc/<pid>/cmdline` and contradicts this project's own
  rule for secrets. The header is now read from stdin with `-H @-`.
- **A hardcoded UID 999 stood in for the image's `miner` account** (review L10) —
  the Dockerfile creates `miner` with `useradd -r`, so its UID is allocated, not
  fixed. `start.sh`, `setup-runtime-user.sh` and the CI default-UID assertion now
  resolve the account instead of assuming 999.
- **Debug output shipped in the normal startup log** (review L16) — the `[D]` X
  keyboard/input dumps now require `GUPAX_DEBUG=true`.
- **The image redistributed Gupax without its licence text** (review L6) —
  `LICENSE` and `NOTICE` are now copied to `/usr/share/doc/gupax-docker/` and
  `.dockerignore` no longer excludes them. The OCI licence label was metadata
  only, not the licence the GPL requires to accompany a distribution.
- **The Docker Hub description sync never verified its own write** (review M5) —
  a 2xx from the PATCH only means the request was accepted, and this API
  silently ignores fields it does not model. The script now reads
  `full_description` back and fails if the value did not take. The base64
  fallback for the raw README fetch was also wrong (`v3.raw` is plain text) and
  is gone.
- **Concurrent publishes could move `:latest` backwards** (review M6) — two
  pushes to main built in parallel and raced on the tag, so the older commit
  could finish last. The publish workflow now serialises on a concurrency group
  and cancels a superseded run.
- **A dead QEMU setup step** (review L7) — the build is `linux/amd64` only, so
  setting up QEMU did nothing. Removed.
- **A dispatch input was interpolated into shell and into JS** (review L8) — the
  mirror workflow pasted `${{ inputs.tag }}` straight into `run:` and into a
  template literal. It now arrives through `env:` and is referenced as a
  variable.
- **A harness failure counted as a test pass** (review L13) — the fake Tor
  server reports 99 when it never started, and the "exits non-zero" assertions
  accepted that. They now require exit 1 exactly.
- **`pr-tests.yml` inherited the repository's default token permissions**
  (review L17) — now `contents: read`.
- **The Tor probe's timeout budget exceeded Docker's** (review L18) — the
  bootstrap check used a 5 s connect timeout against a 5 s HEALTHCHECK timeout,
  so it could be killed before printing why it failed. Now 3 s, and the contract
  checker enforces the budget for every probe rather than only the noVNC one.
- **The contract checker could not see the two most drift-prone surfaces**
  (review L14) — it now compares the README and `templates/README` port tables
  line for line, asserts the Tor version is parsed from the Dockerfile rather
  than hardcoded, and checks every probe timeout.
- **The VNC token and `TOR_EXPOSE_RPC=true` paths were untested** (review L11,
  L12) — CI only ever ran the no-auth VNC branch and the RPC-off default. Two
  new smoke steps assert that the token path uses `-passwdfile` without putting
  the token in argv, and that the opt-in hidden-service RPC is published and
  warned about.
- **The 4 GB memory limit was below the stack's working set** (review M2) —
  XMRig's RandomX dataset (~2.1 GB plus scratchpad), monerod during sync and the
  X stack do not fit, so the container could be OOM-killed as 137. Raised to
  6 GB in compose and the Unraid template. The figure is a footprint-based
  estimate, not a measured peak; the docs say to confirm with `docker stats`.
- **A lint suppression that could never fire** (review L15) — `.hadolint.yaml`
  ignored SC2046, which only applies to an *unquoted* command substitution. The
  Dockerfile has two, both quoted or assignments, so the ignore was dead weight
  that would have hidden the first real one. Removed.
- **Gupax could not write its shader cache** (live log evidence) — `useradd -m`
  creates `/home/miner` as 0750 owned by `miner`, and `start.sh` only widens it
  to 0755 (traversable, not writable). With the Unraid default `PUID=99` Gupax
  logged `Failed to create /home/miner/.cache for shader cache (Permission
  denied)--disabling` and recompiled shaders on every start. `start.sh` now
  creates `~/.cache` owned by the runtime UID.
- **`XDG_RUNTIME_DIR` was never set** (live log evidence) — Gupax logged
  `error: XDG_RUNTIME_DIR is not set in the environment`. `start.sh` now creates
  `/tmp/runtime-<PUID>` (0700, owned by the runtime UID) and exports it. Root
  still reaches it through `DAC_OVERRIDE`, which the capability profile includes.
  Both are best-effort: if a directory cannot be created, startup is unchanged.
- **The DNS-blocklist warning misattributed the lookup** (verified against the
  monerod source) — `--enable-dns-blocklist` fetches **TXT** records from
  `blocklist.moneropulse.*` through the system resolver; it does not resolve
  seed nodes. Seed-node DNS is a separate clearnet lookup that `--tx-proxy` does
  not cover either, and only a full `--proxy` makes monerod disable both
  (`--proxy-allow-dns-leaks` overrides that). The README no longer implies that
  switching the toggle off makes monerod's DNS private.
- **A branch build could never pass its own digest check** (review L20, found by
  running it) — the publish workflow verifies the pushed image by inspecting
  `:<commit-sha>`, but that tag is only created on `main`; every other ref pushes
  `:<ref>-<sha>`. A `workflow_dispatch` build from a branch therefore compared
  two empty digests and failed *after* successfully pushing the image. The
  verification tag is now computed alongside the tag list, and a branch build no
  longer rewrites the public Docker Hub description.
- **Gupax aborted with `P2Pool Stats: Permission denied` on Unraid** (found
  during 26.04 testing) — the FUSE branch of the permission logic probes
  writability only at the volume root. That root is normally PUID-owned from
  earlier runs, so the probe passed while `p2pool/`, recreated by `start.sh` as
  root at every boot, was unreachable; Gupax then reported
  `App error detected, skipping init_auto()` and showed its unrecoverable-error
  screen. The probe now covers every directory Gupax writes
  (`p2pool`, `node`, `xmrig`, `xmrig-proxy`) and falls back to world-writable
  permissions if any of them is denied.
- **The `gupax` group could never grant access** — `gosu` sets only the primary
  GID and drops supplementary groups (verified against the shipped binary), so
  the FUSE `chgrp gupax` + `g+rwX` strategy granted the Gupax process nothing,
  and its `o-rwx` actively removed access it would otherwise have had. The
  group attempt is kept as a first pass, but the fallback is now what runs on
  Unraid; the log says so instead of implying group ownership worked.

### Documented

- **Port 18081 was documented as "✅ Yes"** (review M4) — monerod binds
  `127.0.0.1` by default and additionally requires `--confirm-external-bind`
  before it will bind elsewhere, so publishing the port is inert unless the
  operator deliberately changes both. The port table, the Unraid template field
  and the README now say so.
- **The Docker Hub badge pointed at a manual-only workflow** (review L1) — a
  status badge on `docker-hub-push.yml` could never show anything, because that
  workflow has no push trigger. Removed.
- **"Auto-restart" overclaimed** (review L2) — `restart: unless-stopped` acts on
  exit only; a hung GUI is reported by the health check, not restarted. README
  and TODO now say that.
- **"Paste the four Tor arguments" listed three** (review L3) — corrected.
- **`ca_profile.xml` read as an orphaned file** (review L5) — kept, and now
  documented in the file itself and in `templates/README.md` as the maintainer
  profile staged for the Community Applications PR.
- **The DNS-blocklist toggle was not named** — the README warned against
  *adding* `--enable-dns-blocklist` but not against leaving Gupax's Node-tab
  **DNS blocklist** toggle on while Tor is enabled. Called out explicitly.
- The Dockerfile comment claiming `TOR_VERSION` and `TOR_KEYRING_SHA256` must
  be "bumped together" was wrong and is corrected: the pins are independent,
  and bumping the keyring hash alongside a Tor release breaks the build.
- **Runtime-downloaded miner binaries are not verified** (review finding H2) —
  the image pins and checks Gupax, the Tor package and the Tor keyring, but
  P2Pool, XMRig, xmrig-proxy and monerod are fetched and executed at runtime by
  Gupax with no hash or signature check. Pinning them in the image is not
  possible: Gupax owns version selection and replaces them on its own update
  path. Rather than fight that, the gap is now documented in `SECURITY.md`:
  download origins per binary, the distinction between the checks the image does
  and does not make, the threat model (integrity and upstream compromise, not
  privilege escalation — the binaries never run as root), a host-side
  verification recipe that compares the running binary against the
  signature-verified upstream archive, and egress guidance.

## [Unreleased] — 2026-10-18

Code-review remediation (22 findings). Runtime verification of the container
changes was not possible in the review environment; the CI job in
`.github/workflows/pr-tests.yml` is the executable gate for every runtime
assertion listed here.

### Fixed

- **XMRig could not start on the default UID 999** (GUP-01) — the `gupax`
  group was only created inside a block that was skipped whenever the UID
  already existed, and `useradd -g <gid>` failed for a GID absent from the
  image. `setup-runtime-user.sh` now always creates the group, resolves or
  creates the primary group, adds the runtime user to `gupax`, and fails
  closed. CI exercises 999/999, 99/100 and 1000/1000.
- **`.env` was inert** (GUP-02) — every user-facing variable is interpolated
  in `docker-compose.yml`, and CI asserts a `.env` file reaches the rendered
  service.
- **Unraid published unauthenticated VNC 5900** (GUP-03) — the template's VNC
  port now defaults to empty, and without `VNC_AUTH_TOKEN` x11vnc binds to
  loopback (`-localhost`), so noVNC still works but the port cannot expose an
  unauthenticated desktop.
- **Wallet RPC was published on the hidden service** (GUP-04) — now opt-in via
  `TOR_EXPOSE_RPC=true`, with a loud warning when RPC is unrestricted.
- **gosu failure fell back to root** (GUP-05) — the entrypoint now exits with
  a clear error instead of running the mining stack as root.
- **Healthcheck could not see a hung Gupax or unbootstrapped Tor** (GUP-06) —
  added a Tor ControlPort/bootstrap check, an X server probe, a Gupax window
  check and a `/proc` process-state check (stopped/zombie).
- **No init/reaper** (GUP-07) — `init: true` in compose and `--init` in the
  Unraid template; CI asserts PID 1 is `docker-init`.
- **NOPASSWD root on a writable XMRig binary** (GUP-08) — removed the sudo
  rule and the `sudo` package. XMRig runs unprivileged; the pkexec wrapper is
  a passthrough. FUSE permissions are group-first with a verified fallback.
- **CI never exercised the hardened capability profile** (GUP-09) — the smoke
  container now runs with the exact compose cap set, asserted by a
  cross-surface contract test.
- **Two independent registry builds** (GUP-10) — one build pushes the same
  digest to GHCR and Docker Hub; a step verifies both digests match. The
  former Docker Hub workflow is now a manual manifest-mirror repair path.
- **`docker run` example omitted hardening and the Tor volume** (GUP-11) —
  mirrors compose (`--init`, cap drop/add, stop timeout, `gupax-tor`).
- **Tor provenance gate only checked a version floor** (GUP-12) — CI asserts
  the installed package comes from `deb.torproject.org`.
- **Tor ran as root** (GUP-13) — runs as `debian-tor` when the volume allows
  ownership changes; SECURITY.md now states exactly which processes stay root.
- **Banner claimed tx-only mode regardless of monerod args** (GUP-14) —
  reworded to distinguish starting Tor from routing through it.
- **Gupax tarball was not hash-pinned** (GUP-15) — `gupax-checksums.txt`
  supplies the trusted digest; the upstream sums remain a secondary check.
  Unpinned auto-detected releases emit a CI warning.
- **Tor package/keyring were not immutably pinned** (GUP-16) — keyring `.deb`
  SHA256 and `tor=<version>` are pinned build args.
- **No stop timeout on Unraid** (GUP-17) — `--stop-timeout=30` matches
  compose.
- **Documentation drift** (GUP-18) — corrected the PUID/PGID defaults, the
  startup-log claim, the VNC security wording, the version-support wording,
  the duplicate TODO checkbox, CONTRIBUTING's UID description, the
  `.dockerignore` stale entry and the hadolint DL3008 rationale.
- **Non-canonical licence and missing provenance labels** (GUP-19) —
  `GPL-3.0-or-later`, `revision`, `created`.
- **VNC tokens were silently truncated** (GUP-20) — startup warns when the
  token exceeds the 8-character protocol limit.
- **Healthcheck's internal timeout equalled Docker's** (GUP-21) — reduced to
  3s against Docker's 5s.
- **Newer non-semver releases were skipped silently** (GUP-22) — the detector
  emits a warning naming the skipped tag; fixtures pin the behaviour.

## [Unreleased] — 2026-10-05

Base image migration (closes #84):

- `ubuntu:22.04` → `ubuntu:26.04` LTS ("resolute"), still digest-pinned.
  22.04 standard support ends April 2027.
- `libasound2` → `libasound2t64`. Ubuntu completed the 64-bit `time_t`
  transition in 24.04 and no package named `libasound2` exists after that;
  `libasound2t64` declares `Provides: libasound2`, so the dependency contract
  is unchanged.
- Tor apt suite `jammy` → `resolute`, which also brought a current Tor
  (0.4.9.x; the pin now names the exact version).

---

## [Unreleased] — 2026-09-29

Follow-up review ([#73](https://github.com/libre-7/gupax-docker/issues/73)) of the
2026-09-27 remediation. The #68 findings were re-verified against code, both
registries and a live CI run; this entry covers the new findings and the two
small regressions in the previous batch's own PRs.

### Fixed

- **Documented install path ran the mining stack as root** (#73 / H1) — The
  image deliberately does not pre-create `/home/miner/.local/share/gupax`, so
  Docker mounts the `gupax-data` named volume `root:root 0755`.
  `start.sh`'s `PUID` detection used `stat … || echo 999`, and that fallback
  only fires when the path is *missing* — so a fresh volume returned `0` and
  `gosu 0:0` ran Gupax, monerod, P2Pool and XMRig as **UID 0**. This hit
  `docker compose up` (the README Quick Start) and the `docker run -v` example.
  The PR smoke test mounted no volume at all, so it took the fallback branch
  and ran as `miner`/999 — the one configuration no user has. `start.sh` now
  treats a detected owner of `0` as unset, compose pins `PUID`/`PGID=999`,
  and CI mounts a volume and asserts Gupax's effective UID is not 0.
- **"RPC is restricted" was claimed even when it wasn't** (#73 / M1) — The Tor
  banner line printed unconditionally, so `MONERO_RPC_RESTRICTED=false` still
  told the operator their RPC was restricted while the recommended arguments
  omitted `--restricted-rpc`. Port `18081` is mapped to the LAN by both compose
  and the Unraid template. The claim is now gated and the docs state plainly
  that the flag shapes a *recommendation* the operator pastes into Gupax, not
  a control the container enforces.
- **CI failure alerts pointed at a ticket that was about to close** (#73 / M2)
  — Both registry workflows hardcoded `issue_number: 68`, the completed
  remediation ticket. Once closed, the comment 404s and the alert is silently
  lost — the exact failure mode the alert was added to prevent. Alerts now
  target a dedicated long-lived CI-watch issue.
- **Release detector's token auth never ran** (#73 / M4) — The script supports
  `GITHUB_TOKEN` to avoid unauthenticated rate limits, but no workflow
  exported it to the calling step, so every build called the GitHub API
  anonymously from shared runner IPs. Both workflows now pass it.
- **Docker Hub served pre-#68 README text** (#73 / M5) — Verified live: wrong
  case `Gupax-docker` clone URLs and badges, and no `docker-hub-push` badge.
  A CI step now syncs the README to `full_description` on every `main` push.
- **Tor regressions could not fail CI** (#73 / M3) — The SOCKS-proxy and
  hidden-service probes printed a warning and fell through. Both are fatal
  now, with unchanged time budgets.
- **Smoke test's process probe was too loose** (#73 / L1) — `pgrep -f gupax`
  also matches the runtime-downloaded `…/gupax/xmrig/xmrig`, so a dead GUI
  with a live daemon passed. Now matches `gupax/gupax`, as `healthcheck.sh`
  already did.
- **Health gate was a single non-polling read** (#73 / L2) — A fixed `sleep 5`
  against a `interval=30s` / `start-period=60s` healthcheck. Now a bounded
  120s poll that fails fast on an explicit `unhealthy`.
- **README's Tor walkthrough instructed a clearnet DNS leak** (#73 / M6) — The
  example start-options line included `--enable-dns-blocklist`, which resolves
  seed DNS over clearnet rather than through Tor. Removed, with a warning.
- **CI build remained untested for the volume path** — Folded into the H1 fix.

### Documentation

- `SECURITY.md` / `TODO.md` / `README.md`: the "runs as a non-root `miner`
  user" claim was false on the compose path; replaced with the actual UID
  matrix. `TODO.md` also notes that only the Gupax GUI is checksum-verified —
  not the P2Pool / XMRig / monerod binaries Gupax fetches at runtime.
- `.dockerignore`: the comment claimed to "exclude all markdown except
  healthcheck.sh", which is not markdown; corrected and grouped (behaviour
  unchanged). `docs/` matched nothing.
- `README.md`: `GUPAX_VERSION` is the newest *semver-tagged* release, not
  necessarily the newest release. `templates/README.md` no longer recommends
  Docker Hub for Unraid when the template pulls from GHCR. `TODO.md`'s date
  example is a real build date rather than a frozen `20260518`.

### Earlier in this batch

- `docs`: corrected the `--tx-proxy` zone/scheme description (#71).
- `ci`: the PR smoke test now fails on a container stuck in `starting`
  rather than accepting it (#72).

---

## [Unreleased] — 2026-09-27

Comprehensive remediation of issue #68. Registry builds have been broken
since 2026-07-12; this release restores them.

### Fixed

- **CI release detection assumed semver tags** (#68 / C1) — Upstream marked a
  non-semver release tag (`critical_update_p2pool`) as its latest release.
  Both registry workflows fed that tag straight into the Dockerfile, which
  constructed a 404 asset URL, so every build since 2026-07-12 failed and
  **both registries have been stuck at the 2026-06-02 image**. New shared
  script `.github/scripts/detect-gupax-version.sh` selects the newest
  non-prerelease `v*` semver release and resolves the actual Linux x64 asset
  filename from that release's `assets[]` instead of constructing it from the
  tag. It fails loudly if no matching asset exists, so a bad upstream state
  can never silently publish unparseable tags.
- **Gupax crash skipped cleanup** (#68 / H1) — Under `set -e`, a non-zero
  Gupax exit aborted `start.sh` at `wait`, so `cleanup()` never ran and the
  exit code was lost. The wait is now guarded with `set +e` / `set -e`.
- **Health check could not detect a dead GUI** (#68 / M1) — The health check
  only probed websockify's static file server, which keeps serving after
  x11vnc dies, so the container reported `healthy` with a black screen. It now
  also probes the VNC port (5900), the `x11vnc` process, and the `gupax`
  process. Covered by a new PR smoke test that kills x11vnc and asserts the
  container transitions to `unhealthy`.
- **Dead `gupax-state` volume** (#68 / H2) — Gupax persists only to
  `dirs::data_dir()` (`/home/miner/.local/share/gupax`); nothing ever wrote to
  `/home/miner/.local/state/gupax`. The volume was removed from compose and
  README, and the misleading Unraid "Gupax config" mapping (described as
  holding the wallet) was corrected to point at the real path.
- **Wallet address instructions named the wrong tab** (#68 / H3) — The wallet
  address is a **P2Pool** field (`state.rs` `P2pool.address`, rendered as
  "Monero Address"); the Node struct has no such field. README, Unraid
  template, TODO, and `.env.example` corrected.
- **Unraid template lost capability hardening** (#68 / M2) — The template
  applied no `cap_drop`/`cap_add` while compose drops ALL and adds five
  specific capabilities. `ExtraParams` now carries the same capability set.
- **`SCREEN_RESOLUTION` accepted degenerate values** — The validation regex
  admitted `0x0x0` and `0x1080x24`; each component must now be positive.
- **Dockerfile comment named a non-existent volume** — Header referenced
  `gupax-share`; the volume is `gupax-data`.
- **Hadolint failures on the Dependabot bump** — `hadolint-action` 3.5.0
  flags `DL3064` (the `VNC_AUTH_TOKEN` ENV) and `DL3025` (shell-form
  `HEALTHCHECK` CMD). Acknowledged with a scoped ignore and by switching the
  healthcheck to exec form, so PR #69's lint job passes.

### Security

- **Actions are now pinned by commit SHA** (#68 / L7) — All nine actions in
  the three workflows are SHA-pinned with the version kept in a trailing
  comment, so a compromised tag cannot silently change what CI runs.
- **CI failures are no longer silent** (#68 / M3) — Both registry workflows
  now comment on issue #68 on failure, so a frozen registry surfaces without
  anyone watching the Actions tab.

### Documentation

- **Repository casing fixed** (#68 / L1) — Badges and clone instructions
  referenced `Gupax-docker`; the repository is `gupax-docker`.
- **Internal planning notes removed from the public repo** (#68 / L2) — The
  committed `.hermes/plans/` files contained pre-rename `VNC_PASSWORD`
  references and internal VM addresses. Removed and added to `.gitignore`.
- **CHANGELOG and TODO refreshed** (#68 / L3, L4) — Recorded the previously
  undocumented work from May–July, and corrected the TODO's false claim that
  `linux/arm64` multi-arch builds are complete (Gupax publishes no arm64
  Linux binary; both workflows are amd64-only — tracked in #61).
- **`eval $(dbus-launch)` annotated** — Intentional word splitting now carries
  an explicit `# shellcheck disable=SC2046` directive.

---

## [v2.0.1-20260518] — 2026-05-18

### Changed

- **Version scheme** — Adopted `v{upstream}-{date}` convention. Version now
  tracks the bundled Gupax release with a date-stamped container build suffix.
  OCI labels (`image.version`, `gupax.version`) updated accordingly (#47).

### Fixed

- **CI build-args broken** (#48) — `GUPAX_VERSION` was arriving empty due to
  multiline YAML scalar not interpolating `${{ }}`. Both registries were
  silently falling back to the hardcoded v2.0.1 default. Fixed with
  comma-separated args + `env:` block pattern.
- **Registry divergence from `paths:` filter** (#48) — Docker Hub workflow had
  a `paths:` filter that skipped docs-only commits. Removed; both registries
  now share identical triggers.
- **Smoke test Gupax race condition** (#51) — Single-shot `pgrep` fired before
  `start.sh` reached Gupax launch (80% failure rate). Replaced with 15-attempt
  polling loop matching Tor/hidden-service probes.
- **Version tag asymmetry** (#53) — Docker Hub tagged `:v2.0.1`, GHCR tagged
  `:2.0.1`. Both now emit `:2.0.1` (stripped) and `:v2.0.1` (v-prefixed).

### Security

- **Hadolint warnings resolved** (#52) — `DL4006/SC3040` (pipefail in dash),
  `DL3009` (uncleaned apt lists), `SC2034` (dead variable). Added `SHELL` to
  bash with pipefail globally.
- **OCI labels corrected** (#52) — `image.source` case fixed
  (`Gupax-docker` → `gupax-docker`), stale `-standalone-tor` suffix removed.
- **Stale comment fixed** (#54) — `VNC_PASSWORD` → `VNC_AUTH_TOKEN` in
  `start.sh` comment (was correct in code, wrong in docs).

### Added

- **Date-stamped image tags** — Both registries now push a `v{version}-{date}`
  immutable tag in addition to the moving tags.

### Documentation

- Port tables consolidated into single master table in README and template
  README (#47).
- License restructured as canonical GPL-3.0 with separate NOTICE and SPDX
  headers.
- Docker Hub build status badge added to README.
- Unraid template docs updated for 6.10+ flash-drive install method.

---

## [2.3.0] — 2026-05-12

### Security

- Health check now monitors Tor SOCKS proxy when enabled (#9)
- Image provenance attestations + SBOM generated for GHCR and Docker Hub (#5)
- Documented FUSE world-writable permission trade-off on Unraid (#8)

### Fixed

- VNC_PASSWORD → VNC_AUTH_TOKEN env var mismatch in compose/template (#1)
- Dockerfile labels updated from deprecated w111a → libre-7 namespace (#2)
- Removed deprecated version: "3.8" from docker-compose.yml (#3)
- Docker Hub builds now pass correct GUPAX_VERSION as build-arg (#7)
- Removed deprecated transitional libgl1-mesa-glx package (#11)
- Replaced racy rm -rf /tmp/.X11-unix with targeted file removal (#10)

### Added

- MONERO_RPC_RESTRICTED surfaced in compose, Unraid template, and .env.example (#6)
- Dependabot configured for GitHub Actions version updates (#14)

---

## [2.2.0] — 2026-04-18

### Added
- **Blockchain volume support** — Mount existing Monero blockchain at `/home/miner/.bitmonero`
- **Unraid template** — Updated with noVNC WebUI (`http://[IP]:[PORT:6080]`) and blockchain volume

### Changed
- **Unraid template** — Renamed from old P2Pool+XMRig direct approach to Gupax GUI approach

---

## [2.1.0] — 2026-04-18

### Added
- **noVNC self-contained GUI** — Container now accessible via web browser at http://localhost:6080
- **Xvfb + x11vnc + websockify** — Virtual framebuffer and VNC-to-WebSocket proxy
- **start.sh** — Startup script orchestrating Xvfb → x11vnc → websockify → Gupax

### Changed
- **Image size** reduced from ~6.14 GB to ~375 MB
- **DISPLAY requirement removed** — Container is now self-contained, no X11 on host needed

### Removed
- P2Pool and XMRig binaries (Gupax manages these internally)

---

## [2.0.0] — 2026-04-18

### Breaking Changes

**Complete rewrite. The previous version managed P2Pool and XMRig directly. This version packages the Gupax GUI application.**

- **Removed** direct P2Pool and XMRig binaries from the container
- **Removed** custom entrypoint script that orchestrated P2Pool + XMRig
- **Removed** environment variables: `P2POOL_MINI`, `XMRIG_THREADS`, `MONERO_NODE`, `P2POOL_STRATUM_PORT`, `P2POOL_MONERO_PORT`
- **Removed** volumes: `gupax-p2pool`, `gupax-monero`
- **Removed** Unraid template (old version)
- **Changed** container behavior: Now runs Gupax GUI application

### Added
- **Gupax GUI** — Full graphical interface for P2Pool + XMRig mining
- **X11 requirement** — Container fails if DISPLAY is not set
- **X11 socket mount** — `/tmp/.X11-unix` mounted automatically
- **Gupax config volume** — `gupax-config:/home/miner/.local/state/gupax`
- **CHANGELOG.md** — This file

### Legacy Files

These files are from the old P2Pool+XMRig direct approach and are kept for reference:
- `entrypoint.sh.LEGACY_P2POOL_XMRIG`
- `.env.example.LEGACY_P2POOL_XMRIG`
- `scripts/get-checksums.sh.LEGACY`
- `templates/gupax-docker.xml.LEGACY_P2POOL_XMRIG`

---

## [1.0.0] — Previous

See git history for previous changes.
