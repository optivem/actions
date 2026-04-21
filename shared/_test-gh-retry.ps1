#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Local smoke-test harness for shared/Invoke-GhWithRetry.ps1.

.DESCRIPTION
    Shadows the `gh` executable on PATH with a fake that returns a scripted
    sequence of exit codes and stderr messages. Not wired into CI — run
    manually: pwsh shared/_test-gh-retry.ps1
#>

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fakeDir = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()))
$fakeState = Join-Path $fakeDir 'state'
$fakeBin = Join-Path $fakeDir 'gh.ps1'

# Fake `gh` — reads GH_FAKE_SEQ (semicolon-separated "code|stderr"), advances
# a counter in $env:FAKE_STATE, writes stdout/stderr, exits with coded status.
@'
param()
$state = $env:FAKE_STATE
$counter = 0
if (Test-Path -LiteralPath $state) {
    $counter = [int](Get-Content -Raw -LiteralPath $state)
}
$seq = $env:GH_FAKE_SEQ -split ';'
$idx = [Math]::Min($counter, $seq.Length - 1)
$entry = $seq[$idx]
$parts = $entry -split '\|', 2
$code = [int]$parts[0]
$stderr = if ($parts.Count -gt 1) { $parts[1] } else { '' }
if ($stderr) { [Console]::Error.WriteLine($stderr) }
Write-Output "fake-stdout-$counter"
Set-Content -LiteralPath $state -Value ($counter + 1) -NoNewline
exit $code
'@ | Set-Content -LiteralPath $fakeBin -Encoding utf8

# Wrap the ps1 in a platform-appropriate `gh` shim on PATH.
if ($IsWindows) {
    $shim = Join-Path $fakeDir 'gh.cmd'
    # Use %* to forward all args.
    Set-Content -LiteralPath $shim -Value "@echo off`npwsh -NoProfile -File `"$fakeBin`" %*" -Encoding ascii
} else {
    $shim = Join-Path $fakeDir 'gh'
    Set-Content -LiteralPath $shim -Value "#!/usr/bin/env bash`npwsh -NoProfile -File `"$fakeBin`" `"`$@`"" -Encoding ascii
    chmod +x $shim 2>$null
}

$env:FAKE_STATE = $fakeState
$env:PATH = "$fakeDir" + [System.IO.Path]::PathSeparator + $env:PATH

try {
    . "$here/Invoke-GhWithRetry.ps1"
    $script:GhRetryDelays = @(0, 0, 0)

    $pass = 0
    $fail = 0
    function Assert-Eq {
        param([string]$Label, $Expected, $Actual)
        if ($Expected -eq $Actual) {
            Write-Host "  PASS $Label"
            $script:pass++
        } else {
            Write-Host "  FAIL $Label"
            Write-Host "    expected: $Expected"
            Write-Host "    actual:   $Actual"
            $script:fail++
        }
    }

    Write-Host "Test 1: transient 502 → 502 → 200 succeeds after 3 attempts"
    Set-Content -LiteralPath $fakeState -Value '0' -NoNewline
    $env:GH_FAKE_SEQ = '1|HTTP 502: Bad Gateway;1|HTTP 502: Bad Gateway;0|'
    $out = Invoke-GhWithRetry api foo
    Assert-Eq 'exit code' 0 $global:LASTEXITCODE
    Assert-Eq 'stdout final attempt' 'fake-stdout-2' $out
    Assert-Eq 'attempt count' '3' ((Get-Content -Raw -LiteralPath $fakeState).Trim())

    Write-Host "Test 2: HTTP 404 non-retryable → 1 attempt, passes through"
    Set-Content -LiteralPath $fakeState -Value '0' -NoNewline
    $env:GH_FAKE_SEQ = '1|HTTP 404: Not Found'
    $out = Invoke-GhWithRetry api foo
    Assert-Eq 'exit code' 1 $global:LASTEXITCODE
    Assert-Eq 'attempt count' '1' ((Get-Content -Raw -LiteralPath $fakeState).Trim())

    Write-Host "Test 3: HTTP 403 rate-limit hard-fail → 1 attempt, passes through"
    Set-Content -LiteralPath $fakeState -Value '0' -NoNewline
    $env:GH_FAKE_SEQ = '1|HTTP 403: API rate limit exceeded'
    $out = Invoke-GhWithRetry api foo
    Assert-Eq 'exit code' 1 $global:LASTEXITCODE
    Assert-Eq 'attempt count' '1' ((Get-Content -Raw -LiteralPath $fakeState).Trim())

    Write-Host "Test 4: 4 straight 502s → exhausts retries, returns non-zero"
    Set-Content -LiteralPath $fakeState -Value '0' -NoNewline
    $env:GH_FAKE_SEQ = '1|HTTP 502;1|HTTP 502;1|HTTP 502;1|HTTP 502'
    $out = Invoke-GhWithRetry api foo
    Assert-Eq 'exit code' 1 $global:LASTEXITCODE
    Assert-Eq 'attempt count' '4' ((Get-Content -Raw -LiteralPath $fakeState).Trim())

    Write-Host "Test 5: GH_RETRY_DISABLE=1 bypasses retry"
    Set-Content -LiteralPath $fakeState -Value '0' -NoNewline
    $env:GH_FAKE_SEQ = '1|HTTP 502;0|'
    $env:GH_RETRY_DISABLE = '1'
    try { Invoke-GhWithRetry api foo | Out-Null } catch { }
    Assert-Eq 'attempt count' '1' ((Get-Content -Raw -LiteralPath $fakeState).Trim())
    Remove-Item Env:\GH_RETRY_DISABLE

    Write-Host ""
    Write-Host "Results: $pass passed, $fail failed"
    if ($fail -gt 0) { exit 1 }
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $fakeDir
}
