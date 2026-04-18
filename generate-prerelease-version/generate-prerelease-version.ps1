#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Assert that the final release tag for the target version has not already been created.
    Used by generate-prerelease-version to prevent creating RC candidates for an
    already-released version.

.PARAMETER TargetVersion
    Target semantic version from VERSION file (e.g., 1.0.0)

.PARAMETER Prefix
    Optional prefix. When set, the final tag checked is "{prefix}-v{version}";
    when empty, "v{version}".
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetVersion,
    [string]$Prefix = ""
)

if ($TargetVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "❌ Invalid version format: $TargetVersion. Expected: X.Y.Z (e.g., 1.0.0)"
    exit 1
}

$prefixPart = if ($Prefix) { "$Prefix-" } else { "" }
$finalTag = "${prefixPart}v$TargetVersion"

Write-Host "📋 Checking final tag does not exist: $finalTag"

$existingFinalTag = & git tag -l $finalTag
if ($existingFinalTag) {
    Write-Error "❌ Version $finalTag is already released. Cannot create release candidates for an existing release. Bump the version in your VERSION file first."
    exit 1
}

Write-Host "✅ Final tag $finalTag not yet released — safe to generate RC."
