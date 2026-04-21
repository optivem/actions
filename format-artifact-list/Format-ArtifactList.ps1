param(
    [Parameter(Mandatory = $false)]
    [string]$ArtifactsInput
)

$ErrorActionPreference = 'Stop'

Write-Host "🔧 Formatting artifact list..." -ForegroundColor Cyan

$formatted = ""

if (-not [string]::IsNullOrWhiteSpace($ArtifactsInput)) {
    Write-Host "📦 Input received: $ArtifactsInput" -ForegroundColor Yellow

    try {
        $items = $ArtifactsInput | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Host "❌ Invalid JSON array format. Expected [""value""] or [""v1"",""v2""]." -ForegroundColor Red
        throw "Invalid JSON array format: $($_.Exception.Message)"
    }

    if ($items -isnot [array] -and $items -isnot [string]) {
        throw "Invalid format: input must be a JSON array, got: $($items.GetType().Name)"
    }

    if ($items -is [string]) {
        $items = @($items)
    }

    $formatted = ($items | ForEach-Object { "• $_" }) -join "`n"

    Write-Host "📋 Formatted output:" -ForegroundColor Cyan
    Write-Host $formatted -ForegroundColor White
}
else {
    Write-Host "ℹ️ No artifacts provided; returning empty output" -ForegroundColor Yellow
}

if ($env:GITHUB_OUTPUT) {
    $outputBlock = @"
formatted<<EOF
$formatted
EOF
"@
    Add-Content -Path $env:GITHUB_OUTPUT -Value $outputBlock
    Write-Host "✅ Output written to GITHUB_OUTPUT" -ForegroundColor Green
}
else {
    Write-Host "⚠️ GITHUB_OUTPUT not set (running standalone). Formatted output:" -ForegroundColor Yellow
    Write-Host $formatted
}
