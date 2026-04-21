# Action naming review — all 46 actions

**Generated:** 2026-04-21 13:37 UTC
**Decisions reached:** 2026-04-21 ~14:00 UTC (through dialogue)

## Decision principle

Prefer mainstream GitHub Actions ecosystem conventions over internal pedagogy. Drop `github-` prefix when the base concept is unambiguous. **Keep `github-` prefix when the base concept collides with other widely-used meanings** (e.g. K8s Deployments, CD "release", generic "workflow").

## Final rename list (8 renames)

| # | Current | Proposed | Reason |
|---|---|---|---|
| 1 | `check-github-container-packages-exist` | `check-ghcr-packages-exist` | `ghcr-` is the precise prefix (GitHub Container Registry is the actual scope, not GitHub broadly); shorter. |
| 2 | `check-unverified-github-commit-status` | `check-unverified-commit-status` | "Commit status" is unambiguous. |
| 3 | `commit-files-via-github-contents-api` | `commit-files` | Mainstream Marketplace doesn't embed implementation details (`actions/github-script`, `peter-evans/create-pull-request` are all API-backed, none say "via-api"). |
| 4 | `create-github-commit-status` | `create-commit-status` | "Commit status" is unambiguous. |
| 5 | `get-github-commit-status` | `get-commit-status` | "Commit status" is unambiguous. |
| 6 | `resolve-github-prerelease-tag` | `resolve-prerelease-tag` | "Prerelease tag" is SemVer vocabulary. |
| 7 | `read-github-workflow-run-number` | `get-github-workflow-run-number` | Keep `github-` (workflow is ambiguous); switch `read-*` → `get-*` (API read, not file read — mainstream convention: `read-*` for files, `get-*` for API/HTTP). |
| 8 | `wait-for-github-commit-run` | `wait-for-github-workflow` | Pairs cleanly with `trigger-and-wait-for-github-workflow` — the names tell the reader what's different (triggers or not), not the internal lookup mechanism. SHA is a parameter, matching `actions/checkout`'s `ref`-as-parameter pattern. |

## Kept with `github-` prefix (ambiguity defence)

| Current | Reason to keep |
|---|---|
| `check-update-since-last-github-workflow-run` | "Workflow" is ambiguous (GitHub workflow, Argo workflow, Jenkins pipeline, business process). |
| `cleanup-github-deployments` | "Deployment" collides with K8s Deployments — dangerous ambiguity. |
| `cleanup-github-prereleases` | Multi-artifact cleanup (Releases + Packages + git tags); consistent with sibling `cleanup-github-deployments`. |
| `create-github-release` | "Release" is ambiguous (deploy, artifact publish, git tag, SemVer release, GitHub Releases UI). |
| `trigger-and-wait-for-github-workflow` | Same "workflow" ambiguity. |

## Also-considered but kept

All 35 other actions are mainstream-aligned as-is. See initial review (overwritten above) for the full 46-row table if needed — the renames listed here are the only changes.

## Execution scope

- **7 directory renames** + 7 `action.yml` `name:` field updates (Title Case)
- **Consumer refs:** estimate ~50–80 across shop, gh-optivem, optivem-testing, courses docs
- **README.md entries** to update (and alphabetical reordering where the rename crosses letters)

### Per-rename expected call-site counts (from audit)

| Rename | Call sites |
|---|---|
| `check-github-container-packages-exist` → `check-ghcr-packages-exist` | 18 (shop) |
| `check-unverified-github-commit-status` → `check-unverified-commit-status` | 1 (gh-optivem) |
| `commit-files-via-github-contents-api` → `commit-files` | 2 (shop) |
| `create-github-commit-status` → `create-commit-status` | 1 (gh-optivem) |
| `get-github-commit-status` → `get-commit-status` | 1 (gh-optivem) |
| `resolve-github-prerelease-tag` → `resolve-prerelease-tag` | 1 (gh-optivem) |
| `read-github-workflow-run-number` → `get-github-workflow-run-number` | 1 (shop) |
| `wait-for-github-commit-run` → `wait-for-github-workflow` | 1 (optivem-testing, 3 call sites) |

**Total estimated:** ~26 consumer refs.

## Approval status

- ✅ All 7 renames approved via chat
- ⏳ Ready to execute when approved
