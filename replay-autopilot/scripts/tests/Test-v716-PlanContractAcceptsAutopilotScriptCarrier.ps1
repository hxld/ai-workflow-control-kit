param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Invoke-PlanContract {
    param([string]$ReplayRoot, [string]$Worktree)

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:Verifier `
        -ReplayRoot $ReplayRoot `
        -Stage Plan `
        -Worktree $Worktree `
        -SkipCarrierAndOracleChecks 2>&1

    $verify = Get-Content -LiteralPath (Join-Path $ReplayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
        Verify = $verify
    }
}

function New-PlanFixture {
    param(
        [string]$Name,
        [string]$TargetCarrierFilePath
    )

    $root = Join-Path $tempRoot $Name
    $replayRoot = Join-Path $root 'replay'
    $worktree = Join-Path $root 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $worktree 'replay-autopilot\scripts\Verify-PlanContract.ps1') 'param()'
    Write-Utf8 (Join-Path $worktree 'replay-autopilot\scripts\tests\Test-v716-Fixture.ps1') 'param()'
    Write-Utf8 (Join-Path $replayRoot 'PHASE0_RESULT.md') @'
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: Verify-PlanContract.ps1
- first_executable_slice: S1_control_plane_verifier
- first_slice_type: core_path
'@
    Write-Utf8 (Join-Path $replayRoot 'EXPLORATION_REPORT.md') @'
# Exploration Report

## source boundary
Replay-autopilot verifier scripts are in scope.

## requirement literal inventory
The target carrier file path must identify a real control-plane carrier.

## candidate surface map
Verify-PlanContract.ps1 is the candidate verifier surface.

## uncertainty ledger
No unresolved uncertainty for this fixture.
'@
    Write-Utf8 (Join-Path $replayRoot 'ROUND_CONTRACT.md') @'
# Round Contract

## Requirement Family Ledger
- requirement_contract

## Real Entry Discovery Matrix
- Verify-PlanContract.ps1

## Behavior Test Charter
- Test-v716-PlanContractAcceptsAutopilotScriptCarrier.ps1

## Critical Surface Allocation Plan
- Verify-PlanContract.ps1

## side-effect ledger
- PHASE0_CONTRACT_VERIFY.json

## coverage cap
- none

## Expected Diff Matrix
- Verify-PlanContract.ps1 path validation branch
'@
    Write-Utf8 (Join-Path $replayRoot 'FAMILY_CONTRACT.json') @'
{
  "schema_version": 1,
  "selected_real_entry": "Verify-PlanContract.ps1",
  "first_executable_slice": "S1_control_plane_verifier",
  "families": [
    {
      "id": "requirement_contract",
      "required": true,
      "proof_required": ["Verify-PlanContract.ps1"],
      "blocker": ""
    }
  ]
}
'@
    Write-Utf8 (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') @'
{
  "schema_version": 1,
  "production_files": 1,
  "high_weight_files": 1,
  "files": [
    {
      "path": "replay-autopilot/scripts/Verify-PlanContract.ps1",
      "weight": "HIGH",
      "is_test": false,
      "is_production": true
    }
  ]
}
'@
    Write-Utf8 (Join-Path $replayRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: control-plane-verifier-path-policy
- first_slice: S1_control_plane_verifier
- first_red_test: Test-v716-PlanContractAcceptsAutopilotScriptCarrier
- required_files: replay-autopilot/scripts/Verify-PlanContract.ps1
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 1/1
- carrier_search: performed
- carrier_search_queries: rg "Verify-PlanContract", rg "target_carrier_file_path", rg "replay-autopilot/scripts"
- existing_production_carriers: replay-autopilot/scripts/Verify-PlanContract.ps1:1 Verify-PlanContract
- selected_carrier_from_search: replay-autopilot/scripts/Verify-PlanContract.ps1:1 Verify-PlanContract
- new_service_proposed: false
- new_service_justification: none
'@
    Write-Utf8 (Join-Path $replayRoot 'PLAN_CANDIDATE_1.md') '# Candidate 1'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_CANDIDATE_2.md') '# Candidate 2'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_CANDIDATE_3.md') '# Candidate 3'
    Write-Utf8 (Join-Path $replayRoot 'PLAN_SELECTION.md') '# Plan Selection'
    Write-Utf8 (Join-Path $replayRoot 'REPLAY_PLAN.md') @'
# Replay Plan

requirement_contract

S1_control_plane_verifier:
- replay-autopilot/scripts/Verify-PlanContract.ps1
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
# Implementation Contract

selected_real_entry: Verify-PlanContract.ps1
first_slice: S1_control_plane_verifier
first_red_test: Test-v716-PlanContractAcceptsAutopilotScriptCarrier

The verifier path policy is the production entry being changed.
'@
    Write-Utf8 (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') @'
# Expected Diff Matrix

| requirement | validation | closure |
|---|---|---|
| replay-autopilot control-plane carrier path policy | focused Plan verifier regression | Verify-PlanContract.ps1 target_carrier_file_path branch |
'@
    Write-Utf8 (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') @'
# Side Effect Ledger

- PLAN_CONTRACT_VERIFY.json records pass/fail path policy issues.
'@
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') @'
# Test Charter

## RED Phase

Test Class: Test-v716-PlanContractAcceptsAutopilotScriptCarrier
Entry Point: Verify-PlanContract.ps1
Side Effects: assert PLAN_CONTRACT_VERIFY.json issues include or exclude first_slice_proof_v457_invalid_file_path.

## GREEN Phase

The verifier accepts replay-autopilot/scripts/*.ps1 production carriers and rejects replay-autopilot/scripts/tests/*.ps1 test carriers.
'@
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

first_slice: S1_control_plane_verifier
highest_weight_open_gate: requirement_contract
selected_real_entry: Verify-PlanContract.ps1
selected_carrier: Verify-PlanContract.ps1
target_subsurface_or_carrier: Verify-PlanContract.ps1
production_boundary: replay-autopilot/scripts/Verify-PlanContract.ps1
proof_kind: real_entry_behavior
real_carrier_kind: production_entry_or_service
first_red_test: Test-v716-PlanContractAcceptsAutopilotScriptCarrier.ps1
public_entry_contract_coverage: Verify-PlanContract.ps1 validates Plan contracts
forbidden_substitute_check: passed
forbidden_substitute_proof: target path must resolve to replay-autopilot production script, not scripts/tests
required_sibling_surfaces: none_with_reason: single verifier entry
minimum_side_effect_or_blocker: PLAN_CONTRACT_VERIFY.json records pass/fail
expected_production_diff: Verify-PlanContract.ps1 path validation branch
red_expectation: invalid target carrier file path is rejected
green_minimum_implementation: autopilot production script target is accepted
fail_closed_condition: first_slice_proof_v457_invalid_file_path appears
coverage_cap_if_not_closed: 60
target_carrier_file_path: $TargetCarrierFilePath
target_carrier_line_number: 1
expected_test_class: Test-v716-PlanContractAcceptsAutopilotScriptCarrier
expected_test_method: testAutopilotScriptCarrierPathPolicy
expected_assertions: ["accept production control-plane script","reject replay-autopilot test script","report v457 issue for invalid script carrier"]
expected_side_effects: [{"file":"PLAN_CONTRACT_VERIFY.json","operation":"write"}]
"@

    return [pscustomobject]@{ ReplayRoot = $replayRoot; Worktree = $worktree }
}

$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:Verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v716-plan-contract-autopilot-script-' + [guid]::NewGuid().ToString('N'))

try {
    $validFixture = New-PlanFixture -Name 'valid-control-plane-script' -TargetCarrierFilePath 'replay-autopilot/scripts/Verify-PlanContract.ps1:1'
    $valid = Invoke-PlanContract -ReplayRoot $validFixture.ReplayRoot -Worktree $validFixture.Worktree
    Assert-True 'autopilot_production_script_exits_zero' ($valid.ExitCode -eq 0) "exit=$($valid.ExitCode) output=$($valid.Output)"
    Assert-True 'autopilot_production_script_contract_passes' ([string]$valid.Verify.verification_status -eq 'PASS') ($valid.Verify | ConvertTo-Json -Depth 8)
    Assert-True 'autopilot_production_script_has_no_v457_path_issue' (-not (@($valid.Verify.issues) -match 'first_slice_proof_v457_invalid_file_path')) ($valid.Verify | ConvertTo-Json -Depth 8)

    $testScriptFixture = New-PlanFixture -Name 'invalid-test-script' -TargetCarrierFilePath 'replay-autopilot/scripts/tests/Test-v716-Fixture.ps1'
    $invalid = Invoke-PlanContract -ReplayRoot $testScriptFixture.ReplayRoot -Worktree $testScriptFixture.Worktree
    Assert-True 'autopilot_test_script_exits_nonzero' ($invalid.ExitCode -ne 0) "exit=$($invalid.ExitCode) output=$($invalid.Output)"
    Assert-True 'autopilot_test_script_rejected_as_invalid_carrier' (@($invalid.Verify.issues) -contains 'first_slice_proof_v457_invalid_file_path:replay-autopilot/scripts/tests/Test-v716-Fixture.ps1') ($invalid.Verify | ConvertTo-Json -Depth 8)

    [ordered]@{
        status = 'PASS'
        version = 'v716'
        assertions = @(
            'autopilot_production_script_exits_zero',
            'autopilot_production_script_contract_passes',
            'autopilot_production_script_has_no_v457_path_issue',
            'autopilot_test_script_exits_nonzero',
            'autopilot_test_script_rejected_as_invalid_carrier'
        )
    } | ConvertTo-Json -Depth 5
    exit 0
} catch {
    [ordered]@{
        status = 'FAIL'
        version = 'v716'
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 5
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
