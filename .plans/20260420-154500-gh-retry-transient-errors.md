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

### Phase 1 — build shared helpers

- [ ] **Create `shared/Invoke-GhWithRetry.ps1`** — PowerShell helper exposing `Invoke-GhWithRetry` (positional args-array parameter, returns the gh output string, throws on final failure with combined attempt history). Encodes the retry policy above. Emits structured `Write-Host` log lines prefixed `[gh-retry]` for each attempt.
  - Affects: new `shared/Invoke-GhWithRetry.ps1`
  - Consumers to update: phase 2 updates 5 `.ps1` scripts
  - Category: new

- [ ] **Create `shared/gh-retry.sh`** — bash helper exposing `gh_retry` function (same policy). Uses `set -o pipefail`-safe patterns, captures combined stdout+stderr, inspects via regex (`grep -Eqi`), sleeps with `sleep`, emits `::notice::[gh-retry] ...` lines per attempt so they surface in the Actions log.
  - Affects: new `shared/gh-retry.sh`
  - Consumers to update: phase 3 updates ~15 `action.yml` files
  - Category: new

- [ ] **Add a small self-test harness** — `shared/_test-gh-retry.sh` + `shared/_test-gh-retry.ps1` that injects a fake `gh` on `$PATH` (or via function override) returning a scripted sequence (e.g. `502, 502, 200`) and asserts the wrapper retries + succeeds. Run locally during development; not wired into CI unless trivial.
  - Affects: new `shared/_test-gh-retry.*`
  - Consumers to update: 0
  - Category: new

### Phase 2 — migrate PowerShell scripts

For each file: dot-source the helper at the top, replace every `& gh @args` / `gh ...` invocation with `Invoke-GhWithRetry @args`, keep argument construction identical. Do not retry `gh auth status` (that's a local auth probe, not an API call). Do not retry commands whose non-zero exit code is already used for flow control (e.g. `gh release view` to detect absence — the 404 case is non-transient and the wrapper won't retry it, but double-check each site).

- [ ] **Migrate `create-github-release/Create-Release.ps1`** — 3 `gh` calls: `gh auth status` (skip — local), `gh release view` (wrap — 404 is non-retryable so safe), `gh release delete`, `gh release create` (the one that just 502'd).
  - Affects: `create-github-release/Create-Release.ps1`
  - Consumers to update: 0 (action contract unchanged)
  - Category: refactor

- [ ] **Migrate `cleanup-prereleases/Cleanup-PrereleaseVersions.ps1`** — 10 `gh` calls (list, view, delete loop). Wrapping is high-value: this script does bulk ops and any mid-loop 502 today aborts the whole cleanup.
  - Affects: `cleanup-prereleases/Cleanup-PrereleaseVersions.ps1`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `cleanup-deployments/Cleanup-Deployments.ps1`** — 5 `gh` calls.
  - Affects: `cleanup-deployments/Cleanup-Deployments.ps1`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `ensure-release-exists/Check-VersionReleaseExists.ps1`** — 1 `gh` call (release-exists probe). Wrap; 404 stays non-retryable so the probe semantics are preserved.
  - Affects: `ensure-release-exists/Check-VersionReleaseExists.ps1`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `find-release-by-run/Find-ReleaseByRun.ps1`** — 1 `gh api graphql` call.
  - Affects: `find-release-by-run/Find-ReleaseByRun.ps1`
  - Consumers to update: 0
  - Category: refactor

### Phase 3 — migrate `action.yml` inline bash steps

Pattern for each step: before any `gh ...` line, add `source "$GITHUB_ACTION_PATH/../shared/gh-retry.sh"` once at the top of the `run:` block, then replace `gh ...` with `gh_retry ...`. Preserve all existing flags, jq filters, output redirection. Skip `gh auth status` probes.

- [ ] **Migrate `trigger-and-wait/action.yml`** — 5 `gh` sites: `gh api rate_limit` (×2 — skip, local-only rate-limit check), `gh workflow run`, `gh run list`, `gh run watch`. Wrap the last three.
  - Affects: `trigger-and-wait/action.yml`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `wait-for-commit-run/action.yml`** — 5 `gh` sites. Wrap all API-bound ones.
  - Affects: `wait-for-commit-run/action.yml`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `bump-patch-versions/action.yml`** — 3 `gh` sites.
  - Affects: `bump-patch-versions/action.yml`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate `resolve-prerelease-tag/action.yml`** — 2 `gh` sites.
  - Affects: `resolve-prerelease-tag/action.yml`
  - Consumers to update: 0
  - Category: refactor

- [ ] **Migrate remaining single-call action.yml files** — `check-artifacts-exist`, `create-commit-status`, `create-github-release` (wrapper-yml's own `gh` if any beyond the PS1), `get-commit-status`, `has-unverified-sha`, `has-update-since-last-run`, `resolve-commit`, `resolve-tag-from-sha`, `summarize-system-stage`. One `gh` call each. Batch into a single PR if diffs stay small.
  - Affects: 9 `action.yml` files
  - Consumers to update: 0
  - Category: refactor

### Phase 4 — guardrails

- [ ] **Add a lint check to prevent raw `gh ` usage going forward** — A small script (bash or PS1) under `shared/_lint/check-no-raw-gh.sh` that greps every `action.yml` and `*.ps1` outside `shared/` for `\bgh\s+(api|release|workflow|run|repo|pr|issue)` and fails if any match is not preceded by `gh_retry` / `Invoke-GhWithRetry`. Wire into a GitHub Action workflow in the `optivem/actions` repo that runs on PRs. Whitelist `gh auth status` and `gh api rate_limit`.
  - Affects: new `shared/_lint/check-no-raw-gh.sh`, new `.github/workflows/lint-gh-usage.yml`
  - Consumers to update: 0
  - Category: new

- [ ] **Document the pattern in `README.md`** — Short section: "Calling `gh` from actions — use the retry wrappers" with a minimal before/after snippet for both shells and a pointer to `shared/`.
  - Affects: `README.md`
  - Consumers to update: 0
  - Category: docs

### Phase 5 — verification

- [ ] **Re-run the failed pipeline** — Trigger `meta-prerelease-stage` on `optivem/shop` main after phases 1–3 merge and tag-bump of `@v1`. Confirm the previously-failing `Promote Prerelease (QA Deployed)` step succeeds (even if GitHub API is healthy — this just confirms no regressions). Bonus: inject a controlled 502 via a test-only flag on the PS1 helper to confirm retry surfaces in logs end-to-end.
  - Affects: runtime verification only
  - Consumers to update: 0
  - Category: verification

- [ ] **Audit other actions repos for the same pattern** — `gh-optivem`, `github-utils`, `courses` CI — if any contain `gh` invocations without retry, either port the helper or at minimum file a follow-up plan. Out of scope for this plan's code changes; include as a one-line summary after verification.
  - Affects: survey only
  - Consumers to update: 0
  - Category: verification

## Open decisions

- **Retry count / backoff tuning**: 4 attempts × 5/15/45s is a starting point (~65s worst-case added latency). If telemetry later shows 502s are very brief, drop to 3 × 5/15s. Defer tuning until we see real data.
- **Should `gh_retry` honour a `GH_RETRY_DISABLE=1` env var** for debugging? **Recommended: yes**, one line, zero runtime cost. Easier to isolate "is this a retry masking a real error" during incident triage.
- **Do we want per-call override of retry count?** Not in v1 — one policy, one place. Revisit only if a specific call site legitimately needs different behaviour.
