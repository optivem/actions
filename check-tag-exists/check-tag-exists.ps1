#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Checks if Git tag already exists

.PARAMETER TagName
    The git tag name to check (e.g., v1.0.3)

.EXAMPLE
    .\check-tag-exists.ps1 -TagName "v1.0.5"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TagName
)

Write-Host "🏷️  Checking if Git tag $TagName already exists..." -ForegroundColor Blue

# Fetch remote tags first (GitHub Actions has shallow clone by default)
Write-Host "📡 Fetching remote tags..." -ForegroundColor Cyan
git fetch origin --tags 2>$null

# Check if Git tag already exists (locally or remotely)
$tagExists = git rev-parse "$TagName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "❌ Git tag $TagName already exists!" -ForegroundColor Red
    Write-Host "That version is already claimed. Consider incrementing to the next version." -ForegroundColor Yellow
    Write-Host "To reuse this tag, delete it first: git tag -d $TagName && git push origin :refs/tags/$TagName" -ForegroundColor Cyan
    exit 1
} else {
    Write-Host "✅ Git tag $TagName does not exist" -ForegroundColor Green
}

exit 0