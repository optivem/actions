# Test both input formats with PowerShell 7
Write-Host "Testing both input formats..." -ForegroundColor Yellow

# Test 1: Newline format
Write-Host "`n=== Test 1: Newline-separated format ===" -ForegroundColor Cyan
$newlineInput = "nginx`nredis"
Write-Host "Input: '$newlineInput'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $newlineInput 2>&1 | Out-Null
    Write-Host "✅ Newline format parsing worked" -ForegroundColor Green
} catch {
    Write-Host "❌ Newline format failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: JSON format  
Write-Host "`n=== Test 2: JSON array format ===" -ForegroundColor Cyan
$jsonInput = '["nginx", "redis"]'
Write-Host "Input: '$jsonInput'"

try {
    & ".\Resolve-DockerImages.ps1" -Tag "test" -ImageUrls $jsonInput 2>&1 | Out-Null
    Write-Host "✅ JSON format parsing worked" -ForegroundColor Green
} catch {
    Write-Host "❌ JSON format failed: $($_.Exception.Message)" -ForegroundColor Red
}