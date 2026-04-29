# Apply bash strict mode (`set -euo pipefail`) everywhere — 2026-04-29 08:44 UTC

## Goal

Apply `set -euo pipefail` as the first executable line of every bash `run:` block in `action.yml` / workflow YAML files, and the first executable line (after the shebang and header comment) of every standalone executable `.sh` script across the workspace. This makes CI scripts fail fast on errors, unset variables, and pipeline failures — closing a class of silent-success bugs.

Rule reference: [`devops-rubric.md` §1.4 "Bash strict mode"](../.claude/agents/docs/devops-rubric.md).

## Rule recap

```bash
set -euo pipefail
```

| flag | catches |
|---|---|
| `-e` | command fails → script keeps going and reports success at the end |
| `-u` | typo in variable name → expands to empty string, silent misbehavior |
| `-o pipefail` | failed stage in a pipeline → masked by successful later stage |

## Exception — sourced library scripts

Files designed to be `source`d by other scripts MUST NOT set `-euo pipefail` at file scope (it contaminates the caller's shell options). Identifiable by a "Source this file from..." comment near the top and no top-level executable logic.

**Excluded from this plan (do not modify):**
- `actions/shared/clear-persisted-credentials.sh`
- `actions/shared/gh-rate-limit.sh`
- `actions/shared/gh-retry.sh`
- `actions/shared/ghcr-probe.sh`
- `actions/shared/remote-url.sh`
- `gh-optivem/.github/scripts/gh-rate-limit.sh`
- `gh-optivem/.github/scripts/gh-retry.sh`
- `github-utils/scripts/common.sh`
- `github-utils/scripts/gh-retry.sh`
- `shop/.github/workflows/scripts/gh-retry.sh`

If any of these are misclassified (turn out to be standalone, not sourced), reclassify and add to the appropriate inventory section below.

## Standard fix pattern

### For inline `run: |` blocks in `action.yml` / workflow YAML

```yaml
- shell: bash
  env:
    FOO: ${{ inputs.foo }}
  run: |
    set -euo pipefail
    # ... existing script body
```

Insert `set -euo pipefail` as the first line of the run-block body, before any other commands. If the block has a comment header, put strict mode first regardless.

### For standalone `.sh` files

```bash
#!/usr/bin/env bash
# header comment block
set -euo pipefail

# ... rest of script
```

Insert `set -euo pipefail` after the shebang and header comment block, before the first executable statement.

## Inventory — composite actions (`action.yml` files in `optivem/actions`)

17 of 42 actions have at least one `shell: bash` block missing strict mode.

- [ ] `actions/check-tag-exists/action.yml`
- [ ] `actions/cleanup-deployments/action.yml`
- [ ] `actions/cleanup-ghcr-orphan-manifests/action.yml`
- [ ] `actions/cleanup-prereleases/action.yml`
- [ ] `actions/compose-docker-image-urls/action.yml`
- [ ] `actions/deploy-docker-compose/action.yml`
- [ ] `actions/get-commit-status/action.yml`
- [ ] `actions/read-base-version/action.yml`
- [ ] `actions/render-stage-summary/action.yml`
- [ ] `actions/resolve-docker-image-digests/action.yml`
- [ ] `actions/resolve-latest-tag-from-sha/action.yml`
- [ ] `actions/tag-docker-images/action.yml`
- [ ] `actions/trigger-and-wait-for-workflow/action.yml`
- [ ] `actions/validate-env-vars-defined/action.yml`
- [ ] `actions/validate-tag-exists/action.yml`
- [ ] `actions/wait-for-endpoints/action.yml`
- [ ] `actions/wait-for-workflow/action.yml`

Note: actions with multiple bash blocks may have strict mode in one block but not another — reverify each on visit and apply to *every* block.

## Inventory — workflow files (`shop` + `gh-optivem`)

22 workflow files have inline bash blocks missing strict mode.

**`gh-optivem`:**
- [ ] `gh-optivem/.github/workflows/gh-post-release-stage.yml`
- [ ] `gh-optivem/.github/workflows/gh-release-stage.yml`

**`shop` — pipeline orchestrator:**
- [ ] `shop/.github/workflows/_prerelease-pipeline.yml`

**`shop` — commit stages:**
- [ ] `shop/.github/workflows/monolith-dotnet-commit-stage.yml`
- [ ] `shop/.github/workflows/monolith-java-commit-stage.yml`
- [ ] `shop/.github/workflows/monolith-typescript-commit-stage.yml`
- [ ] `shop/.github/workflows/multitier-backend-dotnet-commit-stage.yml`
- [ ] `shop/.github/workflows/multitier-backend-java-commit-stage.yml`
- [ ] `shop/.github/workflows/multitier-backend-typescript-commit-stage.yml`
- [ ] `shop/.github/workflows/multitier-frontend-react-commit-stage.yml`

**`shop` — prod stages (local):**
- [ ] `shop/.github/workflows/monolith-dotnet-prod-stage.yml`
- [ ] `shop/.github/workflows/monolith-java-prod-stage.yml`
- [ ] `shop/.github/workflows/monolith-typescript-prod-stage.yml`
- [ ] `shop/.github/workflows/multitier-dotnet-prod-stage.yml`
- [ ] `shop/.github/workflows/multitier-java-prod-stage.yml`
- [ ] `shop/.github/workflows/multitier-typescript-prod-stage.yml`

**`shop` — prod stages (cloud):**
- [ ] `shop/.github/workflows/monolith-dotnet-prod-stage-cloud.yml`
- [ ] `shop/.github/workflows/monolith-java-prod-stage-cloud.yml`
- [ ] `shop/.github/workflows/monolith-typescript-prod-stage-cloud.yml`
- [ ] `shop/.github/workflows/multitier-dotnet-prod-stage-cloud.yml`
- [ ] `shop/.github/workflows/multitier-java-prod-stage-cloud.yml`
- [ ] `shop/.github/workflows/multitier-typescript-prod-stage-cloud.yml`

## Inventory — standalone `.sh` files

7 authored standalone scripts. (Excludes vendored Playwright `bin/Debug/.playwright/package/bin/reinstall_*` scripts and `node_modules`/`obj`/`bin/Debug` build outputs.)

- [ ] `claude/scripts/claude-courses.sh`
- [ ] `courses/scripts/test-course.sh`
- [ ] `gh-optivem/scripts/manual-test-runner-shop.sh`
- [ ] `hub/scripts/pipeline-setup.sh`
- [ ] `shop/compile-all.sh`
- [ ] `shop/scripts/pre-commit-hook.sh`
- [ ] `shop/test-all.sh`

## Rollout order

Suggested sequence (highest blast-radius first — these are the scripts where a silent failure has historically caused the most pain):

1. **Pipeline-orchestrator workflow** (`_prerelease-pipeline.yml`) — touches every stack.
2. **Composite actions called by promote/deploy paths** — `cleanup-deployments`, `cleanup-ghcr-orphan-manifests`, `cleanup-prereleases`, `tag-docker-images`, `deploy-docker-compose`, `wait-for-endpoints`, `wait-for-workflow`, `trigger-and-wait-for-workflow`, `compose-docker-image-urls`, `resolve-docker-image-digests`, `validate-env-vars-defined`, `validate-tag-exists`, `check-tag-exists`, `get-commit-status`, `resolve-latest-tag-from-sha`, `read-base-version`, `render-stage-summary`.
3. **Prod-stage workflows** (12 files: 6 local + 6 cloud).
4. **Commit-stage workflows** (7 files).
5. **gh-optivem release workflows** (2 files).
6. **Standalone `.sh` scripts** (7 files).

Do them in batches by repo to keep PRs reviewable.

## Follow-up — lint enforcement (optional)

Once the codebase is clean, add a lint check at `actions/shared/_lint/check-bash-strict-mode.sh` modelled on `check-no-pwsh.sh` / `check-no-raw-gh.sh`. It should:

1. Parse every `action.yml` / workflow YAML and assert the first non-blank/non-comment line of each `shell: bash` `run:` block is `set -euo pipefail`.
2. Parse every authored `.sh` (with the sourced-library exclusion list) and assert `set -euo pipefail` appears in the file.
3. Run in CI on every PR, similar to the existing lint scripts.

This converts the rubric rule into mechanically-enforced policy and prevents new violations.
