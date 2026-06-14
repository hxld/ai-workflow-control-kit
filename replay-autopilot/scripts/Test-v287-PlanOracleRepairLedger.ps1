param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v287-plan-oracle-repair-ledger'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-PlanReplayRoot {
    param(
        [string]$Root,
        [bool]$WithRepairLedger
    )

    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    $oracle = [ordered]@{
        files = @(
            [ordered]@{ path = 'example-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH' },
            [ordered]@{ path = 'example-core/src/main/java/com/acme/StatefulSideEffectService.java'; is_production = $true; weight = 'HIGH' },
            [ordered]@{ path = 'example-web/src/main/java/com/acme/ExportController.java'; is_production = $true; weight = 'MEDIUM' },
            [ordered]@{ path = 'example-provider/src/main/java/com/acme/ExactContractMapper.java'; is_production = $true; weight = 'MEDIUM' },
            [ordered]@{ path = 'example-domain/src/main/java/com/acme/ExactContractDto.java'; is_production = $true; weight = 'LOW' }
        )
    } | ConvertTo-Json -Depth 6
    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') $oracle

    $ledger = ''
    if ($WithRepairLedger) {
        $ledger = @'

## Oracle Coverage Repair Ledger
oracle_missing_high_weight_files: example-core/src/main/java/com/acme/StatefulSideEffectService.java
oracle_expansion_plan: StatefulSideEffectService.java -> ExistingCoreFlowService.process -> slice-02/AiFlowStatefulSideEffectTest
oracle_out_of_scope_files: none
'@
    }

    $planResult = @"
plan_status: PROCEED
selected_strategy: core-stateful-first
implementation_model_recommendation: gpt-5.3-codex
required_files: example-core/src/main/java/com/acme/CoreFlowService.java
oracle_production_file_overlap: 25%
oracle_high_weight_coverage: 1/2
carrier_search: performed
carrier_search_queries: rg "CoreFlowService" example-core; rg "process" example-core; rg "ExistingCoreFlowService" example-core
existing_production_carriers: ExistingCoreFlowService.process
selected_carrier_from_search: ExistingCoreFlowService.process
new_service_proposed: false
new_service_justification: none
first_slice: CoreFlowService.java via ExistingCoreFlowService.process
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
core_closure_required: true
deploy_surface_required: false
$ledger
"@
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') $planResult

    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $file) "candidate mentions CoreFlowService.java and ExistingCoreFlowService.process"
    }
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[]}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'slice-01 CoreFlowService.java existing production carrier ExistingCoreFlowService.process'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExistingCoreFlowService.process
first_slice: CoreFlowService.java via ExistingCoreFlowService.process
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
GREEN cannot claim core DONE from helper/static-only proof. Forbidden Substitute: Mock Stub InMemory TestOnly Placeholder.
'@
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'requirement -> CoreFlowService.java -> behavior -> ExistingCoreFlowServiceTest'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'ExistingCoreFlowService.process -> stateful side effect -> DB proof required'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED/GREEN order through ExistingCoreFlowService.process'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
highest_weight_open_gate: core_path
selected_carrier: ExistingCoreFlowService.process
target_subsurface_or_carrier: ExistingCoreFlowService.process
production_boundary: example-core production service
proof_kind: real_entry_behavior_test
real_carrier_kind: service
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
public_entry_contract_coverage: none_with_reason: service entry
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason: core-only test fixture
fail_closed_condition: block if ExistingCoreFlowService.process is not exercised
'@
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        test_root = $TestRoot
    } | ConvertTo-Json -Depth 4
    exit 0
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'
$runnerPath = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$verifierPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'

$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$verifier = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

Assert-True ($prompt -match 'Oracle Coverage Repair Ledger') 'Plan prompt must require Oracle Coverage Repair Ledger'
Assert-True (($prompt -match 'oracle_missing_high_weight_files') -and ($prompt -match 'oracle_expansion_plan') -and ($prompt -match 'oracle_out_of_scope_files')) 'Plan prompt must require repair ledger fields'
Assert-True ($runner -match 'oracle_overlap_repair_ledger_missing') 'Repair prompt must repair oracle_overlap_repair_ledger_missing'
Assert-True ($verifier -match 'oracle_overlap_repair_ledger_missing') 'Verifier must emit oracle_overlap_repair_ledger_missing'
Assert-True (($verifier -match 'oracle_missing_production_files') -and ($verifier -match 'oracle_missing_high_weight_files')) 'Verifier must output missing oracle files'

$withoutLedgerRoot = Join-Path $TestRoot 'without-ledger'
New-PlanReplayRoot -Root $withoutLedgerRoot -WithRepairLedger:$false
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifierPath -ReplayRoot $withoutLedgerRoot -Stage Plan | Out-Null
$verifyWithout = Get-Content -LiteralPath (Join-Path $withoutLedgerRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True (($verifyWithout.issues -contains 'oracle_overlap_repair_ledger_missing') -and (($verifyWithout.issues -join ';') -match 'oracle_overlap_below_threshold')) 'Low-overlap plan without repair ledger must fail with repair ledger issue'
Assert-True (($verifyWithout.oracle_missing_high_weight_files | Where-Object { $_ -match 'StatefulSideEffectService\.java' }).Count -eq 1) 'Verifier must expose missing high-weight oracle file'

$withLedgerRoot = Join-Path $TestRoot 'with-ledger'
New-PlanReplayRoot -Root $withLedgerRoot -WithRepairLedger:$true
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifierPath -ReplayRoot $withLedgerRoot -Stage Plan | Out-Null
$verifyWith = Get-Content -LiteralPath (Join-Path $withLedgerRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True (-not ($verifyWith.issues -contains 'oracle_overlap_repair_ledger_missing')) 'Low-overlap plan with populated repair ledger must not fail the ledger-specific check'
Assert-True (($verifyWith.issues -join ';') -match 'oracle_overlap_below_threshold') 'Repair ledger does not waive the 50% oracle overlap hard gate'

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'prompt_requires_oracle_repair_ledger',
        'prompt_requires_ledger_fields',
        'runner_repairs_ledger_issue',
        'verifier_emits_ledger_issue',
        'verifier_outputs_missing_oracle_files',
        'low_overlap_without_ledger_fails',
        'missing_high_weight_exposed',
        'low_overlap_with_ledger_passes_ledger_specific_check',
        'ledger_does_not_waive_overlap_gate'
    )
} | ConvertTo-Json -Depth 6
