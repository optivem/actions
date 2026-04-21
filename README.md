# optivem/actions

## Shell choice — bash only for new work

All actions in this repo run on GitHub-hosted Linux runners, so pwsh buys nothing a bash toolchain doesn't already cover. To avoid paying every cross-cutting concern twice (retry wrappers, lint rules, structured logging, auth), **new work is bash-only**:

- New `action.yml` steps use `shell: bash`.
- New scripts are `.sh`, not `.ps1`. Inline the bash directly in `action.yml` when practical — it's the prevailing pattern in this repo.
- Use [shared/gh-retry.sh](shared/gh-retry.sh) (`gh_retry` wrapper) for any `gh` CLI calls, and `jq` for JSON handling.

Existing pwsh files stay in place until independently touched. When you open one for any reason (bug fix, feature change, retry-wrapper adoption), port the surrounding `pwsh` step or `.ps1` script to bash **in the same PR** unless doing so would triple the diff.

A lint check ([shared/_lint/check-no-new-pwsh.sh](shared/_lint/check-no-new-pwsh.sh), wired via `.github/workflows/lint-shell-policy.yml`) fails PRs that introduce new `shell: pwsh` steps or new `.ps1` files.

## cleanup-prereleases

Cleans up prerelease git tags, GitHub releases, and Docker image tags that are no longer needed.

### Inputs

| Input | Description | Default |
|---|---|---|
| `retention-days` | Days to retain prerelease Docker image tags after release, and superseded RC artifacts before release | `30` |
| `container-packages` | Comma-separated list of container package names for Docker image tag cleanup. If empty, Docker cleanup is skipped. | `''` |
| `delete-delay-seconds` | Seconds to wait between each API delete call to avoid GitHub rate limiting | `10` |
| `rate-limit-threshold` | Pause before each API delete when remaining core-rate-limit requests fall below this number (set `0` to disable) | `50` |
| `dry-run` | If true, only log what would be deleted without actually deleting anything | `false` |

### Usage

```yaml
- uses: optivem/actions/cleanup-prereleases@v1
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### What it deletes

**Released versions** (final tag `vX.Y.Z` exists):
- Immediately: prerelease GitHub releases + git tags (`vX.Y.Z-rc.*`, `vX.Y.Z-rc.*-qa-*`)
- After retention period: prerelease Docker image tags

**Superseded prereleases** (no final release yet):
- After retention period: older RCs + their status tags + Docker image tags
- Never deletes the latest RC

## cleanup-deployments

Cleans up superseded GitHub deployments that are no longer needed.

### Inputs

| Input | Description | Default |
|---|---|---|
| `keep-count` | Per-environment count cap: keep this many newest deployments | `3` |
| `retention-days` | Retention floor in days. Candidates beyond `keep-count` are only deleted once older than this cutoff | `30` |
| `protected-environments` | Comma-separated environment name patterns to never delete. Supports `*` wildcards, case-insensitive | `*-production,production` |
| `delete-delay-seconds` | Seconds to wait between each API delete call to avoid GitHub rate limiting | `10` |
| `rate-limit-threshold` | Pause before each API delete when remaining core-rate-limit requests fall below this number (set `0` to disable) | `50` |
| `dry-run` | If true, only log what would be deleted without actually deleting anything | `false` |

### Usage

```yaml
- uses: optivem/actions/cleanup-deployments@v1
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### What it deletes

**Released-RC deployments** (final tag `vX.Y.Z` exists):
- Immediately deletes any deployment whose SHA matches a `vX.Y.Z-rc.*` tag
- Bypasses both `keep-count` and `retention-days`

**Superseded per environment** (count cap + retention floor):
- Keeps the newest `keep-count` deployments per environment
- Anything beyond the cap is deleted only once older than `retention-days`
  (the floor prevents pruning fresh bursts during active debugging)

**Protected environments** are never touched by either scenario.

### Ordering note

Run this action **before** `cleanup-prereleases` in the same workflow — the
released-RC logic relies on RC git tags being present to resolve SHAs, and
`cleanup-prereleases` deletes those tags immediately for released versions.
