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

### bump-patch-versions

For each `path:tag-prefix1,tag-prefix2,...` entry, reads the VERSION file and — if any `{prefix}{current-version}` tag exists on the remote (`git ls-remote`) — computes a patch bump. Reads only; writes nothing to disk. Pair with `commit-files` to persist the bumps.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `version-files` | yes | — | Newline-separated list of `"path:tag-prefix1,tag-prefix2,..."` entries. Each VERSION file is bumped if ANY tag `{prefix}{current-version}` exists on the remote. Example: `"VERSION:meta-v,monolith-java-v"` |
| `remote` | no | `origin` | Git remote to check for tags |

**Outputs**

| Name | Description |
|---|---|
| `bumps` | JSON array of `{path, old-version, new-version, release-tag}` for files that need bumping |
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

### check-ghcr-packages-exist

Calls `gh api repos/{repo}/packages?package_type=container` (via `gh_retry`) and sets `exist=true`/`false` based on whether the list is non-empty. Useful for skipping pipeline stages when no artifacts have been built yet.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `exist` | Whether container artifacts exist for this repository (`true`/`false`) |

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

### check-tag-pattern-exists

Queries a remote git repository with `git ls-remote --tags "refs/tags/<pattern>"` and reports whether at least one tag matches. Tool-agnostic — no platform API dependency.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag-pattern` | yes | — | Tag pattern to match (e.g., `meta-v*`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

**Outputs**

| Name | Description |
|---|---|
| `exists` | Whether at least one matching tag exists (`true`/`false`) |

### check-unverified-commit-status

Fetches commit statuses on `head-sha` via `gh api repos/{repo}/commits/{sha}/statuses` and checks whether any entry has `context == status-context`, `description == subject-sha`, and `state == success`. Used to skip re-verification when the same subject has already been verified on this HEAD. Fails open to `changed=true` on transient API errors.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `subject-sha` | yes | — | Identity of the subject under test (e.g. the resolved commit SHA of an upstream repo). Matched against the `description` field of commit statuses on head-sha. |
| `status-context` | yes | — | The commit-status context that records prior verification (e.g. `verified-shop-sha`). Matched against the `context` field. |
| `head-sha` | no | `${{ github.sha }}` | Commit whose statuses are inspected |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `changed` | `true` when no matching success status is found on head-sha (subject has NOT been verified yet — run). `false` when a matching success status exists (subject already verified — skip). Fails open to `true` on transient API errors. |
| `verified-at` | ISO 8601 `createdAt` of the matching success status, if one was found. Empty otherwise. |

### check-update-since-last-github-workflow-run

Fetches the most recent successful run of a given workflow via `gh run list` and lexicographically compares its `createdAt` against the caller-supplied `last-updated-at` timestamp. Generic timestamp-vs-run comparator — caller decides what "updated" means (docker push time, git commit time, artifact build time). Fail-open on first run.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `last-updated-at` | yes | — | ISO 8601 timestamp representing when the subject under observation was last updated. Typically resolved by the caller from whatever source is relevant (e.g. latest docker image push time, a git commit time, an artifact push time). |
| `workflow-name` | yes | — | Workflow file name or display name to check last successful run against (e.g. `github.workflow`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/name` form |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `changed` | `true` when `last-updated-at` is strictly newer than the last successful run's `createdAt`, OR when there is no previous successful run (fail-open on first run). `false` when a previous successful run was found AND the subject is not newer than it. |
| `last-run-at` | ISO 8601 `createdAt` of the last successful run. Empty if no previous successful run exists. |

**Notes:** ISO 8601 lexicographic comparison is only correct when both timestamps are UTC with the same format (both Z-suffixed). GitHub API and typical subject timestamps (docker push times, git commit times) satisfy this.

### cleanup-github-deployments

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

**Notes:**
- **Released-RC deployments** (final tag `vX.Y.Z` exists): immediately deletes any deployment whose SHA matches a `vX.Y.Z-rc.*` tag; bypasses both `keep-count` and `retention-days`.
- **Superseded per environment** (count cap + retention floor): keeps the newest `keep-count` deployments per environment; anything beyond the cap is deleted only once older than `retention-days` (the floor prevents pruning fresh bursts during active debugging).
- **Protected environments** are never touched by either scenario.
- **Ordering:** run this action **before** `cleanup-github-prereleases` in the same workflow — the released-RC logic relies on RC git tags being present to resolve SHAs, and `cleanup-github-prereleases` deletes those tags immediately for released versions.

### cleanup-github-prereleases

Cleans up prerelease git tags, GitHub releases, and (optionally) Docker image tags that are no longer needed. Delegates to `cleanup-github-prereleases.sh` in the action directory. Rate-limit-aware.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `retention-days` | no | `30` | Number of days to retain prerelease Docker image tags after release, and superseded RC artifacts before release |
| `container-packages` | no | `` | Comma-separated list of container package names for Docker image tag cleanup (e.g., `"myapp,myapp-worker"`). If empty, Docker cleanup is skipped. |
| `delete-delay-seconds` | no | `10` | Seconds to wait between each API delete call to avoid GitHub rate limiting |
| `rate-limit-threshold` | no | `50` | Pause before each API delete when remaining core-rate-limit requests fall below this number (set `0` to disable) |
| `dry-run` | no | `false` | If `true`, only log what would be deleted without actually deleting anything |
| `token` | no | `${{ github.token }}` | GitHub token used for tag, release, and package API calls |

**Notes:**
- **Released versions** (final tag `vX.Y.Z` exists): immediately deletes prerelease GitHub releases + git tags (`vX.Y.Z-rc.*`, `vX.Y.Z-rc.*-qa-*`); after the retention period, deletes prerelease Docker image tags.
- **Superseded prereleases** (no final release yet): after the retention period, deletes older RCs + their status tags + Docker image tags; never deletes the latest RC.
- **Ordering:** run `cleanup-github-deployments` first (see its Notes).

### commit-files

For each `{path, content, message}` entry, reads the current file SHA from the GitHub Contents API (if any), base64-encodes the new content, and `PUT`s it with the SHA precondition. Retries on HTTP 409/422 (SHA conflict) with exponential backoff. Race-safe alternative to `git push` for concurrent workflows on the same branch.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `files` | yes | — | JSON array of `{path, content, message}` entries. `path` is repo-relative, `content` is the full new file content (plain text, will be base64-encoded before PUT), `message` is the commit message for that file. |
| `branch` | no | `${{ github.ref_name }}` | Branch to commit to |
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

Pure string transform. Concatenates `{prerelease-version}-{environment}-{status}` to compose a status-marker git tag (e.g., `v1.0.0-rc.1` + `qa` + `deployed` → `v1.0.0-rc.1-qa-deployed`). Validates inputs are non-empty.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `prerelease-version` | yes | — | Prerelease version to build from (e.g., `v1.0.0-rc.1`) |
| `environment` | yes | — | Environment name (e.g., `qa`, `staging`, `prod`) |
| `status` | yes | — | Status marker (e.g., `deployed`, `passed`, `failed`, `approved`) |

**Outputs**

| Name | Description |
|---|---|
| `tag` | Composed status-marker tag string (e.g., `v1.0.0-rc.1-qa-deployed`) |

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

### compose-release-notes

Pure string-transform. Composes a GitHub release title (with status/environment icons) and writes a markdown notes body to a tempfile, covering version, environment, status, workflow link, commit link, actor, and optional artifact list. No platform API calls.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `base-version` | yes | — | Original version that triggered the workflow (e.g., `v1.0.0-rc.1`) |
| `release-version` | yes | — | Release version tag (e.g., `v1.0.0-rc.1-qa-deployed`). For signoff statuses (`approved`/`rejected`) the title falls back to `base-version`. |
| `environment` | yes | — | Environment name (e.g., `qa`, `staging`, `prod`). Mapped to a short uppercase label in the title. |
| `status` | yes | — | Status (e.g., `deployed`, `passed`, `failed`, `approved`, `rejected`). Selects icon and title-suffix mapping. |
| `artifact-urls` | no | `[]` | JSON array of artifact URLs to include in the notes. Empty array or empty string skips the artifacts section. |

**Outputs**

| Name | Description |
|---|---|
| `title` | Composed release title (e.g., `"🚀 v1.0.0-rc.1-qa-deployed QA"`) |
| `notes-file` | Path to a tempfile containing the composed markdown release notes |

### compose-release-version

Pure string transform. Strips a prerelease suffix (`-rc.N`, `-alpha.N`, `-beta.N`, `-preview.N`) from a version to produce the release version (e.g., `v1.0.0-rc.1` → `v1.0.0`). Preserves the leading `v` if present on input.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `prerelease-version` | yes | — | Prerelease version to convert (e.g., `v1.0.0-rc.1`, `v1.0.0-alpha.1`, `v1.0.0-beta.1`) |

**Outputs**

| Name | Description |
|---|---|
| `version` | Release version with prerelease suffix removed (e.g., `v1.0.0`) |

### render-system-stage-summary

Thin composite that validates inputs, calls `format-artifact-list` twice (for success and latest artifact arrays), delegates to `render-stage-summary` for the markdown body, and emits a `::notice` annotation on `skipped`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `stage-name` | yes | — | The name of the stage (e.g., Acceptance, QA, Production) |
| `stage-result` | yes | — | Overall result of the stage (`success`/`failure`/`skipped`) |
| `environment` | yes | — | The environment name for this stage |
| `success-version` | no | `''` | The version created on success (e.g., prerelease version). Required when `stage-result == success`. |
| `success-artifact-ids` | no | `''` | The artifact IDs created on success as JSON array. Single artifacts must also be in array format: `["artifact"]`. Multiple artifacts: `["artifact1", "artifact2"]` |
| `skipped-reason` | no | `''` | Human-readable reason the stage was skipped (e.g., "No new artifacts since last successful run"). Only used when `stage-result` is `skipped`. |
| `latest-artifact-ids` | no | `''` | The latest known artifact IDs as JSON array (even though the stage did not run against them). Displayed on skipped. |
| `latest-updated-at` | no | `''` | ISO 8601 timestamp of when the latest artifacts were last updated. Displayed on skipped. |
| `last-run-at` | no | `''` | ISO 8601 timestamp of the last successful run of this workflow. Displayed on skipped. |

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

### create-component-tags

For each `component-name:version-file-path` entry, reads the VERSION file and creates + pushes a git tag `{component-name}-v{version}` using the `github-actions[bot]` identity. Idempotent: skips tags already on the remote, tolerates concurrent creation at the same commit.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `components` | yes | — | Newline-separated list of `component-name:version-file-path` entries (e.g., `monolith-system-java:system/monolith/java/VERSION`) |

### create-github-release

Idempotent GitHub Release primitive. Uses `gh release view` to check existence; if the release exists, updates title/notes via `gh release edit` (preserves asset uploads). Otherwise creates it via `gh release create`. All `gh` calls go through `gh_retry`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Git tag the release is attached to (must already exist on the remote) |
| `title` | yes | — | Release title |
| `notes-file` | yes | — | Path to a file containing the release notes body (markdown) |
| `is-prerelease` | no | `false` | Whether to mark the release as a prerelease |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` form |
| `token` | no | `${{ github.token }}` | GitHub token for release API calls |

**Outputs**

| Name | Description |
|---|---|
| `release-url` | URL of the created or updated GitHub release |

### deploy-docker-compose

Runs `docker compose up -d` (optionally with `-f <compose-file>`) from a working directory. The `environment`, `version`, and `image-urls` inputs are logged for operator visibility but do not alter behavior. Pair with `wait-for-urls` to verify readiness after deployment.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `environment` | yes | — | Label used in logs to identify the target (e.g., acceptance, qa, production) — display only |
| `version` | yes | — | Version label used in logs (e.g., `v1.0.0-rc.1`) — display only |
| `image-urls` | yes | — | Docker image URLs being run (JSON array format) — surfaced in logs |
| `compose-file` | no | `` | Docker Compose file to use (e.g., `docker-compose.yml`). Empty = default compose file resolution. |
| `working-directory` | yes | — | Working directory containing the Docker Compose file |

### deploy-to-cloud-run

Validates `image-url` includes a tag or digest, then calls `gcloud run deploy` with the configured memory/CPU/scaling/env-vars/secrets. Reads the resulting service URL via `gcloud run services describe` and writes a summary table to `$GITHUB_STEP_SUMMARY`. Optionally delegates to `wait-for-urls` to poll the service URL until ready.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `environment` | yes | — | Target deployment environment (e.g., acceptance, qa, production) |
| `version` | yes | — | Release version to deploy (e.g., `v1.0.0-rc.1` or `latest`) |
| `image-url` | yes | — | Docker image URL to deploy (e.g., `ghcr.io/org/repo/service:tag`). Must include a tag or digest. |
| `project-id` | yes | — | GCP project ID |
| `region` | no | `us-central1` | GCP region for Cloud Run deployment |
| `service-name` | yes | — | Full Cloud Run service name to deploy to (e.g., `shop-monolith-java-production`). Caller owns the naming convention; the action does not append the environment. |
| `port` | no | `8080` | Container port to expose |
| `env-vars` | no | `` | Environment variables to set on the Cloud Run service (`KEY=VALUE` format, one per line) |
| `secrets` | no | `` | Secret environment variables to set (`KEY=SECRET_NAME:VERSION` format, one per line) |
| `memory` | no | `512Mi` | Memory limit for the Cloud Run service |
| `cpu` | no | `1` | CPU limit for the Cloud Run service |
| `min-instances` | no | `0` | Minimum number of instances (0 for scale-to-zero) |
| `max-instances` | no | `3` | Maximum number of instances |
| `allow-unauthenticated` | no | `true` | Allow unauthenticated access to the service |
| `wait-for-ready` | no | `true` | Whether to poll the service URL after deploy and fail if it does not become ready. Set to `false` to publish without verifying readiness (e.g. canary deploys with custom health checks). |

**Outputs**

| Name | Description |
|---|---|
| `service-url` | The URL of the deployed Cloud Run service |

**Notes:** Caller is responsible for ensuring `image-url` is pushed and reachable before invoking. Authentication is assumed to be set up by a prior `google-github-actions/auth` step.

### ensure-env-vars-defined

Iterates the newline-separated `names` list and uses `printenv` to confirm each name has a non-empty value in the step's environment. Fails the step with a `::error::Missing required config:` message listing all missing names.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `names` | yes | — | Newline-separated list of environment variable names to validate |

**Notes:** List the names in `names` and pass the values via `env:` at the caller's step — the action reads them from the process environment.

### ensure-tag-exists

Asserts that a git tag exists on a remote via `git ls-remote --tags "refs/tags/<tag>"`. Fails the step if missing. Inverse of `ensure-version-unreleased`.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `tag` | yes | — | Git tag to require (e.g., `meta-v1.0.0-rc.1`, `monolith-java-v1.0.0`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `token` | no | `${{ github.token }}` | Token for authenticating to the remote |
| `git-host` | no | `github.com` | Git host to query (e.g. `github.com`, `gitlab.com`, `codeberg.org`) |

### ensure-version-unreleased

Asserts that a fully-composed version tag does NOT yet exist locally via `git tag -l`. Fails the step if it does. Caller is responsible for composing the full tag (prefix + version). Works against the local workspace only.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `version` | yes | — | Fully composed version tag to check (e.g., `v1.0.0`, `monolith-java-v1.0.0`, `meta-v1.0.0-rc.1-qa-approved`) |

### format-artifact-list

Pure string transform. Parses a JSON array of identifiers via `jq` and formats as a bulleted markdown list (`• <item>` per line). Returns an empty string if the input is blank.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `artifacts` | no | `` | JSON array of artifact identifiers, e.g. `["docker.io/app:v1"]` or `["url1","url2"]`. Empty string returns empty output. |

**Outputs**

| Name | Description |
|---|---|
| `formatted` | Bulleted markdown list (one `• <item>` per line). Empty string if no artifacts provided. |

### get-commit-status

Reads commit statuses via `gh api repos/{repo}/commits/{sha}/statuses` and selects the first match by context (and optionally state). Fails the step if no match is found. Writes description/state/target-url to outputs and appends a line to `$GITHUB_STEP_SUMMARY`.

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

### map-signoff-to-stage-result

Pure string mapping. Emits `stage-result=success` if `result == approved`, otherwise `stage-result=failure`. No git, no platform dependency.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `result` | yes | — | Signoff decision: `approved` or anything else (treated as rejection) |

**Outputs**

| Name | Description |
|---|---|
| `stage-result` | `success` if `result` is `approved`, `failure` otherwise |

### promote-docker-images

Promotes a JSON array of Docker images by issuing a server-side manifest retag (`docker buildx imagetools create --tag <new> <source>`) for each entry. Used for moving an already-built artifact through pipeline stages (Farley-style promotion: `build-once`, promote-many). No image data crosses the runner; multi-arch manifest lists are preserved. Handles login, per-image failure isolation, and emits the new URLs as a JSON array.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `image-urls` | yes | — | JSON array of source Docker image URLs with existing tags |
| `tag` | yes | — | Target tag to apply to images (e.g., `v1.0.5`, `latest`, `production`) |
| `registry` | no | `ghcr.io` | Container registry URL (e.g., `ghcr.io`, `docker.io`, `gcr.io`) |
| `registry-username` | no | `${{ github.actor }}` | Username for registry authentication |
| `token` | no | `${{ github.token }}` | Token used to authenticate against the registry |

**Outputs**

| Name | Description |
|---|---|
| `image-urls` | JSON array of Docker image URLs with new tags applied |

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

### render-stage-summary

Validates `stage-result` is one of `success`/`failure`/`cancelled`/`skipped`, then writes a markdown stage summary (with icons and per-result content blocks) to `$GITHUB_STEP_SUMMARY`. Used directly by commit-stage workflows and composed by `render-system-stage-summary` for richer system-stage rendering.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `stage-result` | yes | — | Result of the stage job (`success`, `failure`, `cancelled`, `skipped`) |
| `stage-name` | yes | — | Name of the stage being summarized |
| `stage-content` | no | `` | General content to display for any stage result (supports markdown) |
| `stage-success-content` | no | `` | Custom content to display on success (supports markdown) |
| `stage-skipped-content` | no | `` | Custom content to display on skipped (supports markdown). When provided, the stage is treated as a first-class skipped outcome rather than unknown. |

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

Delegates to `resolve-docker-image-digests.sh`. For each input image URL, queries its registry to resolve the `sha256:` digest and records its creation timestamp. Emits a JSON array of digest URLs (same order as input) and the most recent image creation timestamp across all processed images.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `image-urls` | yes | — | Image URLs to resolve digests for. Supports both newline-separated list or JSON array format |

**Outputs**

| Name | Description |
|---|---|
| `image-digest-urls` | JSON array of digest URLs in the same order as input |
| `latest-updated-at` | ISO 8601 timestamp of the most recently created image among all processed images |

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

### setup-dotnet

Thin wrapper around `actions/setup-dotnet@v5` that installs the requested .NET SDK version.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `dotnet-version` | yes | — | .NET SDK version to install |

### setup-java-gradle

Thin wrapper that composes `actions/setup-java@v5` (Temurin distribution) and `gradle/actions/setup-gradle@v5`. The `working-directory` input is declared but is not used by the composed steps.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `java-version` | yes | — | Java version to install |
| `working-directory` | yes | — | Working directory containing the Gradle wrapper |

### setup-node

Wraps `actions/setup-node@v5` with npm caching keyed on `{working-directory}/package-lock.json`, then runs `npm ci` in the working directory.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `node-version` | yes | — | Node.js version to install |
| `working-directory` | yes | — | Working directory containing the `package-lock.json` |

### trigger-and-wait-for-github-workflow

Probes the GitHub rate limit (and sleeps until reset if below threshold), dispatches a `workflow_dispatch` workflow via `gh workflow run` (through `gh_retry`), captures the triggered run's ID via `gh run list`, and then `gh run watch --exit-status`es the run to fail the step if the triggered run fails.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `workflow` | yes | — | Workflow filename to trigger (e.g., `monolith-java-commit-stage.yml`) |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `ref` | no | `main` | Git ref to trigger the workflow on |
| `inputs` | no | `{}` | JSON object of workflow inputs (e.g., `{"version": "v1.0.0-rc.1"}`) |
| `poll-interval` | no | `120` | Seconds between status polls |
| `rate-limit-threshold` | no | `50` | Pause when remaining API requests fall below this number |
| `token` | no | `${{ github.token }}` | GitHub token used to dispatch and watch the workflow run. Callers may pass a higher-scoped token (e.g. a PAT) when cross-repo `workflow_dispatch` is required. |

**Outputs**

| Name | Description |
|---|---|
| `run-id` | The database ID of the triggered workflow run |

**Notes:** The run-ID lookup uses `gh run list --limit 1` against `workflow` + `ref`, with a 10s sleep before the lookup. Under heavy concurrent dispatches this could race with a sibling run — acceptable at current scale.

### wait-for-github-workflow

Polls `gh run list` (via `gh_retry`) for runs of a given workflow, filters by `headSha == <commit-sha>` until a match is found, then `gh run watch --exit-status`es the run to fail the step if it fails. Sibling of `trigger-and-wait-for-github-workflow` — use that when you need to dispatch the workflow yourself; use this when a commit push has already triggered it.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `workflow` | yes | — | Workflow filename to wait for (e.g., `java-commit-stage.yml`) |
| `commit-sha` | yes | — | The commit SHA to match against |
| `repository` | no | `${{ github.repository }}` | Repository in `owner/repo` format |
| `poll-interval` | no | `30` | Seconds between discovery polls |
| `watch-interval` | no | `120` | Seconds between `gh run watch` polls |
| `rate-limit-threshold` | no | `50` | Pause when remaining API requests fall below this number |
| `token` | no | `${{ github.token }}` | GitHub token used for API calls |

**Outputs**

| Name | Description |
|---|---|
| `run-id` | The database ID of the matched workflow run |

### wait-for-urls

For each `{name, url}` in the input array, polls the URL with `curl -f` up to `max-attempts` times (waiting `wait-seconds` between attempts). Fails the step if any URL never succeeds. On failure, if `compose-file` is set, dumps `docker compose logs --timestamps` and `docker compose ps` for debugging.

**Inputs**

| Name | Required | Default | Description |
|---|---|---|---|
| `systems` | yes | — | JSON array of systems to health check, each with `name` and `url` (e.g., `[{"name": "API", "url": "http://localhost:8080/health"}]`) |
| `compose-file` | no | `` | Docker Compose file for log dump on failure. If set, runs `docker compose -f <file> logs/ps` when any URL fails. |
| `working-directory` | no | `.` | Working directory for the Docker Compose log dump (used only when `compose-file` is set) |
| `max-attempts` | no | `30` | Maximum number of polling attempts per URL |
| `wait-seconds` | no | `10` | Seconds to wait between attempts |
