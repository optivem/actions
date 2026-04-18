#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Cleans up prerelease versions (git tags, GitHub releases, Docker image tags)
    that are no longer needed.

.DESCRIPTION
    Two cleanup scenarios:

    1. Released versions (final tag vX.Y.Z exists):
       - Immediately delete prerelease GitHub releases and git tags
       - Delete prerelease Docker image tags after retention period

    2. Superseded prereleases (no final release yet):
       - Delete older RC releases/tags/images that are past retention period
       - Always keep the latest RC for each version

.PARAMETER RetentionDays
    Number of days to retain prerelease Docker image tags after release,
    and superseded RC artifacts before release. Default: 30

.PARAMETER ContainerPackages
    Comma-separated list of container package names to clean up Docker image
    tags from (e.g., "myapp,myapp-worker"). If empty, Docker cleanup is skipped.

.PARAMETER DeleteDelaySeconds
    Seconds to wait between each API delete call to avoid GitHub rate limiting. Default: 10

.PARAMETER DryRun
    If true, only log what would be deleted without actually deleting anything.

.PARAMETER Repository
    GitHub repository in owner/repo format. Defaults to GITHUB_REPOSITORY env var.
#>

param(
    [int]$RetentionDays = 30,
    [string]$ContainerPackages = "",
    [int]$DeleteDelaySeconds = 10,
    [bool]$DryRun = $false,
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Prerelease Version Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository:         $Repository"
Write-Host "Retention Days:     $RetentionDays"
Write-Host "Container Packages: $(if ($ContainerPackages) { $ContainerPackages } else { '(none - Docker cleanup skipped)' })"
Write-Host "Delete Delay:       ${DeleteDelaySeconds}s"
Write-Host "Dry Run:            $DryRun"
Write-Host ""

$owner = ($Repository -split '/')[0]
$cutoffDate = (Get-Date).AddDays(-$RetentionDays)

# ── Step 1: Fetch all releases in one batch API call ─────────────────

Write-Host "Fetching all GitHub releases (single API call)..." -ForegroundColor Cyan
$allReleases = @{}
$releasesJson = & gh release list --repo $Repository --limit 999 --json tagName,createdAt,isPrerelease 2>$null
if ($LASTEXITCODE -eq 0 -and $releasesJson) {
    $releasesList = $releasesJson | ConvertFrom-Json
    foreach ($rel in $releasesList) {
        $allReleases[$rel.tagName] = @{
            CreatedAt    = [DateTime]::Parse($rel.createdAt)
            IsPrerelease = $rel.isPrerelease
        }
    }
    Write-Host "  Found $($allReleases.Count) releases" -ForegroundColor Green
} else {
    Write-Host "  No releases found or could not fetch" -ForegroundColor Yellow
}

# ── Step 2: Fetch all Docker package versions in one batch per package

$packageList = @()
if ($ContainerPackages) {
    $packageList = $ContainerPackages -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$dockerVersionsByPackage = @{}
foreach ($package in $packageList) {
    Write-Host "Fetching Docker versions for package: $package..." -ForegroundColor Cyan
    $versionsJson = & gh api "/orgs/$owner/packages/container/$package/versions" --paginate 2>$null
    if ($LASTEXITCODE -eq 0 -and $versionsJson) {
        $dockerVersionsByPackage[$package] = $versionsJson | ConvertFrom-Json
        Write-Host "  Found $($dockerVersionsByPackage[$package].Count) versions" -ForegroundColor Green
    } else {
        Write-Host "  Warning: Could not list versions for package $package" -ForegroundColor Yellow
        $dockerVersionsByPackage[$package] = @()
    }
}

Write-Host ""
Write-Host "API fetching complete. Processing locally from here." -ForegroundColor Cyan
Write-Host ""

# ── Helpers (no API calls) ───────────────────────────────────────────

function Get-TagCreationDate {
    param([string]$Tag)

    # Look up from the pre-fetched releases
    if ($allReleases.ContainsKey($Tag)) {
        return $allReleases[$Tag].CreatedAt
    }

    # Fall back to git tag date (local, no API call)
    $gitDate = & git log -1 --format=%aI $Tag 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitDate) {
        return [DateTime]::Parse($gitDate)
    }

    return $null
}

function Remove-GitTag {
    param([string]$Tag)

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would delete git tag: $Tag" -ForegroundColor Yellow
        return
    }

    # Delete remote tag
    & git push origin --delete "refs/tags/$Tag" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Could not delete remote tag $Tag (may not exist on remote)" -ForegroundColor Yellow
    }

    # Delete local tag
    & git tag -d $Tag 2>$null

    Write-Host "  Deleted git tag: $Tag" -ForegroundColor Green
    Start-Sleep -Seconds $DeleteDelaySeconds
}

function Remove-GitHubRelease {
    param([string]$Tag)

    # Check from pre-fetched data (no API call)
    if (-not $allReleases.ContainsKey($Tag)) {
        return  # No release for this tag
    }

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would delete GitHub release: $Tag" -ForegroundColor Yellow
        return
    }

    & gh release delete $Tag --repo $Repository --yes --cleanup-tag 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Deleted GitHub release: $Tag" -ForegroundColor Green
    } else {
        Write-Host "  Warning: Could not delete release $Tag" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $DeleteDelaySeconds
}

function Remove-DockerImageTag {
    param(
        [string]$PackageName,
        [string]$Tag
    )

    # Look up from pre-fetched data (no API call for lookup)
    $versions = $dockerVersionsByPackage[$PackageName]
    if (-not $versions) { return }

    foreach ($version in $versions) {
        $tags = $version.metadata.container.tags
        if ($tags -contains $Tag) {
            if ($tags.Count -gt 1) {
                Write-Host "  Warning: Version $($version.id) has multiple tags ($($tags -join ', ')). Skipping to avoid deleting other tags." -ForegroundColor Yellow
                return
            }

            if ($DryRun) {
                Write-Host "  [DRY RUN] Would delete Docker image tag: $PackageName`:$Tag" -ForegroundColor Yellow
                return
            }

            & gh api --method DELETE "/orgs/$owner/packages/container/$PackageName/versions/$($version.id)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Deleted Docker image tag: $PackageName`:$Tag" -ForegroundColor Green
            } else {
                Write-Host "  Warning: Could not delete Docker image version $($version.id)" -ForegroundColor Yellow
            }
            Start-Sleep -Seconds $DeleteDelaySeconds
            return
        }
    }
}

# ── Step 3: Categorize git tags (local, no API calls) ────────────────

Write-Host "Categorizing tags..." -ForegroundColor Cyan
$allTags = & git tag -l "v*"
if (-not $allTags) {
    Write-Host "No version tags found. Nothing to clean up." -ForegroundColor Green
    exit 0
}

$finalReleases = @{}       # "1.0.0" -> tag "v1.0.0"
$prereleaseTags = @{}      # "1.0.0" -> @("v1.0.0-rc.1", "v1.0.0-rc.2", ...)
$statusTags = @{}          # "1.0.0" -> @("v1.0.0-rc.1-qa-deployed", ...)

foreach ($tag in $allTags) {
    if ($tag -match '^v(\d+\.\d+\.\d+)$') {
        $finalReleases[$matches[1]] = $tag
    }
    elseif ($tag -match '^v(\d+\.\d+\.\d+)-\w+\.\d+-.+$') {
        $version = $matches[1]
        if (-not $statusTags.ContainsKey($version)) {
            $statusTags[$version] = @()
        }
        $statusTags[$version] += $tag
    }
    elseif ($tag -match '^v(\d+\.\d+\.\d+)-\w+\.\d+$') {
        $version = $matches[1]
        if (-not $prereleaseTags.ContainsKey($version)) {
            $prereleaseTags[$version] = @()
        }
        $prereleaseTags[$version] += $tag
    }
}

$deletedCount = 0

# ── Scenario 1: Released versions ────────────────────────────────────

Write-Host ""
Write-Host "--- Released Versions ---" -ForegroundColor Cyan

# Sort versions oldest-first so least useful artifacts are cleaned up first
$sortedReleasedVersions = $finalReleases.Keys | Sort-Object {
    $tag = $finalReleases[$_]
    $date = Get-TagCreationDate -Tag $tag
    if ($date) { $date } else { [DateTime]::MaxValue }
}

foreach ($version in $sortedReleasedVersions) {
    $releaseTag = $finalReleases[$version]
    $releaseDate = Get-TagCreationDate -Tag $releaseTag
    $dockerEligible = $releaseDate -and ($releaseDate -lt $cutoffDate)

    # @(...) forces array type — a hashtable value with one element would otherwise
    # unwrap to a scalar through the `if` pipeline, turning `$rcTags + $stTags` into
    # string concatenation and producing malformed tag names.
    $rcTags = @(if ($prereleaseTags.ContainsKey($version)) { $prereleaseTags[$version] } else { @() })
    $stTags = @(if ($statusTags.ContainsKey($version)) { $statusTags[$version] } else { @() })

    if ($rcTags.Count -eq 0 -and $stTags.Count -eq 0) {
        continue  # Already cleaned up
    }

    Write-Host ""
    Write-Host "Version $version (released as $releaseTag)" -ForegroundColor White

    # Delete all prerelease GitHub releases and git tags immediately
    foreach ($tag in ($rcTags + $stTags)) {
        Remove-GitHubRelease -Tag $tag
        Remove-GitTag -Tag $tag
        $deletedCount++
    }

    # Delete Docker image tags only after retention period
    if ($packageList.Count -gt 0 -and $rcTags.Count -gt 0) {
        if ($dockerEligible) {
            Write-Host "  Docker retention period passed (released $releaseDate)" -ForegroundColor Gray
            foreach ($package in $packageList) {
                foreach ($tag in $rcTags) {
                    Remove-DockerImageTag -PackageName $package -Tag $tag
                }
            }
        } else {
            Write-Host "  Docker images retained (released $releaseDate, cutoff $cutoffDate)" -ForegroundColor Gray
        }
    }
}

# ── Scenario 2: Superseded prereleases (no final release) ───────────

Write-Host ""
Write-Host "--- Superseded Prereleases ---" -ForegroundColor Cyan

# Sort versions oldest-first
$sortedPrereleaseVersions = $prereleaseTags.Keys | Sort-Object {
    $tags = $prereleaseTags[$_]
    $dates = $tags | ForEach-Object { Get-TagCreationDate -Tag $_ } | Where-Object { $_ }
    if ($dates) { ($dates | Measure-Object -Minimum).Minimum } else { [DateTime]::MaxValue }
}

foreach ($version in $sortedPrereleaseVersions) {
    if ($finalReleases.ContainsKey($version)) {
        continue  # Already handled in Scenario 1
    }

    $rcTags = $prereleaseTags[$version]
    if ($rcTags.Count -le 1) {
        continue  # Only one RC, nothing superseded
    }

    # Sort RC tags by RC number ascending (oldest first for cleanup)
    $sortedRcTags = $rcTags | Sort-Object {
        if ($_ -match '\.(\d+)$') { [int]$matches[1] } else { 0 }
    }

    $latestRc = $sortedRcTags[-1]
    $olderRcs = $sortedRcTags | Select-Object -SkipLast 1

    Write-Host ""
    Write-Host "Version $version (unreleased, latest: $latestRc)" -ForegroundColor White

    foreach ($rcTag in $olderRcs) {
        $tagDate = Get-TagCreationDate -Tag $rcTag
        if (-not $tagDate -or $tagDate -ge $cutoffDate) {
            Write-Host "  Retained $rcTag (created $tagDate, within retention window)" -ForegroundColor Gray
            continue
        }

        Write-Host "  Cleaning up $rcTag (created $tagDate)" -ForegroundColor White

        # Delete the RC release and tag
        Remove-GitHubRelease -Tag $rcTag
        Remove-GitTag -Tag $rcTag
        $deletedCount++

        # Delete associated status tags
        $stTags = if ($statusTags.ContainsKey($version)) { $statusTags[$version] } else { @() }
        $relatedStatusTags = $stTags | Where-Object { $_ -like "$rcTag-*" }
        foreach ($stTag in $relatedStatusTags) {
            Remove-GitHubRelease -Tag $stTag
            Remove-GitTag -Tag $stTag
            $deletedCount++
        }

        # Delete Docker image tags for this superseded RC
        if ($packageList.Count -gt 0) {
            foreach ($package in $packageList) {
                Remove-DockerImageTag -PackageName $package -Tag $rcTag
            }
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Dry run complete. $deletedCount item(s) would be deleted." -ForegroundColor Yellow
} else {
    Write-Host "  Cleanup complete. $deletedCount item(s) deleted." -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan

# External commands (e.g. `git tag -d` when the tag was already removed by
# `gh release delete --cleanup-tag`) leave $LASTEXITCODE non-zero. Without
# an explicit exit, pwsh propagates that and the job fails despite success.
exit 0
