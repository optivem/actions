param(
    [Parameter(Mandatory = $true)]
    [string]$ImageUrls,
    
    [Parameter(Mandatory = $true)]
    [string]$TargetTag
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Validate inputs
if ([string]::IsNullOrWhiteSpace($ImageUrls)) {
    throw "ImageUrls parameter cannot be empty"
}

if ([string]::IsNullOrWhiteSpace($TargetTag)) {
    throw "TargetTag parameter cannot be empty"
}

# Validate target tag format (basic validation)
if ($TargetTag -match '[<>:"|?*\\]') {
    throw "TargetTag contains invalid characters: $TargetTag"
}

try {
    Write-Host "🏷️  Tagging Docker images for production release..." -ForegroundColor Green
    Write-Host "🎯 Target tag: $TargetTag" -ForegroundColor Cyan

    # Parse source image URLs - ensure we always get an array
    try {
        $parsedImages = $ImageUrls | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse ImageUrls as JSON: $($_.Exception.Message)"
    }
    
    # Force to array to handle single item case in PowerShell 7+
    $sourceImages = @($parsedImages)
    
    if ($sourceImages.Count -eq 0) {
        throw "No images found in the provided ImageUrls JSON array"
    }
    
    Write-Host "🔍 Found $($sourceImages.Count) images to tag" -ForegroundColor Yellow
    
    $newImageUrls = @()
    $failedImages = @()
    
    foreach ($sourceImageUrl in $sourceImages) {
        Write-Host "📋 Processing: $sourceImageUrl" -ForegroundColor Blue
        
        try {
            # Validate image URL format
            if ([string]::IsNullOrWhiteSpace($sourceImageUrl)) {
                Write-Host "  ⚠️  Skipping empty image URL" -ForegroundColor Yellow
                continue
            }
            
            # Extract the base image name (handles both tag and digest formats)
            if ($sourceImageUrl -match '^(.+?)[:@](.+)$') {
                $baseImageName = $matches[1]
                $tagOrDigest = $matches[2]
                
                Write-Host "  🔗 Base image: $baseImageName" -ForegroundColor Gray
                Write-Host "  🏷️  Current reference: $tagOrDigest" -ForegroundColor Gray
                
                # Create new image URL with target tag
                $newImageUrl = "${baseImageName}:${TargetTag}"
                Write-Host "  ✨ New image: $newImageUrl" -ForegroundColor Green
                
                # Pull source image
                Write-Host "  📥 Pulling source image..." -ForegroundColor Yellow
                docker pull $sourceImageUrl
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to pull source image: $sourceImageUrl (exit code: $LASTEXITCODE)"
                }
                
                # Tag with new version
                Write-Host "  🏷️  Tagging with new version..." -ForegroundColor Yellow
                docker tag $sourceImageUrl $newImageUrl
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to tag image: $sourceImageUrl -> $newImageUrl (exit code: $LASTEXITCODE)"
                }
                
                # Push new image
                Write-Host "  📤 Pushing new image..." -ForegroundColor Yellow
                docker push $newImageUrl
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to push new image: $newImageUrl (exit code: $LASTEXITCODE)"
                }
                
                # Add to new image URLs
                $newImageUrls += $newImageUrl
                Write-Host "  ✅ Successfully tagged: $sourceImageUrl -> $newImageUrl" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠️  Invalid image URL format: $sourceImageUrl" -ForegroundColor Yellow
                Write-Host "  ℹ️  Expected format: registry/image:tag or registry/image@digest" -ForegroundColor Gray
                # Keep original URL if format is unexpected
                $newImageUrls += $sourceImageUrl
                $failedImages += $sourceImageUrl
            }
        }
        catch {
            Write-Host "  ❌ Error processing image $sourceImageUrl`: $($_.Exception.Message)" -ForegroundColor Red
            $failedImages += $sourceImageUrl
            # Continue processing other images instead of failing completely
        }
    }
    
    # Check if any images were successfully processed
    if ($newImageUrls.Count -eq 0) {
        throw "No images were successfully tagged. All $($sourceImages.Count) images failed."
    }
    
    # Report on failed images
    if ($failedImages.Count -gt 0) {
        Write-Host "⚠️  Warning: $($failedImages.Count) images failed to process:" -ForegroundColor Yellow
        foreach ($failedImage in $failedImages) {
            Write-Host "  - $failedImage" -ForegroundColor Yellow
        }
    }
    
    # Convert to JSON for output - ensure it's always an array
    if ($newImageUrls.Count -eq 1) {
        # Force single item to be an array in JSON
        $newImageUrlsJson = "[$($newImageUrls[0] | ConvertTo-Json)]"
    } else {
        # Multiple items - ConvertTo-Json will naturally create an array
        $newImageUrlsJson = $newImageUrls | ConvertTo-Json -Compress
    }
    
    Write-Host "📦 New image URLs: $newImageUrlsJson" -ForegroundColor Green
    
    # Set output
    Write-Output "image-urls=$newImageUrlsJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    
    $successCount = $newImageUrls.Count
    $totalCount = $sourceImages.Count
    
    if ($failedImages.Count -eq 0) {
        Write-Host "✅ Successfully tagged all $totalCount Docker images for production" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Partially completed: $successCount/$totalCount images tagged successfully" -ForegroundColor Yellow
    }
    
    Write-Host "📤 Output parameter set: image-urls" -ForegroundColor Yellow
}
catch {
    Write-Host "❌ Error tagging Docker images: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "💡 Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "   - Ensure Docker is installed and running" -ForegroundColor Gray
    Write-Host "   - Verify GITHUB_TOKEN has appropriate permissions" -ForegroundColor Gray
    Write-Host "   - Check that source images exist and are accessible" -ForegroundColor Gray
    Write-Host "   - Ensure target registry allows pushes" -ForegroundColor Gray
    exit 1
}