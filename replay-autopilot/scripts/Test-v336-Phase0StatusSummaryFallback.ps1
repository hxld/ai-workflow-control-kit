$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifyPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v336-phase0-summary-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    @'
# Exploration Report

## Requirement Literal Inventory
- literal: sample requirement

## Surface Map
- selected_real_entry: SampleFacade.handle()

## Selected Real Entry
selected_real_entry: SampleFacade.handle()

## First Executable Slice
first_executable_slice: S1 public entry behavior
first_slice_type: core_path

## Evidence
- current worktree source search found SampleFacade.handle()

## Risks
- none

## Next Actions
- proceed
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'EXPLORATION_REPORT.md') -Encoding UTF8

    @'
# Round Contract

- phase0_status: PROCEED
- selected_real_entry: SampleFacade.handle()
- first_executable_slice: S1 public entry behavior
- first_slice_type: core_path

## Requirement Literal Inventory
sample

## Surface Map
sample
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'ROUND_CONTRACT.md') -Encoding UTF8

    @'
# Phase 0 Result

## Summary

**Phase 0 Status**: `PROCEED`

selected_real_entry: SampleFacade.handle()
first_executable_slice: S1 public entry behavior
first_slice_type: core_path
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_RESULT.md') -Encoding UTF8

    [ordered]@{
        phase0_status = 'PROCEED'
        selected_real_entry = 'SampleFacade.handle()'
        first_executable_slice = 'S1 public entry behavior'
        families = @(
            [ordered]@{ id = 'core_entry'; priority = 'HIGH' },
            [ordered]@{ id = 'stateful_side_effect'; priority = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempRoot 'FAMILY_CONTRACT.json') -Encoding UTF8

    Write-Host "=== v336 Phase0 Status Summary Fallback Test ===" -ForegroundColor Cyan

    Write-Host "`n[Test 1] Verifier must not capture the Summary heading as Phase0 status..."
    $verifyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -ReplayRoot $tempRoot -Stage Phase0 2>&1
    if ($LASTEXITCODE -ne 0) { $verifyOutput | Write-Host }
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issuesText = (($verify.issues | ForEach-Object { [string]$_ }) -join "`n")
    Assert-True ($issuesText -notmatch 'phase0_status_not_proceed:Summary') 'Summary heading must not become status'
    Assert-True ($issuesText -notmatch 'phase0_status_not_proceed') 'Phase0 status must resolve to PROCEED'
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 2] Repair prompt must interpolate completion path instead of literal variable..."
    $runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
    Assert-True (-not $runLoopText.Contains('`$phase0RepairResult')) 'repair prompt must not contain escaped literal $phase0RepairResult'
    Assert-True ($runLoopText.Contains('   $phase0RepairResult')) 'repair prompt must contain interpolated completion-path variable'
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 3] Repair prompt hard rules must avoid PowerShell backtick escapes in double-quoted here-string..."
    $repairBlock = [regex]::Match($runLoopText, '(?s)\$phase0RepairText = @"(.*?)"@').Groups[1].Value
    Assert-True (-not $repairBlock.Contains('`phase0_status')) 'repair prompt must not include backtick-quoted phase0_status'
    Assert-True (-not $repairBlock.Contains('`FAMILY_CONTRACT.json')) 'repair prompt must not include backtick-quoted FAMILY_CONTRACT.json'
    Assert-True (-not $repairBlock.Contains('`rg`')) 'repair prompt must not include backtick-quoted rg'
    Write-Host "PASS" -ForegroundColor Green

    [ordered]@{
        status = 'PASS'
        assertions = 7
        cases = @(
            'bold_phase0_status_under_summary_resolves_to_proceed',
            'summary_heading_not_captured_as_status',
            'phase0_status_not_proceed_not_emitted',
            'repair_prompt_no_literal_completion_variable',
            'repair_prompt_contains_interpolated_completion_path',
            'repair_prompt_avoids_backtick_phase0_status_escape',
            'repair_prompt_avoids_backtick_artifact_escape'
        )
    } | ConvertTo-Json -Depth 5
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
