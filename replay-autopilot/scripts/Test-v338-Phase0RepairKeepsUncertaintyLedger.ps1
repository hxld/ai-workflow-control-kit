$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$verifyPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
$repairBlock = [regex]::Match($runLoopText, '(?s)\$phase0RepairText = @"(.*?)"@').Groups[1].Value

Write-Host "=== v338 Phase0 Repair Keeps Uncertainty Ledger Test ===" -ForegroundColor Cyan

Write-Host "`n[Test 1] Repair prompt requires the exact Uncertainty Ledger heading..."
Assert-True ($repairBlock.Contains('EXPLORATION_REPORT.md must contain the exact heading ## Uncertainty Ledger after repair')) 'repair prompt must require exact Uncertainty Ledger heading'
Assert-True ($repairBlock.Contains('keep or recreate the heading')) 'repair prompt must tell repair to keep or recreate the heading'
Assert-True ($repairBlock.Contains('do not delete the section')) 'repair prompt must forbid deleting the section'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 2] Verifier still fails closed when Uncertainty Ledger is missing..."
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v338-uncertainty-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    @'
# Exploration Report

## Source Boundary
source

## Requirement Literal Inventory
literal

## Selected Real Entry
selected_real_entry: SampleService.handle()

## Domain Fact Sheet
facts

## Candidate Surface Map
surface

## Planning Input Summary
summary
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'EXPLORATION_REPORT.md') -Encoding UTF8

    @'
# Round Contract

- phase0_status: PROCEED
- selected_real_entry: SampleService.handle()
- first_executable_slice: S1
- first_slice_type: core_path

## Requirement Family Ledger
family

## Real Entry Discovery Matrix
entry

## Behavior Test Charter
test

## Critical Surface Allocation Plan
surface

side-effect ledger
coverage cap
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'ROUND_CONTRACT.md') -Encoding UTF8

    @'
# Phase 0 Result

phase0_status: PROCEED
selected_real_entry: SampleService.handle()
first_executable_slice: S1
first_slice_type: core_path
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_RESULT.md') -Encoding UTF8

    [ordered]@{
        phase0_status = 'PROCEED'
        selected_real_entry = 'SampleService.handle()'
        first_executable_slice = 'S1'
        families = @(
            [ordered]@{ id = 'core_entry'; priority = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempRoot 'FAMILY_CONTRACT.json') -Encoding UTF8

    $verifyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -ReplayRoot $tempRoot -Stage Phase0 2>&1
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issuesText = (($verify.issues | ForEach-Object { [string]$_ }) -join "`n")
    Assert-True ($LASTEXITCODE -ne 0) 'missing Uncertainty Ledger must keep verifier failing closed'
    Assert-True ($issuesText -match 'exploration_missing:uncertainty ledger') 'missing Uncertainty Ledger issue must be emitted'
    Write-Host "PASS" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

[ordered]@{
    status = 'PASS'
    assertions = 5
    cases = @(
        'repair_prompt_requires_exact_uncertainty_ledger_heading',
        'repair_prompt_requires_keep_or_recreate_heading',
        'repair_prompt_forbids_deleting_section',
        'verifier_fails_closed_when_uncertainty_ledger_missing',
        'verifier_emits_uncertainty_ledger_missing_issue'
    )
} | ConvertTo-Json -Depth 5
