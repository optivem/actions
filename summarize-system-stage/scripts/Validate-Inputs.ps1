param(
    [Parameter(Mandatory = $true)]
    [string]$StageResult,
    
    [Parameter(Mandatory = $false)]
    [string]$SuccessVersion
)

Write-Host "🔍 Validating inputs..." -ForegroundColor Cyan

if ($StageResult -eq "success") {
    if ([string]::IsNullOrWhiteSpace($SuccessVersion)) {
        Write-Host "❌ Error: success-version is required when stage-result is 'success'" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Validation passed: success-version is provided for successful stage" -ForegroundColor Green
} else {
    Write-Host "ℹ️ Stage result is '$StageResult', skipping success validation" -ForegroundColor Yellow
}

Write-Host "✅ Input validation completed" -ForegroundColor Green