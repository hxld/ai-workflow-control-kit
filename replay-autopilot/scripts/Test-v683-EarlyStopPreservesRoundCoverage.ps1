#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$snapshotScript = Join-Path $scriptRoot 'Get-RoundCoverageSnapshot.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v683-early-stop-round-coverage-' + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-Utf8 (Join-Path $replayRoot 'ROUND_RESULT.md') @'
# ROUND_RESULT

## Coverage
- blind_self_assessed_coverage: 25
- verification_capped_coverage: 12
- final_status: BLOCKED
'@
    Write-Utf8 (Join-Path $replayRoot 'PHASE0_RESULT.md') '- phase0_status: PROCEED'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_RESULT.md') '- plan_status: PROCEED'

    $snapshot = & powershell -NoProfile -ExecutionPolicy Bypass -File $snapshotScript -ReplayRoot $replayRoot | ConvertFrom-Json
    Assert-True 'snapshot_exit_zero' ($LASTEXITCODE -eq 0)
    Assert-True 'snapshot_detects_round_result' ([bool]$snapshot.round_result_exists)
    Assert-True 'snapshot_reads_blind_coverage' ([int]$snapshot.blind_self_assessed_coverage -eq 25)
    Assert-True 'snapshot_reads_capped_coverage' ([int]$snapshot.verification_capped_coverage -eq 12)
    Assert-True 'snapshot_reads_final_status' ([string]$snapshot.final_status -eq 'BLOCKED')

    $emptyRoot = Join-Path $tempRoot 'empty-replay'
    New-Item -ItemType Directory -Force -Path $emptyRoot | Out-Null
    $emptySnapshot = & powershell -NoProfile -ExecutionPolicy Bypass -File $snapshotScript -ReplayRoot $emptyRoot | ConvertFrom-Json
    Assert-True 'empty_snapshot_reports_no_round_result' (-not [bool]$emptySnapshot.round_result_exists)
    Assert-True 'empty_snapshot_coverage_defaults_zero' ([int]$emptySnapshot.verification_capped_coverage -eq 0)

    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    Assert-True 'run_loop_calls_round_coverage_snapshot' ($runLoopText.Contains('Get-RoundCoverageSnapshot.ps1'))
    Assert-True 'early_stop_decision_uses_snapshot_capped_coverage' ($runLoopText.Contains('- verification_capped_coverage: $earlyCappedCoverage'))
    Assert-True 'early_stop_summary_uses_snapshot_round_existence' ($runLoopText.Contains('- ROUND_RESULT exists: $roundResultExistsForEarlyStop'))

    Write-Host ''
    Write-Host 'v683 Early Stop Preserves Round Coverage: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
