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

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$summaryScript = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v685-control-summary-stale-blocker-' + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $featureRoot = Join-Path $evidenceRoot 'sample-feature'
    $replayRoot = Join-Path $featureRoot 'claim-codex-replay-v685-autopilot-r01'
    $outputRoot = Join-Path $evidenceRoot '_control'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') @"
# Replay Autopilot Summary

- Replay root: $replayRoot
- ROUND_RESULT exists: False
- blind_self_assessed_coverage: 0
- verification_capped_coverage: 0
- final_status: BLOCKED

## Early Stop Reason

Phase 1 stopped before producing executor-authored ROUND_RESULT.md. reason=executor_failed_without_result:exit_code=1.
"@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- verification_capped_coverage: 0
- decision: STOP_BLOCKED
'@
    $blockerPath = Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md'
    Write-Utf8 $blockerPath 'Phase 1 executor failed with exit code 1.'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_RESULT.md') '- plan_status: PROCEED'

    Write-JsonFile (Join-Path $replayRoot 'SLICE_PROGRESS.json') ([ordered]@{
        replay_root = $replayRoot
        max_slices = 12
        completed = @(1)
        stopped = $false
        stop_reason = ''
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        coverage_delta = 8
        gap_flags = @()
        tests = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 5
        coverage_cap = 25
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
        gap_flags = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        status = 'ALLOW'
        coverage_cap_from_ledger = 25
        final_pass_allowed = $false
        open_required_family_count = 1
    })
    Write-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; status = 'EXECUTABLE_CLOSED' },
            [ordered]@{ id = 'external_integration'; required = $true; status = 'OPEN' }
        )
    })

    $blockerTime = (Get-Date).AddMinutes(-20)
    (Get-Item -LiteralPath $blockerPath).LastWriteTime = $blockerTime
    $execPath = Join-Path $replayRoot 'logs\phase1-slices\slice01\phase1-slice01.exec.json'
    Write-JsonFile $execPath ([ordered]@{
        executor_exit_code = 0
        stdout_log = (Join-Path $replayRoot 'logs\phase1-slices\slice01\phase1-slice01.stdout.log')
        stderr_log = (Join-Path $replayRoot 'logs\phase1-slices\slice01\phase1-slice01.stderr.log')
    })
    (Get-Item -LiteralPath $execPath).LastWriteTime = (Get-Date).AddMinutes(-5)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $replayRoot `
        -OutputRoot $outputRoot `
        -Lookback 1 `
        -TargetCoverage 90 `
        -LowCapThreshold 45 `
        -SkipAuxiliaryArtifacts `
        -Quiet
    Assert-True 'control_summary_exit_zero' ($LASTEXITCODE -eq 0)

    $latest = Get-Content -LiteralPath (Join-Path $outputRoot 'RUN_CONTROL_LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stale_blocker_is_marked_superseded' ([bool]$latest.latest.blocker_file_superseded) ($latest.latest | ConvertTo-Json -Depth 8)
    Assert-True 'superseded_blocker_not_counted_as_active' (-not [bool]$latest.latest.blocker_file) ($latest.latest | ConvertTo-Json -Depth 8)
    Assert-True 'executor_crash_fingerprint_removed' (-not (@($latest.latest.fingerprints) -contains 'executor_resource_or_crash')) (@($latest.latest.fingerprints) -join ',')
    Assert-True 'executor_upgrade_reason_removed' (-not (@($latest.control_decision.reasons) -contains 'executor_retry_or_fallback_needed')) (@($latest.control_decision.reasons) -join ',')
    Assert-True 'low_cap_still_uses_real_slice_value' (@($latest.control_decision.reasons) -contains 'low_verification_cap:5') (@($latest.control_decision.reasons) -join ',')
    Assert-True 'control_decision_no_longer_upgrade' ([string]$latest.control_decision.decision_kind -ne 'UPGRADE') ($latest.control_decision | ConvertTo-Json -Depth 8)

    $sliceStopRoot = Join-Path $featureRoot 'claim-codex-replay-v685-autopilot-r02'
    New-Item -ItemType Directory -Force -Path $sliceStopRoot | Out-Null
    Write-Utf8 (Join-Path $sliceStopRoot 'AUTOPILOT_SUMMARY.md') @'
# Replay Autopilot Summary

- ROUND_RESULT exists: False
- blind_self_assessed_coverage: 0
- verification_capped_coverage: 0
- final_status: BLOCKED

Phase 1 stopped before producing executor-authored ROUND_RESULT.md. reason=executor_failed_without_result:exit_code=1.
'@
    Write-Utf8 (Join-Path $sliceStopRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- verification_capped_coverage: 0
- decision: STOP_BLOCKED
'@
    $sliceStopBlocker = Join-Path $sliceStopRoot 'AUTOPILOT_BLOCKER.md'
    Write-Utf8 $sliceStopBlocker 'Phase 1 executor failed with exit code 1.'
    Write-JsonFile (Join-Path $sliceStopRoot 'SLICE_PROGRESS.json') ([ordered]@{
        replay_root = $sliceStopRoot
        max_slices = 12
        completed = @(1, 2)
        stopped = $true
        stop_reason = 'slice_verifier_refresh_after_side_effect_ledger'
    })
    Write-JsonFile (Join-Path $sliceStopRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        coverage_delta = 8
        gap_flags = @()
        tests = @()
    })
    Write-JsonFile (Join-Path $sliceStopRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 5
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
        gap_flags = @()
    })
    Write-JsonFile (Join-Path $sliceStopRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        status = 'ALLOW'
        coverage_cap_from_ledger = 25
        final_pass_allowed = $false
        open_required_family_count = 1
    })
    Write-JsonFile (Join-Path $sliceStopRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; status = 'EXECUTABLE_CLOSED' },
            [ordered]@{ id = 'stateful_side_effect'; required = $true; status = 'PARTIAL' }
        )
    })
    (Get-Item -LiteralPath $sliceStopBlocker).LastWriteTime = (Get-Date).AddMinutes(-20)
    (Get-Item -LiteralPath (Join-Path $sliceStopRoot 'SLICE_VERIFY_01.json')).LastWriteTime = (Get-Date).AddMinutes(-5)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $sliceStopRoot `
        -OutputRoot $outputRoot `
        -Lookback 1 `
        -TargetCoverage 90 `
        -LowCapThreshold 45 `
        -SkipAuxiliaryArtifacts `
        -Quiet
    Assert-True 'control_summary_slice_stop_exit_zero' ($LASTEXITCODE -eq 0)

    $latest2 = Get-Content -LiteralPath (Join-Path $outputRoot 'RUN_CONTROL_LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'slice_gate_stop_supersedes_stale_phase1_blocker' ([bool]$latest2.latest.blocker_file_superseded -and -not [bool]$latest2.latest.blocker_file) ($latest2.latest | ConvertTo-Json -Depth 8)
    Assert-True 'slice_gate_stop_does_not_trigger_executor_upgrade' ([string]$latest2.control_decision.decision_kind -ne 'UPGRADE' -and -not (@($latest2.control_decision.reasons) -contains 'executor_retry_or_fallback_needed')) ($latest2.control_decision | ConvertTo-Json -Depth 8)

    Write-Host ''
    Write-Host 'v685 Control Summary Supersedes Stale Phase1 Blocker: ALL PASSED'
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
