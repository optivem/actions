# 2026-07-01 05:58:28 UTC — Make `ghcr_bearer_for` status-aware instead of collapsing every failure to "empty bearer"

## TL;DR

**Why:** `check-ghcr-packages-exist` failed in `valentinajemuovic/test-app-f63fa8f5-7482da17578e0506` (run [28495796390](https://github.com/valentinajemuovic/test-app-f63fa8f5-7482da17578e0506/actions/runs/28495796390), job `preflight`, step `Check Container Packages Exist`) with a generic "Token missing or invalid" error. Root cause: `shared/ghcr-probe.sh:38-49` (`ghcr_bearer_for`) never captures the HTTP status of the GHCR token-exchange call — it pipes the raw body straight to `jq -r '.token // empty'`, so every failure mode (expired/revoked/blank PAT, malformed JSON, 401, 403, 5xx, network failure) collapses into the same empty string. This breaks the fail-loud/no-swallow discipline the file already applies one step later in `ghcr_probe_manifest` (lines 58-84), which does branch on 401/403/other.
**End result:** `ghcr_bearer_for` returns enough information (HTTP status + body) for callers to emit a specific, actionable `::error::` message per failure mode (invalid/expired token vs missing scope vs malformed response vs indeterminate/network failure), consistent with the check-* actions no-swallow rule. Verified by a local `_test-ghcr-probe.sh` harness (matching the existing `_test-retry-core.sh` pattern) that fakes `curl` responses for each case.

## Outcomes

- `ghcr_bearer_for()` in `shared/ghcr-probe.sh` distinguishes: clean 200 with missing `.token` field (malformed response), 401 (invalid/expired token), 403 (valid token, wrong scope), and other/network failure (indeterminate) — instead of collapsing all of these into one empty-string return.
- `check-ghcr-packages-exist/check.sh`'s empty-bearer branch (currently lines 35-39) emits a distinct, actionable `::error::` message per case above, matching the specificity already used for the manifest-probe branches (lines 52-63).
- A local smoke-test harness (`shared/_test-ghcr-probe.sh`) exercises `ghcr_bearer_for`'s new branches against faked `curl` responses, without needing a real token.
- Confirmed scope: `check-ghcr-packages-exist/check.sh` is the only caller of `ghcr_bearer_for` in this repo (grepped `ghcr_bearer_for`/`ghcr-probe.sh` across `academy/actions` — only `shared/ghcr-probe.sh` itself and `check-ghcr-packages-exist/check.sh` reference it), so this is a single-caller fix, not a multi-action rollout.
- **Explicitly out of scope:** rotating the `GHCR_TOKEN` PAT for `test-app-f63fa8f5-7482da17578e0506` (created 2026-06-26T12:57:37Z, never rotated, started failing 2026-06-30T22:32 per `gh run list`). That's the acute trigger for the observed run but is an external-credential operational fix, not a code change — do it separately (regenerate the PAT, then re-run `gh-optivem`'s `SetupVariablesAndSecrets` or `gh secret set GHCR_TOKEN --repo valentinajemuovic/test-app-f63fa8f5-7482da17578e0506`).

## ▶ Next executable step (resume here)

Step 1: edit `shared/ghcr-probe.sh`'s `ghcr_bearer_for()` (lines 38-49) to capture the token-exchange HTTP status via `curl -w '\n%{http_code}'`, split body/status, and return a status-tagged result the caller can branch on — mirroring the code-capture style already used in `ghcr_probe_manifest` (lines 58-84).

## Steps

- [ ] Step 1: In `shared/ghcr-probe.sh`, change `ghcr_bearer_for()` (lines 38-49) to capture the token-exchange HTTP status code alongside the body (e.g. `curl -sS -w '\n%{http_code}' ...`, split the trailing status line from the body), and change its output/return contract so the caller can distinguish: 200 + present `.token` (success, unchanged behavior), 200 + missing `.token` (malformed response), 401 (invalid/expired token), 403 (valid token, wrong scope), and any other code or curl failure (indeterminate — treat as fail-hard, not retried, consistent with "anything indeterminate must fail hard" from the check-* actions rule). Keep the function's existing callers working via its stdout/return-code contract — document the new contract in the function's header comment (currently lines 31-37).
- [ ] Step 2: In `check-ghcr-packages-exist/check.sh`, update the empty-bearer branch (currently lines 36-39) to read the new status info from Step 1 and emit a distinct `::error::` message per case, matching the specificity of the existing 401/403/default branches for the manifest probe (lines 52-63) — e.g. "GHCR token exchange returned HTTP 401 for `<path>` — token is invalid or expired", "...HTTP 403 — token lacks read:packages scope", "...malformed response (HTTP 200, no token field) — investigate GHCR", "...HTTP `<code>` — indeterminate, treat as failure".
- [ ] Step 3: Add `shared/_test-ghcr-probe.sh`, following the `_test-retry-core.sh` pattern (fake `curl` binary on `PATH` returning a scripted status+body sequence), asserting `ghcr_bearer_for` produces the right status/message for each of: 200+token, 200 no token, 401, 403, and one indeterminate code (e.g. 500). Run it and confirm all cases pass.
- [ ] Step 4: Run this repo's existing shell lint (`shared/_lint/check-shell-scripts.sh` and friends) against the two edited files to confirm no regressions.

## Open questions

- None — root cause, fix, and verification approach are all pinned to concrete file:line locations and an existing test-harness convention in this repo.
