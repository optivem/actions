# Test script to verify the resolve-docker-images action handles both input formats

Write-Host "🧪 Testing Resolve-DockerImages.ps1 with different input formats" -ForegroundColor Yellow

# Test 1: Newline-separated format (original format)
Write-Host "`n=== Test 1: Newline-separated format ===" -ForegroundColor Cyan
$newlineInput = @"
nginx
redis
postgres
"@

Write-Host "Input (newline-separated):"
Write-Host $newlineInput -ForegroundColor Gray

try {
    $scriptPath = ".\Resolve-DockerImages.ps1"
    & $scriptPath -Tag "v1.0.0" -ImageUrls $newlineInput
    Write-Host "✅ Test 1 passed" -ForegroundColor Green
} catch {
    Write-Host "❌ Test 1 failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n" + "="*50

# Test 2: JSON array format (new format)
Write-Host "`n=== Test 2: JSON array format ===" -ForegroundColor Cyan
$jsonInput = '["nginx", "redis", "postgres"]'

Write-Host "Input (JSON array):"
Write-Host $jsonInput -ForegroundColor Gray

try {
    $scriptPath = ".\Resolve-DockerImages.ps1"
    & $scriptPath -Tag "v1.0.0" -ImageUrls $jsonInput
    Write-Host "✅ Test 2 passed" -ForegroundColor Green
} catch {
    Write-Host "❌ Test 2 failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n" + "="*50

# Test 3: Single item JSON array
Write-Host "`n=== Test 3: Single item JSON array ===" -ForegroundColor Cyan
$singleJsonInput = '["nginx"]'

Write-Host "Input (single item JSON array):"
Write-Host $singleJsonInput -ForegroundColor Gray

try {
    $scriptPath = ".\Resolve-DockerImages.ps1"
    & $scriptPath -Tag "v1.0.0" -ImageUrls $singleJsonInput
    Write-Host "✅ Test 3 passed" -ForegroundColor Green
} catch {
    Write-Host "❌ Test 3 failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n🧪 Testing completed!" -ForegroundColor Yellow