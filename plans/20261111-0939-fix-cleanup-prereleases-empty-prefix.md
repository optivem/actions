# 2026-11-11 09:39:51 UTC — Fix cleanup-prereleases empty-prefix crash + event-hub cleanup config

## TL;DR

**Why:** event-hub's scheduled `cleanup` run ([42946054776](https://github.com/optivem/event-hub/actions/runs/42946054776)) fails in the "Cleanup Prereleases" step with `cleanup-prereleases.sh: line 380: rcs_by_prefix: bad array subscript`. `get_tag_prefix` (`cleanup-prereleases/cleanup-prereleases.sh:244-251`) returns `""` for tags with no prefix (e.g. `v1.0.230-rc.29`…`rc.34`), and bash rejects `""` as a key in an associative array (reproduced locally with bash 5.2). Separately, event-hub's `cleanup.yml` lists `container-packages` copied from shop, so every package lookup returns 404. The script only logs a warning for this, so Docker tag cleanup silently does nothing.
**End result:** `cleanup-prereleases` handles unprefixed RC tags. event-hub cleanup targets its real GHCR packages. If a configured package doesn't exist, the run fails with a clear error instead of skipping.

## Outcomes

- Scenario 2 (superseded prereleases) groups unprefixed RCs without crashing, and the log line still reads "no prefix".
- No other cleanup-* action has the same empty-key associative-array bug.
- event-hub cleanup deletes Docker tags for `event-hub/backend` and `event-hub/frontend`.
- A misspelled or wrong package in `container-packages` (HTTP 404) fails the run with a `::error::` that names the package.
- The event-hub scheduled `cleanup` run is green.

## ▶ Next executable step (resume here)

Step 1: in `cleanup-prereleases/cleanup-prereleases.sh`, inside the Scenario 2 loop (~lines 377-405), store an empty `prefix` under a placeholder key (e.g. `prefix_key="${prefix:-__none__}"`) and use that key in `rcs_by_prefix` at lines 380, 381 and 385. Iterate `${!rcs_by_prefix[@]}`, and when building `prefix_label` (~404-405), treat `__none__` as "no prefix". Gate: a local bash repro (Step 4) passes. This unblocks Step 2.

## Steps

- [ ] Step 1: Fix `cleanup-prereleases/cleanup-prereleases.sh` Scenario 2 grouping. Store an empty prefix under the `__none__` placeholder key at lines 380/381/385, and convert it back to "no prefix" for `prefix_label` at 404-405.
- [ ] Step 2: Search the actions repo (`cleanup-deployments`, `cleanup-ghcr-orphan-manifests`, any other user of `get_tag_prefix`, or any associative array keyed by a value that can be empty) for the same bug, and fix each one the same way.
- [ ] Step 3: In `cleanup-prereleases.sh` (and `cleanup-ghcr-orphan-manifests`), change the HTTP 404 on "list versions for package X" from a warning to `::error::Package X not found in GHCR — check container-packages` + `exit 1`. An existing package with zero versions still counts as a clean result. Other failures (auth, 5xx) already surface via `retry_run`; check they also exit non-zero.
- [ ] Step 4: Local verification: a bash repro that seeds several unprefixed RCs for one unreleased version (plus one prefixed set) and runs the grouping logic, with no error and correct grouping. Run it with Git Bash and confirm it passes.
- [ ] Step 5: In event-hub, edit `.github/workflows/cleanup.yml` and set `container-packages: event-hub/backend,event-hub/frontend` in both the "Cleanup Prereleases" and "Cleanup Orphan Manifests" steps.
- [ ] Step 6: Commit actions + event-hub via `/commit`, move the actions `v1` tag per the repo's release process, then dispatch event-hub `cleanup` with `dry-run=true` and confirm it is green (sleep ≥2 min between status checks). Let the next scheduled run pass.

## Open questions

- Step 3 changes the behaviour for every consumer repo. If any other repo has a wrong `container-packages` list, its cleanup will start failing (which is the intended outcome). Before moving `v1`, check shop and the other consumers' `cleanup.yml` package lists.
