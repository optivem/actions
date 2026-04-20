param(
    [Parameter(Mandatory = $true)]
    [string]$FilesJson,

    [Parameter(Mandatory = $true)]
    [string]$Branch,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3
)

$ErrorActionPreference = 'Stop'

Write-Host "Committing files to $Repository@$Branch via Contents API..."

try {
    $files = $FilesJson | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse files input as JSON: $_"
    exit 1
}

if ($null -eq $files -or $files.Count -eq 0) {
    Write-Host "No files to commit."
    "commits=[]" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "committed=false" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    exit 0
}

$commits = @()

foreach ($file in $files) {
    $path = $file.path
    $content = $file.content
    $message = $file.message

    if (-not $path -or $null -eq $content -or -not $message) {
        Write-Error "Invalid entry — each file must define path, content, and message. Got: $($file | ConvertTo-Json -Compress)"
        exit 1
    }

    $contentB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

    $attempt = 0
    $committed = $false

    while (-not $committed) {
        $attempt++

        $currentSha = $null
        $getResult = & gh api "repos/$Repository/contents/$path`?ref=$Branch" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $currentSha = ($getResult | ConvertFrom-Json).sha
        }
        elseif ($getResult -match '404|Not Found') {
            $currentSha = $null
        }
        else {
            Write-Error "Failed to read $path from $Repository@${Branch}: $getResult"
            exit 1
        }

        $body = [ordered]@{
            message = $message
            content = $contentB64
            branch  = $Branch
        }
        if ($currentSha) { $body.sha = $currentSha }

        $tmpFile = New-TemporaryFile
        try {
            ($body | ConvertTo-Json -Compress) | Out-File -FilePath $tmpFile -Encoding utf8 -NoNewline
            $putResult = & gh api --method PUT "repos/$Repository/contents/$path" --input $tmpFile 2>&1
            $putExit = $LASTEXITCODE
        }
        finally {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }

        if ($putExit -eq 0) {
            $parsed = $putResult | ConvertFrom-Json
            $commits += [ordered]@{
                path          = $path
                'commit-sha'  = $parsed.commit.sha
                'content-sha' = $parsed.content.sha
                'html-url'    = $parsed.commit.html_url
            }
            $shortSha = $parsed.commit.sha.Substring(0, 7)
            Write-Host "Committed $path ($shortSha)"
            $committed = $true
        }
        elseif ($putResult -match 'does not match|409|422' -and $attempt -lt $MaxRetries) {
            $delay = [math]::Pow(2, $attempt)
            Write-Host "::warning::SHA conflict on $path (attempt $attempt/$MaxRetries), retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
        else {
            Write-Error "Failed to commit ${path} after $attempt attempt(s): $putResult"
            exit 1
        }
    }
}

# Force array encoding even for single-element results
$commitsJson = ConvertTo-Json -InputObject @($commits) -Compress -Depth 5

"commits=$commitsJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
"committed=true" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8

Write-Host "Done. Committed $($commits.Count) file(s)."
