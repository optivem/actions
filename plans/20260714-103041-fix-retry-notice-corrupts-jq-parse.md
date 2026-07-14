# 2026-07-14 10:30:41 UTC — Fix retry-notice text corrupting jq-parsed API responses

## TL;DR

**Why:** `commit-files/commit.sh` and `check-commit-status-exists/check.sh` capture `retry_run`'s output with `2>&1` into a single variable and then feed it straight to `jq`. `retry_run` (via `shared/retry-core.sh:124`) writes a live `::notice::[gh] attempt N failed ... retrying in Ns` line to stderr on every retried-but-eventually-successful attempt. Under `2>&1` that notice text lands ahead of the real JSON in the captured variable, so `jq` chokes with `jq: parse error: Expected string key before ':' at line 1, column 1` (exit 5) any time a retry happens before eventual success — even though the underlying call actually succeeded. This broke production run [optivem/shop#29246178611](https://github.com/optivem/shop/actions/runs/29246178611) (`bump-patch-version / bump` job, 2026-07-13): the first VERSION file committed fine, the second file's GET-current-SHA call hit a transient retry, and the merged notice+JSON broke the jq parse, aborting the whole VERSION-bump step.
**End result:** All `retry_run` callers that jq-parse a response capture stdout and stderr into separate streams, so retry notices never corrupt structured-data parsing regardless of how many retries occurred before success. `shared/retry.sh` documents the gotcha so future action authors don't repeat it.

## Outcomes

- `commit-files/commit.sh` commits VERSION-bump (and any other) files reliably even when the GitHub Contents API GET or PUT call needed a transient retry before succeeding — no more spurious `jq` parse failures aborting a successful commit.
- `check-commit-status-exists/check.sh` correctly evaluates commit-status existence even when its `gh api --paginate` call retried before succeeding, instead of hard-failing on a parse error.
- `shared/retry.sh`'s header comment carries a caveat (alongside the existing stdin caveat) warning callers not to merge `retry_run`'s stdout+stderr via `2>&1` when the result will be parsed as structured data.
- Confirmed locally (not just via code review) that the fix actually prevents the reproduced failure: piping a `::notice::...` line followed by a JSON line no longer breaks the affected parse logic.

## ▶ Next executable step (resume here)

Step 1: edit `commit-files/commit.sh` — replace the `2>&1`-merged capture at the GET-current-SHA call (lines ~48-55) with a separate-stream pattern (stderr to a temp file), keeping the existing 404/not-found detection working against the combined text. This is the exact call site that broke run 29246178611, so it's the highest-value fix and unblocks verifying the repro locally against the real script logic.

## Steps

- [ ] Step 1: In `commit-files/commit.sh`, fix the GET-current-SHA call (~lines 46-55):
  ```bash
  stderr_tmp=$(mktemp)
  if get_out=$(retry_run gh api "repos/$REPOSITORY/contents/$path?ref=$BRANCH" 2>"$stderr_tmp"); then
    current_sha=$(jq -r '.sha' <<<"$get_out")
  elif grep -Eqi '404|Not Found' <<<"$get_out"$'\n'"$(cat "$stderr_tmp")"; then
    current_sha=""
  else
    echo "::error::Failed to read $path from $REPOSITORY@$BRANCH: $get_out $(cat "$stderr_tmp")"
    rm -f "$stderr_tmp"
    exit 1
  fi
  rm -f "$stderr_tmp"
  ```
  Preserve the surrounding retry loop (`attempt`/`committed` bookkeeping) untouched — only the capture/parse shape changes.
- [ ] Step 2: In `commit-files/commit.sh`, apply the same separate-stream pattern to the PUT call (~lines 64-90), covering the `commit_sha`/`content_sha`/`html_url` jq extractions and the existing `does not match|409|422` conflict-retry detection (which must keep working against the combined stdout+stderr text).
- [ ] Step 3: In `check-commit-status-exists/check.sh`, apply the same separate-stream pattern to the `statuses=$(retry_run gh api ... --paginate 2>&1)` call (~lines 15-18), keeping the existing hard-fail error message (which references `$statuses`) informative by including both streams' content in the error text.
- [ ] Step 4: Add a caveat to `shared/retry.sh`'s header comment block (near the existing stdin caveat, ~lines 35-39) documenting: callers must not capture `retry_run`'s output with `2>&1` into a variable that gets parsed as structured data (JSON/etc.) — live per-attempt `::notice::`/`::warning::` diagnostics on stderr will corrupt it; capture streams separately instead.
- [ ] Step 5: Verify — check for and run this repo's shell test harness (`shared/_test-retry.sh`, `shared/_test-retry-core.sh`, and any tests colocated with `commit-files/` or `check-commit-status-exists/`), plus a manual dry run: pipe a `::notice::[gh] attempt 1 failed (exit 1): rate limit -- retrying in 5s` line followed by a JSON line through the fixed capture/parse logic in each of the three call sites and confirm the value now parses correctly (matching the local repro already done during diagnosis).
- [ ] Step 6: Confirm no shop-side changes are needed — shop consumes these actions via the `@v1` tag, so once this repo's fix lands and the `v1` tag/release is updated, `optivem/shop`'s workflows pick up the fix automatically. Note in the plan's close-out whether this repo's release process needs an explicit tag-move/version-bump step (check `CONTRIBUTING.md` or release workflow in this repo) to make v1 point at the fixed commit.

## Open questions

- Does this repo have an automated release process that moves the `v1` major tag on merge to main, or does it need a manual tag update after this fix is merged? (Inferred: assumed automatic based on shop's `@v1` usage pattern — needs confirming against this repo's own release workflow before considering the fix "live" for shop.)
