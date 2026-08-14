# 2026-08-14 12:34:06 UTC — Fix transient-failure misclassification in shared retry engine

## TL;DR

**Why:** All 4 `Smoke` jobs in [gh-optivem run 31709529616](https://github.com/optivem/gh-optivem/actions/runs/31709529616) failed under normal concurrent load because two live GitHub API transient blips were misclassified by `academy/actions/shared/retry.sh` — one collided with the hard-fail pattern before the transient pattern could match, the other matched neither pattern and fell through as "unknown."
**End result:** `git push` failures phrased as `[remote rejected] ... (Internal Server Error/Bad Gateway/Service Unavailable/Gateway Timeout)` retry instead of hard-failing, and `gh api --jq` failures phrased as `unexpected end of JSON input` (truncated/empty response body) retry instead of passing through unclassified — fixing every caller of `retry_run` across the repo via the single shared file.

## Outcomes

- A transient 5xx during `publish-tag/tag.sh`'s `git push` of a release/RC tag retries (per the existing 4-attempt/5-15-45s backoff) instead of failing the whole prod-stage pipeline on the first hiccup.
- A transient truncated/empty response from any `gh api ... --jq ...` call routed through `retry_run` (`create-deployment/create.sh`, `create-commit-status/create.sh`, `get-commit-status/read.sh`, `resolve-latest-deployed-prerelease/resolve.sh`) retries instead of failing immediately with an opaque `unexpected end of JSON input`.
- The two new patterns are documented in `retry.sh` with the same comment-block style as the existing SonarCloud JRE-403 and GHCR secondary-rate-limit overrides, referencing this incident (gh-optivem run 31709529616) so future readers know why they're there.
- Confirmed neither new pattern silently masks a real hard-fail (e.g. a genuine `pre-receive hook declined` rejection must still fail fast; a genuine caller-side jq filter bug, if any exists, must not be swallowed as transient).

## ▶ Next executable step (resume here)

Step 1: in `academy/actions/shared/retry.sh`, add a `_RETRY_FORCE_RETRY` entry for git's transient "remote rejected" phrasing (see Step 1 below for the exact pattern and comment-block content).

## Steps

- [ ] Step 1: Add a `_RETRY_FORCE_RETRY` clause in `academy/actions/shared/retry.sh` (near the existing SonarCloud/GHCR overrides, ~line 121) matching `\[remote rejected\].*\((Internal Server Error|Bad Gateway|Service Unavailable|Gateway Timeout)\)`. Add a comment block in the same style as the existing overrides explaining: git phrases *any* server-side push rejection as `[remote rejected] <ref> -> <ref> (<reason>)`, which always collides with the `! \[remote rejected\]` hard-fail pattern (retry.sh line 65) even when `<reason>` is a transient 5xx also present in `_RETRY_RETRYABLE`; force-retry wins because hard-fail is checked first in `retry-core.sh`. Reference the triggering incident: gh-optivem run 31709529616, job "Publish Release Tag" (`academy/actions/publish-tag/tag.sh:38`), observed error `remote: Internal Server Error` / `! [remote rejected] v1.0.187 -> v1.0.187 (Internal Server Error)`.
- [ ] Step 2: Add `unexpected end of JSON input` to `_RETRY_RETRYABLE` in `academy/actions/shared/retry.sh` (~line 58), with a comment explaining it's jq's generic parse-failure text emitted by `gh api ... --jq` when the HTTP response body is truncated or empty — a transient network symptom that `gh api --jq` collapses into an opaque message, not evidence of a real API/auth problem. Reference the triggering incident: gh-optivem run 31709529616, jobs "Record QA Deployment" (dotnet/monolith, typescript/monorepo, java/monorepo) via `academy/actions/create-deployment/create.sh:18`.
- [ ] Step 3: Grep the repo for other `retry_run`-wrapped `gh api ... --jq` call sites to confirm they benefit from the same shared-file fix without individual changes: `create-deployment/create.sh`, `create-commit-status/create.sh`, `get-commit-status/read.sh`, `resolve-latest-deployed-prerelease/resolve.sh`. No per-file changes expected — just confirm none of them have caller-specific jq filters whose syntax errors would also produce `unexpected end of JSON input` (which would then be wrongly retried). If any do, note it as a residual risk rather than blocking the fix.
- [ ] Step 4: Run `shellcheck` on `academy/actions/shared/retry.sh` (and `retry-core.sh` if touched) to confirm no syntax/quoting regressions from the edits.
- [ ] Step 5: Verify classification behavior directly against `retry_with_policy` — check whether the repo already has a bats/bash test harness for `retry-core.sh` (search for existing `*.bats` or `test*.sh` near `shared/`); if one exists, add cases there. If not, write a small throwaway local script that stubs a failing command emitting each of the two new strings (plus one existing hard-fail case, e.g. a genuine `pre-receive hook declined` message, and one existing transient case) through `retry_with_policy`, confirming: (a) the git-push transient case now retries and eventually succeeds/exhausts per the backoff schedule, (b) the jq-truncation case now retries, (c) the untouched hard-fail case (`pre-receive hook declined`) still fails fast with zero retries — i.e. the new patterns don't broaden the hard-fail carve-out. Delete the throwaway script when done (or keep it only if it graduates into a real test per repo convention).
- [ ] Step 6: Self/code-review the diff (small, single-file regex + comment changes) before committing.

## Open questions

- Whether `academy/actions/shared/` already has an automated test harness for `retry-core.sh` classification (Step 5 assumes not, falling back to a manual dry-run, but this should be checked first rather than assumed).
