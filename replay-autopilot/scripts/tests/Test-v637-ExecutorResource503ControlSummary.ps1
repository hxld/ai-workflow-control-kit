#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for executor 503 resource failure classification.

.DESCRIPTION
When the executor returns a gateway/channel 503 before producing replay
artifacts, control summary must classify the run as executor_resource_or_crash
and route to UPGRADE/retry handling instead of workflow EVOLVE.
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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v637-executor-503-control-' + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $featureRoot = Join-Path $evidenceRoot 'sample-feature'
    $replayRoot = Join-Path $featureRoot 'claim-codex-replay-v637-executor-503-r01'
    $phase0Logs = Join-Path $replayRoot 'logs\phase0'
    $outputRoot = Join-Path $evidenceRoot '_control'
    New-Item -ItemType Directory -Force -Path $phase0Logs | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') @'
# Autopilot Blocker

Phase 0 executor failed with exit code 1. Inspect logs under replay logs.
'@

    Write-JsonFile (Join-Path $replayRoot 'EXECUTOR_AUDIT.json') ([ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    })

    $stdoutPath = Join-Path $phase0Logs 'phase0.stdout.log'
    $stderrPath = Join-Path $phase0Logs 'phase0.stderr.log'
    Write-Utf8 $stdoutPath 'API Error: 503 No available channel for model under group default. This is a server-side issue; check inference gateway.'
    Write-Utf8 $stderrPath ''
    Write-JsonFile (Join-Path $phase0Logs 'phase0.exec.json') ([ordered]@{
        executor = 'claude'
        stage = 'phase0'
        stdout_log = $stdoutPath
        stderr_log = $stderrPath
        completion_path = (Join-Path $replayRoot 'PHASE0_RESULT.md')
        exit_code = 1
        executor_exit_code = 1
        failure_category = 'executor'
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\Write-ControlPlaneSummary.ps1') `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot `
        -OutputRoot $outputRoot `
        -RequireExecutor claude `
        -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'Write-ControlPlaneSummary must pass for 503 fixture'

    $summaryPath = Join-Path $replayRoot 'RUN_CONTROL_SUMMARY.json'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'RUN_CONTROL_SUMMARY.json must be written'
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($summary.control_decision.decision_kind -eq 'UPGRADE') '503 executor resource failure must route to UPGRADE, not EVOLVE'
    Assert-True (@($summary.latest.fingerprints) -contains 'executor_resource_or_crash') '503 fixture must record executor_resource_or_crash fingerprint'
    Assert-True (@($summary.control_decision.reasons) -contains 'executor_retry_or_fallback_needed') '503 fixture must recommend executor retry/fallback'
    Assert-True (-not (@($summary.control_decision.reasons) -contains 'executor_credit_required_restore_balance_before_replay')) '503 fixture must not be classified as credit failure'

    Write-Host ''
    Write-Host '=== v637 EXECUTOR 503 CONTROL SUMMARY: PASS ===' -ForegroundColor Green
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
