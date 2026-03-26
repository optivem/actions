#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Creates and pushes a Git tag

.PARAMETER TagName
    The git tag name to create (e.g., v1.0.3)

.EXAMPLE
    .\create-tag.ps1 -TagName "v1.0.5"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TagName
)

Write-Host "🏷️ Creating Git tag ${TagName}..." -ForegroundColor Blue

# Configure git user
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Create annotated tag
git tag -a "${TagName}" -m "Tag ${TagName}"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create tag" -ForegroundColor Red
    exit 1
}

# Push tag to remote
git push origin "${TagName}"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to push tag" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Git tag ${TagName} created and pushed successfully" -ForegroundColor Green
