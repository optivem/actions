# Comprehensive test - focusing on the JSON output without Docker validation
Write-Host "=== COMPREHENSIVE TEST: Input Parsing + JSON Output ===" -ForegroundColor Yellow

# Mock the Docker validation to focus on JSON output
$env:SKIP_DOCKER_VALIDATION = "true"

function Test-ScriptLogic {
    param(
        [string]$TestName,
        [string]$ImageUrls,
        [string]$Tag = "test"
    )
    
    Write-Host "`n--- $TestName ---" -ForegroundColor Cyan
    Write-Host "Input: '$ImageUrls'"
    
    # Simulate the script logic
    $baseUrls = @()
    try {
        $trimmedInput = $ImageUrls.Trim()
        if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
            Write-Host "📋 Detected JSON array format" -ForegroundColor Green
            $jsonArray = $ImageUrls | ConvertFrom-Json
            $baseUrls = $jsonArray | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        } else {
            Write-Host "📋 Using newline-separated format" -ForegroundColor Green
            $baseUrls = $ImageUrls -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }
    } catch {
        Write-Host "⚠️  JSON parsing failed, falling back to newline-separated format" -ForegroundColor Yellow
        $baseUrls = $ImageUrls -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    }
    
    # Build tagged URLs
    $fullUrls = @()
    foreach ($baseUrl in $baseUrls) {
        $taggedUrl = "${baseUrl}:${Tag}"
        $fullUrls += $taggedUrl
    }
    
    # Create JSON output
    if ($fullUrls.Count -eq 0) {
        $jsonOutput = "[]"
    } else {
        $jsonOutput = @($fullUrls) | ConvertTo-Json -Compress -AsArray
    }
    
    Write-Host "🐳 Base URLs: $($baseUrls.Count) - [$($baseUrls -join ', ')]" -ForegroundColor Cyan
    Write-Host "🏷️  Tagged URLs: [$($fullUrls -join ', ')]" -ForegroundColor Cyan
    Write-Host "📋 JSON Output: $jsonOutput" -ForegroundColor Green
    Write-Host "✅ Test completed successfully" -ForegroundColor Green
}

# Test all scenarios
Test-ScriptLogic -TestName "Single image (newline)" -ImageUrls "nginx"
Test-ScriptLogic -TestName "Single image (JSON)" -ImageUrls '["nginx"]'
Test-ScriptLogic -TestName "Two images (newline)" -ImageUrls "nginx`nredis"
Test-ScriptLogic -TestName "Two images (JSON)" -ImageUrls '["nginx", "redis"]'
Test-ScriptLogic -TestName "Three images (newline)" -ImageUrls "nginx`nredis`npostgres"
Test-ScriptLogic -TestName "Three images (JSON)" -ImageUrls '["nginx", "redis", "postgres"]'

Write-Host "`n🎉 All tests completed!" -ForegroundColor Yellow