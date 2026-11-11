# 2026-11-11 09:39:51 UTC — Fix cleanup-prereleases empty-prefix crash + event-hub cleanup config

> 🤖 **Picked up by agent** — `Valentina_Desk` at `2026-11-11T09:41:04Z`

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

Step 5: clone event-hub (not in the local workspace; ask first), then edit `.github/workflows/cleanup.yml` and set `container-packages: event-hub/backend,event-hub/frontend` in both the "Cleanup Prereleases" and "Cleanup Orphan Manifests" steps. Both packages are confirmed to exist in GHCR. Gate: the actions fix (Steps 1–4) is already committed. This unblocks Step 6.

## Steps

- [ ] Step 5: In event-hub, edit `.github/workflows/cleanup.yml` and set `container-packages: event-hub/backend,event-hub/frontend` in both the "Cleanup Prereleases" and "Cleanup Orphan Manifests" steps.
- [ ] Step 6: Commit actions + event-hub via `/commit`, move the actions `v1` tag per the repo's release process, then dispatch event-hub `cleanup` with `dry-run=true` and confirm it is green (sleep ≥2 min between status checks). Let the next scheduled run pass.

## Notes

- Consumer check for Step 3 is done: shop (7 packages) and event-hub (backend, frontend) all exist in GHCR. gh-optivem passes no `container-packages`.
