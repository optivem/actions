# Automated retry on transient `gh` errors — 2026-04-20 15:45 UTC

## Motivation

Pipeline run [optivem/shop#24673369865](https://github.com/optivem/shop/actions/runs/24673369865) failed at the very last step of `multitier-java` → `qa-stage` → `Promote Prerelease (QA Deployed)` with:

```
HTTP 502: Server Error
(https://api.github.com/repos/optivem/shop/releases)
```

Root cause: transient GitHub API error on `gh release create`. The step has no retry, so a one-shot 5xx wasted a 34-minute pipeline run. Every `gh` call in `optivem/actions` has the same exposure — ~50 call sites across ~18 active actions.

## Principle

**Every `gh` invocation inside `optivem/actions` must go through a retry wrapper that transparently retries transient failures (HTTP 5xx, network/DNS/TLS errors, connection resets) with exponential backoff, and fails fast on non-transient errors (4xx, bad args, auth failures).** The retry behaviour lives in two shared helpers (one per shell — PowerShell and bash) so policy changes happen in one place.

## Target state

- **`shared/Invoke-GhWithRetry.ps1`** — PowerShell module-style helper. Exports `Invoke-GhWithRetry` which takes a gh-argument array, runs `gh`, inspects output + exit code, retries on transient patterns. All `.ps1` scripts dot-source it and replace raw `& gh ...` with `Invoke-GhWithRetry`.
- **`shared/gh-retry.sh`** — bash helper. Exports function `gh_retry` that wraps `gh`. All `action.yml` composite steps that invoke `gh` source this file and call `gh_retry` instead of `gh`.
- **Retry policy (shared by both)**:
  - Up to **4 attempts** total.
  - Backoff: **5s → 15s → 45s** between attempts (exponential ×3, capped).
  - Retryable patterns (case-insensitive match against stderr/stdout or `$LASTEXITCODE`-adjacent output):
    - `HTTP 5\d\d` (500, 502, 503, 504, …)
    - `timeout`, `timed out`, `i/o timeout`
    - `connection reset`, `connection refused`, `EOF`, `was closed`
    - `TLS handshake`, `tls:.*handshake`
    - `temporary failure in name resolution`, `no such host` (DNS transient)
    - `Bad Gateway`, `Service Unavailable`, `Gateway Timeout`, `server error`
  - Non-retryable (fail immediately): any 4xx (`HTTP 4\d\d`), argument errors, `not found`, `authentication`, `permission`. Rate-limit (`HTTP 403.*rate limit` or `X-RateLimit-Remaining: 0`) is handled by existing caller-side rate-limit checks — do **not** retry it here (would only burn quota faster).
  - Each retry logs: attempt number, last-seen error snippet, sleep duration. Final failure prints all attempts' outputs.

- **Sharing mechanism**: at runtime, each composite action is checked out under `$GITHUB_ACTION_PATH` = `.../_actions/optivem/actions/<ref>/<action-name>/`. The repo root is `$GITHUB_ACTION_PATH/..`, so steps can source `"$GITHUB_ACTION_PATH/../shared/gh-retry.sh"` and PS1 scripts can dot-source `"$env:GITHUB_ACTION_PATH/../shared/Invoke-GhWithRetry.ps1"`. This keeps one copy of the logic, versioned with the action set.

## Items

### Phase 5 — verification

- [ ] **Re-run the failed pipeline** — Trigger `meta-prerelease-stage` on `optivem/shop` main after phases 1–3 merge and tag-bump of `@v1`. Confirm the previously-failing `Promote Prerelease (QA Deployed)` step succeeds (even if GitHub API is healthy — this just confirms no regressions). Bonus: inject a controlled 502 via a test-only flag on the PS1 helper to confirm retry surfaces in logs end-to-end.
  - Affects: runtime verification only
  - Consumers to update: 0
  - Category: verification

## Sibling-repo audit (2026-04-21)

`gh-optivem`, `github-utils`, `courses` surveyed for raw `gh` calls without a retry wrapper:
- **courses** — no GitHub Actions workflows; nothing to port.
- **github-utils/scripts/** — `check-actions-all.sh`, `delete-packages.sh`, `test-pipeline-templates.sh`, `common.sh` (the `gh_api` wrapper) all call `gh` directly with no transient-error handling.
- **gh-optivem** — 6 raw `gh api` calls in `.github/workflows/gh-post-release-stage.yml` and `gh-release-stage.yml`; `scripts/cleanup-orphans.sh`; Go CLI (`internal/shell/github.go`, `internal/steps/*.go`, `main.go`) shells out to `gh` without retry — different problem class but same 5xx exposure.

Out of scope for this plan's code changes — file follow-up plans per repo if/when this bites again.

## Open decisions

- **Retry count / backoff tuning**: 4 attempts × 5/15/45s is a starting point (~65s worst-case added latency). If telemetry later shows 502s are very brief, drop to 3 × 5/15s. Defer tuning until we see real data.
- **Should `gh_retry` honour a `GH_RETRY_DISABLE=1` env var** for debugging? **Recommended: yes**, one line, zero runtime cost. Easier to isolate "is this a retry masking a real error" during incident triage.
- **Do we want per-call override of retry count?** Not in v1 — one policy, one place. Revisit only if a specific call site legitimately needs different behaviour.
