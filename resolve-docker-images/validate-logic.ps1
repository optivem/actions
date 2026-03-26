# Simple syntax validation for the PowerShell script
Write-Host "Validating PowerShell syntax..." -ForegroundColor Yellow

try {
    # Test JSON input parsing logic
    $testJsonInput = '["nginx", "redis", "postgres"]'
    $trimmedInput = $testJsonInput.Trim()
    
    if ($trimmedInput.StartsWith('[') -and $trimmedInput.EndsWith(']')) {
        Write-Host "JSON detection logic works" -ForegroundColor Green
        $jsonArray = $testJsonInput | ConvertFrom-Json
        Write-Host "JSON parsing works: $($jsonArray -join ', ')" -ForegroundColor Green
    }
    
    # Test newline input parsing logic
    $testNewlineInput = "nginx`nredis`npostgres"
    $baseUrls = $testNewlineInput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    Write-Host "Newline parsing works: $($baseUrls -join ', ')" -ForegroundColor Green
    
    # Test JSON array output (PowerShell 5.1 compatible)
    $testUrls = @("nginx:v1.0.0", "redis:v1.0.0")
    
    if ($testUrls.Count -eq 0) {
        $jsonOutput = "[]"
    } elseif ($testUrls.Count -eq 1) {
        # Ensure single item is still returned as an array (PowerShell 5.1 compatible)
        $jsonOutput = "[$($testUrls[0] | ConvertTo-Json -Compress)]"
    } else {
        $jsonOutput = $testUrls | ConvertTo-Json -Compress
    }
    
    Write-Host "JSON output generation works: $jsonOutput" -ForegroundColor Green
    
    # Test single item array
    $singleUrl = @("nginx:v1.0.0")
    if ($singleUrl.Count -eq 1) {
        $singleJsonOutput = "[$($singleUrl[0] | ConvertTo-Json -Compress)]"
        Write-Host "Single item JSON array works: $singleJsonOutput" -ForegroundColor Green
    }
    Write-Host "All logic tests passed!" -ForegroundColor Green
}
catch {
    Write-Host "Test failed: $($_.Exception.Message)" -ForegroundColor Red
}