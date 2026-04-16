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
