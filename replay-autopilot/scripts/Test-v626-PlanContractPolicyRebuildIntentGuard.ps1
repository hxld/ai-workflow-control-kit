#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for policy rebuild intent scoping in Verify-PlanContract.

.DESCRIPTION
The policy rebuild source-chain gate must not activate merely because an
ordinary TaskProcessor plan mentions policyNum/insureNum as side-effect fields.
It should activate only when the plan or SOURCE_CHAIN_CONTRACT explicitly names
the rebuild/source-chain boundary.
#>

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ''
    )
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-PlanFixture {
    param(
        [string]$Root,
        [switch]$WithExplicitRebuildIntent
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    $intentLine = if ($WithExplicitRebuildIntent) {
        'source_chain_intent: ExampleApplyClaimApiTaskProcessor.rebuildTaskData preserves policyNum and insureNum through RequestBuildContext'
    } else {
        'side_effect_field_mapping: ExampleApplyClaimApiTaskProcessor.handleTaskResponse writes compensate detail fields protectionItemId, compensateAmount, policyNum, insureNum'
    }

    $planMd = @"
plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg "class ExampleApplyClaimApiTaskProcessor"; rg "handleTaskResponse"; rg "ExampleFlowService"
existing_production_carriers: ExampleApplyClaimApiTaskProcessor; ExampleFlowService; CaseRouteService
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
new_service_proposed: false
oracle_production_file_overlap: 80%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: stateful_side_effect -> ExampleApplyClaimApiTaskProcessor.handleTaskResponse -> RED auto-flow side effects absent -> GREEN compensate writes and status change -> executable mapper assertions
first_slice: S1-CORE auto-flow trigger
first_red_test: ExampleApplyClaimApiTaskProcessorTest.testHandleTaskResponse_AutoFlowTriggered_Success
core_closure_required: true
blocker: none
next_action: PROCEED_TO_SLICE_1
$intentLine
"@
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') $planMd

    Write-JsonFile (Join-Path $Root 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'example-core/src/main/java/com/example/ExampleApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 42
        expected_test_class = 'ExampleApplyClaimApiTaskProcessorTest'
        expected_test_method = 'testHandleTaskResponse_AutoFlowTriggered_Success'
        side_effects = @('insert compensate detail with policyNum and insureNum fields')
        expected_side_effects = @([ordered]@{ state = 'compensate_detail'; operation = 'insert'; proof = 'mapper assertion includes policyNum and insureNum field mapping' })
        expected_assertions = @('verify compensate detail mapper receives policyNum and insureNum field values')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -f worktree/pom.xml -pl example-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
        blocker = 'none'
        invalid_reason = 'none'
    })

    Write-Utf8 (Join-Path $Root 'PHASE0_RESULT.md') @'
phase0_status: PROCEED
selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask, ExampleApplyClaimApiTaskResponse)
'@
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') "Slice 1: stateful_side_effect auto-flow through ExampleApplyClaimApiTaskProcessor.handleTaskResponse."
    Write-Utf8 (Join-Path $Root 'PLAN_SELECTION.md') "Selected: stateful_side_effect core-entry plan."
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') "requirement -> ExampleApplyClaimApiTaskProcessor.handleTaskResponse -> LOGIC_FIX -> mapper assertions."
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @"
selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask, ExampleApplyClaimApiTaskResponse)
first_red_test: ExampleApplyClaimApiTaskProcessorTest.testHandleTaskResponse_AutoFlowTriggered_Success
shallow_green_ban: no helper-only or DTO-only proof
"@
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') "entry -> side effect -> state -> proof`nExampleApplyClaimApiTaskProcessor.handleTaskResponse -> insert compensate detail -> policyNum/insureNum mapped -> mapper assertion"
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') @"
test_surface: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
entry_point: ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask, ExampleApplyClaimApiTaskResponse)
test_class: ExampleApplyClaimApiTaskProcessorTest
test_method: testHandleTaskResponse_AutoFlowTriggered_Success
DB Verification: mapper argument captures compensate detail with policyNum and insureNum field mapping
Side Effects: verify compensate detail insert and case route update
"@
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1-CORE auto-flow trigger
golden_slice_binding: stateful_side_effect -> ExampleApplyClaimApiTaskProcessor.handleTaskResponse -> RED auto-flow side effects absent -> GREEN compensate writes and status change -> executable mapper assertions
highest_weight_open_gate: core_entry
first_slice_family: core_entry
first_red_test: ExampleApplyClaimApiTaskProcessorTest.testHandleTaskResponse_AutoFlowTriggered_Success
selected_real_entry: ExampleApplyClaimApiTaskProcessor.handleTaskResponse(ExampleApplyClaimApiTask, ExampleApplyClaimApiTaskResponse)
public_entry_contract_coverage: real public task processor entry
selected_carrier: ExampleApplyClaimApiTaskProcessor
target_subsurface_or_carrier: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
production_boundary: ExampleApplyClaimApiTaskProcessor.handleTaskResponse
proof_kind: stateful_side_effect
real_carrier_kind: production_entry_or_service
required_sibling_surfaces: none
minimum_side_effect_or_blocker: compensate detail insert
expected_production_diff: ExampleApplyClaimApiTaskProcessor.handleTaskResponse conditional auto-flow call
red_expectation: auto-flow side effects absent before production change
green_minimum_implementation: invoke auto-flow and persist side effects
forbidden_substitute_check: passed
forbidden_substitute_proof: real entry with mapper assertions
fail_closed_condition: block if no executable mapper assertion
coverage_cap_if_not_closed: 10 if no stateful side effect proof
target_carrier_file_path: example-core/src/main/java/com/example/ExampleApplyClaimApiTaskProcessor.java
target_carrier_line_number: 42
expected_test_class: ExampleApplyClaimApiTaskProcessorTest
expected_test_method: testHandleTaskResponse_AutoFlowTriggered_Success
expected_assertions: ["mapper receives compensate detail","case route updated","progress inserted"]
expected_side_effects: [{"state":"compensate_detail","operation":"insert","proof":"mapper assertion"}]
"@
    Write-JsonFile (Join-Path $Root 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
        source_chain_mode = 'none'
    })

    return $worktree
}

function Invoke-PlanVerify {
    param(
        [string]$Root,
        [string]$Worktree
    )

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') `
        -ReplayRoot $Root `
        -Stage Plan `
        -Worktree $Worktree `
        -SkipCarrierAndOracleChecks | Out-Null

    $verifyPath = Join-Path $Root 'PLAN_CONTRACT_VERIFY.json'
    Assert-True 'verify_artifact_written' (Test-Path -LiteralPath $verifyPath) $Root
    return Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v626-plan-policy-intent-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    $autoFlowRoot = Join-Path $tmp 'auto-flow-taskprocessor-fields'
    $autoFlowWorktree = Write-PlanFixture -Root $autoFlowRoot
    $autoFlowVerify = Invoke-PlanVerify -Root $autoFlowRoot -Worktree $autoFlowWorktree
    $autoFlowJson = $autoFlowVerify | ConvertTo-Json -Depth 12
    Assert-True 'taskprocessor_field_mapping_does_not_activate_policy_gate' ($autoFlowJson -notmatch 'policy_rebuild_source_chain_plan_gate_active|policy_rebuild_plan_') $autoFlowJson
    $assertions++

    $rebuildRoot = Join-Path $tmp 'explicit-rebuild-intent'
    $rebuildWorktree = Write-PlanFixture -Root $rebuildRoot -WithExplicitRebuildIntent
    $rebuildVerify = Invoke-PlanVerify -Root $rebuildRoot -Worktree $rebuildWorktree
    $rebuildJson = $rebuildVerify | ConvertTo-Json -Depth 12
    Assert-True 'explicit_rebuild_intent_still_activates_policy_gate' ($rebuildJson -match 'policy_rebuild_source_chain_plan_gate_active') $rebuildJson
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'taskprocessor_policy_fields_without_rebuild_intent_do_not_trigger_policy_gate',
            'explicit_rebuild_intent_still_triggers_policy_gate'
        )
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tmp)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }
}
