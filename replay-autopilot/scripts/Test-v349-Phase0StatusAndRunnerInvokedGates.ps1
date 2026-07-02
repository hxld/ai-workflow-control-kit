param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Write-Utf8 {
    param(
        [string]$Path,
        [string]$Value
    )
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ("replay-v349-status-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    Write-Utf8 (Join-Path $tempRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED_WITH_ORACLE_VERIFICATION
- selected_real_entry: ClaimService.handle()
- first_executable_slice: S1 core path
- first_slice_type: core_path
'@

    Write-Utf8 (Join-Path $tempRoot 'EXPLORATION_REPORT.md') @'
# Exploration Report

## Source Boundary
requirement only

## Requirement Literal Inventory
literal list

## Candidate Surface Map
surface list

## Uncertainty Ledger
none
'@

    Write-Utf8 (Join-Path $tempRoot 'ROUND_CONTRACT.md') @'
# Round Contract

## Requirement Family Ledger
core_entry

## Real Entry Discovery Matrix
ClaimService.handle()

## Behavior Test Charter
business assertion

## Critical Surface Allocation Plan
core first

## side-effect ledger
db write

## coverage cap
cap

## Expected Diff Matrix
example-core service
'@

    Write-Utf8 (Join-Path $tempRoot 'FAMILY_CONTRACT.json') @'
{
  "phase0_status": "PROCEED_WITH_ORACLE_VERIFICATION",
  "selected_real_entry": "ClaimService.handle()",
  "first_executable_slice": "S1 core path",
  "families": [
    {
      "id": "core_entry",
      "required": true,
      "proof_required": ["real_entry_behavior"]
    }
  ]
}
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $tempRoot -Stage Phase0 | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issuesText = (@($verify.issues) -join ',')
    Assert-True ($issuesText -match 'phase0_status_noncanonical:PROCEED_WITH_ORACLE_VERIFICATION') 'Verifier must flag generic PROCEED_WITH_* statuses as noncanonical.'
    Assert-True ($issuesText -notmatch 'phase0_status_not_proceed') 'Verifier must route generic PROCEED_WITH_* through PROCEED so contract repair can run instead of unsupported-status exit.'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $tempRoot | Out-Null
    $summaryText = Get-Content -LiteralPath (Join-Path $tempRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
    Assert-True ($summaryText -match '(?m)^- phase0_status: PROCEED') 'Parser summary must normalize generic PROCEED_WITH_* to PROCEED.'

    Write-Utf8 (Join-Path $tempRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: GREEN_PROCEED
- selected_real_entry: ClaimService.handle()
- first_executable_slice: S1 core path
- first_slice_type: core_path
'@

    Write-Utf8 (Join-Path $tempRoot 'FAMILY_CONTRACT.json') @'
{
  "phase0_status": "GREEN_PROCEED",
  "selected_real_entry": "ClaimService.handle()",
  "first_executable_slice": "S1 core path",
  "families": [
    {
      "id": "core_entry",
      "required": true,
      "proof_required": ["real_entry_behavior"]
    }
  ]
}
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $tempRoot -Stage Phase0 | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issuesText = (@($verify.issues) -join ',')
    Assert-True ($issuesText -match 'phase0_status_noncanonical:GREEN_PROCEED') 'Verifier must flag GREEN_PROCEED as noncanonical.'
    Assert-True ($issuesText -notmatch 'phase0_status_not_proceed') 'Verifier must normalize GREEN_PROCEED to PROCEED for runner continuation.'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $tempRoot | Out-Null
    $summaryText = Get-Content -LiteralPath (Join-Path $tempRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
    Assert-True ($summaryText -match '(?m)^- phase0_status: PROCEED') 'Parser summary must normalize GREEN_PROCEED to PROCEED.'

    $runLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    $sliceLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8

    Assert-True ($runLoopText.Contains('Invoke-V348PreS1CarrierVerification')) 'Run-ReplayLoop must invoke the v348 carrier gate.'
    Assert-True ($runLoopText.Contains('verify-carrier.ps1')) 'Run-ReplayLoop must reference verify-carrier.ps1 from an invoked gate.'
    Assert-True ($runLoopText.Contains('PROCEED_WITH_*')) 'Run-ReplayLoop repair prompt must ban generic PROCEED_WITH_* statuses.'
    Assert-True ($sliceLoopText.Contains('Invoke-V348SliceQualityGates')) 'Run-SliceLoop must invoke v348 slice quality gates.'
    Assert-True ($sliceLoopText.Contains('verify-horizontal-slice.ps1')) 'Run-SliceLoop must invoke verify-horizontal-slice.ps1.'
    Assert-True ($sliceLoopText.Contains('verify-test-charter.ps1')) 'Run-SliceLoop must invoke verify-test-charter.ps1.'

    Write-Host 'Test-v349-Phase0StatusAndRunnerInvokedGates: PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
