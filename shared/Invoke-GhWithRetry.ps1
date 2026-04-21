#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Wraps `gh` CLI invocations with exponential-backoff retry on transient errors.

.DESCRIPTION
    Dot-source this file from any PowerShell script under optivem/actions that
    calls the GitHub CLI, then replace `& gh ...` with `Invoke-GhWithRetry ...`.

    The wrapper buffers each attempt's stdout and stderr. On success, stdout is
    returned to the caller (and stderr forwarded to the console), preserving
    `$LASTEXITCODE = 0`. On transient failure (HTTP 5xx, network/DNS/TLS blips,
    connection resets), the call is retried up to 4 times with 5s → 15s → 45s
    backoff between attempts. On non-transient failure (4xx, auth, bad args,
    404 existence probes), the wrapper returns the attempt's output and
    preserves the original non-zero `$LASTEXITCODE` — callers that use exit
    code for flow control (e.g. `gh release view` to detect absence) keep
    working unchanged.

    Skip the wrapper for purely local probes that don't hit the GitHub API
    (`gh auth status`, `gh api rate_limit` — see the Phase-3 guidance in
    `.plans/20260420-154500-gh-retry-transient-errors.md`).

.EXAMPLE
    . "$PSScriptRoot/../shared/Invoke-GhWithRetry.ps1"
    $json = Invoke-GhWithRetry api "repos/owner/repo/releases" --paginate
    if ($LASTEXITCODE -eq 0) { ... }

.NOTES
    Set `GH_RETRY_DISABLE=1` to bypass the retry loop (useful when triaging
    whether retries are masking a real error).
#>

$GhRetryAttempts = 4
$GhRetryDelays = @(5, 15, 45)

$GhRetryRetryablePatterns = @(
    'HTTP 5\d\d'
    'timeout'
    'timed out'
    'i/o timeout'
    'connection reset'
    'connection refused'
    '\bEOF\b'
    'was closed'
    'TLS handshake'
    'tls:.*handshake'
    'temporary failure in name resolution'
    'no such host'
    'Bad Gateway'
    'Service Unavailable'
    'Gateway Timeout'
    'server error'
)

$GhRetryHardFailPatterns = @(
    'HTTP 4\d\d'
    'HTTP 403.*rate limit'
)

function Test-GhRetryHardFail {
    param([string]$Output)
    if ([string]::IsNullOrEmpty($Output)) { return $false }
    foreach ($pat in $GhRetryHardFailPatterns) {
        if ($Output -imatch $pat) { return $true }
    }
    return $false
}

function Test-GhRetryable {
    param([string]$Output)
    if ([string]::IsNullOrEmpty($Output)) { return $false }
    foreach ($pat in $GhRetryRetryablePatterns) {
        if ($Output -imatch $pat) { return $true }
    }
    return $false
}

function Invoke-GhWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GhArgs
    )

    if ($env:GH_RETRY_DISABLE -eq '1') {
        $out = & gh @GhArgs 2>&1
        return $out
    }

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        for ($attempt = 1; $attempt -le $GhRetryAttempts; $attempt++) {
            Set-Content -LiteralPath $tmpOut -Value '' -NoNewline -Encoding utf8 -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $tmpErr -Value '' -NoNewline -Encoding utf8 -ErrorAction SilentlyContinue

            $proc = Start-Process -FilePath 'gh' -ArgumentList $GhArgs `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $code = $proc.ExitCode

            $stdout = Get-Content -Raw -LiteralPath $tmpOut -ErrorAction SilentlyContinue
            if ($null -eq $stdout) { $stdout = '' }
            $stderr = Get-Content -Raw -LiteralPath $tmpErr -ErrorAction SilentlyContinue
            if ($null -eq $stderr) { $stderr = '' }

            if ($code -eq 0) {
                if ($stderr.Trim()) { [Console]::Error.Write($stderr) }
                $global:LASTEXITCODE = 0
                return $stdout.TrimEnd("`r", "`n")
            }

            $combined = "$stdout`n$stderr"

            if ((Test-GhRetryHardFail $combined) -or -not (Test-GhRetryable $combined)) {
                if ($stderr.Trim()) { [Console]::Error.Write($stderr) }
                if ($stdout) { Write-Output $stdout.TrimEnd("`r", "`n") }
                $global:LASTEXITCODE = $code
                return
            }

            $snippet = (($combined -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
            if ($attempt -lt $GhRetryAttempts) {
                $delayIdx = [Math]::Min($attempt - 1, $GhRetryDelays.Count - 1)
                $sleep = $GhRetryDelays[$delayIdx]
                Write-Host "[gh-retry] attempt $attempt failed (exit $code): $snippet -- retrying in ${sleep}s"
                Start-Sleep -Seconds $sleep
            }
            else {
                Write-Host "[gh-retry] exhausted $GhRetryAttempts attempts (exit $code): $snippet"
                if ($stderr.Trim()) { [Console]::Error.Write($stderr) }
                if ($stdout) { Write-Output $stdout.TrimEnd("`r", "`n") }
                $global:LASTEXITCODE = $code
                return
            }
        }
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath $tmpOut, $tmpErr
    }
}
