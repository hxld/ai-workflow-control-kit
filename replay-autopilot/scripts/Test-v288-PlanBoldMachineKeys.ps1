param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v288-plan-bold-machine-keys'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$oracle = [ordered]@{
    files = @(
        [ordered]@{ path = 'claim-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH' },
        [ordered]@{ path = 'claim-core/src/main/java/com/acme/StatefulSideEffectService.java'; is_production = $true; weight = 'HIGH' }
    )
} | ConvertTo-Json -Depth 6
Write-Utf8 (Join-Path $TestRoot 'ORACLE_DIFF_ANALYSIS.json') $oracle

Write-Utf8 (Join-Path $TestRoot 'PLAN_RESULT.md') @'
**plan_status**: PROCEED
**selected_strategy**: core-stateful-first
**first_slice**: CoreFlowService.java and StatefulSideEffectService.java via ExistingCoreFlowService.process
**first_red_test**: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
**oracle_production_file_overlap**: 100%
**oracle_high_weight_coverage**: 2/2
**carrier_search**: performed
**carrier_search_queries**: rg "ExistingCoreFlowService" claim-core; rg "CoreFlowService" claim-core; rg "StatefulSideEffectService" claim-core
**existing_production_carriers**: ExistingCoreFlowService.process
**selected_carrier_from_search**: ExistingCoreFlowService.process
**new_service_proposed**: false
**new_service_justification**: none
'@

foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
    Write-Utf8 (Join-Path $TestRoot $file) 'candidate mentions CoreFlowService.java and StatefulSideEffectService.java'
}
Write-Utf8 (Join-Path $TestRoot 'FAMILY_CONTRACT.json') '{"families":[]}'
Write-Utf8 (Join-Path $TestRoot 'REPLAY_PLAN.md') 'CoreFlowService.java; StatefulSideEffectService.java; ExistingCoreFlowService.process'
Write-Utf8 (Join-Path $TestRoot 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExistingCoreFlowService.process
first_slice: CoreFlowService.java and StatefulSideEffectService.java
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
GREEN cannot claim core DONE from helper/static-only proof. Forbidden Substitute: Mock Stub InMemory TestOnly Placeholder.
'@
Write-Utf8 (Join-Path $TestRoot 'EXPECTED_DIFF_MATRIX.md') 'requirement -> CoreFlowService.java; StatefulSideEffectService.java -> validation: ExistingCoreFlowServiceTest -> closure: DB side effect asserted'
Write-Utf8 (Join-Path $TestRoot 'SIDE_EFFECT_LEDGER.md') 'ExistingCoreFlowService.process -> DB write -> transaction proof'
Write-Utf8 (Join-Path $TestRoot 'TEST_CHARTER.md') 'RED/GREEN order through ExistingCoreFlowService.process'
Write-Utf8 (Join-Path $TestRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
highest_weight_open_gate: core_path
selected_real_entry: ExistingCoreFlowService.process
selected_carrier: ExistingCoreFlowService.process
target_subsurface_or_carrier: ExistingCoreFlowService.process
production_boundary: claim-core production service
proof_kind: real_entry_behavior_test
real_carrier_kind: production_service
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
public_entry_contract_coverage: none_with_reason: service entry
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: service triggers DB write
expected_production_diff: CoreFlowService.java and StatefulSideEffectService.java behavior change
red_expectation: assertion failure before implementation
green_minimum_implementation: production service closes real entry behavior
forbidden_substitute_proof: no Mock/Stub/InMemory/TestOnly used
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
required_sibling_surfaces: none_with_reason: core-only test fixture
fail_closed_condition: block if ExistingCoreFlowService.process is not exercised
'@

$verifierPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifierPath -ReplayRoot $TestRoot -Stage Plan | Out-Null
$verify = Get-Content -LiteralPath (Join-Path $TestRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$issueText = @($verify.issues) -join ';'
Assert-True ($verify.verification_status -eq 'PASS') "Bold machine keys should PASS, issues=$issueText"
Assert-True ($verify.oracle_overlap_percent -eq 100) 'Bold oracle_production_file_overlap should not hide overlap evidence'
Assert-True ($issueText -notmatch 'carrier_search_missing|carrier_search_queries_missing|carrier_search_existing_carriers_missing|carrier_search_selected_carrier_missing|plan_result_missing:oracle_production_file_overlap') 'Bold keys must not trigger machine-key missing issues'

[ordered]@{
    status = 'PASS'
    assertions = 3
    cases = @(
        'bold_machine_keys_parse',
        'bold_oracle_overlap_parse',
        'bold_carrier_fields_parse'
    )
} | ConvertTo-Json -Depth 5
