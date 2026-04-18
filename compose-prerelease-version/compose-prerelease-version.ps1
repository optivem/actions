#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Compose a prerelease version string from its parts. Pure function — no git or filesystem side effects.

.PARAMETER TargetVersion
    Target semantic version (e.g., 1.0.0)

.PARAMETER Suffix
    Prerelease suffix (e.g., rc, dev, alpha, beta)

.PARAMETER Number
    Counter appended after the suffix (e.g., github.run_number or a build number)

.PARAMETER Prefix
    Optional prefix prepended to the tag. When set, output is
    "{prefix}-v{version}-{suffix}.{number}". When empty, output is
    "v{version}-{suffix}.{number}".

.EXAMPLE
    .\compose-prerelease-version.ps1 -TargetVersion "1.0.0" -Suffix "rc" -Number 42
    Output: v1.0.0-rc.42

.EXAMPLE
    .\compose-prerelease-version.ps1 -TargetVersion "1.0.0" -Suffix "dev" -Number 3 -Prefix "monolith-java"
    Output: monolith-java-v1.0.0-dev.3
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetVersion,
    [Parameter(Mandatory = $true)]
    [string]$Suffix,
    [Parameter(Mandatory = $true)]
    [int]$Number,
    [string]$Prefix = "",
    [string]$GitHubOutput = $env:GITHUB_OUTPUT
)

if ($TargetVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "❌ Invalid version format: $TargetVersion. Expected: X.Y.Z (e.g., 1.0.0)"
    exit 1
}

$prefixPart = if ($Prefix) { "$Prefix-" } else { "" }
$version = "${prefixPart}v$TargetVersion-$Suffix.$Number"

Write-Host "📦 Composed prerelease version: $version"

if ($GitHubOutput) {
    Add-Content -Path $GitHubOutput -Value "version=$version"
}
