# 2026-08-17 10:10:28 UTC — Finish docker-login migration in tag-docker-images

## TL;DR

**Why:** GitHub Actions run [32014167930/job/95340499840](https://github.com/optivem/gh-optivem/actions/runs/32014167930/job/95340499840) (smoke test, multitier/monorepo/typescript) failed at its nested acceptance-stage run's "Tag Docker Images for Prerelease" step. The "Log in to Container Registry" sub-step hit a transient GitHub-hosted-runner DNS timeout resolving `ghcr.io` (`i/o timeout` via the runner's local `127.0.0.53:53` resolver) and exhausted all 3 retry attempts. Root cause: `tag-docker-images/action.yml` still uses the legacy `Wandalen/wretry.action@v3` + `docker/login-action@v4` combo (3 attempts, fixed 10s delay, no backoff) — exactly the pattern `optivem/actions/docker-login@v1` was built to replace (its own description says so), because `docker-login` uses the shared `retry_run` helper (4 attempts, 5s→15s→45s backoff, and its `_RETRY_RETRYABLE` regex explicitly matches `i/o timeout` / `no such host` / DNS-class failures). `docker-login@v1` was adopted at the two earlier "Log in to GHCR"/"Log in to Docker Hub" steps in the same workflow (both passed in this run) but the migration was never finished for `tag-docker-images`'s own login step — it's the last `Wandalen/wretry.action` call site left in the whole `actions` repo.
**End result:** `tag-docker-images/action.yml`'s login step calls `optivem/actions/docker-login@v1` like every other login step in the pipeline, giving it the same DNS-aware exponential-backoff retry. No `Wandalen/wretry.action` references remain anywhere in the `actions` repo. Since every language/architecture's acceptance-stage workflow (java, dotnet, typescript × monolith, multitier) calls this one shared composite action, the fix applies everywhere without touching per-language workflow files.

## Outcomes

- `tag-docker-images/action.yml`'s "Log in to Container Registry" step is migrated off `Wandalen/wretry.action@v3` + `docker/login-action@v4` onto `optivem/actions/docker-login@v1`, matching the shape already used elsewhere in the acceptance-stage workflows (e.g. `shop/.github/workflows/multitier-typescript-acceptance-stage.yml:93-96`).
- The step gets the shared retry policy (4 attempts, 5s→15s→45s backoff, DNS/timeout-aware matching) instead of the old fixed 3×10s retry — reducing (not eliminating, since this is a runner-network flake) the chance a transient DNS blip fails the whole prerelease-tagging step.
- Zero remaining `Wandalen/wretry.action` call sites in the `actions` repo (verified by grep).
- No changes needed to `shop`'s per-language acceptance-stage workflows — they all consume `tag-docker-images@v1` as-is, so the fix is centralized.

## ▶ Next executable step (resume here)

Edit `tag-docker-images/action.yml` (repo root: `C:\Users\valen\Documents\GitHub\optivem\academy\actions`), replacing the "Log in to Container Registry" step (currently lines 38-47, using `Wandalen/wretry.action@v3` wrapping `docker/login-action@v4` with `attempt_limit: 3` / `attempt_delay: 10000`) with a call to `uses: optivem/actions/docker-login@v1`, passing `registry: ${{ inputs.registry }}`, `username: ${{ inputs.registry-username }}`, `password: ${{ inputs.token }}` — mirroring the existing usage at `shop/.github/workflows/multitier-typescript-acceptance-stage.yml:93-96` (adjusting input names: `docker-login@v1` takes `registry`/`username`/`password`, not `registry-username`/`token`). Then grep the whole `actions` repo for `Wandalen/wretry.action` to confirm no call sites remain, and grep `shop/.github/workflows/*acceptance-stage*.yml` to confirm the composite action's inputs/outputs contract (`image-urls`, `tag`, `registry-username`, `token` in; `tagged-image-urls` out) is untouched by the edit. This is the only step in the plan.

## Steps

- [ ] Step 1: In `tag-docker-images/action.yml`, replace the "Log in to Container Registry" step (lines 38-47) with a call to `optivem/actions/docker-login@v1`, mapping `registry` → `inputs.registry`, `username` → `inputs.registry-username`, `password` → `inputs.token`.
- [ ] Step 2: Grep the `actions` repo for `Wandalen/wretry.action` and confirm zero matches remain.
- [ ] Step 3: Diff-review that `tag-docker-images/action.yml`'s public inputs/outputs (`image-urls`, `tag`, `image-tags`, `registry`, `registry-username`, `token`, `tagged-image-urls`) are unchanged — this is an internal implementation swap, not a contract change, so no caller in `shop`'s workflows needs updating.
- [ ] Step 4: Note in the PR/commit that this is an infra-flake mitigation (DNS timeout on GitHub-hosted runners resolving `ghcr.io`), not a deterministic bug fix — there's no local repro and no test that will "go green" to prove it; verification is structural (config now matches the already-proven-good `docker-login@v1` pattern used elsewhere in the same workflow).

## Open questions

None — root cause, fix, and scope were fully pinned down during triage (`/fix-bug`) before this plan was drafted.
