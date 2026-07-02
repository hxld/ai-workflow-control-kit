param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-NoChangePolicyFixture {
    param([string]$Root)

    $worktree = Join-Path $Root 'worktree'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java') 'class ExampleApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleCalculatorApiTaskProcessor.java') 'class ExampleCalculatorApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') 'phase0_status: PROCEED'
    Write-Text (Join-Path $Root 'ROUND_CONTRACT.md') 'Requirement Family Ledger: core_entry stateful_side_effect'
    Write-Text (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[{"id":"core_entry","required":true,"weight":100,"proof_required":["RED","GREEN"]}],"selected_real_entry":"ExampleApplyClaimApiTaskProcessor.rebuildTaskData","first_executable_slice":"S1"}'
    Write-Text (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') '{"production_files":2,"high_weight_files":2,"files":[{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java","is_production":true,"weight":"HIGH","additions":2},{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java","is_production":true,"weight":"HIGH","additions":2}]}'
    Write-Text (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') '{"required_source_chain":true}'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_1.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_2.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_3.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_SELECTION.md') 'selection'
    Write-Text (Join-Path $Root 'PLAN_RESULT.md') @'
plan_status: PROCEED
required_files: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> ExampleApplyClaimApiTaskProcessor.rebuildTaskData -> req.setPolicyNum(buildContext.getPolicyNum()) -> upstream lambda assignment verified
carrier_search: performed
carrier_search_queries: rg "class.*ExampleApplyClaimApiTaskProcessor" --type java; rg "class.*ExampleCalculatorApiTaskProcessor" --type java; rg "rebuildTaskData" --type java
existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ExampleCalculatorApiTaskProcessor; ExampleDataAssemblyHelper
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor; ExampleCalculatorApiTaskProcessor
new_service_proposed: false
new_service_justification: none
first_slice: S1 - AI Payload Contract Validation
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java
core_closure_required: false
highest_weight_open_gate: wire_payload_api_contract
Total Production Changes: 0 lines (all verified present)
'@
    Write-Text (Join-Path $Root 'PLAN_RESULT.json') '{"plan_status":"PROCEED","target_carrier_file_path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java","highest_weight_open_gate":"wire_payload_api_contract","core_closure_required":false}'
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') @'
## Slice 1: AI Payload Contract Validation
The baseline already contains the complete implementation.
| example-core | core_entry | ExampleApplyClaimApiTaskProcessor.java | NO_CHANGE | VERIFIED_PRESENT |
Only test changes are needed.
'@
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) ExampleApplyClaimApiTaskProcessor.rebuildTaskData ExampleCalculatorApiTaskProcessor.rebuildTaskData'
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'ExampleApplyClaimApiTaskProcessor LOGIC_FIX; ExampleCalculatorApiTaskProcessor LOGIC_FIX; -pl example-server -am'
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') 'Test harness: No-Spring JUnit with Mockito; example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java'
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PolicyNum
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> RED -> GREEN -> stateful_side_effect
highest_weight_open_gate: wire_payload_api_contract
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: Rebuild lambda implementation
production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
proof_kind: real_entry_behavior
real_carrier_kind: production_service_method
minimum_side_effect_or_blocker: Lambda assigns buildContext values to request fields
required_sibling_surfaces: ExampleCalculatorApiTaskProcessor.rebuildTaskData
expected_production_diff: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
red_expectation: request fields missing before implementation
green_minimum_implementation: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum())
forbidden_substitute_proof: production RequestBuildFunction only
fail_closed_condition: both sibling processors must be covered
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: EXISTING_PATTERN
pattern_return_type: REQUEST
pattern_error_handling: existing behavior
pattern_evidence_source: rg "RequestBuildFunction"
target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java; example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
target_carrier_line_number: 374; 344
expected_test_class: ExampleApplyClaimApiTaskProcessorTest
expected_test_method: testRebuildTaskData_PolicyNum
expected_assertions: ["assertNotNull(result)", "assertEquals(policyNum, result.getPolicyNum())", "assertEquals(insureNum, result.getInsureNum())"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"}]
'@

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$prompt = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\phase-plan-tournament.prompt.md'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-oracle-additions-v494-" + [guid]::NewGuid().ToString('N'))

try {
    $verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8
    Assert-True 'verifier_flags_no_production_change_against_oracle_additions' ($verifierText.Contains('policy_rebuild_plan_invalid:no_production_change_against_oracle_additions'))
    Assert-True 'verifier_flags_highest_weight_gate_not_core_entry' ($verifierText.Contains('policy_rebuild_plan_invalid:highest_weight_gate_not_core_entry'))
    Assert-True 'repair_prompt_handles_no_production_change_issue' ($runLoopText.Contains('policy_rebuild_plan_invalid:no_production_change_against_oracle_additions'))
    Assert-True 'plan_prompt_forbids_no_change_when_oracle_has_additions' ($promptText.Contains('ORACLE_DIFF_ANALYSIS.json') -and $promptText.Contains('NO_CHANGE') -and $promptText.Contains('Total Production Changes: 0'))

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = New-NoChangePolicyFixture -Root $replayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)
    Assert-True 'no_change_plan_fails_when_oracle_has_production_additions' ($issues -contains 'policy_rebuild_plan_invalid:no_production_change_against_oracle_additions')
    Assert-True 'wire_payload_gate_fails_for_policy_rebuild_core_entry' ($issues -contains 'policy_rebuild_plan_invalid:highest_weight_gate_not_core_entry')
    Assert-True 'core_closure_false_fails_for_oracle_additions' ($issues -contains 'policy_rebuild_plan_invalid:core_closure_false_against_oracle')

    Write-Host 'PASS: v494 policy rebuild oracle additions require production diff'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
