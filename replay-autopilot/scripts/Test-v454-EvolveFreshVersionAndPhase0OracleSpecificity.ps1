param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = $PSScriptRoot
$controller = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v454-test-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $testRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-core\src\main\java\com\example') | Out-Null

    Write-Text (Join-Path $testRoot 'EXPLORATION_REPORT.md') @'
# Exploration Report

## Source Boundary
baseline worktree only

## Requirement Literal Inventory
literal present

## Candidate Surface Map
ExampleApplyClaimApiTaskProcessor.handleTaskResponse exists

## Uncertainty Ledger
planned_new_carrier uses oracle additions for scope only.

## Schema and Exact Contract Discovery Ledger
entity mapper dto service xml searched

## Selected Real Entry
selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
carrier_status: EXISTING
planned_new_carrier: ExampleFlowService
oracle additions: allowed here as planned-new-carrier scope, not selected-entry authority.
'@

    Write-Text (Join-Path $testRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
- first_executable_slice: S1
- first_slice_type: core_path_with_existing_entry

## Search Commands Used
rg "class ExampleApplyClaimApiTaskProcessor" worktree --glob "*.java"
# result_summary: FOUND
rg "handleTaskResponse" worktree --glob "*.java"
# result_summary: FOUND
rg "ExampleFlowService" worktree --glob "*.java"
# result_summary: NOT_FOUND, planned_new_carrier only
'@

    Write-Text (Join-Path $testRoot 'ROUND_CONTRACT.md') @'
# Round Contract

## Requirement Family Ledger
core_entry

## Real Entry Discovery Matrix
selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse

## Behavior Test Charter
side effect assertion

## Critical Surface Allocation Plan
planned_new_carrier: ExampleFlowService
oracle additions may describe planned-new scope only.

## side-effect ledger
DB/state/log proof

## coverage cap
60
'@

    Write-Text (Join-Path $testRoot 'FAMILY_CONTRACT.json') @'
{
  "schema_version": 1,
  "phase0_status": "PROCEED",
  "selected_real_entry": "ExampleApplyClaimApiTaskProcessor.handleTaskResponse",
  "first_executable_slice": "S1",
  "families": [
    {
      "id": "core_entry",
      "required": true,
      "first_executable_carrier": "ExampleApplyClaimApiTaskProcessor.handleTaskResponse",
      "planned_new_carrier": "ExampleFlowService",
      "coverage_cap_if_open": 85
    }
  ]
}
'@

    $verifyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Stage Phase0 2>&1
    $verifyJson = Get-Content -LiteralPath (Join-Path $testRoot 'PHASE0_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'planned_new_oracle_additions_do_not_flag_selected_entry_oracle' -Condition (-not (@($verifyJson.issues) -contains 'phase0_oracle_inferred_selected_entry'))

    $controllerText = Get-Content -LiteralPath $controller -Raw -Encoding UTF8
    Assert-True -Name 'controller_extracts_version_from_latest_root' -Condition ($controllerText -match 'Get-VersionNumberFromText')
    Assert-True -Name 'controller_tracks_evolve_without_latest_root_advance' -Condition ($controllerText -match '\$evolveWithoutLatestRootAdvance')
    Assert-True -Name 'controller_requires_after_version_gt_latest_root_version' -Condition ($controllerText -match '\$afterVersionNumber\s+-le\s+\$latestRootVersionNumber')
    Assert-True -Name 'controller_blocks_continue_on_stale_evolve' -Condition ($controllerText -match 'evolve_without_latest_root_advance')

    Write-Host 'PASS: v454 EVOLVE fresh version and Phase0 oracle specificity'
    [ordered]@{ status = 'PASS'; assertions = 5; verifier_exit = $LASTEXITCODE } | ConvertTo-Json -Depth 5
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
