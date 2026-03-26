param(
    [Parameter(Mandatory = $true)]
    [string]$PrereleaseVersion
)

# Set error action preference
$ErrorActionPreference = 'Stop'

try {
    Write-Host "🏷️  Converting prerelease version to release version..." -ForegroundColor Green
    Write-Host "📦 Input prerelease version: $PrereleaseVersion" -ForegroundColor Cyan

    # Remove common prerelease suffixes
    $releaseVersion = $PrereleaseVersion
    
    # Remove -rc, -alpha, -beta, -preview suffixes (case insensitive)
    $releaseVersion = $releaseVersion -replace '-rc(\d+)?$', '' -replace '-alpha(\d+)?$', '' -replace '-beta(\d+)?$', '' -replace '-preview(\d+)?$', ''
    
    # Validate that we have a valid version
    if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
        throw "Failed to generate release version from: $PrereleaseVersion"
    }
    
    # Ensure version starts with 'v' if the original did
    if ($PrereleaseVersion.StartsWith('v') -and -not $releaseVersion.StartsWith('v')) {
        $releaseVersion = "v$releaseVersion"
    }
    
    Write-Host "✅ Generated release version: $releaseVersion" -ForegroundColor Green
    
    # Set output
    Write-Output "version=$releaseVersion" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    
    Write-Host "📤 Output parameter set: version=$releaseVersion" -ForegroundColor Yellow
}
catch {
    Write-Host "❌ Error generating production version: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}