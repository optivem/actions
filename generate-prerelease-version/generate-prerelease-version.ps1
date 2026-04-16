#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generate prerelease version from target version with incrementing RC number

.PARAMETER TargetVersion
    Target semantic version from VERSION file (e.g., 1.0.0)

.PARAMETER PrereleaseSuffix
    Prerelease suffix (e.g., rc, alpha, beta)

.EXAMPLE
    .\generate-prerelease-version.ps1 -TargetVersion "1.0.0" -PrereleaseSuffix "rc"
    Output: v1.0.0-rc.1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetVersion,
    [string]$PrereleaseSuffix = "rc",
    [string]$GitHubOutput = $env:GITHUB_OUTPUT
)

Write-Host "🏷️ Generating prerelease version..."
Write-Host ""
Write-Host "📋 Input Parameters:"
Write-Host "   Target Version: $TargetVersion"
Write-Host "   Prerelease Suffix: $PrereleaseSuffix"
Write-Host ""

# Validate target version format
if ($TargetVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "❌ Invalid version format: $TargetVersion. Expected: X.Y.Z (e.g., 1.0.0)"
    exit 1
}

# Check if the final version already exists
$finalTag = "v$TargetVersion"
$existingFinalTag = & git tag -l $finalTag
if ($existingFinalTag) {
    Write-Error "❌ Version $finalTag is already released. Cannot create release candidates for an existing release. Bump the version in your VERSION file first."
    exit 1
}

# Find existing RC tags for this target version
$pattern = "v$TargetVersion-$PrereleaseSuffix.*"
Write-Host "📋 Finding existing tags matching: $pattern"
$existingTags = & git tag -l $pattern

$maxRc = 0

if ($existingTags) {
    foreach ($tag in $existingTags) {
        if ($tag -match "-$([regex]::Escape($PrereleaseSuffix))\.(\d+)") {
            $rcNum = [int]$matches[1]
            if ($rcNum -gt $maxRc) {
                $maxRc = $rcNum
            }
        }
    }
    Write-Host "📌 Found existing tags, highest RC number: $maxRc"
} else {
    Write-Host "🆕 No existing RC tags found for v$TargetVersion"
}

$nextRc = $maxRc + 1
$prereleaseVersion = "v$TargetVersion-$PrereleaseSuffix.$nextRc"

Write-Host ""
Write-Host "📦 Generated prerelease version: $prereleaseVersion"

# Output the version
if ($GitHubOutput) {
    Add-Content -Path $GitHubOutput -Value "version=$prereleaseVersion"
    Write-Host "✅ Set output 'version' to: $prereleaseVersion"
} else {
    Write-Host "Prerelease Version: $prereleaseVersion"
}

Write-Host ""
Write-Host "🎉 Version generation completed successfully!"
