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

function New-PolicyReplayFixture {
    param(
        [string]$Root,
        [string]$HarnessLine
    )

    $worktree = Join-Path $Root 'worktree'
    $applyPath = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java'
    $lossPath = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleCalculatorApiTaskProcessor.java'
    Write-Text $applyPath 'class ExampleApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text $lossPath 'class ExampleCalculatorApiTaskProcessor { void rebuildTaskData() {} }'

    Write-Text (Join-Path $Root 'PHASE0_RESULT.md') @'
phase0_status: PROCEED
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)
'@
    Write-Text (Join-Path $Root 'ROUND_CONTRACT.md') 'Requirement Family Ledger: core_entry stateful_side_effect'
    Write-Text (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[{"id":"core_entry","required":true,"weight":100,"proof_required":["RED","GREEN"]}],"selected_real_entry":"ExampleApplyClaimApiTaskProcessor.rebuildTaskData","first_executable_slice":"S1"}'
    Write-Text (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') '{"production_files":2,"high_weight_files":2,"files":[{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java","is_production":true,"weight":"HIGH"},{"path":"example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java","is_production":true,"weight":"HIGH"}]}'
    Write-Text (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') '{"required_source_chain":true}'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_1.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_2.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_CANDIDATE_3.md') 'candidate'
    Write-Text (Join-Path $Root 'PLAN_SELECTION.md') 'selection'
    Write-Text (Join-Path $Root 'PLAN_RESULT.md') @'
plan_status: PROCEED
first_slice: S1
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorRebuildTest.testRebuildTaskData_PolicyNumAndInsureNum_NullWithoutFix
carrier_search: performed
carrier_search_queries: rg "rebuildTaskData"; rg "ExampleDataAssemblyHelper"; rg "policyNum"
existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ExampleCalculatorApiTaskProcessor; ExampleDataAssemblyHelper
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
new_service_proposed: false
new_service_justification: none_with_reason
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> RED -> GREEN -> stateful_side_effect
'@
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') 'rebuildTaskData policyNum insureNum example-server/src/test/java -pl example-server -am ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) ExampleApplyClaimApiTaskProcessor.rebuildTaskData ExampleCalculatorApiTaskProcessor.rebuildTaskData'
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData. shallow GREEN forbidden. ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'validation closure status example-server/src/test/java -pl example-server -am'
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction ExampleDataAssemblyHelper.RequestBuildFunction req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') @"
## RED Phase
## GREEN Phase
- $HarnessLine
- example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorRebuildTest.java
"@
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorRebuildTest.testRebuildTaskData_PolicyNumAndInsureNum_NullWithoutFix
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> RED -> GREEN -> stateful_side_effect
highest_weight_open_gate: core_entry
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: ExampleDataAssemblyHelper.RequestBuildFunction
production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
public_entry_contract_coverage: rebuildTaskData
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: request.policyNum and request.insureNum set from RequestBuildContext
required_sibling_surfaces: ExampleCalculatorApiTaskProcessor.rebuildTaskData
expected_production_diff: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
red_expectation: request fields missing before implementation
green_minimum_implementation: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum())
forbidden_substitute_proof: production RequestBuildFunction only
fail_closed_condition: both sibling processors must be covered
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: NEW_PATTERN
pattern_return_type: REQUEST
pattern_error_handling: existing behavior
pattern_evidence_source: rg "RequestBuildFunction"
target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java; example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
target_carrier_line_number: 385; 354
expected_test_class: ExampleApplyClaimApiTaskProcessorRebuildTest
expected_test_method: testRebuildTaskData_PolicyNumAndInsureNum_NullWithoutFix
expected_assertions: ["assertNotNull(request.getPolicyNum())", "assertNotNull(request.getInsureNum())", "assertEquals(buildContext.getPolicyNum(), request.getPolicyNum())"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"}]
'@

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-verifier-v491-" + [guid]::NewGuid().ToString('N'))

try {
    $verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
    Assert-True 'verifier_has_no_spring_residue_helper' ($verifierText.Contains('function Test-PolicySpringHarnessResidue'))
    Assert-True 'verifier_splits_target_carrier_file_path_candidates' ($verifierText.Contains('$carrierFilePathCandidates') -and $verifierText.Contains("-split '\s*(?:;|,|\|)\s*'"))

    $validRoot = Join-Path $tempRoot 'valid-no-spring'
    $validHarness = @'
Test harness: No-Spring JUnit with Mockito

**Avoid**:
- @SpringBootTest
- @RunWith(SpringJUnit4ClassRunner.class)
- @ContextConfiguration
- @Resource injection
- AbstractTestClass extension
'@
    $validWorktree = New-PolicyReplayFixture -Root $validRoot -HarnessLine $validHarness
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $validRoot -Stage Plan -Worktree $validWorktree | Out-Null
    $valid = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $validIssues = @($valid.issues)
    Assert-True 'no_spring_negative_guard_does_not_trigger_spring_context_harness' (-not ($validIssues -contains 'policy_rebuild_plan_invalid:spring_context_harness'))
    Assert-True 'semicolon_sibling_carrier_paths_do_not_trigger_file_not_found' (-not ((@($validIssues) -join ';') -match 'first_slice_proof_v457_file_not_found'))

    $invalidRoot = Join-Path $tempRoot 'invalid-spring'
    $invalidWorktree = New-PolicyReplayFixture -Root $invalidRoot -HarnessLine 'Test harness: AbstractTestClass with Spring context'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $invalidRoot -Stage Plan -Worktree $invalidWorktree | Out-Null
    $invalid = Get-Content -LiteralPath (Join-Path $invalidRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'real_spring_harness_still_fails' (@($invalid.issues) -contains 'policy_rebuild_plan_invalid:spring_context_harness')

    Write-Host 'PASS: v491 policy rebuild verifier sibling carrier and no-spring guards'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
