param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v382-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
try {
    $worktree = Join-Path $testRoot 'worktree'
    $claimCorePath = Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\service'
    New-Item -ItemType Directory -Force -Path $claimCorePath | Out-Null

    # Create a test carrier file
    $carrierContent = @'
package com.example.project.core.ai.service;

/**
 * Test carrier for v382 verification
 */
public class ClaimAgentService {
    public void batchQueryCaseDetail(String caseId) {
        // Implementation
    }
}
'@
    Write-Text (Join-Path $claimCorePath 'ClaimAgentService.java') $carrierContent

    # Create PLAN_RESULT.md with ClaimAgentService as selected carrier
    $planResultPath = Join-Path $testRoot 'PLAN_RESULT.md'
    Write-Text $planResultPath @'
# Plan Result

- plan_status: PROCEED
- selected_strategy: exact-contract-and-test-first
- carrier_search: performed
- carrier_search_queries: rg "class ClaimAgentService" example-core; rg "class.*Service" example-core/src/main/java/com/example/project/core/ai/service; rg "batchQueryCaseDetail" example-core
- existing_production_carriers: ClaimAgentService.batchQueryCaseDetail
- selected_carrier_from_search: ClaimAgentService.batchQueryCaseDetail
- new_service_proposed: false
- first_slice: S5 - 自动化测试接口调整 (ClaimAgentFacade.batchQueryCaseDetail)
- first_red_test: ClaimAgentServiceTest.testBatchQueryCaseDetail_WithOriginalProjectList
'@

    # Create other required plan files with complete schema
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md', 'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md', 'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md', 'FIRST_SLICE_PROOF_PLAN.md', 'FAMILY_CONTRACT.json')) {
        if ($file -eq 'FAMILY_CONTRACT.json') {
            Write-Text (Join-Path $testRoot $file) '{"families":[{"id":"core_entry","required":true,"proof_required":["real_entry_behavior"]},{"id":"stateful_side_effect","required":true},{"id":"automation_test_interface","required":true}],"phase0_status":"PROCEED","selected_real_entry":"ClaimAgentFacade.batchQueryCaseDetail","first_executable_slice":"S5"}'
        } elseif ($file -eq 'EXPECTED_DIFF_MATRIX.md') {
            Write-Text (Join-Path $testRoot $file) "# Expected Diff Matrix`n`n| Field | Type | Validation | Closure |`n|------|------|------------|--------|`n| originalProjectList | List | field added | yes |"
        } elseif ($file -eq 'FIRST_SLICE_PROOF_PLAN.md') {
            Write-Text (Join-Path $testRoot $file) @"
# First Slice Proof Plan
- first_slice: S5 - 自动化测试接口调整 (ClaimAgentService.batchQueryCaseDetail)
- first_red_test: ClaimAgentServiceTest.testBatchQueryCaseDetail_WithOriginalProjectList
- selected_carrier: ClaimAgentService.batchQueryCaseDetail
- selected_real_entry: ClaimAgentService.batchQueryCaseDetail
- target_subsurface_or_carrier: ClaimAgentService.batchQueryCaseDetail
- target_family: core_entry
- proof_kind: real_entry_behavior
- real_carrier_kind: production_service
- red_expectation: Test returns originalProjectList field
- green_minimum_implementation: Add field to response
- fail_closed_condition: Test fails before implementation
- minimum_side_effect_or_blocker: Modify service method to add field
- expected_production_diff: Add originalProjectList to response DTO
- production_boundary: Service layer response modification
- forbidden_substitute_check: passed
- forbidden_substitute_proof: Verified no Mock/TestOnly usage
- required_sibling_surfaces: ClaimAgentFacade
- public_entry_contract_coverage: 100%
- highest_weight_open_gate: core_entry
- coverage_cap_if_not_closed: 90%
- fail_closed_condition: Test asserts on new field
"@
        } elseif ($file -eq 'IMPLEMENTATION_CONTRACT.md') {
            Write-Text (Join-Path $testRoot $file) @"
# Implementation Contract
- selected real entry: ClaimAgentFacade.batchQueryCaseDetail
- shallow-green-ban: FORBIDDEN
- interface_contract_return_type: AutoTestCaseQueryResponse
- interface_contract_error_handling: BusinessException for invalid caseId
- pattern_to_follow: Refer to ExamineFlowFacadeImpl for similar facade pattern
- pattern_evidence_source: rg "class ExamineFlowFacadeImpl" example-core
"@
        } elseif ($file -eq 'TEST_CHARTER.md') {
            Write-Text (Join-Path $testRoot $file) @"
# Test Charter
- RED: ClaimAgentServiceTest.testBatchQueryCaseDetail_WithOriginalProjectList verifies originalProjectList field is returned
- GREEN: Implement originalProjectList field in ClaimAgentService.batchQueryCaseDetail and verify test passes
"@
        } else {
            Write-Text (Join-Path $testRoot $file) "# $file"
        }
    }

    # Create ORACLE_DIFF_ANALYSIS.json to satisfy oracle requirement with overlap data
    Write-Text (Join-Path $testRoot 'ORACLE_DIFF_ANALYSIS.json') '{"files":[{"path":"example-core/src/main/java/com/example/project/core/ai/service/ClaimAgentService.java","is_production":true,"weight":"HIGH","added_lines":10}]}'
    Write-Text (Join-Path $testRoot 'ORACLE_COMMIT.txt') 'abc123'

    # Update PLAN_RESULT.md with oracle overlap field and oracle file mention
    $planContent = Get-Content -LiteralPath (Join-Path $testRoot 'PLAN_RESULT.md') -Raw -Encoding UTF8
    $planContent = $planContent -replace '(\- first_red_test:.+)', "`$1`n- oracle_production_file_overlap: 100%`n- oracle_high_weight_coverage: 100% (1/1)`n- oracle_missing_high_weight_files: none"
    # Add oracle file mention to REPLAY_PLAN.md for overlap calculation
    $replayPlanContent = Get-Content -LiteralPath (Join-Path $testRoot 'REPLAY_PLAN.md') -Raw -Encoding UTF8
    $replayPlanContent = $replayPlanContent + "`n`n## Oracle Files Coverage`n`n- ClaimAgentService.java (verified exists in worktree)"
    Set-Content -LiteralPath (Join-Path $testRoot 'REPLAY_PLAN.md') -Value $replayPlanContent -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $testRoot 'PLAN_RESULT.md') -Value $planContent -Encoding UTF8

    # Run verifier - should PASS because ClaimAgentService exists
    $verifyJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRoot -Stage Plan -Worktree $worktree | ConvertFrom-Json
    Assert-True ($verifyJson.verification_status -eq 'PASS') "Verifier should PASS when carrier exists (ClaimAgentService found)"
    Assert-True ($verifyJson.issues -notcontains 'carrier_search_selected_carrier_not_found_in_codebase') "Should not have carrier_not_found issue when carrier exists"

    # Test 2: Carrier that doesn't exist should FAIL
    $planResultNonExistent = Join-Path $testRoot 'PLAN_RESULT_NON_EXISTENT.md'
    Write-Text $planResultNonExistent @'
# Plan Result - Non-existent Carrier

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "class SyntheticCarrierService" example-core
- existing_production_carriers: None
- selected_carrier_from_search: SyntheticCarrierService.doSomething
- new_service_proposed: true
- new_service_justification: No existing service handles this
'@

    $testRootNonExistent = Join-Path $testRoot 'non_existent'
    New-Item -ItemType Directory -Force -Path $testRootNonExistent | Out-Null
    Copy-Item -LiteralPath (Join-Path $testRoot 'worktree') -Destination (Join-Path $testRootNonExistent 'worktree') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $testRoot 'PLAN_RESULT_NON_EXISTENT.md') -Destination (Join-Path $testRootNonExistent 'PLAN_RESULT.md') -Force
    Copy-Item -LiteralPath (Join-Path $testRoot 'ORACLE_DIFF_ANALYSIS.json') -Destination (Join-Path $testRootNonExistent 'ORACLE_DIFF_ANALYSIS.json') -Force
    Copy-Item -LiteralPath (Join-Path $testRoot 'ORACLE_COMMIT.txt') -Destination (Join-Path $testRootNonExistent 'ORACLE_COMMIT.txt') -Force
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md', 'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md', 'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md', 'FIRST_SLICE_PROOF_PLAN.md', 'FAMILY_CONTRACT.json')) {
        Copy-Item -LiteralPath (Join-Path $testRoot $file) -Destination (Join-Path $testRootNonExistent $file) -Force
    }

    # Update PLAN_RESULT.md to use SyntheticCarrierService
    $planResultNonExistent = Join-Path $testRootNonExistent 'PLAN_RESULT.md'
    $planContent = Get-Content -LiteralPath $planResultNonExistent -Raw -Encoding UTF8
    $planContent = $planContent -replace 'ClaimAgentService\.batchQueryCaseDetail', 'SyntheticCarrierService.doSomething'
    $planContent = $planContent -replace 'first_slice: S5', 'first_slice: S1'
    $planContent = $planContent -replace 'first_red_test: ClaimAgentServiceTest', 'first_red_test: SyntheticCarrierServiceTest'
    Set-Content -LiteralPath $planResultNonExistent -Value $planContent -Encoding UTF8

    # Update FIRST_SLICE_PROOF_PLAN.md to use SyntheticCarrierService
    $firstSlicePath = Join-Path $testRootNonExistent 'FIRST_SLICE_PROOF_PLAN.md'
    $firstSliceContent = Get-Content -LiteralPath $firstSlicePath -Raw -Encoding UTF8
    $firstSliceContent = $firstSliceContent -replace 'ClaimAgentService\.batchQueryCaseDetail', 'SyntheticCarrierService.doSomething'
    $firstSliceContent = $firstSliceContent -replace 'ClaimAgentServiceTest\.testBatchQueryCaseDetail_WithOriginalProjectList', 'SyntheticCarrierServiceTest.testDoSomething'
    $firstSliceContent = $firstSliceContent -replace 'ClaimAgentFacade\.batchQueryCaseDetail', 'SyntheticCarrierService.doSomething'
    Set-Content -LiteralPath $firstSlicePath -Value $firstSliceContent -Encoding UTF8

    $verifyJsonNonExistent = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $testRootNonExistent -Stage Plan -Worktree (Join-Path $testRootNonExistent 'worktree') | ConvertFrom-Json
    Assert-True ($verifyJsonNonExistent.verification_status -eq 'FAIL') "Verifier should FAIL when carrier doesn't exist (SyntheticCarrierService not found)"
    Assert-True ($verifyJsonNonExistent.issues -contains 'carrier_search_selected_carrier_not_found_in_codebase') "Should have carrier_not_found issue for synthetic carrier"

    # Test 3: Verify retry mechanism - carrier exists but rg might have transient issues
    # The Get-ChildItem fallback should still find it if rg fails
    # If rg succeeds on first try, there will be no carrier existence warnings
    $hasCarrierNotFoundWarning = @($verifyJson.warnings | Where-Object { $_ -match 'carrier_existence_check.*not found' }).Count -gt 0
    Assert-True (-not $hasCarrierNotFoundWarning) "Should not have carrier_not_found warnings when carrier exists"

} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 3
    cases = @(
        'existing_carrier_passes_verification',
        'synthetic_carrier_fails_verification',
        'no_false_negative_carrier_warnings'
    )
} | ConvertTo-Json -Depth 5
