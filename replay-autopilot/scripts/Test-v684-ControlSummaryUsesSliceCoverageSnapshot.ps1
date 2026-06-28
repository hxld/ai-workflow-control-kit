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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v684-control-summary-slice-snapshot-' + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $featureRoot = Join-Path $evidenceRoot 'sample-feature'
    $replayRoot = Join-Path $featureRoot 'claim-codex-replay-v684-autopilot-r01'
    $outputRoot = Join-Path $evidenceRoot '_control'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') @"
# Replay Autopilot Summary

- Replay root: $replayRoot
- PHASE0_RESULT exists: True
- PLAN_RESULT exists: True
- ROUND_RESULT exists: False
- phase0_status: PROCEED
- plan_status: BLOCKED
- blind_self_assessed_coverage: 0
- verification_capped_coverage: 0
- final_status: BLOCKED
"@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- verification_capped_coverage: 0
- decision: STOP_BLOCKED
'@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') '# blocker'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_RESULT.md') '- plan_status: PROCEED'

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        coverage_delta = 20
        gap_flags = @()
        tests = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'DONE'
        coverage_delta = 25
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
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 7
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
    $roundSummary = Get-Content -LiteralPath (Join-Path $replayRoot 'RUN_CONTROL_SUMMARY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'latest_uses_slice_snapshot_source' ([string]$latest.latest.coverage_source -eq 'slice_artifacts') ($latest.latest | ConvertTo-Json -Depth 8)
    Assert-True 'latest_preserves_slice_capped_coverage' ([int]$latest.latest.verification_capped_coverage -eq 12) ($latest.latest | ConvertTo-Json -Depth 8)
    Assert-True 'latest_preserves_slice_blind_coverage' ([int]$latest.latest.blind_self_assessed_coverage -eq 45) ($latest.latest | ConvertTo-Json -Depth 8)
    Assert-True 'per_round_summary_preserves_slice_capped_coverage' ([int]$roundSummary.latest.verification_capped_coverage -eq 12) ($roundSummary.latest | ConvertTo-Json -Depth 8)
    Assert-True 'low_cap_reason_uses_recovered_value' (@($latest.control_decision.reasons) -contains 'low_verification_cap:12') ($latest.control_decision.reasons -join ',')
    Assert-True 'old_zero_summary_does_not_win' (-not (@($latest.control_decision.reasons) -contains 'low_verification_cap:0')) ($latest.control_decision.reasons -join ',')

    Write-Host ''
    Write-Host 'v684 Control Summary Uses Slice Coverage Snapshot: ALL PASSED'
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
