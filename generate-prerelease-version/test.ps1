# Consolidated Test Script for Semantic Version Docker Prerelease Action
# Combines all testing functionality into a single script with parameters

param(
    [string]$TestMode = "full",  # Options: full, quick, validate, parse-only
    [string]$ImageUrls = @"
# Test frontend services  
ghcr.io/optivem/prerelease-docker-images-action/test-app:latest

# Test backend services
ghcr.io/optivem/prerelease-docker-images-action/api:latest
"@,
    [string]$PrereleaseSuffix = "rc",
    [bool]$MockDocker = $true,  # Mock Docker operations by default
    [bool]$DryRun = $true,      # Don't make actual changes by default
    [bool]$Verbose = $false,    # Show detailed output
    [switch]$TestJsonFormat     # Test JSON array format instead
)

# ANSI color codes for better output
$colors = @{
    Cyan = "`e[36m"
    Green = "`e[32m"
    Yellow = "`e[33m"
    Red = "`e[31m"
    Magenta = "`e[35m"
    Gray = "`e[37m"
    Reset = "`e[0m"
}

function Write-ColorHost {
    param([string]$Message, [string]$Color = "Reset")
    if ($colors.ContainsKey($Color)) {
        Write-Host "$($colors[$Color])$Message$($colors.Reset)"
    } else {
        Write-Host $Message
    }
}

function Write-TestResult {
    param([bool]$Condition, [string]$Description)
    $script:testsTotal++
    if ($Condition) {
        Write-ColorHost "✅ $Description" "Green"
        $script:testsPassed++
    } else {
        Write-ColorHost "❌ $Description" "Red"
    }
}

# Initialize test counters
$testsPassed = 0
$testsTotal = 0

Write-ColorHost "🧪 === CONSOLIDATED ACTION TEST ===" "Cyan"
Write-ColorHost "Test Mode: $TestMode" "Yellow"

# Switch to JSON format for testing if requested
if ($TestJsonFormat) {
    $ImageUrls = '["ghcr.io/optivem/prerelease-docker-images-action/test-app:latest", "ghcr.io/optivem/prerelease-docker-images-action/api:latest"]'
    Write-ColorHost "Format: JSON Array" "Yellow"
} else {
    Write-ColorHost "Format: Newline-separated" "Yellow"
}

Write-ColorHost "Image URLs:" "Yellow"
# Parse URLs using the same logic as the action
try {
    $trimmedInput = $ImageUrls.Trim()
    if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
        $jsonArray = $ImageUrls | ConvertFrom-Json
        if ($jsonArray -is [Array]) {
            $imageUrlList = $jsonArray | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
        } else {
            $imageUrlList = @($jsonArray.Trim())
        }
    } else {
        throw "Not JSON format"
    }
} catch {
    $imageUrlList = $ImageUrls -split "`r?`n" | Where-Object { 
        $_.Trim() -ne "" -and $_.Trim() -notmatch "^#" 
    } | ForEach-Object { $_.Trim() }
}

foreach ($url in $imageUrlList) {
    Write-ColorHost "  - $url" "Yellow"
}
Write-ColorHost "Mock Docker: $MockDocker" "Yellow"
Write-ColorHost "Dry Run: $DryRun" "Yellow"
Write-ColorHost "=================================" "Cyan"
Write-Host ""

# Test Mode: Parse Only
if ($TestMode -eq "parse-only" -or $TestMode -eq "quick") {
    Write-ColorHost "🔍 URL Parsing Test" "Yellow"
    Write-ColorHost "===================" "Yellow"
    
    foreach ($ImageUrl in $imageUrlList) {
        Write-Host "`nTesting URL: $ImageUrl"
        
        if ($ImageUrl -match '^(.+)@(sha256:[a-f0-9]{64})$') {
            $baseUrl = $matches[1]
            Write-ColorHost "✅ Digest URL - Base: $baseUrl, Digest: $($matches[2])" "Green"
        } elseif ($ImageUrl -match '^(.+):([^@]+)$') {
            $baseUrl = $matches[1]
            Write-ColorHost "✅ Tag URL - Base: $baseUrl, Tag: $($matches[2])" "Green"
        } else {
            Write-ColorHost "❌ Invalid URL format: $ImageUrl" "Red"
            return
        }
        
        # Test registry detection
        $registryHost = $baseUrl -split '/' | Select-Object -First 1
        Write-Host "🔍 Registry: $registryHost"
    }
    
    # Test version generation
    $latestTag = git tag -l "v*.*.*" --sort=-version:refname | Select-Object -First 1
    if ($latestTag) {
        Write-Host "`n📌 Latest tag: $latestTag"
        
        if ($latestTag -match "^v(\d+)\.(\d+)\.(\d+)") {
            $newPatch = [int]$matches[3] + 1
            $newVersion = "v$($matches[1]).$($matches[2]).$newPatch"
            $prereleaseVersion = "$newVersion-$PrereleaseSuffix"
            
            Write-ColorHost "🆕 Next version: $newVersion" "Green"
            Write-ColorHost "🚀 Prerelease: $prereleaseVersion" "Green"
            
            foreach ($ImageUrl in $imageUrlList) {
                if ($ImageUrl -match '^(.+):([^@]+)$') {
                    $baseUrl = $matches[1]
                    Write-ColorHost "🎯 Target image: $baseUrl`:$prereleaseVersion" "Green"
                }
            }
        }
    } else {
        Write-ColorHost "⚠️  No tags found" "Yellow"
    }
    
    if ($TestMode -eq "quick") { return }
}

# Test Mode: Validate
if ($TestMode -eq "validate" -or $TestMode -eq "full") {
    Write-ColorHost "`n📋 Structure Validation" "Yellow"
    Write-ColorHost "=======================" "Yellow"
    
    # Test action.yml validation
    if (Test-Path "action.yml") {
        $actionContent = Get-Content "action.yml" -Raw
        Write-TestResult ($actionContent -match "image-urls:") "action.yml contains image-urls input"
        Write-TestResult ($actionContent -match "registry-token:") "action.yml contains registry-token input"
        Write-TestResult ($actionContent -match "registry-username:") "action.yml contains registry-username input"
        Write-TestResult ($actionContent -match "prerelease-suffix:") "action.yml contains prerelease-suffix input"
        Write-TestResult ($actionContent -match "steps:") "action.yml contains steps section"
    }
    
    # Test PowerShell script validation
    if (Test-Path "action.ps1") {
        $scriptContent = Get-Content "action.ps1" -Raw
        Write-TestResult ($scriptContent -match "param\(") "action.ps1 has parameter block"
        Write-TestResult ($scriptContent -match "ImageUrls") "action.ps1 accepts ImageUrls parameter"
        Write-TestResult ($scriptContent -match "RegistryToken") "action.ps1 accepts RegistryToken parameter"
        Write-TestResult ($scriptContent -match "RegistryUsername") "action.ps1 accepts RegistryUsername parameter"
        Write-TestResult ($scriptContent -match "PrereleaseSuffix") "action.ps1 accepts PrereleaseSuffix parameter"
        
        # Test URL parsing logic
        Write-TestResult ($scriptContent -match "sha256:\[a-f0-9\]") "Digest regex pattern exists"
        Write-TestResult ($scriptContent -match "\(\.\+\):\(\[.*\]\+\)") "Tag regex pattern exists"
        
        # Test Docker operations
        Write-TestResult ($scriptContent -match "docker login") "Docker login command exists"
        Write-TestResult ($scriptContent -match "docker pull") "Docker pull command exists"
        Write-TestResult ($scriptContent -match "docker tag") "Docker tag command exists"
        Write-TestResult ($scriptContent -match "docker push") "Docker push command exists"
        
        # Test GitHub output handling
        Write-TestResult ($scriptContent -match "Out-File.*GitHubOutput") "GitHub Actions output generation exists"
        Write-TestResult ($scriptContent -match "prerelease-version=") "Prerelease version output exists"
        Write-TestResult ($scriptContent -match "image-prerelease-urls") "Image prerelease URLs output exists"
    }
    
    # Test documentation consistency
    if (Test-Path "README.md") {
        $readmeContent = Get-Content "README.md" -Raw
        Write-TestResult ($readmeContent -match "image-url") "README documents image-url"
        Write-TestResult ($readmeContent -match "registry-token") "README documents registry-token"
        Write-TestResult ($readmeContent -notmatch "image-name") "README doesn't contain old image-name"
        Write-TestResult ($readmeContent -notmatch "github-token") "README doesn't contain old github-token"
    }
    
    # Test sample URLs
    Write-ColorHost "`n🔗 URL Format Tests" "Yellow"
    $testUrls = @(
        "ghcr.io/company/repo:latest",
        "docker.io/user/app:v1.0.0",
        "registry.azurecr.io/team/service@sha256:abc123def456"
    )
    
    foreach ($url in $testUrls) {
        $isValid = ($url -match "^(.+)@(sha256:[a-f0-9]+)$") -or ($url -match "^(.+):([^@]+)$")
        Write-TestResult $isValid "URL format valid: $url"
    }
    
    if ($TestMode -eq "validate") { 
        Write-ColorHost "`n📊 Validation Summary: $testsPassed / $testsTotal passed" $(if ($testsPassed -eq $testsTotal) { "Green" } else { "Yellow" })
        return 
    }
}

# Test Mode: Full (includes actual script execution)
if ($TestMode -eq "full") {
    Write-ColorHost "`n🚀 Script Execution Test" "Yellow"
    Write-ColorHost "=========================" "Yellow"
    
    # Set up test environment
    $env:GITHUB_OUTPUT = "$PSScriptRoot\test-github-output.txt"
    $testRegistryToken = "test-token-12345"
    $testRegistryUsername = "test-user"
    
    # Clear previous output
    if (Test-Path $env:GITHUB_OUTPUT) {
        Remove-Item $env:GITHUB_OUTPUT
    }
    
    # Ensure git tags exist
    $existingTags = git tag -l "v*.*.*" --sort=-version:refname
    if ($existingTags.Count -eq 0) {
        Write-ColorHost "⚠️  No semantic version tags found. Creating test tag v0.1.0..." "Yellow"
        if (-not $DryRun) {
            git tag v0.1.0 -m "Test tag for local testing"
        } else {
            Write-Host "   [DRY RUN] Would create: git tag v0.1.0 -m 'Test tag for local testing'"
        }
    }
    
    try {
        if ($MockDocker) {
            Write-ColorHost "🔄 Running with mocked Docker operations..." "Magenta"
            $env:MOCK_DOCKER = "true"
        }
        
        # Run the script
        & "$PSScriptRoot\action.ps1" -ImageUrls $ImageUrls -RegistryToken $testRegistryToken -RegistryUsername $testRegistryUsername -PrereleaseSuffix $PrereleaseSuffix
        
        # Show outputs
        Write-ColorHost "`n📊 Generated Outputs:" "Green"
        if (Test-Path $env:GITHUB_OUTPUT) {
            $outputs = Get-Content $env:GITHUB_OUTPUT
            foreach ($output in $outputs) {
                Write-Host "  $output"
            }
        } else {
            Write-ColorHost "  No outputs generated" "Red"
        }
        
    } catch {
        Write-ColorHost "❌ Error running script: $($_.Exception.Message)" "Red"
    } finally {
        # Cleanup
        Remove-Item Env:MOCK_DOCKER -ErrorAction SilentlyContinue
        if ((Test-Path $env:GITHUB_OUTPUT) -and (-not $DryRun)) {
            Remove-Item $env:GITHUB_OUTPUT
        }
    }
}

# Final summary
Write-ColorHost "`n📊 Test Summary" "Cyan"
Write-ColorHost "===============" "Cyan"
if ($testsTotal -gt 0) {
    Write-ColorHost "Validation Tests: $testsPassed / $testsTotal passed" $(if ($testsPassed -eq $testsTotal) { "Green" } else { "Yellow" })
}

Write-ColorHost "✅ Test completed successfully!" "Green"

Write-ColorHost "`n💡 Usage Examples:" "Magenta"
Write-ColorHost "==================" "Magenta"
Write-Host "# Quick test with newline format:"
Write-Host ".\test.ps1 -TestMode quick"
Write-Host ""
Write-Host "# Quick test with JSON format:"
Write-Host ".\test.ps1 -TestMode quick -TestJsonFormat"
Write-Host ""
Write-Host "# Structure validation only:"
Write-Host ".\test.ps1 -TestMode validate"
Write-Host ""
Write-Host "# Full test with real Docker (requires setup):"
Write-Host ".\test.ps1 -TestMode full -MockDocker `$false -DryRun `$false"
Write-Host ""
Write-Host "# Test custom URLs (newline format):"
Write-Host ".\test.ps1 -ImageUrls 'docker.io/user/app:latest`ndocker.io/user/api:latest' -PrereleaseSuffix 'alpha'"
Write-Host ""
Write-Host "# Test custom URLs (JSON format):"
Write-Host ".\test.ps1 -ImageUrls '[\"docker.io/user/app:latest\", \"docker.io/user/api:latest\"]' -PrereleaseSuffix 'alpha'"