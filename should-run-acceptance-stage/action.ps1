param(
    [Parameter(Mandatory=$true)]
    [string]$RepoOwner,
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$false)]
    [string]$WorkflowName = ''
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

# SHA-identity mode: skip if the acceptance HEAD already carries a success
# status with the given context and description matching the subject SHA.
# Opt-in via the subject-sha input — callers using timestamp mode are unaffected.
$SubjectSha = $env:SUBJECT_SHA
$StatusContext = $env:STATUS_CONTEXT

if (-not [string]::IsNullOrWhiteSpace($SubjectSha)) {
    if ([string]::IsNullOrWhiteSpace($StatusContext)) {
        Write-Host "❌ 'status-context' is required when 'subject-sha' is set"
        Write-GitHubOutput "error-message" "'status-context' is required when 'subject-sha' is set"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
        Write-Host "❌ GITHUB_SHA is not set"
        Write-GitHubOutput "error-message" "GITHUB_SHA is not set"
        exit 1
    }

    Write-Host "Mode: SHA-identity check"
    Write-Host "Subject SHA: $SubjectSha"
    Write-Host "Status context: $StatusContext"
    Write-Host "Acceptance HEAD: $env:GITHUB_SHA"

    $statusesJson = gh api "repos/$RepoOwner/$RepoName/commits/$env:GITHUB_SHA/statuses" --paginate 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Fail open: run the stage rather than silently skipping on transient API errors.
        Write-Host "⚠️ Could not fetch commit statuses: $statusesJson"
        Write-Host "Defaulting to should-run=true"
        Write-GitHubOutput "should-run" "true"
        Write-GitHubOutput "reason" "status-check-failed"
        exit 0
    }

    $statuses = $statusesJson | ConvertFrom-Json
    $match = $statuses | Where-Object {
        $_.context -eq $StatusContext -and
        $_.description -eq $SubjectSha -and
        $_.state -eq 'success'
    } | Select-Object -First 1

    if ($match) {
        Write-Host "ℹ️ Subject already verified on this HEAD (status created $($match.created_at))"
        Write-Host "❌ ACCEPTANCE SKIPPED — already verified"
        Write-GitHubOutput "should-run" "false"
        Write-GitHubOutput "reason" "already-verified"
        exit 0
    }

    Write-Host "✅ No matching verified status on HEAD — ACCEPTANCE SHOULD RUN"
    Write-GitHubOutput "should-run" "true"
    Write-GitHubOutput "reason" "not-verified"
    Write-GitHubOutput "latest-commit" $env:GITHUB_SHA
    exit 0
}

Write-Host "Acceptance Workflow: $WorkflowName"

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
if ([string]::IsNullOrWhiteSpace($WorkflowName)) {
    Write-Host "❌ 'workflow-name' input is required in timestamp mode"
    Write-GitHubOutput "error-message" "'workflow-name' input is required in timestamp mode"
    exit 1
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
