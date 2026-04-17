param(
    [Parameter(Mandatory=$true)]
    [string]$RepoOwner,
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$WorkflowName,
    [Parameter(Mandatory=$false)]
    [bool]$ForceRun = $false
)

# Helper function to safely write to GitHub output
function Write-GitHubOutput {
    param([string]$Name, [string]$Value)

    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    } else {
        Write-Host "GitHub Output: $Name=$Value"
    }
}

Write-Host "🔍 Checking if acceptance stage should run..."
Write-Host "Repository: $RepoOwner/$RepoName"
Write-Host "Acceptance Workflow: $WorkflowName"
Write-Host "Force Run: $ForceRun"

# Resolve last-updated-at timestamp: prefer new input, fall back to deprecated alias.
$LastUpdatedAt = $env:LAST_UPDATED_AT
if ([string]::IsNullOrWhiteSpace($LastUpdatedAt)) {
    $LastUpdatedAt = $env:LATEST_IMAGE_TIMESTAMP
    if (-not [string]::IsNullOrWhiteSpace($LastUpdatedAt)) {
        Write-Host "⚠️  'latest-image-timestamp' input is deprecated — use 'last-updated-at' instead."
    }
}
if ([string]::IsNullOrWhiteSpace($LastUpdatedAt)) {
    Write-Host "❌ 'last-updated-at' input is required (or the deprecated 'latest-image-timestamp')"
    Write-GitHubOutput "error-message" "'last-updated-at' input is required"
    exit 1
}

# If force run is enabled, always run
if ($ForceRun) {
    Write-Host "🚀 Force run enabled - acceptance stage will run"
    Write-GitHubOutput "should-run" "true"
    Write-GitHubOutput "reason" "force-run"
    Write-GitHubOutput "latest-commit" "$env:GITHUB_SHA"
    exit 0
}

# Get timestamp from last successful acceptance workflow run
$lastWorkflowRun = gh run list --repo "$RepoOwner/$RepoName" --workflow "$WorkflowName" --status completed --json conclusion,createdAt | ConvertFrom-Json | Where-Object { $_.conclusion -eq 'success' } | Select-Object -First 1
if ($lastWorkflowRun) {
    $LastCheckedTimestamp = $lastWorkflowRun.createdAt
    Write-Host "Last successful acceptance run: $LastCheckedTimestamp"
} else {
    $LastCheckedTimestamp = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "No previous acceptance runs found, using fallback: $LastCheckedTimestamp"
}

Write-Host "Last updated at: $LastUpdatedAt"
Write-Host "Checking if subject is newer than: $LastCheckedTimestamp"

try {
    # Parse timestamps
    $subjectUpdated = [DateTime]::Parse($LastUpdatedAt)
    $lastChecked = [DateTime]::Parse($LastCheckedTimestamp)

    Write-Host "Subject updated: $($subjectUpdated.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    Write-Host "Last checked: $($lastChecked.ToString('yyyy-MM-ddTHH:mm:ssZ'))"

    $shouldRun = $false
    $reason = ""

    # Check if subject is newer than last acceptance run
    if ($subjectUpdated -gt $lastChecked) {
        Write-Host "✅ Subject is newer than last acceptance run"
        $shouldRun = $true
        $reason = "subject-updated"
    } else {
        Write-Host "ℹ️ Subject is not newer than last acceptance run"
    }

    # Check if acceptance test repo has newer commits
    if (-not $shouldRun) {
        Write-Host "🔍 Checking for new commits in repo: $RepoOwner/$RepoName"

        $sinceTimestamp = $lastChecked.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $commits = gh api "repos/$RepoOwner/$RepoName/commits?since=$sinceTimestamp&per_page=1" 2>&1

        if ($LASTEXITCODE -eq 0) {
            $commitList = $commits | ConvertFrom-Json
            if ($commitList.Count -gt 0) {
                $latestTestCommit = $commitList[0].sha.Substring(0, 7)
                Write-Host "✅ Acceptance test repo has newer commits (latest: $latestTestCommit) - ACCEPTANCE SHOULD RUN!"
                $shouldRun = $true
                $reason = "new-test-changes"
            } else {
                Write-Host "ℹ️ No new commits in acceptance test repo since last run"
            }
        } else {
            Write-Host "⚠️ Could not check acceptance test repo commits: $commits"
        }
    }

    if ($shouldRun) {
        Write-Host "✅ ACCEPTANCE SHOULD RUN! Reason: $reason"
        Write-GitHubOutput "should-run" "true"
        Write-GitHubOutput "reason" $reason
        Write-GitHubOutput "latest-commit" "$env:GITHUB_SHA"
        Write-GitHubOutput "last-updated-at" $LastUpdatedAt
        exit 0
    } else {
        Write-Host "❌ No acceptance stage run needed (no new image, no new test changes)"
        Write-GitHubOutput "should-run" "false"
        Write-GitHubOutput "reason" "no-changes"
        exit 0
    }

} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "⚠️ Could not parse timestamps: $errorMessage"
    Write-Host "❌ Processing error - failing to prevent silent issues"
    Write-GitHubOutput "error-message" $errorMessage

    exit 1
}
