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

function New-PolicyDtoFirstFixture {
    param([string]$Root)

    $worktree = Join-Path $Root 'worktree'
    $applyProcessor = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java'
    $lossProcessor = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleCalculatorApiTaskProcessor.java'
    $applyDto = Join-Path $worktree 'example-domain\src\main\java\com\example\project\domain\ai\dto\ExampleApplyClaimRequest.java'
    $lossDto = Join-Path $worktree 'example-domain\src\main\java\com\example\project\domain\ai\dto\ExampleCalculatorRequest.java'
    $testPath = Join-Path $worktree 'example-server\src\test\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessorTest.java'

    Write-Text $applyProcessor 'package com.example.project.core.ai.task; public class ExampleApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text $lossProcessor 'package com.example.project.core.ai.task; public class ExampleCalculatorApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text $applyDto 'package com.example.project.domain.ai.dto; public class ExampleApplyClaimRequest {}'
    Write-Text $lossDto 'package com.example.project.domain.ai.dto; public class ExampleCalculatorRequest {}'
    Write-Text $testPath 'package com.example.project.core.ai.task; public class ExampleApplyClaimApiTaskProcessorTest {}'
    Write-Text (Join-Path $worktree 'pom.xml') '<project />'
    Write-Text (Join-Path $worktree 'example-server\pom.xml') '<project />'

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
required_files: example-domain/src/main/java/com/example/project/domain/ai/dto/ExampleApplyClaimRequest.java, example-domain/src/main/java/com/example/project/domain/ai/dto/ExampleCalculatorRequest.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> ExampleApplyClaimApiTaskProcessor.rebuildTaskData -> req.setPolicyNum(buildContext.getPolicyNum()) -> rebuild lambda executes
carrier_search: performed
carrier_search_queries: rg "class.*ExampleApplyClaimRequest" --type java; rg "interface.*RequestBuildFunction" --type java
existing_production_carriers: ExampleApplyClaimRequest; ExampleCalculatorRequest; ExampleDataAssemblyHelper; ExampleApplyClaimApiTaskProcessor; ExampleCalculatorApiTaskProcessor
selected_carrier_from_search: ExampleDataAssemblyHelper.RequestBuildFunction
new_service_proposed: false
new_service_justification: none
first_slice: S1
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java
'@
    Write-Text (Join-Path $Root 'PLAN_RESULT.json') @'
{
  "plan_status": "PROCEED",
  "target_carrier_file_path": "example-domain/src/main/java/com/example/project/domain/ai/dto/ExampleApplyClaimRequest.java",
  "expected_test_class": "example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java",
  "expected_test_method": "testRebuildTaskData_PreservesPolicyNumAndInsureNum",
  "side_effects": ["TaskData.setPolicyNum()", "TaskData.setInsureNum()"],
  "expected_assertions": ["assertNotNull(result)", "assertEquals(policyNum, result.getPolicyNum())", "assertEquals(insureNum, result.getInsureNum())"],
  "test_infrastructure_check": {
    "test_module_for_target": "example-server",
    "test_module_has_dependencies": true,
    "test_harness_available": true,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 0,
    "compilation_dry_run_command": "mvn -s D:\\maven\\settings\\settings.xml -f <worktree>\\pom.xml -pl example-server -am test-compile",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "none"
  }
}
'@
    Write-Text (Join-Path $Root 'REPLAY_PLAN.md') @'
## Slice 1: Contract Definition (DTO Fields)

### Surfaces
- wire_payload_api_contract: Request DTO field additions

### Tests
- None (compile-time validation only)

## Slice 2: Core Rebuild Logic
- ExampleApplyClaimApiTaskProcessor lambda copies policyNum from buildContext
- ExampleCalculatorApiTaskProcessor lambda copies insureNum from buildContext
'@
    Write-Text (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) ExampleApplyClaimApiTaskProcessor.rebuildTaskData ExampleCalculatorApiTaskProcessor.rebuildTaskData'
    Write-Text (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'Slice 1 Contract Definition FIELD_ADD compile-time validation only; Slice 2 LOGIC_FIX example-core processors; -pl example-server -am'
    Write-Text (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'TaskData.setPolicyNum TaskData.setInsureNum req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $Root 'TEST_CHARTER.md') @'
## RED Phase
Test harness: No-Spring JUnit with Mockito; do NOT extend AbstractTestClass or use Spring context
example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.java
'@
    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
first_red_test: example-server/src/test/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessorTest.testRebuildTaskData_PreservesPolicyNumAndInsureNum
golden_slice_binding: exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction -> RED -> GREEN -> stateful_side_effect
highest_weight_open_gate: core_entry
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
selected_carrier: ExampleDataAssemblyHelper.RequestBuildFunction
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
target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
target_carrier_line_number: 374
expected_test_class: ExampleApplyClaimApiTaskProcessorTest
expected_test_method: testRebuildTaskData_PreservesPolicyNumAndInsureNum
expected_assertions: ["assertNotNull(result)", "assertEquals(policyNum, result.getPolicyNum())", "assertEquals(insureNum, result.getInsureNum())"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"}]
'@
    Write-Text (Join-Path $Root 'TEST_INFRASTRUCTURE_DRY_RUN.json') '{"command":"mvn -s D:\\maven\\settings\\settings.xml -f <worktree>\\pom.xml -pl example-server -am test-compile","exit_code":0,"stdout_tail":"BUILD SUCCESS"}'

    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$constraintCheck = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-dto-first-v493-" + [guid]::NewGuid().ToString('N'))

try {
    $verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
    $constraintText = Get-Content -LiteralPath $constraintCheck -Raw -Encoding UTF8
    Assert-True 'verifier_reads_plan_result_json_for_dual_contract_drift' ($verifierText.Contains('$planJsonText'))
    Assert-True 'verifier_flags_policy_rebuild_dto_only_signal' ($verifierText.Contains('$hasPolicyDtoOnlySignal'))
    Assert-True 'pre_execution_no_longer_uses_rg_glob_without_pattern' (-not ($constraintText.Contains('rg "--type=java" "-l" "-g"')))
    Assert-True 'pre_execution_uses_fixed_string_carrier_search' ($constraintText.Contains('"--fixed-strings"'))

    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = New-PolicyDtoFirstFixture -Root $replayRoot

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'policy_rebuild_dto_first_plan_fails_plan_contract' (@($verify.issues) -contains 'policy_rebuild_plan_invalid:dto_or_downstream_only')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $constraintCheck -ReplayRoot $replayRoot -Worktree $worktree -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') -BaselineRoot $worktree | Out-Null
    Assert-True 'pre_execution_writes_json_for_dto_carrier_failure' (Test-Path -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -PathType Leaf)
    $pre = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $layer = $pre.checks | Where-Object { $_.name -eq 'carrier_in_valid_layer' } | Select-Object -First 1
    Assert-True 'pre_execution_fails_dto_layer_without_tool_crash' ([string]$layer.status -eq 'FAIL')
    Assert-True 'pre_execution_reports_structured_failure' (-not [string]::IsNullOrWhiteSpace([string]$layer.reason))

    Write-Host 'PASS: v493 policy rebuild DTO-first and pre-exec no-crash guards'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
