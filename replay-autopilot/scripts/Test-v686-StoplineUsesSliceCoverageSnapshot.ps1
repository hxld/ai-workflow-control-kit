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
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v686-stopline-slice-snapshot-' + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v686-autopilot'
    $replayRoot = "$replayBase-r01"
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') @"
# Replay Autopilot Summary

- ROUND_RESULT exists: False
- blind_self_assessed_coverage: 0
- verification_capped_coverage: 0
- final_status: BLOCKED

Phase 1 stopped before producing executor-authored ROUND_RESULT.md.
"@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- verification_capped_coverage: 0
- decision: STOP_BLOCKED
'@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') 'stale phase1 blocker'

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

    & powershell -NoProfile -ExecutionPolicy Bypass -File $stoplineGate `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 1 `
        -RepeatThreshold 1 `
        -MinimumVerificationProgress 5 `
        -Quiet | Out-Null
    Assert-True 'stopline_does_not_block_recovered_slice_progress' ($LASTEXITCODE -eq 0)

    $analysis = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $record = @($analysis.records)[0]
    Assert-True 'stopline_decision_pass' ([string]$analysis.decision -eq 'PASS') ($analysis | ConvertTo-Json -Depth 12)
    Assert-True 'record_uses_slice_artifact_snapshot' ([string]$record.coverage_source -eq 'slice_artifacts') ($record | ConvertTo-Json -Depth 12)
    Assert-True 'record_preserves_recovered_cap' ([int]$record.verification_capped_coverage -eq 12) ($record | ConvertTo-Json -Depth 12)
    Assert-True 'record_is_substantive_progress' (-not [bool]$record.no_progress -and [bool]$record.substantive_progress) ($record | ConvertTo-Json -Depth 12)
    Assert-True 'stale_zero_summary_did_not_trigger' (-not [bool]$analysis.triggered) ($analysis | ConvertTo-Json -Depth 12)

    Write-Host ''
    Write-Host 'v686 Stopline Uses Slice Coverage Snapshot: ALL PASSED'
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
