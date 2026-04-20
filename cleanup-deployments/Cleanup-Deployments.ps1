#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Cleans up superseded GitHub deployments that are no longer needed.

.DESCRIPTION
    Mirrors cleanup-prereleases logic, adapted for deployments:

    Scenario 1 — Released versions (final tag vX.Y.Z exists):
      - Immediately delete deployments whose SHA corresponds to any
        vX.Y.Z-rc.* tag (bypassing keep-count and retention)

    Scenario 2 — Superseded per environment (count cap + retention floor):
      - For each environment, keep the newest KeepCount deployments
      - Anything beyond the cap is deleted only if also older than
        RetentionDays (the floor prevents pruning fresh bursts mid-debug)

    GitHub requires a deployment to be inactive before deletion, so each
    deployment gets a new "inactive" status created before the DELETE call.

    IMPORTANT: run this action BEFORE cleanup-prereleases — Scenario 1
    relies on the RC git tags still being present to resolve SHAs.

.PARAMETER KeepCount
    Per-environment count cap. Keep this many newest deployments regardless
    of age; candidates beyond the cap are eligible if past RetentionDays. Default: 3

.PARAMETER RetentionDays
    Retention floor in days. Candidates beyond KeepCount are only deleted
    once older than this cutoff. Default: 30

.PARAMETER ProtectedEnvironments
    Comma-separated list of environment name patterns whose deployments must never be
    deleted. Supports `*` wildcards, case-insensitive. Default: "*-production,production".

.PARAMETER DeleteDelaySeconds
    Seconds to wait between each API delete call to avoid GitHub rate limiting. Default: 10

.PARAMETER DryRun
    If true, only log what would be deleted without actually deleting anything.

.PARAMETER Repository
    GitHub repository in owner/repo format. Defaults to GITHUB_REPOSITORY env var.
#>

param(
    [int]$KeepCount = 3,
    [int]$RetentionDays = 30,
    [string]$ProtectedEnvironments = "*-production,production",
    [int]$DeleteDelaySeconds = 10,
    [bool]$DryRun = $false,
    [string]$Repository = $env:GITHUB_REPOSITORY
)

$ErrorActionPreference = 'Stop'

$protectedPatterns = @()
foreach ($name in ($ProtectedEnvironments -split ',')) {
    $trimmed = $name.Trim()
    if ($trimmed) { $protectedPatterns += $trimmed }
}

function Test-EnvironmentProtected {
    param([string]$EnvironmentName)
    if (-not $EnvironmentName) { return $false }
    foreach ($pattern in $protectedPatterns) {
        # PowerShell -like is case-insensitive and supports * wildcards
        if ($EnvironmentName -like $pattern) { return $true }
    }
    return $false
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deployment Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository:             $Repository"
Write-Host "Keep Count:             $KeepCount"
Write-Host "Retention Days:         $RetentionDays"
Write-Host "Protected Environments: $(if ($protectedPatterns.Count) { ($protectedPatterns -join ', ') } else { '(none)' })"
Write-Host "Delete Delay:           ${DeleteDelaySeconds}s"
Write-Host "Dry Run:                $DryRun"
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

# Filter out deployments in protected environments before any scenario runs.
# These are never eligible for deletion. Belt-and-suspenders: Remove-Deployment
# also enforces this, so a regression in either guard is caught by the other.
$protectedCount = 0
$allDeployments = @($allDeployments | Where-Object {
    if (Test-EnvironmentProtected -EnvironmentName $_.environment) {
        $protectedCount++
        $false
    } else {
        $true
    }
})
if ($protectedCount -gt 0) {
    Write-Host "  Excluded $protectedCount deployment(s) in protected environment(s)" -ForegroundColor Cyan
}
Write-Host ""

# ── Helpers ─────────────────────────────────────────────────────────

function Remove-Deployment {
    param($Deployment, [string]$Reason)

    $id = $Deployment.id
    $env = $Deployment.environment
    $sha = $Deployment.sha.Substring(0, 7)

    # Safety net: never delete a deployment to a protected environment,
    # even if upstream logic thought it was eligible. This is the last line
    # of defense against accidental production-deployment deletion.
    if (Test-EnvironmentProtected -EnvironmentName $env) {
        Write-Host "  Protected: skipping deployment ${id} (env=${env}, sha=${sha}) — ${Reason}" -ForegroundColor Cyan
        return
    }

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
    if ($deployments.Count -le $KeepCount) {
        continue  # Within count cap, nothing eligible
    }

    # Sort newest first by created_at
    $sorted = $deployments | Sort-Object { [DateTime]::Parse($_.created_at) } -Descending
    $candidates = $sorted | Select-Object -Skip $KeepCount

    Write-Host ""
    Write-Host "Environment: $env (total=$($deployments.Count), keep-cap=$KeepCount, candidates=$($candidates.Count))" -ForegroundColor White

    foreach ($deployment in $candidates) {
        $createdAt = [DateTime]::Parse($deployment.created_at)
        if ($createdAt -ge $cutoffDate) {
            Write-Host "  Retained $($deployment.id) (beyond keep-cap but within retention floor)" -ForegroundColor Gray
            continue
        }

        Remove-Deployment -Deployment $deployment -Reason "superseded, beyond keep-count=$KeepCount and past retention"
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
