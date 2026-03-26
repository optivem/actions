# Test JSON output format specifically
Write-Host "Testing JSON output format..." -ForegroundColor Yellow

# Create a modified version of the script function to test JSON output
function Test-JsonOutput {
    param(
        [string[]]$FullUrls
    )
    
    # This mimics the logic in our script
    if ($FullUrls.Count -eq 0) {
        $jsonArray = "[]"
    } else {
        # Use -AsArray to ensure single items are returned as arrays too
        # Force array conversion for PowerShell JSON quirks
        $jsonArray = @($FullUrls) | ConvertTo-Json -Compress -AsArray
    }
    
    return $jsonArray
}

# Test cases
Write-Host "`n=== JSON Output Format Tests ===" -ForegroundColor Cyan

# Test 1: Empty array
$empty = @()
$emptyResult = Test-JsonOutput -FullUrls $empty
Write-Host "Empty array: $emptyResult" -ForegroundColor Green

# Test 2: Single item
$single = @("nginx:v1.0.0")
$singleResult = Test-JsonOutput -FullUrls $single
Write-Host "Single item: $singleResult" -ForegroundColor Green

# Test 3: Multiple items
$multiple = @("nginx:v1.0.0", "redis:v1.0.0", "postgres:v1.0.0")
$multipleResult = Test-JsonOutput -FullUrls $multiple
Write-Host "Multiple items: $multipleResult" -ForegroundColor Green

# Verify they are all valid JSON arrays
Write-Host "`n=== JSON Validation ===" -ForegroundColor Cyan

function Test-ValidJsonArray {
    param([string]$JsonString)
    
    try {
        $parsed = $JsonString | ConvertFrom-Json
        # Handle PowerShell's quirk where single-item arrays become strings
        if ($parsed -is [array] -or $JsonString -eq "[]" -or ($JsonString.StartsWith("[") -and $JsonString.EndsWith("]"))) {
            Write-Host "✅ Valid JSON array: $JsonString" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ Not an array: $JsonString" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Invalid JSON: $JsonString" -ForegroundColor Red
        return $false
    }
}

Test-ValidJsonArray -JsonString $emptyResult
Test-ValidJsonArray -JsonString $singleResult  
Test-ValidJsonArray -JsonString $multipleResult