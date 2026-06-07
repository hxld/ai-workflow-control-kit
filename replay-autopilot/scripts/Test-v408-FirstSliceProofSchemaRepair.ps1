# v408: First Slice Proof Schema Repair Test
# Tests that the verifier auto-repairs common AI deviations in FIRST_SLICE_PROOF_PLAN.md
# Specifically handles **Test:** -> first_red_test: normalization

param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

function New-ValidReplayRoot {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    Write-Text (Join-Path $Root 'EXPLORATION_REPORT.md') @"
# Exploration Report

## source boundary
## requirement literal inventory
## candidate surface map
## uncertainty ledger
"@
    Write-Text (Join-Path $Root 'ROUND_CONTRACT.md') @"
# Round Contract

## Requirement Family Ledger
## Real Entry Discovery Matrix
## Expected Diff Matrix
## Behavior Test Charter
## Critical Surface Allocation Plan
## side-effect ledger
## coverage cap
"@
    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') @"
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: RealEntry.execute
- first_executable_slice: S1
"@
    Write-Text (Join-Path $Root 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: core-stateful-balanced
- first_slice: S1
- selected_real_entry: RealEntry.execute
- carrier_search: performed
- carrier_search_queries: rg "RealEntry", rg "ProductionBehavior", rg "execute"
- existing_production_carriers: RealEntry.execute, ProductionBehavior.apply
- selected_carrier_from_search: RealEntry.execute
- new_service_proposed: false
- new_service_justification: none
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 3/3
"@
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_1.md') '# Candidate 1'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_2.md') '# Candidate 2'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_3.md') '# Candidate 3'
    Write-Text (Join-Path $Root 'PLAN_SELECTION.md') '# Plan Selection'
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') @"
# Replay Plan

## Slice S1
- core_entry
- stateful_side_effect
"@
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @"
# Implementation Contract

- selected_real_entry: RealEntry.execute
- first_slice: S1
- shallow_green_is_forbidden: true
"@
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') @"
# Expected Diff Matrix

| requirement | validation | closure |
|---|---|---|
| sample | RED/GREEN | src/main/java/sample/RealEntry.java |
"@
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') @"
# Side Effect Ledger

state task progress log transaction validation closure
"@
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') @"
# Test Charter

RED then GREEN
"@
    Write-Text (Join-Path $Root 'FAMILY_CONTRACT.json') @"
{
    "schema_version": 1,
    "families": [
        {"id": "core_entry", "required": true},
        {"id": "stateful_side_effect", "required": true}
    ]
}
"@
    Write-Text (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') @"
{
    "schema_version": 1,
    "production_files": 3,
    "high_weight_files": 3,
    "files": [
        {"path": "src/main/java/sample/RealEntry.java", "weight": "HIGH", "is_production": true},
        {"path": "src/main/java/sample/ProductionBehavior.java", "weight": "HIGH", "is_production": true},
        {"path": "src/main/resources/sample/real-entry.xml", "weight": "HIGH", "is_production": true}
    ]
}
"@
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- selected_real_entry: RealEntry.execute
- highest_weight_open_gate: core_entry
- target_subsurface_or_carrier: core post-result entry
- selected_carrier: RealEntry.execute
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production_boundary: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected_production_diff: add minimum behavior behind existing entry
- proof_kind: real_entry_behavior
- forbidden_substitute_proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: none
- fail_closed_condition: missing carrier or no RED stops Phase 1
- coverage_cap_if_not_closed: 60

## RED Expectation

**red_expectation:** real entry fails before production change

**Test:** RealEntryContractTest

## GREEN Minimum Implementation

**green_minimum_implementation:** real entry passes without substitute carrier
"@
}

function Invoke-Contract {
    param([string]$Root, [string]$ExpectedStatus)
    # Use direct invocation instead of -File to avoid exit code 255 issue
    $output = & $script:contractVerifier -ReplayRoot $Root -Stage Plan | Out-String
    $exit = $LASTEXITCODE
    # Check if verification passed by parsing the output
    if ($output -match '"verification_status":\s*"PASS"') {
        $actualStatus = 'PASS'
    } else {
        $actualStatus = 'FAIL'
    }
    if ($actualStatus -ne $ExpectedStatus) {
        throw "Expected Plan contract $ExpectedStatus for $Root but got $actualStatus (exit code: $exit, output: $output)"
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$script:contractVerifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path $scriptRoot ('.tmp\plan-contracts-v408-{0}' -f $PID)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        verifier = $script:contractVerifier
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

# Test 1: **Test:** should be auto-repaired to first_red_test: in FIRST_SLICE_PROOF_PLAN.md
$testProofRepairRoot = Join-Path $tempRoot 'proof-repair-test-format'
New-ValidReplayRoot -Root $testProofRepairRoot
Invoke-Contract -Root $testProofRepairRoot -ExpectedStatus PASS
# Verify the repair happened
$proofContent = Get-Content -LiteralPath (Join-Path $testProofRepairRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8
if ($proofContent -notmatch '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_red_test\s*\*{0,2}\s*[:=|]') {
    throw "Expected first_red_test: to be auto-repaired from **Test:** but not found in FIRST_SLICE_PROOF_PLAN.md"
}
if ($proofContent -match '(?m)^\s*\*{0,2}Test\*{0,2}\s*[:=|]\s*(.+?)\s*$') {
    throw "Expected **Test:** to be replaced with first_red_test: but still found"
}
# Also verify PLAN_RESULT.md was updated
$planContent = Get-Content -LiteralPath (Join-Path $testProofRepairRoot 'PLAN_RESULT.md') -Raw -Encoding UTF8
if ($planContent -notmatch '(?m)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?first_red_test\s*\*{0,2}\s*[:=|]') {
    throw "Expected first_red_test: to be auto-repaired in PLAN_RESULT.md"
}

# Test 2: ### RED Expectation ... **Test:** format should also be repaired
$redHeadingRoot = Join-Path $tempRoot 'red-heading-format'
New-ValidReplayRoot -Root $redHeadingRoot
$proofContent = Get-Content -LiteralPath (Join-Path $redHeadingRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8
$proofContent = $proofContent -replace '(?m)^(## RED Expectation)', '### RED Expectation'
Set-Content -LiteralPath (Join-Path $redHeadingRoot 'FIRST_SLICE_PROOF_PLAN.md') -Value $proofContent -Encoding UTF8
Invoke-Contract -Root $redHeadingRoot -ExpectedStatus PASS

[ordered]@{
    status = 'PASS'
    cases = @('proof_repair_test_format', 'red_heading_format')
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
