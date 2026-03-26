param(
    [Parameter(Mandatory = $false)]
    [string]$ArtifactsInput
)

Write-Host "🔧 Processing artifact IDs..." -ForegroundColor Cyan

$formattedArtifacts = ""

if (-not [string]::IsNullOrWhiteSpace($ArtifactsInput)) {
    Write-Host "📦 Input received: $ArtifactsInput" -ForegroundColor Yellow
    
    # Only accept JSON array format
    try {
        $jsonArray = $ArtifactsInput | ConvertFrom-Json -ErrorAction Stop
        if ($jsonArray -is [array] -or ($jsonArray -is [string] -and $jsonArray.Count -eq 1)) {
            Write-Host "✅ Valid JSON array format detected" -ForegroundColor Green
            # Ensure we always work with an array, even if single item
            if ($jsonArray -is [string]) {
                $jsonArray = @($jsonArray)
            }
            # Process JSON array - convert to formatted list
            $formattedArtifacts = ($jsonArray | ForEach-Object { "• $_" }) -join "`n"
        } else {
            Write-Host "❌ Error: Input must be a JSON array. Expected format: [""value""] or [""value1"", ""value2""]" -ForegroundColor Red
            throw "Invalid format: Expected JSON array"
        }
    } catch {
        Write-Host "❌ Error: Invalid JSON array format. Expected format: [""artifact1"", ""artifact2""]" -ForegroundColor Red
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  Single artifact: [""docker.io/myapp:v1.2.3""]" -ForegroundColor White
        Write-Host "  Multiple artifacts: [""docker.io/myapp:v1.2.3"", ""https://github.com/owner/repo/releases/tag/v1.2.3""]" -ForegroundColor White
        throw "Invalid JSON array format: $($_.Exception.Message)"
    }
    
    Write-Host "📋 Formatted artifacts:" -ForegroundColor Cyan
    Write-Host $formattedArtifacts -ForegroundColor White
} else {
    Write-Host "ℹ️ No artifacts provided" -ForegroundColor Yellow
}

# Output for GitHub Actions
if ($env:GITHUB_OUTPUT) {
    $outputContent = @"
artifacts-formatted<<EOF
$formattedArtifacts
EOF
"@
    Add-Content -Path $env:GITHUB_OUTPUT -Value $outputContent
    Write-Host "✅ Output written to GITHUB_OUTPUT" -ForegroundColor Green
} else {
    Write-Host "⚠️ GITHUB_OUTPUT not set, running in test mode" -ForegroundColor Yellow
    Write-Host "Output would be:" -ForegroundColor Cyan
    Write-Host $formattedArtifacts -ForegroundColor White
}

Write-Host "✅ Artifact processing completed" -ForegroundColor Green