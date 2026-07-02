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

function New-PolicyValidNoChangePhraseFixture {
    param([string]$Root)

    $worktree = Join-Path $Root 'worktree'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java') 'class ExampleApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleCalculatorApiTaskProcessor.java') 'class ExampleCalculatorApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') 'phase0_status: PROCEED'
    Write-Text (Join-Path $Root 'ROUND_CONTRACT.md') 'Requirement Family Ledger: core_entry stateful_side_effect'
    Write-Text (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[{"id":"core_entry","required":true,"weight":100,"proof_required":["RED","GREEN"]}],"selected_real_entry":"ExampleApplyClaimApiTaskProcessor.rebuildTaskData","first_executable_slice":"S1"}'
    Write-Text (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') '{"production_files":2,"high_weight_files":2,"files":[{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java","is_production":true,"weight":"HIGH","additions":2},{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java","is_production":true,"weight":"HIGH","additions":2}]}'
    Write-Text (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') '{"required_source_chain":true}'
    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Text (Join-Path $Root $name) 'candidate'
    }
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
carrier_search_queries: rg "class.*TaskProcessor" --type java; rg "rebuildTaskData" --type java; rg "buildRequestCommon" --type java
existing_production_carriers: ExampleApplyClaimApiTaskProcessor.rebuildTaskData; ExampleCalculatorApiTaskProcessor.rebuildTaskData
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.rebuildTaskData; ExampleCalculatorApiTaskProcessor.rebuildTaskData
new_service_proposed: false
new_service_justification: none
first_slice: s1_core_rebuild_lambda_fix
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java
core_closure_required: true
highest_weight_open_gate: core_entry
downstream_validation: TaskData.setPolicyNum(request.getPolicyNum()) is allowed only because upstream req.setPolicyNum(buildContext.getPolicyNum()) is the production diff.
'@
    Write-Text (Join-Path $Root 'PLAN_RESULT.json') '{"plan_status":"PROCEED","target_carrier_file_path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java","highest_weight_open_gate":"core_entry","core_closure_required":true}'
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') 'Slice 1: Core Rebuild Lambda Fix with LOGIC_FIX in both TaskProcessor files. No helper-only path is used.'
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) shallow GREEN forbidden ExampleApplyClaimApiTaskProcessor.rebuildTaskData ExampleCalculatorApiTaskProcessor.rebuildTaskData'
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'ExampleApplyClaimApiTaskProcessor LOGIC_FIX 2 lines; ExampleCalculatorApiTaskProcessor LOGIC_FIX 2 lines; -pl example-server -am'
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') 'Test harness: No-Spring JUnit with Mockito; example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java'
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: s1_core_rebuild_lambda_fix
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PolicyNum
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> RED -> GREEN -> stateful_side_effect
highest_weight_open_gate: core_entry
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
public_entry_contract_coverage: rebuildTaskData private method is proven through real production method invocation
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: buildContext to request object mapping in rebuildTaskData lambda
production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
proof_kind: real_entry_behavior
real_carrier_kind: production_service_method
minimum_side_effect_or_blocker: request.policyNum and request.insureNum are assigned from buildContext
forbidden_substitute_check: passed - not using helper/test-only/static substitutes, testing real rebuildTaskData method with mocked dependencies
required_sibling_surfaces: ExampleCalculatorApiTaskProcessor.rebuildTaskData
expected_production_diff: core_entry LOGIC_FIX adds req.setPolicyNum and req.setInsureNum in both processors
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
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"},{"memory":"request.insureNum","operation":"set","value":"from buildContext.getInsureNum()"}]
'@

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-no-change-false-positive-v495-" + [guid]::NewGuid().ToString('N'))

try {
    $verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    Assert-True 'verifier_no_change_regex_does_not_match_bare_test_only' (-not ($verifierText.Contains('|test-only|')))
    Assert-True 'repair_prompt_handles_side_effects_insufficient' ($runLoopText.Contains('first_slice_proof_v457_side_effects_insufficient') -and $runLoopText.Contains('request.policyNum'))

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = New-PolicyValidNoChangePhraseFixture -Root $replayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)
    Assert-True 'negative_test_only_substitute_text_does_not_trigger_no_production_change' (-not ($issues -contains 'policy_rebuild_plan_invalid:no_production_change_against_oracle_additions'))
    Assert-True 'downstream_validation_with_upstream_assignment_does_not_trigger_dto_only' (-not ($issues -contains 'policy_rebuild_plan_invalid:dto_or_downstream_only'))
    Assert-True 'non_empty_expected_side_effects_passes_v457_count' (-not ((@($issues) -join ';') -match 'first_slice_proof_v457_side_effects_insufficient'))

    Write-Host 'PASS: v495 policy rebuild no-change false-positive and side-effect repair'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
