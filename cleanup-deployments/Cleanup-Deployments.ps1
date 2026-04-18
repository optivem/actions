#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Cleans up superseded GitHub deployments that are no longer needed.

.DESCRIPTION
    Mirrors cleanup-prereleases logic, adapted for deployments:

    Scenario 1 — Released versions (final tag vX.Y.Z exists):
      - Immediately delete deployments whose SHA corresponds to any
        vX.Y.Z-rc.* tag (bypassing the retention window)

    Scenario 2 — Superseded per environment:
      - For each environment, always keep the latest deployment
      - Delete older deployments past the retention period

    GitHub requires a deployment to be inactive before deletion, so each
    deployment gets a new "inactive" status created before the DELETE call.

    IMPORTANT: run this action BEFORE cleanup-prereleases — Scenario 1
    relies on the RC git tags still being present to resolve SHAs.

.PARAMETER RetentionDays
    Number of days to retain superseded deployments before deletion. Default: 30

.PARAMETER DeleteDelaySeconds
    Seconds to wait between each API delete call to avoid GitHub rate limiting. Default: 10

.PARAMETER DryRun
    If true, only log what would be deleted without actually deleting anything.

.PARAMETER Repository
    GitHub repository in owner/repo format. Defaults to GITHUB_REPOSITORY env var.
#>

param(
    [int]$RetentionDays = 30,
    [int]$DeleteDelaySeconds = 10,
    [bool]$DryRun = $false,
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deployment Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository:     $Repository"
Write-Host "Retention Days: $RetentionDays"
Write-Host "Delete Delay:   ${DeleteDelaySeconds}s"
Write-Host "Dry Run:        $DryRun"
Write-Host ""

$cutoffDate = (Get-Date).AddDays(-$RetentionDays)

# ── Step 1: Categorize tags (local, no API calls) ───────────────────

Write-Host "Categorizing tags..." -ForegroundColor Cyan
$allTags = & git tag -l "v*"

$finalReleases = @{}     # "1.0.0" -> tag "v1.0.0"
$prereleaseTags = @{}    # "1.0.0" -> @("v1.0.0-rc.1", "v1.0.0-rc.2", ...)

if ($allTags) {
    foreach ($tag in $allTags) {
        if ($tag -match '^v(\d+\.\d+\.\d+)$') {
            $finalReleases[$matches[1]] = $tag
        }
        elseif ($tag -match '^v(\d+\.\d+\.\d+)-\w+\.\d+$') {
            $version = $matches[1]
            if (-not $prereleaseTags.ContainsKey($version)) {
                $prereleaseTags[$version] = @()
            }
            $prereleaseTags[$version] += $tag
        }
    }
    Write-Host "  Final releases:  $($finalReleases.Count)" -ForegroundColor Green
    Write-Host "  RC versions:     $($prereleaseTags.Count)" -ForegroundColor Green
} else {
    Write-Host "  No version tags found" -ForegroundColor Yellow
}

# ── Step 2: Build set of "released-RC SHAs" ─────────────────────────
# SHAs of any RC tag whose version has a final release.
# Deployments matching these SHAs are deleted immediately (Scenario 1).

$releasedRcShas = @{}
foreach ($version in $finalReleases.Keys) {
    if (-not $prereleaseTags.ContainsKey($version)) { continue }
    foreach ($rcTag in $prereleaseTags[$version]) {
        $sha = & git rev-list -n 1 $rcTag 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) {
            $releasedRcShas[$sha.Trim()] = $rcTag
        }
    }
}
Write-Host "  Released-RC SHAs: $($releasedRcShas.Count)" -ForegroundColor Green
Write-Host ""

# ── Step 3: Fetch all deployments (paginated) ───────────────────────

Write-Host "Fetching all deployments..." -ForegroundColor Cyan
$deploymentsJson = & gh api "/repos/$Repository/deployments" --paginate 2>$null
if ($LASTEXITCODE -ne 0 -or -not $deploymentsJson) {
    Write-Host "  No deployments found or could not fetch" -ForegroundColor Yellow
    exit 0
}

# --paginate concatenates JSON arrays as "][" — merge into a single array
$deploymentsJson = $deploymentsJson -replace '\]\[', ','
$allDeployments = $deploymentsJson | ConvertFrom-Json
Write-Host "  Found $($allDeployments.Count) deployment(s)" -ForegroundColor Green
Write-Host ""

# ── Helpers ─────────────────────────────────────────────────────────

function Remove-Deployment {
    param($Deployment, [string]$Reason)

    $id = $Deployment.id
    $env = $Deployment.environment
    $sha = $Deployment.sha.Substring(0, 7)

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would delete deployment ${id} (env=${env}, sha=${sha}) — ${Reason}" -ForegroundColor Yellow
        return
    }

    # Mark inactive first — GitHub rejects DELETE on an active deployment
    # unless the caller has repo_deployment scope. Creating an inactive
    # status is the documented workaround and always works with deployments:write.
    & gh api --method POST "/repos/$Repository/deployments/$id/statuses" `
        -f state=inactive 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Could not mark deployment ${id} inactive — skipping delete" -ForegroundColor Yellow
        return
    }

    & gh api --method DELETE "/repos/$Repository/deployments/$id" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Deleted deployment ${id} (env=${env}, sha=${sha}) — ${Reason}" -ForegroundColor Green
    } else {
        Write-Host "  Warning: Could not delete deployment ${id}" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $DeleteDelaySeconds
}

# ── Step 4: Scenario 1 — released-RC deployments (delete immediately)

Write-Host "--- Scenario 1: Released-RC Deployments ---" -ForegroundColor Cyan

$deletedCount = 0
$remainingDeployments = @()

foreach ($deployment in $allDeployments) {
    if ($releasedRcShas.ContainsKey($deployment.sha)) {
        $rcTag = $releasedRcShas[$deployment.sha]
        Remove-Deployment -Deployment $deployment -Reason "RC ${rcTag} (released)"
        $deletedCount++
    } else {
        $remainingDeployments += $deployment
    }
}

if ($deletedCount -eq 0) {
    Write-Host "  No released-RC deployments found" -ForegroundColor Gray
}
Write-Host ""

# ── Step 5: Scenario 2 — superseded per environment ─────────────────

Write-Host "--- Scenario 2: Superseded Per Environment ---" -ForegroundColor Cyan

$byEnvironment = @{}
foreach ($deployment in $remainingDeployments) {
    $env = $deployment.environment
    if (-not $byEnvironment.ContainsKey($env)) {
        $byEnvironment[$env] = @()
    }
    $byEnvironment[$env] += $deployment
}

# Sort environments alphabetically for stable log output
$sortedEnvironments = $byEnvironment.Keys | Sort-Object

foreach ($env in $sortedEnvironments) {
    $deployments = $byEnvironment[$env]
    if ($deployments.Count -le 1) {
        continue  # Only one deployment for this env, nothing superseded
    }

    # Sort newest first by created_at
    $sorted = $deployments | Sort-Object { [DateTime]::Parse($_.created_at) } -Descending
    $latest = $sorted[0]
    $older = $sorted | Select-Object -Skip 1

    Write-Host ""
    Write-Host "Environment: $env (latest: $($latest.id) at $($latest.created_at))" -ForegroundColor White

    foreach ($deployment in $older) {
        $createdAt = [DateTime]::Parse($deployment.created_at)
        if ($createdAt -ge $cutoffDate) {
            Write-Host "  Retained $($deployment.id) (created $createdAt, within retention window)" -ForegroundColor Gray
            continue
        }

        Remove-Deployment -Deployment $deployment -Reason "superseded, past retention"
        $deletedCount++
    }
}

# ── Summary ─────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Dry run complete. $deletedCount deployment(s) would be deleted." -ForegroundColor Yellow
} else {
    Write-Host "  Cleanup complete. $deletedCount deployment(s) deleted." -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan

exit 0
