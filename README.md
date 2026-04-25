# optivem/actions

## Versioning policy — stay on `@v1`

This repo is a single-consumer project (only the `optivem` org workspace uses it). We **do not bump the major tag** on breaking input renames or removals — the `@v1` tag gets moved to the new commit, and all callers inside the workspace are updated atomically in the same change.

This deliberately violates SemVer. It's safe here because:

- There are no external consumers pinned to `@v1` who could silently break.
- All callers live alongside the actions in this workspace and move together.
- Skipping `@v2`/`@v3` cycles avoids churn that buys nothing when the consumer graph is `{self}`.

If this repo ever gains an external consumer, revisit this policy and start cutting proper major tags.

## Shell choice — bash only

All actions in this repo run on GitHub-hosted Linux runners, so pwsh buys nothing a bash toolchain doesn't already cover. To avoid paying every cross-cutting concern twice (retry wrappers, lint rules, structured logging, auth), **all production code is bash-only**:

- `action.yml` steps use `shell: bash`.
- Scripts are `.sh`, not `.ps1`. Inline the bash directly in `action.yml` when practical — it's the prevailing pattern in this repo.
- Use [shared/gh-retry.sh](shared/gh-retry.sh) (`gh_retry` wrapper) for any `gh` CLI calls, and `jq` for JSON handling.
- UTF-8 shell is assumed. Several actions emit emoji (✅ ❌ 🚀 📦) to `$GITHUB_STEP_SUMMARY`. GitHub-hosted Linux runners default to UTF-8 so this is transparent; any self-hosted runner must run bash under a UTF-8 locale.

Two lint checks enforce the conventions:
- [shared/_lint/check-no-pwsh.sh](shared/_lint/check-no-pwsh.sh) (via `.github/workflows/lint-shell-policy.yml`) fails PRs that contain any `shell: pwsh` or `.ps1` files (except `shared/_test-*` harnesses).
- [shared/_lint/check-no-raw-gh.sh](shared/_lint/check-no-raw-gh.sh) (via `.github/workflows/lint-gh-usage.yml`) fails PRs that call `gh` without the `gh_retry` wrapper. Whitelist: `gh auth status`, `gh api rate_limit`.

## Actions

| Action | Inputs | Outputs |
|---|---|---|
| [bump-patch-versions](#bump-patch-versions) | • `version-files`<br>• `repository`<br>• `token` | • `bumps`<br>• `bumped`<br>• `summary` |
| [check-changes-since-tag](#check-changes-since-tag) | • `tag-patterns`<br>• `paths` | • `changed`<br>• `baseline-tag`<br>• `baseline-sha`<br>• `changed-files` |
| [check-commit-status-exists](#check-commit-status-exists) | • `commit-sha`<br>• `status-context`<br>• `head-sha`<br>• `repository`<br>• `token` | • `exists`<br>• `created-at` |
| [check-ghcr-packages-exist](#check-ghcr-packages-exist) | • `image-urls`<br>• `tag`<br>• `token`<br>• `fail-on-error` | • `exist`<br>• `results` |
| [check-sha-on-branch](#check-sha-on-branch) | • `commit-sha`<br>• `base-branch` | • `on-branch` |
| [check-tag-exists](#check-tag-exists) | • `tag`<br>• `repository`<br>• `token`<br>• `git-host` | • `exists` |
| [check-timestamp-newer](#check-timestamp-newer) | • `latest`<br>• `since` | • `newer` |
| [cleanup-deployments](#cleanup-deployments) | • `keep-count`<br>• `retention-days`<br>• `protected-environments`<br>• `delete-delay-seconds`<br>• `rate-limit-threshold`<br>• `dry-run`<br>• `token` | • `deleted-count`<br>• `dry-run-count` |
| [cleanup-prereleases](#cleanup-prereleases) | • `retention-days`<br>• `container-packages`<br>• `delete-delay-seconds`<br>• `rate-limit-threshold`<br>• `dry-run`<br>• `token` | • `deleted-count`<br>• `dry-run-count` |
| [commit-files](#commit-files) | • `files`<br>• `branch`<br>• `max-retries`<br>• `token` | • `commits`<br>• `committed` |
| [compose-docker-image-urls](#compose-docker-image-urls) | • `tag`<br>• `base-image-urls` | • `image-urls` |
| [compose-prerelease-status](#compose-prerelease-status) | • `prerelease-version`<br>• `environment`<br>• `status` | • `status-tag` |
| [compose-prerelease-version](#compose-prerelease-version) | • `base-version`<br>• `suffix`<br>• `build-number`<br>• `prefix` | • `version` |
| [compose-release-version](#compose-release-version) | • `prerelease-version` | • `version` |
| [compose-tags](#compose-tags) | • `versions`<br>• `template` | • `tags` |
| [create-commit-status](#create-commit-status) | • `commit-sha`<br>• `context`<br>• `state`<br>• `description`<br>• `target-url`<br>• `token` | — |
| [deploy-docker-compose](#deploy-docker-compose) | • `environment`<br>• `version`<br>• `image-urls`<br>• `compose-file`<br>• `working-directory` | — |
| [evaluate-run-gate](#evaluate-run-gate) | • `skip-conditions` | • `should-run`<br>• `skip-reason` |
| [format-artifact-list](#format-artifact-list) | • `artifacts` | • `formatted` |
| [generate-release-notes](#generate-release-notes) | • `prerelease-version`<br>• `release-version`<br>• `artifact-urls` | • `title`<br>• `notes-file` |
| [get-commit-status](#get-commit-status) | • `commit-sha`<br>• `context`<br>• `state`<br>• `repository`<br>• `token` | • `description`<br>• `state`<br>• `target-url` |
| [get-last-workflow-run](#get-last-workflow-run) | • `workflow-name`<br>• `repository`<br>• `exclude-run-id`<br>• `token` | • `timestamp`<br>• `status`<br>• `conclusion` |
| [publish-tag](#publish-tag) | • `tag`<br>• `commit-sha`<br>• `repository`<br>• `git-host`<br>• `token` | — |
| [read-base-version](#read-base-version) | • `file` | • `base-version` |
| [read-base-versions](#read-base-versions) | • `entries` | • `versions` |
| [render-stage-summary](#render-stage-summary) | • `stage-name`<br>• `stage-result`<br>• `stage-content`<br>• `stage-success-content`<br>• `stage-skipped-content` | — |
| [render-system-stage-summary](#render-system-stage-summary) | • `stage-name`<br>• `stage-result`<br>• `environment`<br>• `success-version`<br>• `success-artifact-ids`<br>• `skipped-reason`<br>• `latest-artifact-ids`<br>• `latest-updated-at`<br>• `last-run-at` | — |
| [resolve-commit](#resolve-commit) | • `repository`<br>• `ref`<br>• `token`<br>• `git-host` | • `sha`<br>• `timestamp` |
| [resolve-docker-image-digests](#resolve-docker-image-digests) | • `base-image-urls`<br>• `tag` | • `image-digest-urls`<br>• `latest-updated-at` |
| [resolve-latest-prerelease-tag](#resolve-latest-prerelease-tag) | • `tag-prefix`<br>• `tag-suffix`<br>• `repository`<br>• `token`<br>• `git-host` | • `tag`<br>• `base-tag` |
| [resolve-latest-tag-from-sha](#resolve-latest-tag-from-sha) | • `repository`<br>• `commit-sha`<br>• `pattern`<br>• `token`<br>• `git-host` | • `tag` |
| [tag-docker-images](#tag-docker-images) | • `image-urls`<br>• `tag`<br>• `image-tags`<br>• `registry`<br>• `registry-username`<br>• `token` | • `tagged-image-urls` |
| [trigger-and-wait-for-workflow](#trigger-and-wait-for-workflow) | • `workflow`<br>• `repository`<br>• `ref`<br>• `workflow-inputs`<br>• `poll-interval`<br>• `rate-limit-threshold`<br>• `timeout-seconds`<br>• `token` | • `run-id` |
| [validate-env-vars-defined](#validate-env-vars-defined) | • `names` | — |
| [validate-tag-exists](#validate-tag-exists) | • `tag`<br>• `repository`<br>• `token`<br>• `git-host` | — |
| [wait-for-endpoints](#wait-for-endpoints) | • `endpoints`<br>• `compose-file`<br>• `working-directory`<br>• `max-attempts`<br>• `wait-seconds`<br>• `timeout-seconds` | — |
| [wait-for-workflow](#wait-for-workflow) | • `workflow`<br>• `commit-sha`<br>• `repository`<br>• `poll-interval`<br>• `watch-interval`<br>• `max-discovery-attempts`<br>• `rate-limit-threshold`<br>• `timeout-seconds`<br>• `token` | • `run-id` |

### bump-patch-versions

For each `{path, signal, value}` entry, reads the VERSION file and — if the matching artifact already exists — computes a patch bump. Each entry picks one signal source: `git-tag` probes a tag on the remote via `git ls-remote`; `ghcr-image` probes a GHCR image manifest. Reads only; writes nothing to disk. Pair with `commit-files` to persist the bumps.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `version-files` | yes | — | JSON array of `{"path": string, "signal": "git-tag"\|"ghcr-image", "value": string}` objects. `git-tag`: bump if tag `{value}{current-version}` exists on the remote (e.g. `value="meta-v"` + version `1.0.40` probes tag `meta-v1.0.40`). `ghcr-image`: bump if GHCR image `{value}:v{current-version}` exists (e.g. `value="ghcr.io/optivem/shop/backend-java"` + version `1.5.24` probes that image at `:v1.5.24`). |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format (used for `git-tag` probes) |
| `token` | no | `${{ github.token }}` | Token for git remote auth and GHCR auth |

**Outputs**

| Name | Description |
|---|---|
| `bumps` | JSON array of `{path, old-version, new-version, release-signal}` for files that need bumping. `release-signal` is the concrete artifact reference (tag name or `image:tag`). |
| `bumped` | `true` if at least one file needs bumping |
| `summary` | Human-readable summary (one line per file, bumped or skipped) |

### check-changes-since-tag

Walks tag patterns in priority order, resolves the most recent matching tag as a baseline, and runs `git diff --name-only baseline HEAD -- <paths>` to detect whether the given pathspecs have changed. Fail-open: if no tag matches any pattern, reports `changed=true`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag-patterns` | yes | — | Newline-separated git tag globs in priority order. The first pattern that matches at least one tag wins; the most recent match within that pattern (by `git tag --sort=-version:refname`) is used as the baseline. |
| `paths` | yes | — | Newline-separated path filters passed to `git diff`. Supports any pathspec syntax (directories, globs, `:(exclude)`...). |

**Outputs**

| Name | Description |
|---|---|
| `changed` | `true` if any of the specified paths changed between the baseline tag's SHA and HEAD. Also `true` (fail-open) if no baseline tag matched any pattern. `false` only when a baseline was found AND no paths changed. |
| `baseline-tag` | The tag used as the comparison baseline. Empty if no tag matched. |
| `baseline-sha` | Commit SHA of the baseline tag. Empty if no tag matched. |
| `changed-files` | Newline-separated list of changed files under the specified paths. Empty if no changes. |

**Notes:** Requires the caller to have checked out with `fetch-depth: 0` (or equivalent) so tag history is available. A defensive `git fetch --tags` runs first.

### check-commit-status-exists

Boolean existence check for a success commit-status on `head-sha` matching `(context, description=commit-sha)`. Returns `exists=true` when the status is present, `false` otherwise. Caller-defined semantics — the caller picks the `status-context` label, the action only reports presence. Fails open to `exists=false` on transient API errors so callers never silently skip work. Pairs with `create-commit-status` (write) and `get-commit-status` (read state).

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `commit-sha` | yes | — | Commit SHA to look up in the `description` field of commit-statuses (typically an upstream-repo commit the pipeline previously processed). |
| `status-context` | yes | — | The commit-status context to search for (e.g. `acceptance-stage`). Matched against the `context` field. Caller-chosen label encoding the type of check; no verb suffix — the `state` field carries the outcome. |
| `head-sha` | no | `${{ github.sha }}` | Commit whose statuses are inspected |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `exists` | `true` when a success commit-status on head-sha matches the given context + description=commit-sha. `false` when none found. Fails open to `false` on transient API errors. |
| `created-at` | ISO 8601 `createdAt` of the matching success status, if one was found. Empty otherwise. |

### check-ghcr-packages-exist

Probes GHCR packages to determine whether a tag exists for each, via OCI `HEAD /v2/{path}/manifests/{tag}`. Each input line is either a plain `ghcr.io/{owner}/{repo}/{image}` path (probed with the default `tag` input) or `ghcr.io/{owner}/{repo}/{image}:{tag}` (per-line tag override). Works uniformly for user- and org-owned repos and for public/private packages. Two usage shapes: preflight gate — read the any-of `exist` output; per-image probe — read the keyed `results` output. Auth/unexpected-HTTP errors are soft by default (treated as missing); set `fail-on-error=true` for strict mode.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `image-urls` | yes | — | Newline-separated list of GHCR packages to probe. Each line is either `ghcr.io/{owner}/{repo}/{image}` (uses the default `tag` input) or `ghcr.io/{owner}/{repo}/{image}:{tag}` (per-line tag override). OCI image paths contain no `:` so the tag separator is unambiguous. |
| `tag` | no | `latest` | Default tag to probe when a line omits its own `:tag` suffix. `latest` is the reliable "any artifact has been built" signal since the commit stage always publishes it alongside versioned tags. |
| `token` | no | `${{ github.token }}` | Token used for GHCR authentication. |
| `fail-on-error` | no | `false` | If `true`, fail the step on authentication errors, unexpected HTTP codes, or token-exchange failures. If `false` (default), those conditions emit a warning and the affected entry is reported as `exists=false`. Strict mode is appropriate for release-gate checks where an auth error must not be silently swallowed. |

**Outputs**

| Name | Description |
|---|---|
| `exist` | Whether any of the probed packages have the probed tag published (`true`/`false`). In soft-fail mode (the default), authentication errors resolve this to `false` — the downstream stage will surface a clearer error if packages are genuinely missing vs. unauthorized. |
| `results` | JSON array of `{"image": string, "tag": string, "exists": boolean}` objects, one entry per input line. `image` is the URL without any `:tag` suffix; `tag` is the effective tag probed (per-line override if given, else the `tag` input default). Preserves input order. |

### check-sha-on-branch

Fetches the base branch from origin and runs `git merge-base --is-ancestor <sha> origin/<base-branch>` to determine whether the SHA is in the branch's history. Writes the result to `$GITHUB_STEP_SUMMARY`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `commit-sha` | no | `${{ github.sha }}` | Git SHA to check |
| `base-branch` | no | `main` | Base branch to check ancestry against |

**Outputs**

| Name | Description |
|---|---|
| `on-branch` | `true` if the SHA is an ancestor of the base branch, `false` otherwise |

**Notes:** Use to guard downstream steps against `workflow_dispatch` inputs pointing at commits not in the base branch.

### check-tag-exists

Queries a remote git repository with `git ls-remote --tags "refs/tags/<tag>"` and reports whether at least one tag matches. Accepts either an exact tag or a glob pattern. Tool-agnostic — no platform API dependency.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Exact tag or glob pattern to match (e.g., `monolith-java-v1.0.0` or `meta-v*`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

**Outputs**

| Name | Description |
|---|---|
| `exists` | Whether at least one matching tag exists (`true`/`false`) |

### check-timestamp-newer

Pure ISO 8601 timestamp comparator. Lexicographically compares `latest` against `since` — outputs `newer=true` when `latest` is strictly newer, OR when `since` is empty (fail-open). Outputs `newer=false` when `since` is set and `latest` is not newer. No platform dependency.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `latest` | yes | — | ISO 8601 timestamp under observation (e.g. latest docker image push time, latest artifact build time, latest commit timestamp). |
| `since` | no | `` | ISO 8601 timestamp to compare against (typically the last-run timestamp). When empty, the action returns `newer=true` (fail-open — useful for "first run" semantics). |

**Outputs**

| Name | Description |
|---|---|
| `newer` | `true` when `latest` is strictly newer than `since`, OR when `since` is empty (fail-open). `false` when `since` is set AND `latest` is not newer than it. |

**Notes:** ISO 8601 lexicographic comparison is only correct when both timestamps are UTC with the same format (both Z-suffixed). GitHub API and typical observed timestamps (docker push times, git commit times) satisfy this.

### cleanup-deployments

Fetches all GitHub deployments and deletes superseded ones, subject to a per-environment count cap and a retention-days floor. Delegates to `cleanup-deployments.sh` in the action directory. Protects configured environments and RCs (via git tag lookup).

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `keep-count` | no | `3` | Per-environment count cap: keep this many newest deployments; candidates beyond the cap are eligible for deletion if past `retention-days` |
| `retention-days` | no | `30` | Retention floor in days. Deployments beyond `keep-count` are only deleted once older than this cutoff |
| `protected-environments` | no | `*-production,production` | Comma-separated list of environment name patterns whose deployments must never be deleted. Supports `*` wildcards, case-insensitive |
| `delete-delay-seconds` | no | `10` | Seconds to wait between each API delete call to avoid GitHub rate limiting |
| `rate-limit-threshold` | no | `50` | Pause before each API delete when remaining core-rate-limit requests fall below this number (set `0` to disable) |
| `dry-run` | no | `false` | If `true`, only log what would be deleted without actually deleting anything |
| `token` | no | `${{ github.token }}` | GitHub token used for deployment API calls |

**Outputs**

| Name | Description |
|---|---|
| `deleted-count` | Number of deployments actually deleted (real mode only; `0` in dry-run) |
| `dry-run-count` | Number of deployments that would be deleted (dry-run mode only; `0` in real mode) |

**Notes:**
- **Released-RC deployments** (final tag `vX.Y.Z` exists): immediately deletes any deployment whose SHA matches a `vX.Y.Z-rc.*` tag; bypasses both `keep-count` and `retention-days`.
- **Superseded per environment** (count cap + retention floor): keeps the newest `keep-count` deployments per environment; anything beyond the cap is deleted only once older than `retention-days` (the floor prevents pruning fresh bursts during active debugging).
- **Protected environments** are never touched by either scenario.
- **Ordering:** run this action **before** `cleanup-prereleases` in the same workflow — the released-RC logic relies on RC git tags being present to resolve SHAs, and `cleanup-prereleases` deletes those tags immediately for released versions.

### cleanup-prereleases

Cleans up prerelease git tags, GitHub releases, and (optionally) Docker image tags that are no longer needed. Delegates to `cleanup-prereleases.sh` in the action directory. Rate-limit-aware.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `retention-days` | no | `30` | Number of days to retain prerelease Docker image tags after release, and superseded RC artifacts before release |
| `container-packages` | no | `` | Comma-separated list of container package names for Docker image tag cleanup (e.g., `"myapp,myapp-worker"`). If empty, Docker cleanup is skipped. |
| `delete-delay-seconds` | no | `10` | Seconds to wait between each API delete call to avoid GitHub rate limiting |
| `rate-limit-threshold` | no | `50` | Pause before each API delete when remaining core-rate-limit requests fall below this number (set `0` to disable) |
| `dry-run` | no | `false` | If `true`, only log what would be deleted without actually deleting anything |
| `token` | no | `${{ github.token }}` | GitHub token used for tag, release, and package API calls |

**Outputs**

| Name | Description |
|---|---|
| `deleted-count` | Number of items (git tags, GitHub releases, Docker image tags) actually deleted (real mode only; `0` in dry-run) |
| `dry-run-count` | Number of items that would be deleted (dry-run mode only; `0` in real mode) |

**Notes:**
- **Released versions** (final tag `vX.Y.Z` exists): immediately deletes prerelease GitHub releases + git tags (`vX.Y.Z-rc.*`, `vX.Y.Z-rc.*-qa-*`); after the retention period, deletes prerelease Docker image tags.
- **Superseded prereleases** (no final release yet): after the retention period, deletes older RCs + their status tags + Docker image tags; never deletes the latest RC.
- **Ordering:** run `cleanup-deployments` first (see its Notes).

### commit-files

For each `{path, content, message}` entry, reads the current file SHA from the GitHub Contents API (if any), base64-encodes the new content, and `PUT`s it with the SHA precondition. Retries on HTTP 409/422 (SHA conflict) with exponential backoff. Race-safe alternative to `git push` for concurrent workflows on the same branch.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `files` | yes | — | JSON array of `{path, content, message}` entries. `path` is repo-relative, `content` is the full new file content (plain text, will be base64-encoded before PUT), `message` is the commit message for that file. |
| `branch` | yes | — | Branch to commit to (e.g. `main`). Pass explicitly — do not rely on `github.ref_name`: on tag pushes it is the tag name, and on `workflow_call`/`workflow_dispatch` it is the caller/dispatcher ref, neither of which is a safe commit target. |
| `max-retries` | no | `3` | Maximum number of retries per file on SHA-precondition conflict (HTTP 409/422) |
| `token` | no | `${{ github.token }}` | GitHub token with `contents:write` permission on the target branch |

**Outputs**

| Name | Description |
|---|---|
| `commits` | JSON array of `{path, commit-sha, content-sha, html-url}` for each file that was committed |
| `committed` | `true` if at least one file was committed |

### compose-docker-image-urls

Pure string helper. Takes a list of base image URLs (JSON array or newline-separated) and a tag, and returns a JSON array of `{base}:{tag}` URLs. No registry lookup. Delegates to `compose-docker-image-urls.sh`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Tag to append to base image URLs (e.g., `v1.0.0-rc.1`) |
| `base-image-urls` | yes | — | Base image URLs (without tag). Accepts either JSON array format or newline-separated list |

**Outputs**

| Name | Description |
|---|---|
| `image-urls` | JSON array of resolved image URLs with tags |

### compose-prerelease-status

Pure string transform. Concatenates `{prerelease-version}-{environment}-{status}` to compose a status-marker git tag (e.g., `v1.0.0-rc.1` + `qa` + `deployed` → `v1.0.0-rc.1-qa-deployed`). Validates inputs are non-empty and `status` is one of `deployed`, `passed`, `failed`, `approved`, `rejected`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `prerelease-version` | yes | — | Prerelease version to build from (e.g., `v1.0.0-rc.1`) |
| `environment` | yes | — | Environment name (e.g., `qa`, `staging`, `prod`) |
| `status` | yes | — | Status marker. Must be one of: `deployed`, `passed`, `failed`, `approved`, `rejected`. |

**Outputs**

| Name | Description |
|---|---|
| `status-tag` | Composed status-marker tag string (e.g., `v1.0.0-rc.1-qa-deployed`). Not a SemVer version — a git tag marker for pipeline gates. |

### compose-prerelease-version

Pure string transform. Validates `base-version` matches `X.Y.Z` and composes `v{version}-{suffix}.{build-number}` (or `{prefix}-v{version}-{suffix}.{build-number}` when a prefix is supplied).

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `base-version` | yes | — | Base semantic version the prerelease parts are appended to (e.g., `1.0.0`) |
| `suffix` | yes | — | Prerelease suffix (e.g., `rc`, `dev`, `alpha`, `beta`) |
| `build-number` | yes | — | CI build counter appended after the suffix (e.g., `github.run_number`). Forms the second dot-separated pre-release identifier per SemVer. |
| `prefix` | no | `` | Optional prefix prepended to the tag. Produces `{prefix}-v{version}-{suffix}.{build-number}` when set, else `v{version}-{suffix}.{build-number}` |

**Outputs**

| Name | Description |
|---|---|
| `version` | The composed prerelease version string |

### compose-release-version

Pure string transform. Strips any SemVer prerelease identifier of the shape `-<word>.<number>` (e.g., `v1.0.0-rc.1` → `v1.0.0`, `v1.0.0-nightly.42` → `v1.0.0`). Preserves the leading `v` if present on input.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `prerelease-version` | yes | — | Prerelease version to convert. Accepts any SemVer prerelease identifier of the form `-<word>.<number>` (e.g., `v1.0.0-rc.1`, `v1.0.0-alpha.1`, `v1.0.0-dev.3`, `v1.0.0-nightly.42`). |

**Outputs**

| Name | Description |
|---|---|
| `version` | Release version with the prerelease identifier removed (e.g., `v1.0.0`) |

### compose-tags

Pure string transform over a keyed list. For each `{key, version}` entry, applies a template (default `v{version}`) and emits `{key, tag}`. Key is opaque and preserved — the action doesn't know or care what it represents. Pairs naturally with `read-base-versions` upstream and `tag-docker-images` (map mode) downstream, but works for any caller that wants batched version → tag templating.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `versions` | yes | — | JSON array of `{"key": string, "version": string}` objects |
| `template` | no | `v{version}` | Template string containing the `{version}` placeholder |

**Outputs**

| Name | Description |
|---|---|
| `tags` | JSON array of `{"key": string, "tag": string}` objects. Keys preserved from input; tags produced by substituting `{version}` in the template. |

### create-commit-status

Calls `gh api repos/{repo}/statuses/{sha}` (via `gh_retry`) to POST a commit status with the given context, state, description, and target URL. Defaults `sha` to `github.sha` and `target-url` to the current workflow run URL.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `commit-sha` | no | `` | Commit SHA to attach the status to. Empty = current commit (`github.sha`). |
| `context` | yes | — | Status context (label shown on the commit) |
| `state` | no | `success` | Status state: `success`, `failure`, `pending`, or `error` |
| `description` | no | `` | Short human-readable description (often the subject identifier, e.g. the verified upstream SHA) |
| `target-url` | no | `` | URL the status links to. Empty = link to the current workflow run. |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

### deploy-docker-compose

Runs `docker compose up -d` (optionally with `-f <compose-file>`) from a working directory — the local-deployment stepping stone from the Farley deploy vocabulary. The `environment`, `version`, and `image-urls` inputs are logged for operator visibility but do not alter behavior. Pair with `wait-for-endpoints` to verify readiness after deployment.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `environment` | yes | — | Display-only label shown in step logs (e.g., acceptance, qa, production). Required — every run must announce its target. The action does not route based on this value. |
| `version` | yes | — | Display-only version label shown in step logs (e.g., `v1.0.0-rc.1`). Required — every run must announce the version being deployed. The action does not select artifacts based on this value. |
| `image-urls` | yes | — | Docker image URLs being run (JSON array format) — surfaced in logs |
| `compose-file` | no | `` | Docker Compose file to use (e.g., `docker-compose.yml`) |
| `working-directory` | yes | — | Working directory containing the Docker Compose file |

### evaluate-run-gate

Aggregates multiple skip signals into a single go/no-go decision for a pipeline stage. Evaluates `skip-conditions` in priority order; the first entry whose `when` is true wins and yields `should-run=false` plus its `reason`. If none match, `should-run=true` and `skip-reason` is empty. Generic — use for any stage that composes multiple skip signals (release race, stale artifacts, missing inputs, etc.).

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `skip-conditions` | yes | — | JSON array of `{"when": boolean, "reason": string}` entries, evaluated in priority order. Caller composes each `when` from GitHub Actions expressions (e.g. `${{ steps.x.outputs.y == 'true' }}`) so the boolean is already resolved before the action runs. |

**Outputs**

| Name | Description |
|---|---|
| `should-run` | `"true"` when no skip-condition matched, `"false"` when one did. |
| `skip-reason` | The reason from the first matching skip-condition, or empty string when `should-run=true`. |

### format-artifact-list

Pure string transform. Splits a newline-separated list of identifiers, trims whitespace, drops blank lines, and formats as a bulleted markdown list (`• <item>` per line). Returns an empty string if the input is blank.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `artifacts` | no | `` | Newline-separated artifact identifiers (e.g. a single `docker.io/app:v1` or multiple entries via a multiline YAML string). Empty string returns empty output. |

**Outputs**

| Name | Description |
|---|---|
| `formatted` | Bulleted markdown list (one `• <item>` per line). Empty string if no artifacts provided. |

### generate-release-notes

Generates a production-release title and a markdown notes file (written to a `mktemp` path on the runner filesystem) for the release being cut. Returns both the title and the notes-file path so the caller can pass them to `softprops/action-gh-release` or equivalent. Production-deployment releases only — the `🚀 <release-version> PROD` title shape is hardcoded because every caller to date emits prod-deployed release notes. If a QA / signoff / acceptance variant is ever needed, write a sibling action.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `prerelease-version` | yes | — | The prerelease RC tag being promoted (e.g., `v1.0.0-rc.1`). Shown in the notes body as the version this release was promoted from. |
| `release-version` | yes | — | The final SemVer release being cut (e.g., `v1.0.0`). Used as the release title version. |
| `artifact-urls` | no | `[]` | JSON array of artifact URLs to include under an Artifacts section of the notes. Empty array or empty string skips the section. |

**Outputs**

| Name | Description |
|---|---|
| `title` | Composed release title (e.g., `"🚀 v1.0.0 PROD"`) |
| `notes-file` | Absolute path to a temp file on the runner filesystem (plain markdown, UTF-8). Valid only for the duration of the current job. |

### get-commit-status

Reads commit statuses via `gh api repos/{repo}/commits/{sha}/statuses` and selects the first match by context (and optionally state). Returns empty outputs if no match is found (caller-side check required). Writes description/state/target-url to outputs and appends a line to `$GITHUB_STEP_SUMMARY`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `commit-sha` | yes | — | Commit SHA to read the status from |
| `context` | yes | — | Status context to look up |
| `state` | no | `success` | Required state filter (`success`, `failure`, `pending`, `error`). Empty = any state. |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `description` | The description field of the matched status |
| `state` | The state of the matched status |
| `target-url` | The `target_url` of the matched status |

### get-last-workflow-run

Returns metadata of the most recent run of a given workflow (excluding the current run by default), queried via `gh run list`. Outputs `timestamp`, `status`, and `conclusion` — all empty when no previous run exists. Pair `timestamp` with `check-timestamp-newer` to skip stages when nothing has changed since the last run.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `workflow-name` | yes | — | Workflow file name or display name to query (e.g. `github.workflow`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form |
| `exclude-run-id` | no | `${{ github.run_id }}` | Run ID to exclude from results — typically the current run, so the action returns the previous run. Set to empty string to disable exclusion. |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `timestamp` | ISO 8601 `createdAt` of the last run. Empty if no previous run exists. |
| `status` | Status of the last run (`queued`, `in_progress`, `completed`, etc.). Empty if no previous run exists. |
| `conclusion` | Conclusion of the last run (`success`, `failure`, `cancelled`, `skipped`, etc.). Empty if the run has not completed, or if no previous run exists. |

### publish-tag

Publishes a git tag to origin at a given commit SHA (or current HEAD) using the `github-actions[bot]` identity. Idempotent — no-ops if the tag already exists at the same commit, tolerates concurrent creation, fails hard only if the remote tag points at a different commit.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Git tag name to create (e.g., `v1.0.3-rc.1`) |
| `commit-sha` | no | `` | Commit SHA to tag. Empty = current HEAD. |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `git-host` | no | `github.com` | Git host to push to (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |
| `token` | no | `${{ github.token }}` | Token used to push the tag. Pass a PAT or GitHub App token with `workflows:write` when the tagged commit contains workflow file changes that differ from the default branch — `GITHUB_TOKEN` cannot push such refs. |

### read-base-version

Reads the first line of a VERSION file (stripping whitespace) and exposes it as an output. Fails the step if the file does not exist.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `file` | no | `VERSION` | Path to the VERSION file |

**Outputs**

| Name | Description |
|---|---|
| `base-version` | The base semantic version (e.g., `1.0.0`) |

### read-base-versions

Batched, keyed form of `read-base-version`. For each `{key, file}` entry, reads the first line of the VERSION file (stripping whitespace) and emits `{key, version}` preserving the original key. Key is opaque — use it to pair versions with whatever downstream needs them (image URLs, component names, etc.). Fails fast if any file is missing or empty.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `entries` | yes | — | JSON array of `{"key": string, "file": string}` objects. The key is opaque (caller-supplied); the file is the path to a VERSION file relative to the workspace. |

**Outputs**

| Name | Description |
|---|---|
| `versions` | JSON array of `{"key": string, "version": string}` objects. Keys preserved from input; versions are the trimmed first line of each file. |

### render-stage-summary

Validates `stage-result` is one of `success`/`failure`/`cancelled`/`skipped`, then writes a markdown stage summary (with icons and per-result content blocks) to `$GITHUB_STEP_SUMMARY`. Used directly by commit-stage workflows and composed by `render-system-stage-summary` for richer system-stage rendering.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `stage-name` | yes | — | Name of the stage being summarized |
| `stage-result` | yes | — | Result of the stage job (`success`, `failure`, `cancelled`, `skipped`) |
| `stage-content` | no | `` | General content to display for any stage result (supports markdown) |
| `stage-success-content` | no | `` | Custom content to display on success (supports markdown) |
| `stage-skipped-content` | no | `` | Custom content to display on skipped (supports markdown). When provided, the stage is treated as a first-class skipped outcome rather than unknown. |

### render-system-stage-summary

Thin composite that validates inputs, calls `format-artifact-list` twice (for success and latest artifact lists), delegates to `render-stage-summary` for the markdown body, and emits a `::notice` annotation on `skipped`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `stage-name` | yes | — | The name of the stage (e.g., Acceptance, QA, Production) |
| `stage-result` | yes | — | Overall result of the stage (`success`/`failure`/`skipped`) |
| `environment` | yes | — | The environment name for this stage |
| `success-version` | no | `` | The version created on success (e.g., prerelease version). Required when `stage-result == success`. |
| `success-artifact-ids` | no | `` | The artifact IDs created on success as a newline-separated list. Single artifact: a plain string. Multiple artifacts: a multiline YAML string (one per line). |
| `skipped-reason` | no | `` | Human-readable reason the stage was skipped (e.g., "No new artifacts since last successful run"). Only used when `stage-result` is `skipped`. |
| `latest-artifact-ids` | no | `` | The latest known artifact IDs as a newline-separated list (even though the stage did not run against them). Displayed on skipped. Same format as `success-artifact-ids`. |
| `latest-updated-at` | no | `` | ISO 8601 timestamp of when the latest artifacts were last updated. Displayed on skipped. |
| `last-run-at` | no | `` | ISO 8601 timestamp of the last successful run of this workflow. Displayed on skipped. |

### resolve-commit

Resolves a remote git ref (branch, tag, or SHA) to its 40-char commit SHA + committer timestamp. Uses a throwaway `git init` + shallow `git fetch --depth=1 <ref>` against the remote URL — works on any host that supports `uploadpack.allowReachableSHA1InWant` (GitHub does).

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `repository` | yes | — | Repository in `owner/name` form (e.g. `optivem/shop`). Resolved against the configured `git-host` (defaults to github.com). |
| `ref` | no | `main` | Git ref to resolve (branch, tag, or SHA). Empty defaults to `main`. |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

**Outputs**

| Name | Description |
|---|---|
| `sha` | 40-character commit SHA |
| `timestamp` | Committer timestamp in ISO 8601 format |

### resolve-docker-image-digests

Finds Docker images and resolves their `sha256:` digests from any container registry. Takes base image URLs plus a tag — appends `:tag` to each base URL and resolves the digest. Callers own the tag convention (e.g. `latest`, `sha-<sha>` for `docker/metadata-action`'s `type=sha,format=long` convention used by the commit stage, or `v1.2.3`). Emits a JSON array of digest URLs (same order as input) and the most recent image creation timestamp across all processed images. Delegates to `resolve-docker-image-digests.sh`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `base-image-urls` | yes | — | Base image URLs (no `:tag`). Combined with `tag` to produce the image reference. Supports newline-separated list or JSON array format. |
| `tag` | no | `latest` | Image tag to resolve (e.g. `latest`, `sha-<sha>`, `v1.2.3`). Appended after `:` to each base URL. |

**Outputs**

| Name | Description |
|---|---|
| `image-digest-urls` | JSON array of digest URLs in the same order as input |
| `latest-updated-at` | ISO 8601 timestamp of the most recently created image among all processed images |

### resolve-latest-prerelease-tag

Finds the latest git tag in a repository that matches a given prefix (and optional suffix) using `git ls-remote` + version-aware sort. Tool-agnostic — no releases API dependency. Pair with `validate-tag-exists` for the "validate an explicit tag" case.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag-prefix` | yes | — | Required tag prefix (e.g. `monolith-java-v`). Tags matching `${tag-prefix}*${tag-suffix}` are considered; the highest by version-aware sort wins. |
| `tag-suffix` | no | `` | Optional tag suffix (e.g. `-qa-approved`). When set, only tags that also end with this suffix are considered, and the `base-tag` output contains the matched tag with the suffix stripped. |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

**Outputs**

| Name | Description |
|---|---|
| `tag` | The latest tag matching `tag-prefix` (and `tag-suffix`, if provided) |
| `base-tag` | The matched tag with `tag-suffix` stripped (equals `tag` when `tag-suffix` is empty) |

### resolve-latest-tag-from-sha

Calls `git ls-remote --tags` against the remote URL, filters by the given glob pattern (default `*` matches any tag), matches tags (lightweight or annotated, peeled) against the target SHA, and picks the highest by `sort -V` (version sort). Returns empty if no matching tag points at the SHA.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form (e.g. `optivem/shop`) |
| `commit-sha` | yes | — | Commit SHA to look up |
| `pattern` | no | `*` | Tag glob pattern to filter by (e.g. `monolith-typescript-v1.0.26-rc.*`). Default `*` matches any tag. |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

**Outputs**

| Name | Description |
|---|---|
| `tag` | The highest tag (by version sort) matching the pattern and pointing at the SHA, or empty string if none found |

**Notes:** `git ls-remote --tags` fetches the full tag list and filters client-side. Fine at current scale (dozens of tags); for thousands of tags, a paginated `gh api /repos/.../tags` would be faster.

### tag-docker-images

Promotes existing Docker images by issuing a server-side manifest retag (`docker buildx imagetools create --tag <new> <source>`) for each entry. Used for moving already-built artifacts through pipeline stages (Farley-style promotion: `build-once`, promote-many). No image data crosses the runner; multi-arch manifest lists are preserved. Same registry throughout — only a tag is added, no image content moves.

Two mutually exclusive input modes:

- **Broadcast** — `image-urls` + `tag`: apply one uniform tag to every image in the list. Example: re-tag all system images with `v1.3.2`.
- **Map** — `image-tags`: apply a per-image tag. Chains directly with `compose-tags` output (both use the `key` field for the source image URL). Example: re-tag each component image with its own `v{component-version}`.

Exactly one mode must be used. Both modes set or neither set → fails fast with a clear error.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `image-urls` | no | `` | Broadcast mode: JSON array of source Docker image URLs with existing tags. Requires `tag`. Mutually exclusive with `image-tags`. |
| `tag` | no | `` | Broadcast mode: target tag applied uniformly to every image in `image-urls` (e.g., `v1.0.5`, `latest`, `production`). Mutually exclusive with `image-tags`. |
| `image-tags` | no | `` | Map mode: JSON array of `{"key": string, "tag": string}` objects where `key` is the source image URL and `tag` is the tag to apply to it. Mutually exclusive with `image-urls` + `tag`. |
| `registry` | no | `ghcr.io` | Container registry URL (e.g., `ghcr.io`, `docker.io`, `gcr.io`) |
| `registry-username` | no | `${{ github.actor }}` | Username for registry authentication |
| `token` | no | `${{ github.token }}` | Token used to authenticate against the registry |

**Outputs**

| Name | Description |
|---|---|
| `tagged-image-urls` | JSON array of Docker image URLs with new tags applied |

### trigger-and-wait-for-workflow

Probes the GitHub rate limit (and sleeps until reset if below threshold), dispatches a `workflow_dispatch` workflow via `gh workflow run` (through `gh_retry`), captures the triggered run's ID via `gh run list`, and then `gh run watch --exit-status`es the run to fail the step if the triggered run fails.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `workflow` | yes | — | Workflow filename (e.g. `monolith-java-commit-stage.yml`) — matches `gh workflow run --workflow` |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `ref` | no | `main` | Git ref to trigger the workflow on |
| `workflow-inputs` | no | `{}` | JSON object of workflow inputs (e.g., `{"version": "v1.0.0-rc.1"}`). Named `workflow-inputs` rather than `inputs` to avoid shadowing the workflow inputs context at the caller site. |
| `poll-interval` | no | `120` | Seconds between status polls |
| `rate-limit-threshold` | no | `50` | Pause when remaining API requests fall below this number |
| `timeout-seconds` | no | `1800` | Hard timeout on the watch phase. Action fails with exit code 124 if the triggered run has not terminated within this many seconds. Default is 30 minutes (fast-feedback sizing); callers that trigger longer-running workflows must override upward. |
| `token` | no | `${{ github.token }}` | GitHub token used to dispatch and watch the workflow run. Callers may pass a higher-scoped token (e.g. a PAT) when cross-repo `workflow_dispatch` is required. |

**Outputs**

| Name | Description |
|---|---|
| `run-id` | The database ID of the triggered workflow run |

**Notes:** The run-ID lookup uses `gh run list --limit 1` against `workflow` + `ref`, with a 10s sleep before the lookup. Under heavy concurrent dispatches this could race with a sibling run — acceptable at current scale.

### validate-env-vars-defined

Iterates the newline-separated `names` list and uses `printenv` to confirm each name has a non-empty value in the step's environment. Fails the step with a `::error::Missing required config:` message listing all missing names.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `names` | yes | — | Newline-separated list of environment variable names to validate. Leading/trailing whitespace on each name is trimmed; blank lines are ignored. |

**Notes:** List the names in `names` and pass the values via `env:` at the caller's step — the action reads them from the process environment.

### validate-tag-exists

Asserts that a git tag exists on a remote via `git ls-remote --tags "refs/tags/<tag>"`. Fails the step if missing. For the inverse (assert a tag does NOT exist) or for soft-predicate usage, use `check-tag-exists` and gate on its `exists` output.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Git tag to require (e.g., `meta-v1.0.0-rc.1`, `monolith-java-v1.0.0`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

### wait-for-endpoints

For each `{name, url}` in the input array, polls the URL with `curl -f` up to `max-attempts` times with exponential backoff between attempts, subject to a hard total-time ceiling from `timeout-seconds`. Fails the step with exit code 124 if the ceiling is hit, or exit code 1 if any URL exhausts `max-attempts` first. On failure, if `compose-file` is set, dumps `docker compose logs --timestamps` and `docker compose ps` for debugging.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `endpoints` | yes | — | JSON array of endpoints to health check, each with `name` and `url` (e.g., `[{"name": "API", "url": "http://localhost:8080/health"}]`) |
| `compose-file` | no | `` | Docker Compose file for log dump on failure. If set, runs `docker compose -f <file> logs/ps` when any URL fails. |
| `working-directory` | no | `.` | Working directory for the Docker Compose log dump (used only when `compose-file` is set) |
| `max-attempts` | no | `30` | Maximum number of polling attempts per URL |
| `wait-seconds` | no | `10` | Base seconds to wait between attempts (doubled each attempt, capped at `wait-seconds * 16`, plus small jitter) |
| `timeout-seconds` | no | `900` | Hard timeout on the total polling time across all endpoints. Action fails with exit code 124 if not all endpoints become ready within this ceiling. Default is 15 min — aligned with fast-feedback sizing. |

### wait-for-workflow

Polls `gh run list` (via `gh_retry`) for runs of a given workflow, filters by `headSha == <commit-sha>` until a match is found, then `gh run watch --exit-status`es the run to fail the step if it fails. Sibling of `trigger-and-wait-for-workflow` — use that when you need to dispatch the workflow yourself; use this when a commit push has already triggered it.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `workflow` | yes | — | Workflow filename (e.g. `monolith-java-commit-stage.yml`) — matches `gh workflow run --workflow` |
| `commit-sha` | yes | — | The commit SHA to match against |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `poll-interval` | no | `30` | Seconds between discovery polls |
| `watch-interval` | no | `120` | Seconds between `gh run watch` polls |
| `max-discovery-attempts` | no | `120` | Maximum number of discovery polls before the action fails with "run never appeared" |
| `rate-limit-threshold` | no | `50` | Pause when remaining API requests fall below this number |
| `timeout-seconds` | no | `1800` | Hard timeout on the combined discovery + watch phases. Action fails with exit code 124 if a matching run has not been discovered AND watched to completion within this many seconds. Default is 30 minutes (fast-feedback sizing); callers waiting for longer-running workflows must override upward. |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `run-id` | The database ID of the matched workflow run |
