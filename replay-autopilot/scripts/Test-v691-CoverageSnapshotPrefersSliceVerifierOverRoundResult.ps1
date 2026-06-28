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

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$snapshotScript = Join-Path $scriptRoot 'Get-RoundCoverageSnapshot.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v691-coverage-snapshot-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'ROUND_RESULT.md') @'
# Round Result

## Coverage

- blind_self_assessed_coverage: `25`
- verification_capped_coverage: `25`
- final_status: `PARTIAL`
'@
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        coverage_delta = 10
        gap_flags = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_02.json') ([ordered]@{
        slice_index = 2
        slice_status = 'BLOCKED'
        coverage_delta = 0
        gap_flags = @('no_progress_slice')
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
        gap_flags = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_02.json') ([ordered]@{
        slice_index = 2
        verification_status = 'BLOCKED'
        adjusted_coverage_delta = 0
        should_continue = $false
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('tooling_enforcement_stop')
        gap_flags = @('no_progress_slice')
    })
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json') ([ordered]@{
        coverage_cap_from_ledger = 25
        final_pass_allowed = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'core_entry'; required = $true; status = 'EXECUTABLE_CLOSED' },
            [ordered]@{ id = 'stateful_side_effect'; required = $true; status = 'PARTIAL' }
        )
    })

    $snapshot = & powershell -NoProfile -ExecutionPolicy Bypass -File $snapshotScript -ReplayRoot $replayRoot | ConvertFrom-Json
    Assert-True 'snapshot_exit_zero' ($LASTEXITCODE -eq 0)
    Assert-True 'slice_artifacts_win_over_round_result' ([string]$snapshot.coverage_source -eq 'slice_artifacts') ($snapshot | ConvertTo-Json -Depth 8)
    Assert-True 'slice_verifier_adjusted_coverage_wins' ([int]$snapshot.verification_capped_coverage -eq 3) ($snapshot | ConvertTo-Json -Depth 8)
    Assert-True 'slice_result_blind_coverage_wins' ([int]$snapshot.blind_self_assessed_coverage -eq 10) ($snapshot | ConvertTo-Json -Depth 8)
    Assert-True 'non_authorizing_slice_marks_blocked' ([string]$snapshot.final_status -eq 'BLOCKED') ($snapshot | ConvertTo-Json -Depth 8)

    Write-Host ''
    Write-Host 'v691 Coverage Snapshot Prefers Slice Verifier Over Round Result: ALL PASSED'
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
