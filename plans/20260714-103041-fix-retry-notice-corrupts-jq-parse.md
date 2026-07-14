# 2026-07-14 10:30:41 UTC — Fix retry-notice text corrupting jq-parsed API responses

🤖 **Picked up by agent** — `ValentinaLaptop` at `2026-07-14T10:35:49Z`

## TL;DR

**Why:** `commit-files/commit.sh` and `check-commit-status-exists/check.sh` capture `retry_run`'s output with `2>&1` into a single variable and then feed it straight to `jq`. `retry_run` (via `shared/retry-core.sh:124`) writes a live `::notice::[gh] attempt N failed ... retrying in Ns` line to stderr on every retried-but-eventually-successful attempt. Under `2>&1` that notice text lands ahead of the real JSON in the captured variable, so `jq` chokes with `jq: parse error: Expected string key before ':' at line 1, column 1` (exit 5) any time a retry happens before eventual success — even though the underlying call actually succeeded. This broke production run [optivem/shop#29246178611](https://github.com/optivem/shop/actions/runs/29246178611) (`bump-patch-version / bump` job, 2026-07-13): the first VERSION file committed fine, the second file's GET-current-SHA call hit a transient retry, and the merged notice+JSON broke the jq parse, aborting the whole VERSION-bump step.
**End result:** All `retry_run` callers that jq-parse a response capture stdout and stderr into separate streams, so retry notices never corrupt structured-data parsing regardless of how many retries occurred before success. `shared/retry.sh` documents the gotcha so future action authors don't repeat it.

## Outcomes

- `commit-files/commit.sh` commits VERSION-bump (and any other) files reliably even when the GitHub Contents API GET or PUT call needed a transient retry before succeeding — no more spurious `jq` parse failures aborting a successful commit.
- `check-commit-status-exists/check.sh` correctly evaluates commit-status existence even when its `gh api --paginate` call retried before succeeding, instead of hard-failing on a parse error.
- `shared/retry.sh`'s header comment carries a caveat (alongside the existing stdin caveat) warning callers not to merge `retry_run`'s stdout+stderr via `2>&1` when the result will be parsed as structured data.
- Confirmed locally (not just via code review) that the fix actually prevents the reproduced failure: piping a `::notice::...` line followed by a JSON line no longer breaks the affected parse logic.

## ▶ Next executable step (resume here)

Step 5: Verify — the code fixes (Steps 1-4) are already applied to `commit-files/commit.sh`, `check-commit-status-exists/check.sh`, and `shared/retry.sh`. Next, check for `shared/_test-retry.sh` / `shared/_test-retry-core.sh` and any colocated tests, run them, and do a manual dry run confirming a `::notice::...` line followed by JSON no longer breaks the parse in each of the three call sites.

## Steps

## Open questions

None — resolved before execution: `.github/workflows/update-v1.yml` force-retags `v1` to the latest `main` commit on every push (and via `workflow_dispatch`), so merging this fix to `main` automatically makes it live for shop's `@v1` references. No manual tag/version-bump step is needed.
