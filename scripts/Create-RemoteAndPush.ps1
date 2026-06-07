param(
    [string]$Owner = "hxld",
    [string]$Repo = "ai-workflow-control-kit",
    [string]$Description = "Personal AI workflow control kit for skills, hooks, rules, and unattended replay automation.",
    [switch]$Public,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-GitHubTokenCandidates {
    $names = @("GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN")
    $candidates = @()
    foreach ($name in $names) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, "User") }
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, "Machine") }
        if ($value) {
            $candidates += @{ Name = $name; Value = $value }
        }
    }
    return $candidates
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [object]$Body = $null,
        [Parameter(Mandatory = $true)][string]$Token
    )

    $headers = @{
        Authorization = "Bearer $Token"
        "User-Agent" = "ai-workflow-control-kit"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -TimeoutSec 30
    }

    $json = $Body | ConvertTo-Json -Depth 8
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $json -ContentType "application/json" -TimeoutSec 30
}

function Ensure-CleanWorktree {
    $status = git status --short
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed"
    }
    if ($status) {
        throw "Worktree is not clean. Commit or stash local changes before pushing."
    }
}

$repoFullName = "$Owner/$Repo"
$repoUrl = "https://github.com/$repoFullName.git"
$isPrivate = -not $Public

Write-Output "target_repo=$repoFullName"
Write-Output "visibility=$(if ($isPrivate) { 'private' } else { 'public' })"

Ensure-CleanWorktree

$tokenCandidates = Get-GitHubTokenCandidates
if (-not $tokenCandidates -or $tokenCandidates.Count -eq 0) {
    throw "No GitHub token found. Set GH_TOKEN, GITHUB_TOKEN, or GITHUB_PERSONAL_ACCESS_TOKEN."
}

$tokenInfo = $null
foreach ($candidate in $tokenCandidates) {
    try {
        $user = Invoke-GitHubApi -Method "Get" -Uri "https://api.github.com/user" -Token $candidate.Value
        $tokenInfo = $candidate
        Write-Output "github_auth=ok user=$($user.login) token_env=$($candidate.Name)"
        break
    } catch {
        Write-Output "github_auth=invalid token_env=$($candidate.Name)"
    }
}

if (-not $tokenInfo) {
    throw "No valid GitHub token found. Refresh GH_TOKEN, GITHUB_TOKEN, or GITHUB_PERSONAL_ACCESS_TOKEN."
}

$existing = $null
try {
    $existing = Invoke-GitHubApi -Method "Get" -Uri "https://api.github.com/repos/$repoFullName" -Token $tokenInfo.Value
    Write-Output "remote_repo=exists"
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    if ($statusCode -ne 404) {
        throw
    }
}

if (-not $existing) {
    Write-Output "remote_repo=missing"
    if ($DryRun) {
        Write-Output "dry_run=create_repo_skipped"
    } else {
        $body = @{
            name = $Repo
            description = $Description
            private = $isPrivate
            auto_init = $false
        }
        $created = Invoke-GitHubApi -Method "Post" -Uri "https://api.github.com/user/repos" -Body $body -Token $tokenInfo.Value
        Write-Output "remote_repo=created html_url=$($created.html_url)"
    }
}

$currentOrigin = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    if ($DryRun) {
        Write-Output "dry_run=remote_add origin $repoUrl"
    } else {
        git remote add origin $repoUrl
    }
} elseif ($currentOrigin -ne $repoUrl) {
    if ($DryRun) {
        Write-Output "dry_run=remote_set-url origin $repoUrl"
    } else {
        git remote set-url origin $repoUrl
    }
}

if ($DryRun) {
    Write-Output "dry_run=push_skipped"
    exit 0
}

git push -u origin main
if ($LASTEXITCODE -ne 0) {
    throw "git push failed. Check GitHub credentials or repository permission."
}

Write-Output "push=ok $repoUrl"
