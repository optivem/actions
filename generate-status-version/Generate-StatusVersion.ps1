param(
    [Parameter(Mandatory = $true)]
    [string]$BaseVersion,
    
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$Status
)

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

try {
    # Validate inputs
    if ([string]::IsNullOrWhiteSpace($BaseVersion)) {
        throw "BaseVersion cannot be null or empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($Environment)) {
        throw "Environment cannot be null or empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($Status)) {
        throw "Status cannot be null or empty"
    }
    
    # Trim whitespace from inputs
    $BaseVersion = $BaseVersion.Trim()
    $Environment = $Environment.Trim()
    $Status = $Status.Trim()
    
    # Generate the version string
    $builtVersion = "$BaseVersion-$Environment-$Status"
    
    # Output information
    Write-Host "=== Generate Status Version Action ===" -ForegroundColor Magenta
    Write-Host "Base version: $BaseVersion" -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Cyan
    Write-Host "Status: $Status" -ForegroundColor Cyan
    Write-Host "Built version: $builtVersion" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Magenta
    
    # Set the output for GitHub Actions
    if ($env:GITHUB_OUTPUT) {
        "version=$builtVersion" >> $env:GITHUB_OUTPUT
        Write-Host "✅ Output parameter set: version=$builtVersion" -ForegroundColor Yellow
    } else {
        Write-Warning "GITHUB_OUTPUT environment variable not found. This script should be run within GitHub Actions."
        Write-Host "Generated version: $builtVersion"
    }
    
    # Exit successfully
    exit 0
}
catch {
    Write-Error "❌ Error generating status version: $($_.Exception.Message)"
    exit 1
}