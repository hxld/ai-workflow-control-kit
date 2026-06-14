# Invoke-TodoPlaceholderCheck.ps1
# v432: RED Phase TODO Ban (Experiment 3 from NEXT_EXPERIMENT_PLAN.md)

<#
.SYNOPSIS
Checks for TODO/FIXME/XXX placeholders in production code.

.DESCRIPTION
Scans claim-core, claim-api, claim-web source directories for TODO placeholders.
Throws if any TODO placeholders found, forcing executable behavior instead of placeholders.

.PARAMETER Worktree
Path to the worktree directory

.PARAMETER ValidateOnly
If set, only validates the script without running checks
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Worktree,

    [Parameter(Mandatory = $false)]
    [string[]]$Paths,

    [Parameter(Mandatory = $false)]
    [string]$PathList,

    [Parameter(Mandatory = $false)]
    [string]$ResultPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'TODO placeholder check for production code',
            'Bans TODO/FIXME/XXX in claim-core, claim-api, claim-web',
            'Allows TODO in test files'
        )
    } | Format-List
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Worktree) -or -not (Test-Path -LiteralPath $Worktree)) {
    Write-Host "WARNING: Worktree not found or not specified: $Worktree" -ForegroundColor Yellow
    exit 0  # Don't block if worktree doesn't exist
}

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path $Worktree 'TODO_CHECK_RESULT.json'
}

$forbiddenPaths = @(
    "claim-core/src/main/java",
    "claim-api/src/main/java",
    "claim-web/src/main/java"
)

$explicitPaths = @()
if ($Paths -and $Paths.Count -gt 0) {
    $explicitPaths += @($Paths)
}
if (-not [string]::IsNullOrWhiteSpace($PathList)) {
    $explicitPaths += @($PathList -split [regex]::Escape([System.IO.Path]::PathSeparator))
}

if ($explicitPaths.Count -gt 0) {
    $forbiddenPaths = @($explicitPaths | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        ([string]$_) -match '(?i)src[\\/]+main[\\/]+java' -and
        ([string]$_) -notmatch '(?i)src[\\/]+test[\\/]+java'
    })
}

$result = [ordered]@{
    gate = 'todo_placeholder_check'
    worktree = $Worktree
    can_proceed = $true
    validation_status = 'PASS'
    findings = @()
    validated_at = (Get-Date).ToString('s')
}

$results = @()

foreach ($path in $forbiddenPaths) {
    $targetPath = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $Worktree $path }
    $targetPath = $targetPath -replace '\\', '/'
    if (Test-Path -LiteralPath $targetPath) {
        $matches = rg "\b(TODO|FIXME|XXX)\b" $targetPath -n 2>$null
        if ($matches) {
            $results += $matches
        }
    }
}

if ($results.Count -gt 0) {
    $result.can_proceed = $false
    $result.validation_status = 'FAIL'
    $result.findings = @($results | Select-Object -First 20)

    $errorMsg = "TODO placeholders detected in production code:`n"
    $errorMsg += ($results | Select-Object -First 5) -join "`n"
    if ($results.Count -gt 5) {
        $errorMsg += "`n... and $($results.Count - 5) more"
    }

    Write-Host $errorMsg -ForegroundColor Red
    Write-Host "TODO placeholders are forbidden in production code. Write failing tests instead." -ForegroundColor Yellow
} else {
    Write-Host "TODO placeholder check: PASSED (no TODO found in production code)" -ForegroundColor Green
}

$resultParent = Split-Path -Parent $ResultPath
if (-not [string]::IsNullOrWhiteSpace($resultParent) -and -not (Test-Path -LiteralPath $resultParent)) {
    New-Item -ItemType Directory -Force -Path $resultParent | Out-Null
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

exit $(if ($result.can_proceed) { 0 } else { 1 })
