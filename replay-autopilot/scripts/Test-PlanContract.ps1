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

function Write-FamilyContract {
    param([string]$Path)
    $families = @(
        'core_entry',
        'stateful_side_effect',
        'deploy_export_page',
        'wire_payload_api_contract',
        'config_policy_threshold',
        'generated_artifact_template_upload',
        'external_integration',
        'automation_test_interface',
        'lifecycle_cleanup_retention'
    ) | ForEach-Object {
        [ordered]@{
            id = $_
            required = $true
            weight = 80
            first_executable_carrier = "$_.carrier"
            planned_slice = 'S1'
            proof_required = @('RED', 'GREEN', 'executable proof')
            forbidden_proof = @('helper_only', 'static_only', 'mock_only')
            coverage_cap_if_open = 60
        }
    }
    [ordered]@{
        schema_version = 1
        source_boundary = [ordered]@{}
        selected_real_entry = 'RealEntry.execute'
        first_executable_slice = 'S1'
        families = @($families)
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-OracleAnalysis {
    param([string]$Path)
    [ordered]@{
        schema_version = 1
        production_files = 3
        high_weight_files = 3
        files = @(
            [ordered]@{
                path = 'src/main/java/sample/RealEntry.java'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
            },
            [ordered]@{
                path = 'src/main/java/sample/ProductionBehavior.java'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
            },
            [ordered]@{
                path = 'src/main/resources/sample/real-entry.xml'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-ValidReplayRoot {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $familyList = @(
        'core_entry',
        'stateful_side_effect',
        'deploy_export_page',
        'wire_payload_api_contract',
        'config_policy_threshold',
        'generated_artifact_template_upload',
        'external_integration',
        'automation_test_interface',
        'lifecycle_cleanup_retention'
    ) -join "`n"

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
$familyList

## Real Entry Discovery Matrix
## Expected Diff Matrix
## Behavior Test Charter
## Critical Surface Allocation Plan
## side-effect ledger
## coverage cap
"@
    Write-FamilyContract (Join-Path $Root 'FAMILY_CONTRACT.json')
    Write-OracleAnalysis (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json')
    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') @"
# Phase 0 Result

- phase0_status: PROCEED
- selected_real_entry: RealEntry.execute
- first_executable_slice: S1
- family_contract: $Root\FAMILY_CONTRACT.json
- first_slice_type: core_path
"@
    Write-Text (Join-Path $Root 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: core-stateful-balanced
- first_slice: S1
- first_red_test: RealEntryContractTest
- required_files: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 3/3
- carrier_search: performed
- carrier_search_queries: rg "RealEntry", rg "ProductionBehavior", rg "execute"
- existing_production_carriers: RealEntry.execute, ProductionBehavior.apply
- selected_carrier_from_search: RealEntry.execute
- new_service_proposed: false
- new_service_justification: none
"@
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_1.md') '# Candidate 1'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_2.md') '# Candidate 2'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_3.md') '# Candidate 3'
    Write-Text (Join-Path $Root 'PLAN_SELECTION.md') '# Plan Selection'
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') @"
# Replay Plan

$familyList

S1 core slice:
- src/main/java/sample/RealEntry.java
- src/main/java/sample/ProductionBehavior.java
- src/main/resources/sample/real-entry.xml
"@
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @"
# Implementation Contract

- selected_real_entry: RealEntry.execute
- first_slice: S1
- first_red_test: RealEntryContractTest
- selected real entry: RealEntry.execute
- shallow green is forbidden
"@
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') @"
# Expected Diff Matrix

| requirement | validation | closure |
|---|---|---|
| sample | RED/GREEN | src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml |
"@
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') @"
# Side Effect Ledger

state task progress log transaction
"@
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') @"
# Test Charter

RED then GREEN
"@
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: RealEntryContractTest
- selected_real_entry: RealEntry.execute
- highest_weight_open_gate: core_entry
- target family: core_entry
- target_subsurface_or_carrier: core post-result entry
- selected_carrier: RealEntry.execute
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production_boundary: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected production diff: add minimum behavior behind existing entry
- RED assertion: real entry fails before production change
- GREEN minimum implementation: real entry passes without substitute carrier
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: none
- fail_closed_condition: missing carrier or no RED stops Phase 1
- coverage cap if not closed: 60
"@
}

function Invoke-Contract {
    param([string]$Root, [string]$Stage, [string]$ExpectedStatus)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script:contractVerifier -ReplayRoot $Root -Stage $Stage | Out-Null
    $exit = $LASTEXITCODE
    $actualStatus = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
    if ($actualStatus -ne $ExpectedStatus) {
        throw "Expected $Stage contract $ExpectedStatus for $Root but got $actualStatus"
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$script:contractVerifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path $scriptRoot ('.tmp\plan-contracts-{0}' -f $PID)
$planPrompt = Join-Path $scriptRoot 'prompts\phase-plan-tournament.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        verifier = $script:contractVerifier
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

$planPromptText = Get-Content -LiteralPath $planPrompt -Raw -Encoding UTF8
foreach ($requiredPromptToken in @('`first_slice:`', '`first_red_test:`', '`selected_real_entry:`', '`selected_carrier:`', '`target_subsurface_or_carrier:`', '`real_carrier_kind:`', '`minimum_side_effect_or_blocker:`', '`forbidden_substitute_check:`')) {
    if ($planPromptText.IndexOf($requiredPromptToken, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Plan prompt missing required first-slice schema token $requiredPromptToken"
    }
}

$validRoot = Join-Path $tempRoot 'valid'
New-ValidReplayRoot -Root $validRoot
Invoke-Contract -Root $validRoot -Stage Phase0 -ExpectedStatus PASS
Invoke-Contract -Root $validRoot -Stage Plan -ExpectedStatus PASS

$phase0NoExpectedDiffRoot = Join-Path $tempRoot 'phase0-no-expected-diff'
New-ValidReplayRoot -Root $phase0NoExpectedDiffRoot
(Get-Content -LiteralPath (Join-Path $phase0NoExpectedDiffRoot 'ROUND_CONTRACT.md') -Raw -Encoding UTF8).Replace("## Expected Diff Matrix`r`n", '').Replace("## Expected Diff Matrix`n", '') |
    Set-Content -LiteralPath (Join-Path $phase0NoExpectedDiffRoot 'ROUND_CONTRACT.md') -Encoding UTF8
Invoke-Contract -Root $phase0NoExpectedDiffRoot -Stage Phase0 -ExpectedStatus PASS

$missingFamilyRoot = Join-Path $tempRoot 'missing-family-contract'
New-ValidReplayRoot -Root $missingFamilyRoot
Remove-Item -LiteralPath (Join-Path $missingFamilyRoot 'FAMILY_CONTRACT.json') -Force
Invoke-Contract -Root $missingFamilyRoot -Stage Phase0 -ExpectedStatus FAIL

$missingRedRoot = Join-Path $tempRoot 'missing-first-red'
New-ValidReplayRoot -Root $missingRedRoot
Write-Text (Join-Path $missingRedRoot 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: missing-red
- first_slice: S1
- first_red_test:
"@
Invoke-Contract -Root $missingRedRoot -Stage Plan -ExpectedStatus FAIL

$missingCandidateRoot = Join-Path $tempRoot 'missing-candidates'
New-ValidReplayRoot -Root $missingCandidateRoot
Remove-Item -LiteralPath (Join-Path $missingCandidateRoot 'PLAN_CANDIDATE_1.md') -Force
Invoke-Contract -Root $missingCandidateRoot -Stage Plan -ExpectedStatus FAIL

$missingCarrierSearchRoot = Join-Path $tempRoot 'missing-carrier-search'
New-ValidReplayRoot -Root $missingCarrierSearchRoot
$missingCarrierPlan = (Get-Content -LiteralPath (Join-Path $missingCarrierSearchRoot 'PLAN_RESULT.md') -Raw -Encoding UTF8) -replace '(?m)^- carrier_search:.*\r?\n', '' -replace '(?m)^- carrier_search_queries:.*\r?\n', '' -replace '(?m)^- existing_production_carriers:.*\r?\n', '' -replace '(?m)^- selected_carrier_from_search:.*\r?\n', ''
Set-Content -LiteralPath (Join-Path $missingCarrierSearchRoot 'PLAN_RESULT.md') -Encoding UTF8 -Value $missingCarrierPlan
Invoke-Contract -Root $missingCarrierSearchRoot -Stage Plan -ExpectedStatus FAIL

$unjustifiedNewServiceRoot = Join-Path $tempRoot 'unjustified-new-service'
New-ValidReplayRoot -Root $unjustifiedNewServiceRoot
$unjustifiedPlan = Get-Content -LiteralPath (Join-Path $unjustifiedNewServiceRoot 'PLAN_RESULT.md') -Raw -Encoding UTF8
$unjustifiedPlan = $unjustifiedPlan.Replace('- selected_carrier_from_search: RealEntry.execute', '- selected_carrier_from_search: NewPlaceholderService')
$unjustifiedPlan = $unjustifiedPlan.Replace('- new_service_proposed: false', '- new_service_proposed: true')
$unjustifiedPlan = $unjustifiedPlan.Replace('- new_service_justification: none', '- new_service_justification: for easier testing')
Set-Content -LiteralPath (Join-Path $unjustifiedNewServiceRoot 'PLAN_RESULT.md') -Encoding UTF8 -Value $unjustifiedPlan
Invoke-Contract -Root $unjustifiedNewServiceRoot -Stage Plan -ExpectedStatus FAIL

$alternateProofRoot = Join-Path $tempRoot 'alternate-proof-format'
New-ValidReplayRoot -Root $alternateProofRoot
Write-Text (Join-Path $alternateProofRoot 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: core-stateful-balanced
- first_slice: S1 - core entry and config contract
- first_red_test: processor-level RED without fixed method token
- required_files: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 3/3
- carrier_search: performed
- carrier_search_queries: rg "RealEntry", rg "ProductionBehavior", rg "execute"
- existing_production_carriers: RealEntry.execute, ProductionBehavior.apply
- selected_carrier_from_search: RealEntry.execute
- new_service_proposed: false
- new_service_justification: none
"@
Write-Text (Join-Path $alternateProofRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: processor-level RED at real entry
- selected_real_entry: RealEntry.execute
- target_family: core_entry
- highest_weight_open_gate: core_entry
- target_subsurface_or_carrier: core post-result entry
- selected_carrier: RealEntry.execute
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production_boundary: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected production diff: add minimum behavior behind existing entry
- RED assertion: real entry fails before production change
- GREEN minimum implementation: real entry passes without substitute carrier
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: none
- fail_closed_condition: missing carrier or no RED stops Phase 1
- coverage cap if not closed: 60
"@
Invoke-Contract -Root $alternateProofRoot -Stage Plan -ExpectedStatus PASS

$definitionListProofRoot = Join-Path $tempRoot 'definition-list-proof-format'
New-ValidReplayRoot -Root $definitionListProofRoot
Write-Text (Join-Path $definitionListProofRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

first_slice:
: S1

first_red_test:
: RealEntryContractTest

selected_real_entry:
: RealEntry.execute

highest_weight_open_gate:
: core_entry

selected_carrier:
: RealEntry.execute

real_carrier_kind:
: production_entry_or_service

minimum_side_effect_or_blocker:
: real entry calls production behavior and proves output side effect

forbidden_substitute_check:
: passed

target_subsurface_or_carrier:
: core post-result entry

production_boundary:
: existing entry calls production behavior

public_entry_contract_coverage:
: RealEntry.execute is the public entry that calls production behavior

expected_production_diff:
: add minimum behavior behind existing entry

red_expectation:
: real entry fails before production change

green_minimum_implementation:
: real entry passes without substitute carrier

proof_kind:
: real_entry_behavior and stateful_side_effect

forbidden_substitute_proof:
: helper_only static_presence dto_only compile_only

required_sibling_surfaces:
: none

fail_closed_condition:
: missing carrier or no RED stops Phase 1

coverage_cap_if_not_closed:
: 60
"@
Invoke-Contract -Root $definitionListProofRoot -Stage Plan -ExpectedStatus PASS

$conditionalBlockerPhraseRoot = Join-Path $tempRoot 'conditional-blocker-phrase'
New-ValidReplayRoot -Root $conditionalBlockerPhraseRoot
Write-Text (Join-Path $conditionalBlockerPhraseRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: RealEntryContractTest
- selected_real_entry: RealEntry.execute
- highest_weight_open_gate: core_entry
- selected_carrier: RealEntry.execute
- target_subsurface_or_carrier: core post-result entry
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: real entry calls production behavior; if unavailable then PLAN_BLOCKED_REAL_CARRIER
- forbidden_substitute_check: passed
- production_boundary: existing entry calls production behavior
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected_production_diff: add minimum behavior behind existing entry
- red_expectation: real entry fails before production change
- green_minimum_implementation: real entry passes without substitute carrier
- proof_kind: real_entry_behavior
- forbidden_substitute_proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: none
- fail_closed_condition: missing carrier or no RED stops Phase 1
- coverage_cap_if_not_closed: 60
- coverage_cap_if_missing: 60
"@
Invoke-Contract -Root $conditionalBlockerPhraseRoot -Stage Plan -ExpectedStatus PASS

$missingFirstSliceProofRoot = Join-Path $tempRoot 'missing-first-slice-proof'
New-ValidReplayRoot -Root $missingFirstSliceProofRoot
Remove-Item -LiteralPath (Join-Path $missingFirstSliceProofRoot 'FIRST_SLICE_PROOF_PLAN.md') -Force
Invoke-Contract -Root $missingFirstSliceProofRoot -Stage Plan -ExpectedStatus FAIL

$staticFirstSliceProofRoot = Join-Path $tempRoot 'static-first-slice-proof'
New-ValidReplayRoot -Root $staticFirstSliceProofRoot
Write-Text (Join-Path $staticFirstSliceProofRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: RealEntryContractTest
- selected_real_entry: RealEntry.execute
- target family: core_entry
- target sibling/surface: core post-result entry
- existing production carrier: RealEntry.execute
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production boundary: existing entry calls production behavior
- expected production diff: add minimum behavior behind existing entry
- RED assertion: constant missing
- GREEN minimum implementation: add constant
- proof_kind: static_presence
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- fail-closed condition: missing carrier or no RED stops Phase 1
- coverage cap if not closed: 60
"@
Invoke-Contract -Root $staticFirstSliceProofRoot -Stage Plan -ExpectedStatus FAIL

$substituteCarrierKindRoot = Join-Path $tempRoot 'substitute-carrier-kind'
New-ValidReplayRoot -Root $substituteCarrierKindRoot
Write-Text (Join-Path $substituteCarrierKindRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: RealEntryContractTest
- selected_real_entry: RealEntry.execute
- target family: core_entry
- target sibling/surface: core post-result entry
- existing production carrier: RealEntry.execute
- real_carrier_kind: protected_hook
- minimum_side_effect_or_blocker: only subclass counter
- forbidden_substitute_check: failed:protected_hook
- production boundary: existing entry calls production behavior
- expected production diff: add minimum behavior behind existing entry
- RED assertion: constant missing
- GREEN minimum implementation: add constant
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- fail-closed condition: missing carrier or no RED stops Phase 1
- coverage cap if not closed: 60
"@
Invoke-Contract -Root $substituteCarrierKindRoot -Stage Plan -ExpectedStatus FAIL

[ordered]@{
    status = 'PASS'
    cases = @('plan_prompt_first_slice_schema_tokens', 'phase0_valid', 'plan_valid', 'phase0_expected_diff_deferred_to_plan', 'phase0_missing_family_contract_fails', 'plan_missing_first_red_fails', 'plan_missing_candidate_fails', 'plan_missing_carrier_search_fails', 'plan_unjustified_new_service_fails', 'plan_alternate_first_slice_proof_format_passes', 'plan_definition_list_first_slice_proof_format_passes', 'plan_conditional_blocker_phrase_passes', 'plan_missing_first_slice_proof_fails', 'plan_static_first_slice_proof_fails', 'plan_substitute_carrier_kind_fails')
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
