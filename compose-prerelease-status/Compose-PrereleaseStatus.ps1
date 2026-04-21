param(
    [Parameter(Mandatory = $true)]
    [string]$PrereleaseVersion,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$Status
)

$ErrorActionPreference = "Stop"

try {
    if ([string]::IsNullOrWhiteSpace($PrereleaseVersion)) {
        throw "PrereleaseVersion cannot be null or empty"
    }

    if ([string]::IsNullOrWhiteSpace($Environment)) {
        throw "Environment cannot be null or empty"
    }

    if ([string]::IsNullOrWhiteSpace($Status)) {
        throw "Status cannot be null or empty"
    }

    $PrereleaseVersion = $PrereleaseVersion.Trim()
    $Environment = $Environment.Trim()
    $Status = $Status.Trim()

    $statusTag = "$PrereleaseVersion-$Environment-$Status"

    Write-Host "=== Compose Prerelease Status Action ===" -ForegroundColor Magenta
    Write-Host "Prerelease version: $PrereleaseVersion" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Cyan
    Write-Host "Status: $Status" -ForegroundColor Cyan
    Write-Host "Composed tag: $statusTag" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Magenta

    if ($env:GITHUB_OUTPUT) {
        "tag=$statusTag" >> $env:GITHUB_OUTPUT
        Write-Host "✅ Output parameter set: tag=$statusTag" -ForegroundColor Yellow
    } else {
        Write-Warning "GITHUB_OUTPUT environment variable not found. This script should be run within GitHub Actions."
        Write-Host "Composed tag: $statusTag"
    }

    exit 0
}
catch {
    Write-Error "❌ Error composing prerelease status tag: $($_.Exception.Message)"
    exit 1
}
