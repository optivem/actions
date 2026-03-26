# Test single image vs multiple images with both input formats
Write-Host "Testing single vs multiple images..." -ForegroundColor Yellow

# Test 1: Single image - Newline format
Write-Host "`n=== Test 1: Single image (newline format) ===" -ForegroundColor Cyan
$singleNewline = "nginx"
Write-Host "Input: '$singleNewline'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $singleNewline 2>&1 | Out-Null
    Write-Host "✅ Single image newline format worked" -ForegroundColor Green
} catch {
    Write-Host "❌ Single image newline failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Single image - JSON format
Write-Host "`n=== Test 2: Single image (JSON format) ===" -ForegroundColor Cyan
$singleJson = '["nginx"]'
Write-Host "Input: '$singleJson'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $singleJson 2>&1 | Out-Null
    Write-Host "✅ Single image JSON format worked" -ForegroundColor Green
} catch {
    Write-Host "❌ Single image JSON failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Multiple images - Newline format
Write-Host "`n=== Test 3: Multiple images (newline format) ===" -ForegroundColor Cyan
$multipleNewline = "nginx`nredis`npostgres"
Write-Host "Input: '$multipleNewline'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $multipleNewline 2>&1 | Out-Null
    Write-Host "✅ Multiple images newline format worked" -ForegroundColor Green
} catch {
    Write-Host "❌ Multiple images newline failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Multiple images - JSON format
Write-Host "`n=== Test 4: Multiple images (JSON format) ===" -ForegroundColor Cyan
$multipleJson = '["nginx", "redis", "postgres"]'
Write-Host "Input: '$multipleJson'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $multipleJson 2>&1 | Out-Null
    Write-Host "✅ Multiple images JSON format worked" -ForegroundColor Green
} catch {
    Write-Host "❌ Multiple images JSON failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== JSON Output Format Test ===" -ForegroundColor Cyan
Write-Host "Testing JSON output formatting directly..."

# Test the JSON output formatting logic directly
$testUrls1 = @("nginx:test")
$testUrls2 = @("nginx:test", "redis:test")

Write-Host "Single URL array: $($testUrls1 | ConvertTo-Json -Compress -AsArray)"
Write-Host "Multiple URL array: $($testUrls2 | ConvertTo-Json -Compress -AsArray)"