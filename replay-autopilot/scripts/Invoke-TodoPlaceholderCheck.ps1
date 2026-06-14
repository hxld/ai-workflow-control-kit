# Invoke-TodoPlaceholderCheck.ps1
# v432: RED Phase TODO Ban (Experiment 3 from NEXT_EXPERIMENT_PLAN.md)

<#
.SYNOPSIS
Checks for TODO/FIXME/XXX placeholders in production code.

.DESCRIPTION
Scans example-core, example-api, example-web source directories for TODO placeholders.
Throws if any TODO placeholders found, forcing executable behavior instead of placeholders.

.PARAMETER Worktree
Path to the worktree directory

.PARAMETER ValidateOnly
If set, only validates the script without running checks
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Worktree,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'TODO placeholder check for production code',
            'Bans TODO/FIXME/XXX in example-core, example-api, example-web',
            'Allows TODO in test files'
        )
    } | Format-List
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Worktree) -or -not (Test-Path -LiteralPath $Worktree)) {
    Write-Host "WARNING: Worktree not found or not specified: $Worktree" -ForegroundColor Yellow
    exit 0  # Don't block if worktree doesn't exist
}

$resultPath = Join-Path $Worktree 'TODO_CHECK_RESULT.json'

$forbiddenPaths = @(
    "example-core/src/main/java",
    "example-api/src/main/java",
    "example-web/src/main/java"
)

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
    $targetPath = Join-Path $Worktree $path -replace '\\', '/'
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

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

exit $(if ($result.can_proceed) { 0 } else { 1 })
