param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [int]$SearchLimit = 20,

    [Parameter(Mandatory = $true)]
    [string]$GithubToken
)

$ErrorActionPreference = 'Stop'

try {
    Write-Host "🔍 Searching last $SearchLimit releases for run $RunId in $Repository..."

    $env:GH_TOKEN = $GithubToken

    $owner, $name = $Repository -split '/', 2

    $query = @'
query($owner: String!, $name: String!, $n: Int!) {
  repository(owner: $owner, name: $name) {
    releases(first: $n, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes { tagName description isPrerelease }
    }
  }
}
'@

    $response = gh api graphql `
        -f query=$query `
        -f owner=$owner `
        -f name=$name `
        -F n=$SearchLimit | ConvertFrom-Json

    if (-not $response.data.repository.releases.nodes) {
        Write-Host "::error::No releases returned from GitHub API"
        exit 1
    }

    $needle = "/runs/$RunId"
    $match = $response.data.repository.releases.nodes |
        Where-Object { $_.isPrerelease -and $_.description -and $_.description.Contains($needle) } |
        Select-Object -First 1

    if (-not $match) {
        Write-Host "::error::No prerelease found whose body references run $RunId (scanned $SearchLimit releases)"
        exit 1
    }

    $tag = $match.tagName
    Write-Host "✅ Found release $tag for run $RunId" -ForegroundColor Green

    "tag=$tag" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    Write-Host "📋 GitHub Actions Output: tag=$tag" -ForegroundColor Cyan

    exit 0
}
catch {
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
