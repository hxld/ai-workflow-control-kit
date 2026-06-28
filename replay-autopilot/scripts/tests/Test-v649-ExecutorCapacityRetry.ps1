#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for executor model-capacity retry handling.

.DESCRIPTION
The exact executor error "Selected model is at capacity. Please try a
different model." is a transient resource blocker. It must route through the
same bounded retry path as rate-limit style failures, not the credit stopline
or workflow-evolution path.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 10)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoScriptRoot = Resolve-Path (Join-Path $scriptRoot '..')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v649-executor-capacity-retry-' + [guid]::NewGuid().ToString('N'))
$capacityText = 'Selected model is at capacity. Please try a different model.'

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $controlRoot = Join-Path $evidenceRoot '_control'
    $fakeBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Force -Path $controlRoot, $fakeBin | Out-Null

    $counterPath = Join-Path $tempRoot 'capacity-counter.txt'
    @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "$counter=$env:FAKE_CAPACITY_COUNTER; if (-not (Test-Path -LiteralPath $counter)) { Set-Content -LiteralPath $counter -Value '1' -Encoding UTF8; Write-Output 'Selected model is at capacity. Please try a different model.'; exit 1 }; Write-Output 'OK'; exit 0"
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Encoding ASCII

    $oldPath = $env:PATH
    $oldCounter = $env:FAKE_CAPACITY_COUNTER
    $env:PATH = "$fakeBin;$oldPath"
    $env:FAKE_CAPACITY_COUNTER = $counterPath
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoScriptRoot 'Invoke-ExecutorResourcePreflight.ps1') `
            -EvidenceRoot $evidenceRoot `
            -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
            -Executor codex `
            -RequireExecutor codex `
            -Probe `
            -ProbeTimeoutSeconds 5 `
            -MaxResourceRetries 1 `
            -RetryDelaySeconds 0 `
            -Quiet *> (Join-Path $tempRoot 'preflight.out')
        $preflightExit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
        if ($null -eq $oldCounter) {
            Remove-Item Env:\FAKE_CAPACITY_COUNTER -ErrorAction SilentlyContinue
        } else {
            $env:FAKE_CAPACITY_COUNTER = $oldCounter
        }
    }

    Assert-True ($preflightExit -eq 0) "capacity probe should retry and pass, got exit $preflightExit"
    $preflightPath = Join-Path $controlRoot 'EXECUTOR_RESOURCE_PREFLIGHT.json'
    Assert-True (Test-Path -LiteralPath $preflightPath) 'preflight JSON must be written'
    $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($preflight.decision -eq 'ALLOW') "expected ALLOW after retry, got $($preflight.decision)"
    Assert-True ([int]$preflight.attempts -eq 2) "expected two preflight attempts, got $($preflight.attempts)"
    Assert-True ($preflight.reason -eq 'live_probe_passed') "expected live_probe_passed, got $($preflight.reason)"

    $featureRoot = Join-Path $evidenceRoot 'sample-feature'
    $replayRoot = Join-Path $featureRoot 'claim-codex-replay-v649-capacity-r01'
    $phase0Logs = Join-Path $replayRoot 'logs\phase0'
    $summaryOutputRoot = Join-Path $evidenceRoot '_control-summary'
    New-Item -ItemType Directory -Force -Path $phase0Logs | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') @"
# Autopilot Blocker

Phase 0 executor failed with: $capacityText
"@

    Write-JsonFile (Join-Path $replayRoot 'EXECUTOR_AUDIT.json') ([ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'codex'
        require_executor = 'codex'
        allow_codex_executor = $true
        policy = 'passed'
    })

    $stdoutPath = Join-Path $phase0Logs 'phase0.stdout.log'
    $stderrPath = Join-Path $phase0Logs 'phase0.stderr.log'
    Write-Utf8 $stdoutPath $capacityText
    Write-Utf8 $stderrPath ''
    Write-JsonFile (Join-Path $phase0Logs 'phase0.exec.json') ([ordered]@{
        executor = 'codex'
        stage = 'phase0'
        stdout_log = $stdoutPath
        stderr_log = $stderrPath
        completion_path = (Join-Path $replayRoot 'PHASE0_RESULT.md')
        exit_code = 86
        executor_exit_code = 1
        failure_category = 'usage_limit'
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoScriptRoot 'Write-ControlPlaneSummary.ps1') `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot `
        -OutputRoot $summaryOutputRoot `
        -RequireExecutor codex `
        -SkipAuxiliaryArtifacts `
        -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Write-ControlPlaneSummary must pass for capacity fixture'

    $summaryPath = Join-Path $replayRoot 'RUN_CONTROL_SUMMARY.json'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'RUN_CONTROL_SUMMARY.json must be written'
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($summary.control_decision.decision_kind -eq 'UPGRADE') 'capacity resource failure must route to UPGRADE, not EVOLVE'
    Assert-True (@($summary.latest.fingerprints) -contains 'executor_resource_or_crash') 'capacity fixture must record executor_resource_or_crash fingerprint'
    Assert-True (-not (@($summary.latest.fingerprints) -contains 'executor_credit_required')) 'capacity fixture must not record executor_credit_required'
    Assert-True (@($summary.control_decision.reasons) -contains 'executor_retry_or_fallback_needed') 'capacity fixture must recommend executor retry/fallback'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoScriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 1 `
        -BlockerReason $capacityText *> (Join-Path $tempRoot 'recovery.out')
    Assert-True ($LASTEXITCODE -eq 0) 'Get-RecoveryAction must pass for capacity blocker'
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($recovery.recovery_action -eq 'RETRY_AFTER_QUOTA_RESET') "expected RETRY_AFTER_QUOTA_RESET, got $($recovery.recovery_action)"
    Assert-True ([bool]$recovery.should_retry) 'capacity recovery action must be retryable'

    $agentPromptText = Get-Content -LiteralPath (Join-Path $repoScriptRoot 'Invoke-AgentPrompt.ps1') -Raw -Encoding UTF8
    $sliceLoopText = Get-Content -LiteralPath (Join-Path $repoScriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($agentPromptText -match 'selected model is at capacity') 'Invoke-AgentPrompt must classify capacity as retryable'
    Assert-True ($sliceLoopText -match 'selected model is at capacity') 'Run-SliceLoop transient retry must include capacity text'

    Write-Host ''
    Write-Host '=== v649 EXECUTOR CAPACITY RETRY: PASS ===' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
