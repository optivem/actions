param(
    [Parameter(Mandatory=$true)]
    [string]$CheckScript,
    
    [Parameter(Mandatory=$false)]
    [string]$ScriptArgs = "",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 30,
    
    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 10,
    
    [Parameter(Mandatory=$false)]
    [string]$ConditionName = "condition"
)

Write-Host "⏳ Polling until $ConditionName is met..." -ForegroundColor Blue
Write-Host "   Check script: $CheckScript" -ForegroundColor Gray
Write-Host "   Max retries: $MaxRetries" -ForegroundColor Gray
Write-Host "   Interval: ${IntervalSeconds}s" -ForegroundColor Gray
Write-Host ""

$attempt = 0
$conditionMet = $false

# Resolve script path: relative to workspace (GITHUB_WORKSPACE) or use as absolute
$workspace = $env:GITHUB_WORKSPACE
if ([string]::IsNullOrEmpty($workspace)) { $workspace = Get-Location }
$scriptPath = if ([System.IO.Path]::IsPathRooted($CheckScript)) {
    $CheckScript
} else {
    Join-Path $workspace $CheckScript
}

if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ Check script not found: $scriptPath" -ForegroundColor Red
    exit 1
}

while ($attempt -lt $MaxRetries) {
    $attempt++
    
    Write-Host "[$attempt/$MaxRetries] Checking $ConditionName..." -ForegroundColor Yellow
    
    try {
        # Execute the check script with arguments
        if ($ScriptArgs) {
            $argArray = $ScriptArgs -split ' '
            & $scriptPath @argArray
        } else {
            & $scriptPath
        }
        
        # Check exit code:
        # 0 = condition met (success)
        # 1 = permanent failure (stop polling)
        # 2 = still waiting (continue polling)
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "✅ Condition met: $ConditionName" -ForegroundColor Green
            $conditionMet = $true
            break
        } elseif ($LASTEXITCODE -eq 1) {
            Write-Host ""
            Write-Host "❌ Permanent failure detected, stopping polling" -ForegroundColor Red
            exit 1
        }
        # Exit code 2 means keep polling
        
    } catch {
        Write-Host "   ⚠️  Error running check script: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    if ($attempt -lt $MaxRetries -and -not $conditionMet) {
        Write-Host "   Waiting ${IntervalSeconds}s before next check..." -ForegroundColor Gray
        Start-Sleep -Seconds $IntervalSeconds
    }
}

if (-not $conditionMet) {
    Write-Host ""
    Write-Host "❌ Timed out waiting for '$ConditionName' after $MaxRetries attempts" -ForegroundColor Red
    exit 1
}
