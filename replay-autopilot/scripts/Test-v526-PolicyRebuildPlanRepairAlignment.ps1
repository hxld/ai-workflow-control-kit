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

function Write-Json {
    param([string]$Path, $Data)
    $Data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-v526-" + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$worktree = Join-Path $replayRoot 'worktree'

try {
    $applyPath = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task\AiApplyClaimApiTaskProcessor.java'
    $lossPath = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task\AiCalculateLossApiTaskProcessor.java'
    Write-Text $applyPath 'class AiApplyClaimApiTaskProcessor { void rebuildTaskData() {} }'
    Write-Text $lossPath 'class AiCalculateLossApiTaskProcessor { void rebuildTaskData() {} }'

    $binding = 'stateful_side_effect -> AiClaimDataAssemblyHelper.buildRequestCommon -> AiClaimDataAssemblyHelper.RequestBuildFunction -> AiApplyClaimApiTaskProcessor.rebuildTaskData -> RED: upstream source-chain missing before fix -> GREEN: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum()) -> executable assertion passes'

    Write-Text (Join-Path $replayRoot 'PHASE0_RESULT.md') 'phase0_status: PROCEED'
    Write-Text (Join-Path $replayRoot 'ROUND_CONTRACT.md') 'Requirement Family Ledger: core_entry stateful_side_effect AiClaimDataAssemblyHelper.buildRequestCommon AiClaimDataAssemblyHelper.RequestBuildFunction'
    Write-Json (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{ families = @([ordered]@{ id = 'core_entry'; required = $true; weight = 100 }) })
    Write-Json (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{ required_source_chain = $true })
    Write-Json (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'; is_production = $true; weight = 'HIGH'; additions = '2' },
            [ordered]@{ path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java'; is_production = $true; weight = 'HIGH'; additions = '2' }
        )
    })
    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Text (Join-Path $replayRoot $name) 'candidate'
    }

    Write-Text (Join-Path $replayRoot 'PLAN_RESULT.md') @"
plan_status: PROCEED
selected_strategy: exact-contract-and-test-first
carrier_search: performed
carrier_search_queries: rg "rebuildTaskData"; rg "AiClaimDataAssemblyHelper"; rg "policyNum"
existing_production_carriers: AiApplyClaimApiTaskProcessor; AiCalculateLossApiTaskProcessor; AiClaimDataAssemblyHelper
selected_carrier_from_search: AiApplyClaimApiTaskProcessor.rebuildTaskData
new_service_proposed: false
new_service_justification: none
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: $binding
first_slice: S1 - policy_num_exact_contract_verification
first_red_test: AiClaimRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
"@
    Write-Json (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        selected_strategy = 'exact-contract-and-test-first'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 355
        expected_test_class = 'AiClaimRebuildPathTest'
        expected_test_method = 'testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors'
        first_slice = 'S1 - policy_num_exact_contract_verification'
        first_red_test = 'AiClaimRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors'
        expected_assertions = @('assert request policyNum from context', 'assert request insureNum from context', 'assert taskData receives context values')
        side_effects = @('request.policyNum set from RequestBuildContext', 'request.insureNum set from RequestBuildContext')
        golden_slice_binding = $binding
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f worktree\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })
    Write-Text (Join-Path $replayRoot 'REPLAY_PLAN.md') "AiClaimDataAssemblyHelper.buildRequestCommon AiClaimDataAssemblyHelper.RequestBuildFunction RequestBuildContext claim-server/src/test/java -pl claim-server -am LOGIC_FIX req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum()) AiApplyClaimApiTaskProcessor.rebuildTaskData AiCalculateLossApiTaskProcessor.rebuildTaskData"
    Write-Text (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: AiApplyClaimApiTaskProcessor.rebuildTaskData, AiCalculateLossApiTaskProcessor.rebuildTaskData
AiClaimDataAssemblyHelper.buildRequestCommon
AiClaimDataAssemblyHelper.RequestBuildFunction
RequestBuildContext
req.setPolicyNum(buildContext.getPolicyNum())
req.setInsureNum(buildContext.getInsureNum())

**No-Spring JUnit**:
- No @SpringBootTest
- No @RunWith(SpringJUnit4ClassRunner.class)
- No @ContextConfiguration
- No @Resource injection
- No AbstractTestClass extension
'@
    Write-Text (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') 'LOGIC_FIX claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java claim-server/src/test/java -pl claim-server -am validation closure status'
    Write-Text (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') 'stateful side effect: AiClaimDataAssemblyHelper.buildRequestCommon invokes AiClaimDataAssemblyHelper.RequestBuildFunction; request.policyNum set from RequestBuildContext; request.insureNum set from RequestBuildContext'
    Write-Text (Join-Path $replayRoot 'TEST_CHARTER.md') @'
## RED Phase
Entry Point: AiApplyClaimApiTaskProcessor.rebuildTaskData and AiCalculateLossApiTaskProcessor.rebuildTaskData
Test Class: AiClaimRebuildPathTest no-Spring JUnit Mockito test
DB Verification: AtomicReference captures AiClaimDataAssemblyHelper.buildRequestCommon RequestBuildFunction output
Side Effects: verify request.policyNum and request.insureNum are assigned from RequestBuildContext
## GREEN Phase
claim-server/src/test/java/com/huize/claim/core/ai/task/AiClaimRebuildPathTest.java
'@
    Write-Text (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1 - policy_num_exact_contract_verification
first_red_test: AiClaimRebuildPathTest.testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
golden_slice_binding: $binding
highest_weight_open_gate: core_entry
selected_real_entry: AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId), AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)
selected_carrier: AiApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: AiClaimDataAssemblyHelper.RequestBuildFunction
production_boundary: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
public_entry_contract_coverage: AiClaimDataAssemblyHelper.buildRequestCommon RequestBuildFunction source-chain assignment
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: request.policyNum and request.insureNum set from RequestBuildContext
required_sibling_surfaces: AiCalculateLossApiTaskProcessor.rebuildTaskData
expected_production_diff: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java, claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java
red_expectation: source-chain assignment missing before fix
green_minimum_implementation: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum())
forbidden_substitute_proof: production RequestBuildFunction only
fail_closed_condition: both sibling processors must be covered
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: NEW_PATTERN
pattern_return_type: REQUEST
pattern_error_handling: existing behavior
pattern_evidence_source: rg "AiClaimDataAssemblyHelper.buildRequestCommon|RequestBuildFunction"
target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java; claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java
target_carrier_line_number: 355; 326
expected_test_class: AiClaimRebuildPathTest
expected_test_method: testRebuildTaskData_PreservesPolicyNumAndInsureNumForBothProcessors
expected_assertions: ["assert request policyNum from context","assert request insureNum from context","assert taskData receives context values"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"},{"memory":"request.insureNum","operation":"set","value":"from buildContext.getInsureNum()"}]
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)
    Assert-True 'v526_fixture_not_missing_build_request_common' (-not ($issues -contains 'policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.buildRequestCommon'))
    Assert-True 'v526_fixture_not_missing_request_build_function' (-not ($issues -contains 'policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.RequestBuildFunction'))
    Assert-True 'v526_no_spring_negative_lines_not_flagged' (-not ($issues -contains 'policy_rebuild_plan_invalid:spring_context_harness'))
    Assert-True 'v526_policy_plan_contract_passes' ($verify.verification_status -eq 'PASS')

    Write-Host 'PASS: v526 policy rebuild plan repair alignment'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
