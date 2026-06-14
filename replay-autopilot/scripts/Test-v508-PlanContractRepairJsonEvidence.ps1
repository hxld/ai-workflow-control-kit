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
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("plan-contract-json-evidence-v508-" + [guid]::NewGuid().ToString('N'))

try {
    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    Assert-True 'contract_repair_allows_plan_result_json' ($runLoopText.Contains('- PLAN_RESULT.json'))
    Assert-True 'contract_repair_treats_issue_evidence_as_authoritative' ($runLoopText.Contains('If `issue_evidence` exists in PLAN_CONTRACT_VERIFY.json'))
    Assert-True 'contract_repair_forbids_returns_null_pass_regex_shape' ($runLoopText.Contains('returns null ... pass/passes/passed/passing') -and $runLoopText.Contains('including PLAN_RESULT.json'))
    Assert-True 'contract_repair_self_scan_includes_plan_result_json' ($runLoopText.Contains('self-scan PLAN_RESULT.md, PLAN_RESULT.json'))

    $root = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    $safeBinding = 'stateful_side_effect -> AiClaimDataAssemblyHelper.RequestBuildFunction -> AiApplyClaimApiTaskProcessor.rebuildTaskData -> RED: source-chain assignment missing before fix -> GREEN: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum()) -> executable assertion passes'
    Write-Text (Join-Path $root 'PLAN_RESULT.md') @"
plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg rebuildTaskData; rg RequestBuildFunction; rg AiApplyClaimApiTaskProcessor
existing_production_carriers: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java; claim-core/src/main/java/com/huize/claim/core/ai/task/AiCalculateLossApiTaskProcessor.java
selected_carrier_from_search: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
new_service_proposed: false
oracle_production_file_overlap: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: oracle files -> existing TaskProcessor carriers -> S1
oracle_out_of_scope_files: none
golden_slice_binding: $safeBinding
first_slice: S1
first_red_test: AiApplyClaimApiTaskProcessorTest.testRebuildTaskData_SourceChainAssignment
"@

    Write-Json (Join-Path $root 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        golden_slice_binding = 'stateful_side_effect -> AiClaimDataAssemblyHelper.RequestBuildFunction -> AiApplyClaimApiTaskProcessor.rebuildTaskData -> RED: request.getPolicyNum() returns null -> GREEN: req.setPolicyNum(buildContext.getPolicyNum()) -> unit test passes'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 355
        expected_test_class = 'AiApplyClaimApiTaskProcessorTest'
        expected_test_method = 'testRebuildTaskData_SourceChainAssignment'
        first_red_test = 'AiApplyClaimApiTaskProcessorTest.testRebuildTaskData_SourceChainAssignment'
        expected_assertions = @('assert request policyNum from context', 'assert request insureNum from context', 'assert taskData receives context values')
        side_effects = @('request.policyNum set from RequestBuildContext')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'sample-module'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -f "worktree/pom.xml" -pl sample-module -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Text (Join-Path $root $name) "candidate: sample"
    }
    Write-Text (Join-Path $root 'REPLAY_PLAN.md') 'AiClaimDataAssemblyHelper.buildRequestCommon and AiClaimDataAssemblyHelper.RequestBuildFunction with RequestBuildContext; mvn -pl sample-module -am test-compile'
    Write-Text (Join-Path $root 'IMPLEMENTATION_CONTRACT.md') 'AiClaimDataAssemblyHelper.RequestBuildFunction RequestBuildContext req.setPolicyNum(buildContext.getPolicyNum()) req.setInsureNum(buildContext.getInsureNum())'
    Write-Text (Join-Path $root 'EXPECTED_DIFF_MATRIX.md') 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java LOGIC_FIX'
    Write-Text (Join-Path $root 'SIDE_EFFECT_LEDGER.md') 'memory side effect: request.policyNum set from RequestBuildContext; request.insureNum set from RequestBuildContext'
    Write-Text (Join-Path $root 'TEST_CHARTER.md') 'claim-server/src/test/java sample-module AiClaimDataAssemblyHelper.RequestBuildFunction RequestBuildContext'
    Write-Text (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1
first_red_test: AiApplyClaimApiTaskProcessorTest.testRebuildTaskData_SourceChainAssignment
golden_slice_binding: $safeBinding
highest_weight_open_gate: core_entry
selected_real_entry: AiApplyClaimApiTaskProcessor.rebuildTaskData
selected_carrier: AiApplyClaimApiTaskProcessor.rebuildTaskData
target_subsurface_or_carrier: AiApplyClaimApiTaskProcessor.rebuildTaskData
production_boundary: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
public_entry_contract_coverage: RequestBuildFunction source-chain assignment
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: request.policyNum/request.insureNum assigned from RequestBuildContext
required_sibling_surfaces: AiCalculateLossApiTaskProcessor.rebuildTaskData
expected_production_diff: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
red_expectation: source-chain assignment missing before fix
green_minimum_implementation: req.setPolicyNum(buildContext.getPolicyNum()) and req.setInsureNum(buildContext.getInsureNum())
forbidden_substitute_proof: uses AiClaimDataAssemblyHelper.RequestBuildFunction and RequestBuildContext
fail_closed_condition: missing RequestBuildFunction assignment blocks Phase1
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: existing rebuildTaskData signature
pattern_return_type: taskData
pattern_error_handling: exception_propagation
pattern_evidence_source: rg rebuildTaskData
target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
target_carrier_line_number: 355
expected_test_class: AiApplyClaimApiTaskProcessorTest
expected_test_method: testRebuildTaskData_SourceChainAssignment
expected_assertions: ["assert request policyNum from context","assert request insureNum from context","assert taskData receives context values"]
expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"}]
"@
    Write-Json (Join-Path $root 'FAMILY_CONTRACT.json') ([ordered]@{ families = @([ordered]@{ id = 'core_entry'; required = $true; proof_required = @('source-chain') }) })
    Write-Json (Join-Path $root 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{ required_source_chain = $true })
    Write-Json (Join-Path $root 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{ path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'; is_production = $true; high_weight = $true; additions = '2' }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $root -Stage Plan | Out-Null
    Assert-True 'verifier_fails_json_returns_null_pass_residue' ($LASTEXITCODE -ne 0)
    $verify = Get-Content -LiteralPath (Join-Path $root 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'verifier_reports_null_taskdata_issue' ((@($verify.issues) -contains 'policy_rebuild_plan_invalid:null_taskdata_pass_path'))
    $jsonEvidence = @($verify.issue_evidence | Where-Object { $_.issue -eq 'policy_rebuild_plan_invalid:null_taskdata_pass_path' -and $_.artifact -eq 'PLAN_RESULT.json' })
    Assert-True 'verifier_reports_plan_result_json_issue_evidence' ($jsonEvidence.Count -gt 0)
    Assert-True 'verifier_issue_evidence_contains_returns_null_snippet' ([string]$jsonEvidence[0].snippet -match 'returns null')

    Write-Host 'PASS: v508 plan contract repair JSON evidence'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
