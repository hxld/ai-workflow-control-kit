param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-PlanFixture {
    param(
        [string]$Root,
        [string]$FirstSliceFamily
    )

    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core\src\main\java\com\example') | Out-Null
    Write-Utf8 (Join-Path $worktree 'claim-core\src\main\java\com\example\AiClaimModuleConfigService.java') @'
package com.example;
class AiClaimModuleConfigService {
  void save(Object dto) {}
}
'@

    $plan = @"
plan_status: PROCEED
selected_strategy: prerequisite-first
carrier_search: performed
existing_production_carriers: AiClaimModuleConfigService; AiApplyClaimApiTaskProcessor
selected_carrier: AiClaimModuleConfigService
oracle_production_file_overlap: 80%
oracle_high_weight_file_overlap: 80%
oracle_repair_ledger: none
oracle_missing_high_weight_map: none
oracle_out_of_scope_files: none
golden_slice_binding: exact_contract_gap -> config_policy_threshold -> AiClaimModuleConfigService -> RED -> GREEN -> DB side effect
first_slice: S1 - config threshold prerequisite
first_red_test: AiClaimModuleConfigServiceTest.freeReviewAmount_save_shouldPersist
core_closure_required: true
"@
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') $plan
    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_1.md') $plan
    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_2.md') $plan
    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_3.md') $plan
    Write-Utf8 (Join-Path $Root 'PLAN_SELECTION.md') 'selected_strategy: prerequisite-first'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'core_entry config_policy_threshold S2 AiApplyClaimApiTaskProcessor core tracer'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: com.example.AiApplyClaimApiTaskProcessor.handleTaskResponse()
first_slice: S1 - config threshold prerequisite
first_red_test: AiClaimModuleConfigServiceTest.freeReviewAmount_save_shouldPersist
shallow-green-ban: GREEN cannot claim core DONE until S2 core tracer'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'validation closure status for AiClaimModuleConfigService.java'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction DB insert/update free_review_amount'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED GREEN AiClaimModuleConfigServiceTest freeReviewAmount_save_shouldPersist'
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"selected_real_entry":"com.example.AiApplyClaimApiTaskProcessor.handleTaskResponse()","first_executable_slice":"S1","families":[{"id":"core_entry","required":true,"proof_required":["S2 core tracer"]},{"id":"config_policy_threshold","required":true,"proof_required":["S1 config field"]}]}'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1 - config threshold prerequisite
first_red_test: AiClaimModuleConfigServiceTest.freeReviewAmount_save_shouldPersist
golden_slice_binding: exact_contract_gap -> config_policy_threshold -> AiClaimModuleConfigService -> RED -> GREEN -> DB side effect
highest_weight_open_gate: core_entry
first_slice_family: $FirstSliceFamily
selected_real_entry: com.example.AiApplyClaimApiTaskProcessor.handleTaskResponse()
public_entry_contract_coverage: not_public_entry_with_reason:first_slice_family_$FirstSliceFamily
selected_carrier: AiClaimModuleConfigService
target_subsurface_or_carrier: AiClaimModuleConfigService.save
production_boundary: claim-core/src/main/java/com/example/AiClaimModuleConfigService.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
minimum_side_effect_or_blocker: mapper insert/update persists free_review_amount
expected_production_diff: claim-core/src/main/java/com/example/AiClaimModuleConfigService.java
red_expectation: test fails before freeReviewAmount persistence exists
green_minimum_implementation: add minimum service/entity/mapper field persistence
forbidden_substitute_check: passed
forbidden_substitute_proof: not helper-only
fail_closed_condition: fail if S1 claims core closure
coverage_cap_if_not_closed: core remains capped until S2
target_carrier_file_path: claim-core/src/main/java/com/example/AiClaimModuleConfigService.java
target_carrier_line_number: 3
expected_test_class: AiClaimModuleConfigServiceTest
expected_test_method: freeReviewAmount_save_shouldPersist
expected_assertions: ["captured entity contains freeReviewAmount", "mapper insert called", "mapper update called"]
expected_side_effects: [{"table":"t_ai_claim_module_config","operation":"insert/update free_review_amount"}]
"@
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifyScript = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v595-first-slice-family-" + [guid]::NewGuid().ToString('N'))

try {
    $prereqRoot = Join-Path $tempRoot 'prerequisite'
    New-PlanFixture -Root $prereqRoot -FirstSliceFamily 'config_policy_threshold'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $prereqRoot -Stage Plan -Worktree (Join-Path $prereqRoot 'worktree') | Out-Null
    $prereq = Get-Content -LiteralPath (Join-Path $prereqRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $prereqIssues = @($prereq.issues) -join ' '
    Assert-True 'prerequisite_slice_does_not_fail_core_layer_gate' ($prereqIssues -notmatch 'layer_validation_failed:core_entry_requires_facade_controller')
    Assert-True 'prerequisite_slice_does_not_fail_public_entry_mismatch' ($prereqIssues -notmatch 'first_slice_proof_invalid:public_entry_carrier_mismatch')
    Assert-True 'prerequisite_slice_warns_core_deferred' ((@($prereq.warnings) -join ' ') -match 'core_entry_deferred_by_prerequisite_slice:config_policy_threshold')

    $coreRoot = Join-Path $tempRoot 'core'
    New-PlanFixture -Root $coreRoot -FirstSliceFamily 'core_entry'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $coreRoot -Stage Plan -Worktree (Join-Path $coreRoot 'worktree') | Out-Null
    $core = Get-Content -LiteralPath (Join-Path $coreRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $coreIssues = @($core.issues) -join ' '
    Assert-True 'core_entry_service_still_fails_layer_gate' ($coreIssues -match 'layer_validation_failed:core_entry_requires_facade_controller')

    Write-Host 'PASS: v595 prerequisite first-slice family gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
