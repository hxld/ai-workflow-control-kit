<#
.SYNOPSIS
    Regression tests for v525 executor resource preflight.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$preflight = Join-Path $scriptRoot 'Invoke-ExecutorResourcePreflight.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

Write-Host "=== v525 Executor Resource Preflight Test ===" -ForegroundColor Cyan

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("executor-resource-preflight-v525-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$controlRoot = Join-Path $evidenceRoot '_control'
New-Item -ItemType Directory -Force -Path $controlRoot | Out-Null

try {
    @'
{
  "schema": "replay_control_summary.v1",
  "latest": {
    "fingerprints": [
      "executor_credit_required",
      "low_verification_cap"
    ]
  },
  "control_decision": {
    "decision_kind": "STOPLINE",
    "recommended_next_step": "Restore Claude/executor credit."
  }
}
'@ | Set-Content -LiteralPath (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $preflight `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
        -Executor claude `
        -RequireExecutor claude `
        -Model claude-sonnet-4-6 `
        -Quiet *> (Join-Path $tempRoot 'blocked.out')
    $blockedExit = $LASTEXITCODE
    Assert-True ($blockedExit -eq 86) "expected recent credit blocker exit 86, got $blockedExit"
    $blocked = Get-Content -LiteralPath (Join-Path $controlRoot 'EXECUTOR_RESOURCE_PREFLIGHT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($blocked.decision -eq 'BLOCK') "expected BLOCK, got $($blocked.decision)"
    Assert-True ($blocked.failure_category -eq 'executor_credit_required') "expected executor_credit_required, got $($blocked.failure_category)"

    Remove-Item -LiteralPath (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') -Force
    & powershell -NoProfile -ExecutionPolicy Bypass -File $preflight `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
        -Executor claude `
        -RequireExecutor claude `
        -Quiet *> (Join-Path $tempRoot 'allow.out')
    $allowExit = $LASTEXITCODE
    Assert-True ($allowExit -eq 0) "expected allow exit 0 without recent blocker, got $allowExit"
    $allow = Get-Content -LiteralPath (Join-Path $controlRoot 'EXECUTOR_RESOURCE_PREFLIGHT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($allow.decision -eq 'ALLOW') "expected ALLOW, got $($allow.decision)"

    $fakeBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
    @'
@echo off
echo API Error: 402 Credit required. To prevent abuse, a positive balance is required for this model.
exit /b 1
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'claude.cmd') -Encoding ASCII

    $oldPath = $env:PATH
    $env:PATH = "$fakeBin;$oldPath"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $preflight `
            -EvidenceRoot $evidenceRoot `
            -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
            -Executor claude `
            -RequireExecutor claude `
            -Model claude-sonnet-4-6 `
            -Probe `
            -Quiet *> (Join-Path $tempRoot 'probe.out')
        $probeExit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }
    Assert-True ($probeExit -eq 86) "expected live probe resource exit 86, got $probeExit"
    $probe = Get-Content -LiteralPath (Join-Path $controlRoot 'EXECUTOR_RESOURCE_PREFLIGHT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($probe.decision -eq 'BLOCK') "expected probe BLOCK, got $($probe.decision)"
    Assert-True ($probe.failure_category -eq 'executor_credit_required') "expected probe executor_credit_required, got $($probe.failure_category)"

    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $preflightIndex = $runLoopText.IndexOf('Invoke-ExecutorResourcePreflight.ps1')
    $startIndex = $runLoopText.IndexOf('Start-ReplayRound.ps1')
    Assert-True ($preflightIndex -ge 0) 'Run-ReplayLoop must invoke executor resource preflight'
    Assert-True ($startIndex -ge 0) 'Run-ReplayLoop must still invoke Start-ReplayRound'
    Assert-True ($preflightIndex -lt $startIndex) 'executor resource preflight must run before Start-ReplayRound'

    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
