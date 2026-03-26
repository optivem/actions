param(
    [Parameter(Mandatory = $true)]
    [string]$StatusVersion,
    
    [Parameter(Mandatory = $true)]
    [string]$OriginalVersion,
    
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$Status,
    
    [Parameter(Mandatory = $false)]
    [string]$ArtifactUrls = '[]',
    
    [Parameter(Mandatory = $false)]
    [bool]$IsPrerelease = $true,
    
    [Parameter(Mandatory = $true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    
    [Parameter(Mandatory = $true)]
    [string]$ServerUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    [string]$CommitSha,
    
    [Parameter(Mandatory = $true)]
    [string]$Actor
)

Write-Host "🚀 Creating GitHub release for $Environment $Status..." -ForegroundColor Yellow
Write-Host "📦 Status Version: $StatusVersion" -ForegroundColor Cyan
Write-Host "🏷️ Original Version: $OriginalVersion" -ForegroundColor Cyan
Write-Host "🌍 Environment: $Environment" -ForegroundColor Cyan
Write-Host "📊 Status: $Status" -ForegroundColor Cyan
Write-Host "🔖 Is Prerelease: $IsPrerelease" -ForegroundColor Cyan

# Debug authentication
Write-Host "🔍 Debugging authentication..." -ForegroundColor Yellow
Write-Host "🔑 GitHubToken parameter present: $($GitHubToken -ne $null -and $GitHubToken -ne '')" -ForegroundColor Gray
Write-Host "🔑 GH_TOKEN env var present: $($env:GH_TOKEN -ne $null -and $env:GH_TOKEN -ne '')" -ForegroundColor Gray

# Ensure GH_TOKEN is set from parameter if not already set
if ($env:GH_TOKEN -eq $null -or $env:GH_TOKEN -eq '') {
    Write-Host "⚠️ GH_TOKEN environment variable not set, setting from parameter..." -ForegroundColor Yellow
    $env:GH_TOKEN = $GitHubToken
}

# Check GitHub CLI authentication status
Write-Host "🔐 Checking GitHub CLI authentication..." -ForegroundColor Yellow
$authStatus = & gh auth status 2>&1
Write-Host "📋 Auth status output: $authStatus" -ForegroundColor Gray
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ GitHub CLI not authenticated, attempting to use token..." -ForegroundColor Yellow
}

try {
    # Parse artifact URLs
    $artifacts = @()
    if ($ArtifactUrls -and $ArtifactUrls -ne '[]') {
        try {
            $parsedUrls = $ArtifactUrls | ConvertFrom-Json
            $artifacts = $parsedUrls
            Write-Host "📋 Found $($artifacts.Count) artifact(s)" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Could not parse artifact URLs, proceeding without artifacts" -ForegroundColor Yellow
        }
    }

    # Determine status icon and description
    $statusIcon = switch ($Status.ToLower()) {
        "deployed" { "🚀" }
        "prerelease" { "📦" }
        "approved" { "🧑‍💻" }
        "rejected" { "🧑‍💻" }
        default { "📊" }
    }

    # Create release title and body
    $releaseTitle = "$statusIcon $Environment $Status - $StatusVersion"
    
    $releaseBody = @"
# $statusIcon $Environment $Status

**Original Version:** $OriginalVersion  
**Status Version:** $StatusVersion  
**Environment:** $Environment  
**Status:** $Status  
**Workflow:** [$RunId]($ServerUrl/$Repository/actions/runs/$RunId)  
**Commit:** [$($CommitSha.Substring(0,7))]($ServerUrl/$Repository/commit/$CommitSha)  
**Actor:** $Actor  

"@

    # Add artifacts section if any
    if ($artifacts.Count -gt 0) {
        $releaseBody += @"
## 📦 Artifacts

"@
        foreach ($artifact in $artifacts) {
            $releaseBody += "- $artifact`n"
        }
        $releaseBody += "`n"
    }

    # Add timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    $releaseBody += "---`n*Created: $timestamp*"

    Write-Host "📝 Release Title: $releaseTitle" -ForegroundColor Green
    Write-Host "📄 Checking if release already exists..." -ForegroundColor Yellow

    # Check if release already exists and delete it if it does
    $existingRelease = & gh release view $StatusVersion --repo $Repository 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "🗑️  Found existing release $StatusVersion, deleting it..." -ForegroundColor Yellow
        Write-Host "📄 Existing release info: $($existingRelease | Select-Object -First 1)" -ForegroundColor Gray
        
        $deleteOutput = & gh release delete $StatusVersion --repo $Repository --yes 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Successfully deleted existing release" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Failed to delete existing release: $deleteOutput" -ForegroundColor Yellow
            Write-Host "📄 Proceeding to create release anyway..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "📄 No existing release found" -ForegroundColor Yellow
    }

    Write-Host "📄 Creating release with GitHub CLI..." -ForegroundColor Yellow

    # Create the release using GitHub CLI
    $releaseArgs = @(
        "release", "create", $StatusVersion,
        "--title", $releaseTitle,
        "--notes", $releaseBody,
        "--repo", $Repository
    )

    if ($IsPrerelease) {
        $releaseArgs += "--prerelease"
    }

    $releaseOutput = & gh @releaseArgs 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $releaseUrl = $releaseOutput.Trim()
        Write-Host "✅ Successfully created release: $releaseUrl" -ForegroundColor Green
        
        # Set output for GitHub Actions
        "release-url=$releaseUrl" >> $env:GITHUB_OUTPUT
        Write-Host "📤 Set output: release-url=$releaseUrl" -ForegroundColor Yellow
    }
    else {
        Write-Error "❌ Failed to create release. GitHub CLI output: $releaseOutput"
        exit 1
    }
}
catch {
    Write-Error "❌ Error creating release: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}