param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name - $Details"
    }
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

function Write-Json {
    param([string]$Path, $Data)
    $Data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-harness-v565-" + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java') 'class ExampleApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleCalculatorApiTaskProcessor.java') 'class ExampleCalculatorApiTaskProcessor { void rebuildTaskData() {} }'

    $binding = 'stateful_side_effect -> ExampleDataAssemblyHelper.buildRequestCommon -> ExampleDataAssemblyHelper.RequestBuildFunction -> ExampleApplyClaimApiTaskProcessor.rebuildTaskData -> RED: source-chain assignment missing before fix -> GREEN: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum()) -> executable assertion passes'

    Write-Text (Join-Path $replayRoot 'PHASE0_RESULT.md') 'phase0_status: PROCEED'
    Write-Text (Join-Path $replayRoot 'ROUND_CONTRACT.md') 'Requirement Family Ledger: core_entry stateful_side_effect ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction'
    Write-Json (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{ families = @([ordered]@{ id = 'core_entry'; required = $true; weight = 100 }) })
    Write-Json (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{ required_source_chain = $true })
    Write-Json (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'; is_production = $true; weight = 'HIGH'; additions = '2' },
            [ordered]@{ path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java'; is_production = $true; weight = 'HIGH'; additions = '2' }
        )
    })
    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Text (Join-Path $replayRoot $name) 'candidate'
    }

    Write-Text (Join-Path $replayRoot 'PLAN_RESULT.md') @"
plan_status: PROCEED
selected_strategy: exact-contract-and-test-first
carrier_search: performed
carrier_search_queries: rg "rebuildTaskData"; rg "ExampleDataAssemblyHelper"; rg "policyNum"
existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ExampleCalculatorApiTaskProcessor; ExampleDataAssemblyHelper
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
new_service_proposed: false
new_service_justification: none
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: $binding
first_slice: S1 - policy_num_exact_contract_verification
first_red_test: ExampleRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
"@
    Write-Json (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 355
        expected_test_class = 'ExampleRebuildPathTest'
        expected_test_method = 'testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors'
        first_slice = 'S1 - policy_num_exact_contract_verification'
        first_red_test = 'ExampleRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors'
        expected_assertions = @('assert request policyNum from context', 'assert request insureNum from context', 'assert taskData receives context values')
        side_effects = @('request.policyNum set from RequestBuildContext', 'request.insureNum set from RequestBuildContext')
        golden_slice_binding = $binding
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f worktree\pom.xml -pl example-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    Write-Text (Join-Path $replayRoot 'REPLAY_PLAN.md') 'ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext -pl example-server -am LOGIC_FIX req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) ExampleApplyClaimApiTaskProcessor.rebuildTaskData ExampleCalculatorApiTaskProcessor.rebuildTaskData'
    Write-Text (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData, ExampleCalculatorApiTaskProcessor.rebuildTaskData ExampleDataAssemblyHelper.buildRequestCommon ExampleDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') 'LOGIC_FIX example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java -pl example-server -am validation closure status'
    Write-Text (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') 'stateful side effect: ExampleDataAssemblyHelper.buildRequestCommon invokes ExampleDataAssemblyHelper.RequestBuildFunction; request.policyNum set from RequestBuildContext; request.insureNum set from RequestBuildContext'
    Write-Text (Join-Path $replayRoot 'TEST_CHARTER.md') @'
## RED Phase
Entry Point: ExampleApplyClaimApiTaskProcessor.rebuildTaskData and ExampleCalculatorApiTaskProcessor.rebuildTaskData
Test Class: ExampleRebuildPathTest no-Spring JUnit Mockito test
DB Verification: AtomicReference captures ExampleDataAssemblyHelper.buildRequestCommon RequestBuildFunction output
Side Effects: verify request.policyNum and request.insureNum are assigned from RequestBuildContext
## GREEN Phase
example-server unit harness with existing dependencies
'@
    Write-Text (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1 - policy_num_exact_contract_verification
first_red_test: ExampleRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
golden_slice_binding: $binding
highest_weight_open_gate: core_entry
selected_real_entry: ExampleApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), ExampleCalculatorApiTaskProcessor.rebuildTaskData(Long caseId)
selected_carrier: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: ExampleDataAssemblyHelper.RequestBuildFunction
production_boundary: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
public_entry_contract_coverage: ExampleDataAssemblyHelper.buildRequestCommon RequestBuildFunction source-chain assignment
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: request.policyNum and request.insureNum set from RequestBuildContext
required_sibling_surfaces: ExampleCalculatorApiTaskProcessor.rebuildTaskData
expected_production_diff: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java, example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
red_expectation: source-chain assignment missing before fix
green_minimum_implementation: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum())
forbidden_substitute_proof: production RequestBuildFunction only
fail_closed_condition: both sibling processors must be covered
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: NEW_PATTERN
pattern_return_type: REQUEST
pattern_error_handling: existing behavior
pattern_evidence_source: rg "ExampleDataAssemblyHelper.buildRequestCommon|RequestBuildFunction"
target_carrier_file_path: example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java; example-core/src/main/java/com/example/project/core/ai/task/ExampleCalculatorApiTaskProcessor.java
target_carrier_line_number: 355; 326
expected_test_class: ExampleRebuildPathTest
expected_test_method: testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
expected_assertions: ["assert request policyNum from context","assert request insureNum from context","assert taskData receives context values"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"},{"memory":"request.insureNum","operation":"set","value":"from buildContext.getInsureNum()"}]
"@
    Write-Text (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') '{"command":"mvn -s D:\\maven\\settings\\settings.xml -f worktree\\pom.xml -pl example-server -am test-compile","exit_code":0,"stdout_tail":"BUILD SUCCESS"}'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)
    Assert-True 'machine_harness_closes_claim_server_test_harness_missing_issue' (-not ($issues -contains 'policy_rebuild_plan_missing:claim_server_test_harness')) ($issues -join ';')
    Assert-True 'policy_plan_contract_passes_without_markdown_test_path_literal' ($verify.verification_status -eq 'PASS') ($issues -join ';')

    Write-Host 'PASS: v565 policy rebuild machine harness evidence closes example-server gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
