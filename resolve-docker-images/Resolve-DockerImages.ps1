param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,
    
    [Parameter(Mandatory = $true)]
    [string]$ImageUrls
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Early validation of input parameters
Write-Host "🔍 Validating input parameters..." -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($Tag)) {
    Write-Host "❌ Tag parameter is empty or null" -ForegroundColor Red
    throw "Tag parameter cannot be empty"
}

if ([string]::IsNullOrWhiteSpace($ImageUrls)) {
    Write-Host "❌ ImageUrls parameter is empty or null" -ForegroundColor Red
    throw "ImageUrls parameter cannot be empty"
}

# Process and validate base URLs
Write-Host "🔍 Processing base image URLs..." -ForegroundColor Yellow

# Try to parse as JSON first, then fall back to newline-separated
$baseUrls = @()
try {
    # Check if input looks like JSON (starts with [ and ends with ])
    $trimmedInput = $ImageUrls.Trim()
    if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
        Write-Host "📋 Detected JSON array format" -ForegroundColor Cyan
        $jsonArray = $ImageUrls | ConvertFrom-Json
        $baseUrls = $jsonArray | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    } else {
        Write-Host "📋 Using newline-separated format" -ForegroundColor Cyan
        $baseUrls = $ImageUrls -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    }
} catch {
    Write-Host "⚠️  JSON parsing failed, falling back to newline-separated format" -ForegroundColor Yellow
    $baseUrls = $ImageUrls -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

if ($baseUrls.Count -eq 0) {
    Write-Host "❌ No valid base image URLs found after processing input" -ForegroundColor Red
    Write-Host "📋 Raw input: '$ImageUrls'" -ForegroundColor Cyan
    throw "No base image URLs provided - ensure the base-image-urls input contains valid URLs"
}

Write-Host "✅ Input validation passed:" -ForegroundColor Green
Write-Host "  📦 Tag: $Tag" -ForegroundColor Cyan
Write-Host "  🐳 Base URLs count: $($baseUrls.Count)" -ForegroundColor Cyan
foreach ($url in $baseUrls) {
    Write-Host "    - $url" -ForegroundColor Gray
}

# Function to construct Docker URLs with version tags
function Build-DockerUrls {
    param(
        [string]$Version,
        [string[]]$BaseUrls
    )
    
    try {
        Write-Host "🐳 Constructing Docker URLs for version $Version..."
        
        # Build full URLs with version tags
        $fullUrls = @()
        foreach ($baseUrl in $BaseUrls) {
            # Construct the tagged URL
            $taggedUrl = "${baseUrl}:${Tag}"
            $fullUrls += $taggedUrl
        }
        
        # Create JSON array (force array format even for single items)
        if ($fullUrls.Count -eq 0) {
            $jsonArray = "[]"
        } else {
            # Use -AsArray to ensure single items are returned as arrays too
            # Force array conversion for PowerShell JSON quirks
            $jsonArray = @($fullUrls) | ConvertTo-Json -Compress -AsArray
        }
        
        Write-Host "🏷️  Tag: $Tag" -ForegroundColor Cyan
        foreach ($url in $fullUrls) {
            Write-Host "   🐳 $url" -ForegroundColor Cyan
        }
        
        return @{
            Success = $true
            DockerUrls = $fullUrls[0]  # First URL for backward compatibility
            DockerUrlsJson = $jsonArray
            FullUrls = $fullUrls
            Message = "Successfully constructed $($fullUrls.Count) Docker URLs"
        }
    }
    catch {
        Write-Host "❌ Error constructing Docker URLs: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            DockerUrls = $null
            DockerUrlsJson = "[]"
            FullUrls = @()
            Message = "Error: $($_.Exception.Message)"
        }
    }
}

# Function to verify Docker images exist
function Test-DockerImagesExist {
    param(
        [array]$ImageUrls
    )
    
    try {
        Write-Host "🔍 Verifying Docker images exist..." -ForegroundColor Yellow
        
        foreach ($imageUrl in $ImageUrls) {
            Write-Host "Checking: $imageUrl"
            
            # Check if image exists using docker manifest inspect
            $null = docker manifest inspect $imageUrl 2>&1
            $dockerExitCode = $LASTEXITCODE
            
            if ($dockerExitCode -eq 0) {
                Write-Host "✅ Image exists: $imageUrl" -ForegroundColor Green
            } else {
                Write-Host "❌ Image not found: $imageUrl" -ForegroundColor Red
                # FAIL FAST: Exit immediately on first missing image
                throw "Docker image not found: $imageUrl"
            }
        }
        
        Write-Host "✅ All Docker images verified successfully" -ForegroundColor Green
        return @{
            Success = $true
            AllExist = $true
            Message = "All images exist and verified"
        }
    }
    catch {
        Write-Host "❌ Error verifying Docker images: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            AllExist = $false
            Message = "Error: $($_.Exception.Message)"
        }
    }
}

# Main execution
try {
    # Step 1: Construct Docker URLs
    $constructResult = Build-DockerUrls -Version $Tag -BaseUrls $baseUrls
    
    if (-not $constructResult.Success) {
        throw $constructResult.Message
    }
    
    # Step 2: Verify Docker images exist
    $verifyResult = Test-DockerImagesExist -ImageUrls $constructResult.FullUrls
    
    if (-not $verifyResult.Success) {
        throw $verifyResult.Message
    }
    
    # Set GitHub Actions outputs
    Write-Host "Setting GitHub Actions outputs..." -ForegroundColor Yellow
    Write-Host "🔍 Debug - Raw JSON value: '$($constructResult.DockerUrlsJson)'" -ForegroundColor Magenta
    Write-Host "🔍 Debug - JSON length: $($constructResult.DockerUrlsJson.Length)" -ForegroundColor Magenta
    
    "image-urls=$($constructResult.DockerUrlsJson)" >> $env:GITHUB_OUTPUT
    
    # Verify what was actually written
    Write-Host "🔍 Debug - Checking GITHUB_OUTPUT file contents:" -ForegroundColor Magenta
    if (Test-Path $env:GITHUB_OUTPUT) {
        $outputContent = Get-Content $env:GITHUB_OUTPUT -Raw
        Write-Host "GITHUB_OUTPUT contents:`n$outputContent" -ForegroundColor Magenta
    }
    
    # Print all outputs for debugging
    Write-Host "📋 GitHub Actions Outputs Set:" -ForegroundColor Cyan
    Write-Host "  image-urls: $($constructResult.DockerUrlsJson)" -ForegroundColor Green
    
    # Success: All images found and validated
    Write-Host "✅ All Docker images found and validated" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}