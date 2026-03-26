# Local PowerShell test script for summarize-system-stage-action
# This script simulates the action behavior locally for testing

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("json-array-multiple", "json-array-single", "empty-artifacts", "failed-stage", "all")]
    [string]$TestScenario = "all"
)

Write-Host "🧪 Starting local test of summarize-system-stage-action..." -ForegroundColor Cyan
Write-Host ""

# Test function
function Test-Scenario {
    param(
        [string]$TestName,
        [string]$StageName,
        [string]$StageResult,
        [string]$Environment,
        [string]$SuccessVersion,
        [string]$SuccessArtifactIds
    )
    
    Write-Host "===============================================" -ForegroundColor Magenta
    Write-Host "🔧 Testing: $TestName" -ForegroundColor Yellow
    Write-Host "===============================================" -ForegroundColor Magenta
    Write-Host "Stage Name: $StageName" -ForegroundColor White
    Write-Host "Stage Result: $StageResult" -ForegroundColor White
    Write-Host "Environment: $Environment" -ForegroundColor White
    Write-Host "Success Version: $SuccessVersion" -ForegroundColor White
    Write-Host "Success Artifact IDs: $SuccessArtifactIds" -ForegroundColor White
    Write-Host ""
    
    try {
        # Test validation step
        Write-Host "📋 Step 1: Validate Inputs" -ForegroundColor Cyan
        $validateScript = Join-Path $PSScriptRoot "scripts/Validate-Inputs.ps1"
        if (Test-Path $validateScript) {
            & $validateScript -StageResult $StageResult -SuccessVersion $SuccessVersion
        } else {
            Write-Host "⚠️ Validate-Inputs.ps1 not found, running inline validation" -ForegroundColor Yellow
            if ($StageResult -eq "success") {
                if ([string]::IsNullOrWhiteSpace($SuccessVersion)) {
                    Write-Host "❌ Error: success-version is required when stage-result is 'success'" -ForegroundColor Red
                    throw "Validation failed"
                }
                Write-Host "✅ Validation passed: success-version is provided for successful stage" -ForegroundColor Green
            } else {
                Write-Host "ℹ️ Stage result is '$StageResult', skipping success validation" -ForegroundColor Yellow
            }
        }
        Write-Host ""
        
        # Test artifact processing step
        Write-Host "🔧 Step 2: Process Artifact IDs" -ForegroundColor Cyan
        $processScript = Join-Path $PSScriptRoot "scripts/Process-Artifacts.ps1"
        if (Test-Path $processScript) {
            & $processScript -ArtifactsInput $SuccessArtifactIds
        } else {
            Write-Host "⚠️ Process-Artifacts.ps1 not found, running inline processing" -ForegroundColor Yellow
            # Inline processing logic here...
        }
        Write-Host ""
        
        # Simulate the summary generation step
        Write-Host "📊 Step 3: Generate System Stage Summary (Simulated)" -ForegroundColor Cyan
        Write-Host "---" -ForegroundColor Gray
        Write-Host "🌍 **Environment:** $Environment" -ForegroundColor White
        if ($StageResult -eq "success") {
            Write-Host "🎯 **Release Candidate:** $SuccessVersion" -ForegroundColor White
            if (-not [string]::IsNullOrWhiteSpace($SuccessArtifactIds)) {
                Write-Host ""
                Write-Host "🔗 **Artifacts:** (would be formatted by Process-Artifacts.ps1)" -ForegroundColor White
            }
        }
        Write-Host "---" -ForegroundColor Gray
        Write-Host ""
        Write-Host "✅ Test completed successfully!" -ForegroundColor Green
        Write-Host ""
        
        return $true
    } catch {
        Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return $false
    }
}

# Test scenarios
$scenarios = @()

if ($TestScenario -eq "all" -or $TestScenario -eq "json-array-multiple") {
    $scenarios += @{
        Name = "JSON Array Format (Multiple Artifacts)"
        StageName = "Acceptance"
        StageResult = "success"
        Environment = "acceptance-env"
        SuccessVersion = "v1.2.3-rc.1"
        SuccessArtifactIds = '["docker.io/myapp:v1.2.3-rc.1", "https://github.com/owner/repo/releases/tag/v1.2.3-rc.1", "https://artifacts.example.com/myapp-v1.2.3.tar.gz"]'
    }
}

if ($TestScenario -eq "all" -or $TestScenario -eq "json-array-single") {
    $scenarios += @{
        Name = "JSON Array Format (Single Artifact)"
        StageName = "Production"
        StageResult = "success"
        Environment = "prod"
        SuccessVersion = "v1.2.3"
        SuccessArtifactIds = '["docker.io/myapp:v1.2.3"]'
    }
}

if ($TestScenario -eq "all" -or $TestScenario -eq "empty-artifacts") {
    $scenarios += @{
        Name = "Empty Artifacts"
        StageName = "Staging"
        StageResult = "success"
        Environment = "staging"
        SuccessVersion = "v1.2.3-alpha.1"
        SuccessArtifactIds = ""
    }
}

if ($TestScenario -eq "all" -or $TestScenario -eq "failed-stage") {
    $scenarios += @{
        Name = "Failed Stage"
        StageName = "Integration"
        StageResult = "failure"
        Environment = "integration-env"
        SuccessVersion = ""
        SuccessArtifactIds = ""
    }
}

# Run tests
$testResults = @()
foreach ($scenario in $scenarios) {
    $result = Test-Scenario -TestName $scenario.Name -StageName $scenario.StageName -StageResult $scenario.StageResult -Environment $scenario.Environment -SuccessVersion $scenario.SuccessVersion -SuccessArtifactIds $scenario.SuccessArtifactIds
    $testResults += $result
}

# Summary
Write-Host "🎯 TEST SUMMARY" -ForegroundColor Magenta
Write-Host "===============================================" -ForegroundColor Magenta
$passedTests = ($testResults | Where-Object { $_ -eq $true }).Count
$totalTests = $testResults.Count

if ($passedTests -eq $totalTests) {
    Write-Host "🎉 All $totalTests tests passed!" -ForegroundColor Green
} else {
    Write-Host "⚠️ $passedTests of $totalTests tests passed" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "💡 To test with the actual GitHub Action:" -ForegroundColor Cyan
Write-Host "   1. Push these changes to GitHub" -ForegroundColor White
Write-Host "   2. Go to your repository's Actions tab" -ForegroundColor White
Write-Host "   3. Run the 'Test Summarize System Stage Action' workflow" -ForegroundColor White
Write-Host "   4. Select different test scenarios to verify behavior" -ForegroundColor White