# optivem/actions

## cleanup-prereleases

Cleans up prerelease git tags, GitHub releases, and Docker image tags that are no longer needed.

### Inputs

| Input | Description | Default |
|---|---|---|
| `retention-days` | Days to retain prerelease Docker image tags after release, and superseded RC artifacts before release | `30` |
| `container-packages` | Comma-separated list of container package names for Docker image tag cleanup. If empty, Docker cleanup is skipped. | `''` |
| `delete-delay-seconds` | Seconds to wait between each API delete call to avoid GitHub rate limiting | `10` |
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
| `retention-days` | Days to retain superseded deployments before deletion | `30` |
| `delete-delay-seconds` | Seconds to wait between each API delete call to avoid GitHub rate limiting | `10` |
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

**Superseded per environment** (for all remaining deployments):
- Always keeps the latest deployment per environment
- After retention period: deletes older deployments

### Ordering note

Run this action **before** `cleanup-prereleases` in the same workflow — the
released-RC logic relies on RC git tags being present to resolve SHAs, and
`cleanup-prereleases` deletes those tags immediately for released versions.
