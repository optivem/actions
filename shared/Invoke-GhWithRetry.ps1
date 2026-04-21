#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Wraps `gh` CLI invocations with exponential-backoff retry on transient errors.

.DESCRIPTION
    Dot-source this file from any PowerShell script under optivem/actions that
    calls the GitHub CLI, then replace `& gh ...` with `Invoke-GhWithRetry ...`.

    On success, stdout is returned to the caller (stderr is forwarded to the
    console) and `$LASTEXITCODE` is set to 0. On transient failure (HTTP 5xx,
    network/DNS/TLS blips, connection resets), the call is retried up to 4
    times with 5s → 15s → 45s backoff. On non-transient failure (4xx, auth,
    bad args, 404 existence probes), the wrapper returns the attempt's output
    and preserves the original non-zero `$LASTEXITCODE` — callers that use
    exit code for flow control (e.g. `gh release view` to detect absence)
    keep working unchanged.

    Skip the wrapper for purely local probes that don't hit the GitHub API
    (`gh auth status`, `gh api rate_limit`).

.EXAMPLE
    . "$PSScriptRoot/../shared/Invoke-GhWithRetry.ps1"
    $json = Invoke-GhWithRetry api "repos/owner/repo/releases" --paginate
    if ($LASTEXITCODE -eq 0) { ... }

.NOTES
    Set `GH_RETRY_DISABLE=1` to bypass the retry loop (useful when triaging
    whether retries are masking a real error).
#>

function Invoke-GhWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GhArgs
    )

    $retryAttempts = 4
    $retryDelays = @(5, 15, 45)

    $retryablePatterns = @(
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

    $hardFailPatterns = @(
        'HTTP 4\d\d'
        'HTTP 403.*rate limit'
    )

    function Test-HardFail([string]$Output) {
        if ([string]::IsNullOrEmpty($Output)) { return $false }
        foreach ($pat in $hardFailPatterns) {
            if ($Output -imatch $pat) { return $true }
        }
        return $false
    }

    function Test-Retryable([string]$Output) {
        if ([string]::IsNullOrEmpty($Output)) { return $false }
        foreach ($pat in $retryablePatterns) {
            if ($Output -imatch $pat) { return $true }
        }
        return $false
    }

    if ($env:GH_RETRY_DISABLE -eq '1') {
        $out = & gh @GhArgs 2>&1
        return $out
    }

    for ($attempt = 1; $attempt -le $retryAttempts; $attempt++) {
        $stdoutList = [System.Collections.Generic.List[string]]::new()
        $stderrList = [System.Collections.Generic.List[string]]::new()

        # `& gh @args 2>&1` merges stderr into the output stream as ErrorRecord
        # objects. Split them back out so callers get clean stdout (for JSON
        # parsing, etc.) and retry detection can inspect stderr.
        & gh @GhArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $stderrList.Add([string]$_.Exception.Message)
            }
            else {
                $stdoutList.Add([string]$_)
            }
        }
        $code = $LASTEXITCODE

        $stdout = $stdoutList -join "`n"
        $stderr = $stderrList -join "`n"

        if ($code -eq 0) {
            if ($stderr.Trim()) { [Console]::Error.WriteLine($stderr) }
            $global:LASTEXITCODE = 0
            return $stdout
        }

        $combined = "$stdout`n$stderr"

        if ((Test-HardFail $combined) -or -not (Test-Retryable $combined)) {
            if ($stderr.Trim()) { [Console]::Error.WriteLine($stderr) }
            $global:LASTEXITCODE = $code
            return $stdout
        }

        $snippet = (($combined -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($attempt -lt $retryAttempts) {
            $delayIdx = [Math]::Min($attempt - 1, $retryDelays.Count - 1)
            $sleep = $retryDelays[$delayIdx]
            Write-Host "[gh-retry] attempt $attempt failed (exit $code): $snippet -- retrying in ${sleep}s"
            Start-Sleep -Seconds $sleep
        }
        else {
            Write-Host "[gh-retry] exhausted $retryAttempts attempts (exit $code): $snippet"
            if ($stderr.Trim()) { [Console]::Error.WriteLine($stderr) }
            $global:LASTEXITCODE = $code
            return $stdout
        }
    }
}
