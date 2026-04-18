#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Cleans up superseded GitHub deployments that are no longer needed.

.DESCRIPTION
    Mirrors the "superseded prereleases" logic from cleanup-prereleases:

    For each environment:
      - Always keep the latest deployment (never deleted)
      - Delete older deployments that are past the retention period

    GitHub requires a deployment to be inactive before deletion, so each
    deployment gets a new "inactive" status created before the DELETE call.

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

# ── Step 1: Fetch all deployments (paginated) ───────────────────────

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

# ── Step 2: Group deployments by environment ────────────────────────

$byEnvironment = @{}
foreach ($deployment in $allDeployments) {
    $env = $deployment.environment
    if (-not $byEnvironment.ContainsKey($env)) {
        $byEnvironment[$env] = @()
    }
    $byEnvironment[$env] += $deployment
}

Write-Host "Environments: $($byEnvironment.Count)" -ForegroundColor Cyan
foreach ($env in $byEnvironment.Keys | Sort-Object) {
    Write-Host "  ${env}: $($byEnvironment[$env].Count) deployment(s)" -ForegroundColor Gray
}
Write-Host ""

# ── Helpers ─────────────────────────────────────────────────────────

function Remove-Deployment {
    param($Deployment)

    $id = $Deployment.id
    $env = $Deployment.environment
    $sha = $Deployment.sha.Substring(0, 7)

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would delete deployment ${id} (env=${env}, sha=${sha})" -ForegroundColor Yellow
        return
    }

    # Mark inactive first — GitHub rejects DELETE on an active deployment
    # unless the caller has repo_deployment scope. Creating an inactive
    # status is the documented workaround and always works with contents:write.
    & gh api --method POST "/repos/$Repository/deployments/$id/statuses" `
        -f state=inactive 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Warning: Could not mark deployment ${id} inactive — skipping delete" -ForegroundColor Yellow
        return
    }

    & gh api --method DELETE "/repos/$Repository/deployments/$id" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Deleted deployment ${id} (env=${env}, sha=${sha})" -ForegroundColor Green
    } else {
        Write-Host "  Warning: Could not delete deployment ${id}" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds $DeleteDelaySeconds
}

# ── Step 3: Per environment, keep latest, delete older past retention

$deletedCount = 0

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

        Write-Host "  Cleaning up $($deployment.id) (created $createdAt)" -ForegroundColor White
        Remove-Deployment -Deployment $deployment
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
