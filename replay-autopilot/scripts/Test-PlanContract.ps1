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

function Write-PolicyRebuildOracleAnalysis {
    param([string]$Path)
    [ordered]@{
        schema_version = 1
        production_files = 2
        high_weight_files = 2
        files = @(
            [ordered]@{
                path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
            },
            [ordered]@{
                path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-PolicyRebuildSourceChainContract {
    param([string]$Root)
    [ordered]@{
        required_source_chain = $true
        source_chain_mode = 'task_processor_rebuild'
        next_required_slice = [ordered]@{
            entry = 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)'
            carrier = 'RequestBuildContext.policyNum/insureNum -> RequestBuildFunction -> request -> taskData'
            slice_type = 'exact_contract_slice'
            test_name = 'ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum'
            must_touch_files = @(
                'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java',
                'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'
            )
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') -Encoding UTF8
    Write-PolicyRebuildOracleAnalysis (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json')
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
- target_carrier_file_path: src/main/java/sample/RealEntry.java
- target_carrier_line_number: 42
- expected_test_class: RealEntryContractTest
- expected_test_method: provesRealEntryOutput
- expected_assertions: output side effect is written, public entry delegates once, unrelated helper path is not used
- expected_side_effects: real entry calls production behavior and emits output side effect
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production_boundary: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected_production_diff: add minimum behavior behind existing RealEntry.execute and ProductionBehavior
- red_expectation: RealEntryContractTest.provesRealEntryOutput fails on missing output side effect
- green_minimum_implementation: RealEntry.execute writes the output side effect through ProductionBehavior
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
- target_carrier_file_path: src/main/java/sample/RealEntry.java
- target_carrier_line_number: 42
- expected_test_class: RealEntryContractTest
- expected_test_method: provesRealEntryOutput
- expected_assertions: output side effect is written, public entry delegates once, unrelated helper path is not used
- expected_side_effects: real entry calls production behavior and emits output side effect
- minimum_side_effect_or_blocker: real entry calls production behavior and proves output side effect
- forbidden_substitute_check: passed
- production_boundary: src/main/java/sample/RealEntry.java, src/main/java/sample/ProductionBehavior.java, src/main/resources/sample/real-entry.xml
- public_entry_contract_coverage: RealEntry.execute is the public entry that calls production behavior
- expected_production_diff: add minimum behavior behind existing RealEntry.execute and ProductionBehavior
- red_expectation: RealEntryContractTest.provesRealEntryOutput fails on missing output side effect
- green_minimum_implementation: RealEntry.execute writes the output side effect through ProductionBehavior
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

target_carrier_file_path:
: src/main/java/sample/RealEntry.java

target_carrier_line_number:
: 42

expected_test_class:
: RealEntryContractTest

expected_test_method:
: provesRealEntryOutput

expected_assertions:
: output side effect is written, public entry delegates once, unrelated helper path is not used

expected_side_effects:
: real entry calls production behavior and emits output side effect

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
- target_carrier_file_path: src/main/java/sample/RealEntry.java
- target_carrier_line_number: 42
- expected_test_class: RealEntryContractTest
- expected_test_method: provesRealEntryOutput
- expected_assertions: output side effect is written, public entry delegates once, unrelated helper path is not used
- expected_side_effects: real entry calls production behavior and emits output side effect
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

$policyRebuildValidRoot = Join-Path $tempRoot 'policy-rebuild-source-chain-valid'
New-ValidReplayRoot -Root $policyRebuildValidRoot
Add-PolicyRebuildSourceChainContract -Root $policyRebuildValidRoot
Write-Text (Join-Path $policyRebuildValidRoot 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: policy-rebuild-source-chain
- first_slice: S1
- first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java#testRebuildTaskData_PreservesPolicyNumAndInsureNum
- required_files: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 2/2
- carrier_search: performed
- carrier_search_queries: rg "rebuildTaskData", rg "RequestBuildContext", rg "buildRequestCommon"
- existing_production_carriers: ExampleApplyClaimApiTaskProcessor.rebuildTaskData, ExampleCalculatorApiTaskProcessor.rebuildTaskData
- selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
- new_service_proposed: false
- new_service_justification: none
"@
Write-Text (Join-Path $policyRebuildValidRoot 'REPLAY_PLAN.md') @"
# Replay Plan

core_entry
stateful_side_effect
deploy_export_page
wire_payload_api_contract
config_policy_threshold
generated_artifact_template_upload
external_integration
automation_test_interface
lifecycle_cleanup_retention

S1 policyNum/insureNum rebuild source-chain:
- ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)
- ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
- example-server/src/test/java harness
- mvn --% -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl example-server -am -Dtest=ExampleApplyClaimApiTaskProcessorTest#testRebuildTaskData_PreservesPolicyNumAndInsureNum -Dsurefire.failIfNoSpecifiedTests=false test
"@
Write-Text (Join-Path $policyRebuildValidRoot 'IMPLEMENTATION_CONTRACT.md') @"
# Implementation Contract

- selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
- first_slice: S1
- first_red_test: ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum
- selected real entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData and ExampleCalculatorApiTaskProcessor.rebuildTaskData
- shallow green is forbidden
"@
Write-Text (Join-Path $policyRebuildValidRoot 'EXPECTED_DIFF_MATRIX.md') @"
# Expected Diff Matrix

| requirement | validation | closure |
|---|---|---|
| policyNum/insureNum source-chain rebuild | RED/GREEN deterministic RequestBuildContext test | add req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum()) in both processor builder lambdas |
"@
Write-Text (Join-Path $policyRebuildValidRoot 'TEST_CHARTER.md') @"
# Test Charter

RED then GREEN.

Test file: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java
Command: mvn --% -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl example-server -am -Dtest=ExampleApplyClaimApiTaskProcessorTest#testRebuildTaskData_PreservesPolicyNumAndInsureNum -Dsurefire.failIfNoSpecifiedTests=false test

The RED mocks ExampleDataAssemblyHelper.buildRequestCommon, captures ExampleDataAssemblyHelper.RequestBuildFunction, creates RequestBuildContext with policyNum and insureNum, invokes the captured builder, and asserts the request created from context preserves both fields before taskData is returned.
"@
Write-Text (Join-Path $policyRebuildValidRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java#testRebuildTaskData_PreservesPolicyNumAndInsureNum
- selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId) and ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
- highest_weight_open_gate: core_entry
- target family: core_entry
- target_subsurface_or_carrier: TaskProcessor rebuild source-chain
- selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData and ExampleCalculatorApiTaskProcessor.rebuildTaskData
- real_carrier_kind: production_entry_or_service
- target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
- target_carrier_line_number: 404
- expected_test_class: ExampleApplyClaimApiTaskProcessorTest
- expected_test_method: testRebuildTaskData_PreservesPolicyNumAndInsureNum
- expected_assertions: RequestBuildContext policyNum reaches apply request, RequestBuildContext insureNum reaches apply request, RequestBuildContext policyNum reaches calculate request, RequestBuildContext insureNum reaches calculate request
- expected_side_effects: rebuilt task data carries context-derived policyNum and insureNum
- minimum_side_effect_or_blocker: RequestBuildContext -> ExampleDataAssemblyHelper.RequestBuildFunction -> request -> rebuilt task data
- forbidden_substitute_check: passed
- production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
- public_entry_contract_coverage: existing TaskProcessor private rebuild path is invoked deterministically through reflection without Spring context
- expected_production_diff: add req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum()) in both processor builder lambdas
- red_expectation: captured ExampleDataAssemblyHelper.RequestBuildFunction applied to RequestBuildContext creates request without policyNum/insureNum on baseline
- green_minimum_implementation: both builders copy RequestBuildContext policyNum/insureNum into request
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
- fail_closed_condition: missing RequestBuildFunction or example-server -pl example-server -am command stops Phase 1
- coverage cap if not closed: 60
"@
Invoke-Contract -Root $policyRebuildValidRoot -Stage Plan -ExpectedStatus PASS

$policyRebuildInvalidRoot = Join-Path $tempRoot 'policy-rebuild-source-chain-invalid'
New-ValidReplayRoot -Root $policyRebuildInvalidRoot
Add-PolicyRebuildSourceChainContract -Root $policyRebuildInvalidRoot
Write-Text (Join-Path $policyRebuildInvalidRoot 'TEST_CHARTER.md') @"
# Test Charter

RED then GREEN.

Command: mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl example-core -Dtest=ExampleApplyClaimApiTaskProcessorTest#testTaskData_hasPolicyNumAndInsureNumFields test

Use fixed database caseId 12345L. If taskData == null, print a warning and pass. Only verify DTO getter/setter field existence and the downstream taskData.setPolicyNum(request.getPolicyNum()) line.
"@
Write-Text (Join-Path $policyRebuildInvalidRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: example-core/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java#testTaskData_hasPolicyNumAndInsureNumFields
- selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)
- highest_weight_open_gate: core_entry
- target family: core_entry
- target_subsurface_or_carrier: TaskProcessor rebuild source-chain
- selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
- real_carrier_kind: production_entry_or_service
- target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
- target_carrier_line_number: 404
- expected_test_class: ExampleApplyClaimApiTaskProcessorTest
- expected_test_method: testTaskData_hasPolicyNumAndInsureNumFields
- expected_assertions: DTO getter/setter exists, field existence only, downstream setter line exists
- expected_side_effects: none
- minimum_side_effect_or_blocker: DTO getter/setter existence
- forbidden_substitute_check: passed
- production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
- public_entry_contract_coverage: private method reflection
- expected_production_diff: none
- red_expectation: not applicable
- green_minimum_implementation: taskData.setPolicyNum(request.getPolicyNum())
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: missing
- fail_closed_condition: none
- coverage cap if not closed: 60
"@
Invoke-Contract -Root $policyRebuildInvalidRoot -Stage Plan -ExpectedStatus FAIL

$missingCarrierFileRoot = Join-Path $tempRoot 'missing-carrier-file'
New-ValidReplayRoot -Root $missingCarrierFileRoot
New-Item -ItemType Directory -Force -Path (Join-Path $missingCarrierFileRoot 'worktree\src\main\java\sample') | Out-Null
Invoke-Contract -Root $missingCarrierFileRoot -Stage Plan -ExpectedStatus FAIL
$missingCarrierFileVerify = Get-Content -LiteralPath (Join-Path $missingCarrierFileRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (((@($missingCarrierFileVerify.issues) -join ' ') -notmatch 'first_slice_proof_v457_file_not_found')) {
    throw 'Expected missing carrier file proof issue'
}

$powerShellCarrierRoot = Join-Path $tempRoot 'powershell-control-plane-carrier'
New-ValidReplayRoot -Root $powerShellCarrierRoot
$powerShellCarrierWorktree = Join-Path $powerShellCarrierRoot 'worktree'
$powerShellCarrierRel = 'replay-autopilot/scripts/Invoke-SliceSchemaFailFast.ps1'
$powerShellCarrierFull = Join-Path $powerShellCarrierWorktree $powerShellCarrierRel
Write-Text $powerShellCarrierFull 'function Invoke-SliceSchemaFailFast { return $true }'
Write-Text (Join-Path $powerShellCarrierRoot 'PLAN_RESULT.md') @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1
- selected_strategy: replay-autopilot-control-plane
- first_slice: S1
- first_red_test: Test-v687-ControlPlanePowerShellHarness
- required_files: $powerShellCarrierRel
- oracle_production_file_overlap: 100
- oracle_high_weight_coverage: 1/1
- carrier_search: performed
- carrier_search_queries: rg "Invoke-SliceSchemaFailFast", rg "ControlPlanePowerShellHarness", rg "replay-autopilot/scripts"
- existing_production_carriers: ${powerShellCarrierRel}:12 Invoke-SliceSchemaFailFast
- selected_carrier_from_search: ${powerShellCarrierRel}:12 Invoke-SliceSchemaFailFast
- new_service_proposed: false
- new_service_justification: none
"@
Write-Text (Join-Path $powerShellCarrierRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- first_slice: S1
- first_red_test: Test-v687-ControlPlanePowerShellHarness
- selected_real_entry: $powerShellCarrierRel
- highest_weight_open_gate: automation_test_interface
- target family: automation_test_interface
- target_subsurface_or_carrier: replay-autopilot control-plane schema gate
- selected_carrier: $powerShellCarrierRel
- real_carrier_kind: production_entry_or_service
- target_carrier_file_path: ${powerShellCarrierRel}:12
- target_carrier_line_number: 12
- expected_test_class: Test-v687-ControlPlanePowerShellHarness
- expected_test_method: plan_verifier_accepts_powershell_control_plane_carrier
- expected_assertions: PowerShell carrier path is accepted, non-production test script path is rejected, missing control-plane script is rejected
- expected_side_effects: plan verifier allows replay-autopilot control-plane production script to advance to executable tests
- minimum_side_effect_or_blocker: plan verifier accepts an existing replay-autopilot control-plane production script and keeps file existence checking active
- forbidden_substitute_check: passed
- production_boundary: $powerShellCarrierRel
- public_entry_contract_coverage: replay-autopilot control-plane script is the real runner/verifier entry being evolved
- expected_production_diff: update Verify-PlanContract.ps1 v457 target_carrier_file_path validation for replay-autopilot control-plane scripts
- red_expectation: Test-v687-ControlPlanePowerShellHarness fails before the verifier accepts control-plane PowerShell carriers
- green_minimum_implementation: Verify-PlanContract.ps1 accepts replay-autopilot/scripts/*.ps1 production carriers while rejecting scripts/tests/*.ps1
- proof_kind: real_entry_behavior
- forbidden substitute proof: helper_only static_presence dto_only compile_only
- required_sibling_surfaces: none
- fail_closed_condition: missing carrier file or test-script carrier path stops Plan
- coverage cap if not closed: 60
"@
& powershell -NoProfile -ExecutionPolicy Bypass -File $script:contractVerifier -ReplayRoot $powerShellCarrierRoot -Stage Plan -Worktree $powerShellCarrierWorktree -SkipCarrierAndOracleChecks | Out-Null
if ($LASTEXITCODE -ne 0) {
    $powerShellCarrierVerify = Get-Content -LiteralPath (Join-Path $powerShellCarrierRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    throw "Expected replay-autopilot PowerShell carrier path to pass v457 validation; issues=$(@($powerShellCarrierVerify.issues) -join ';')"
}
$powerShellCarrierVerify = Get-Content -LiteralPath (Join-Path $powerShellCarrierRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (((@($powerShellCarrierVerify.issues) -join ' ') -match 'first_slice_proof_v457_(invalid_file_path|file_not_found)')) {
    throw "PowerShell control-plane carrier should not trip v457 path issues; issues=$(@($powerShellCarrierVerify.issues) -join ';')"
}

$testScriptCarrierRoot = Join-Path $tempRoot 'powershell-test-script-not-carrier'
New-ValidReplayRoot -Root $testScriptCarrierRoot
$testScriptWorktree = Join-Path $testScriptCarrierRoot 'worktree'
$testScriptRel = 'replay-autopilot/scripts/tests/Test-v687-ControlPlanePowerShellHarness.ps1'
Write-Text (Join-Path $testScriptWorktree $testScriptRel) 'Write-Host "PASS"'
$testScriptProof = (Get-Content -LiteralPath (Join-Path $testScriptCarrierRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8) -replace 'src/main/java/sample/RealEntry\.java', $testScriptRel
Set-Content -LiteralPath (Join-Path $testScriptCarrierRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8 -Value $testScriptProof
& powershell -NoProfile -ExecutionPolicy Bypass -File $script:contractVerifier -ReplayRoot $testScriptCarrierRoot -Stage Plan -Worktree $testScriptWorktree -SkipCarrierAndOracleChecks | Out-Null
$testScriptCarrierVerify = Get-Content -LiteralPath (Join-Path $testScriptCarrierRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (((@($testScriptCarrierVerify.issues) -join ' ') -notmatch 'first_slice_proof_v457_invalid_file_path')) {
    throw 'Expected replay-autopilot scripts/tests PowerShell path to remain invalid as a production carrier'
}

$missingPowerShellCarrierRoot = Join-Path $tempRoot 'missing-powershell-control-plane-carrier'
New-ValidReplayRoot -Root $missingPowerShellCarrierRoot
$missingPowerShellWorktree = Join-Path $missingPowerShellCarrierRoot 'worktree'
New-Item -ItemType Directory -Force -Path (Join-Path $missingPowerShellWorktree 'replay-autopilot\scripts') | Out-Null
$missingPowerShellRel = 'replay-autopilot/scripts/DoesNotExist.ps1'
$missingPowerShellProof = (Get-Content -LiteralPath (Join-Path $missingPowerShellCarrierRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8) -replace 'src/main/java/sample/RealEntry\.java', $missingPowerShellRel
Set-Content -LiteralPath (Join-Path $missingPowerShellCarrierRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8 -Value $missingPowerShellProof
& powershell -NoProfile -ExecutionPolicy Bypass -File $script:contractVerifier -ReplayRoot $missingPowerShellCarrierRoot -Stage Plan -Worktree $missingPowerShellWorktree -SkipCarrierAndOracleChecks | Out-Null
$missingPowerShellCarrierVerify = Get-Content -LiteralPath (Join-Path $missingPowerShellCarrierRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (((@($missingPowerShellCarrierVerify.issues) -join ' ') -notmatch 'first_slice_proof_v457_file_not_found')) {
    throw 'Expected missing replay-autopilot PowerShell carrier file to fail closed'
}

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
    cases = @('plan_prompt_first_slice_schema_tokens', 'phase0_valid', 'plan_valid', 'phase0_expected_diff_deferred_to_plan', 'phase0_missing_family_contract_fails', 'plan_missing_first_red_fails', 'plan_missing_candidate_fails', 'plan_missing_carrier_search_fails', 'plan_unjustified_new_service_fails', 'plan_alternate_first_slice_proof_format_passes', 'plan_definition_list_first_slice_proof_format_passes', 'plan_conditional_blocker_phrase_passes', 'plan_policy_rebuild_source_chain_valid_passes', 'plan_policy_rebuild_source_chain_invalid_fails', 'plan_missing_carrier_file_fails', 'plan_powershell_control_plane_carrier_passes', 'plan_powershell_test_script_carrier_fails', 'plan_missing_powershell_carrier_file_fails', 'plan_missing_first_slice_proof_fails', 'plan_static_first_slice_proof_fails', 'plan_substitute_carrier_kind_fails')
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
