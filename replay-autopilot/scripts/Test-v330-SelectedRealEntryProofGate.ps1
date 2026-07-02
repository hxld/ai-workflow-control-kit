param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v330-selected-real-entry-proof-gate'),
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

function New-PlanFixture {
    param([string]$Root, [string]$ProofText)
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') (@{
        files = @(
            @{ path = 'example-core/src/main/java/com/acme/ExistingCoreFlowService.java'; is_production = $true; weight = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6)
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
plan_status: PROCEED
selected_strategy: core-first
first_slice: S1
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 1/1
carrier_search: performed
carrier_search_queries: rg "ExistingCoreFlowService" example-core; rg "shouldCloseCoreFlow" example-server; rg "process" example-core
existing_production_carriers: ExistingCoreFlowService.process
selected_carrier_from_search: ExistingCoreFlowService.process
new_service_proposed: false
new_service_justification: none
'@
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $file) 'candidate covers ExistingCoreFlowService.process'
    }
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[]}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'core_entry ExistingCoreFlowService.process'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: ExistingCoreFlowService.process; first_slice: S1; first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow; Forbidden Substitute Mock Stub InMemory TestOnly Placeholder'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'validation closure ExistingCoreFlowService'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED GREEN'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') $ProofText
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }

$baseProofWithoutEntry = @'
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: ExistingCoreFlowServiceTest.shouldCloseCoreFlow
public_entry_contract_coverage: not_public_entry_with_reason
selected_carrier: ExistingCoreFlowService.process
target_subsurface_or_carrier: ExistingCoreFlowService.process
real_carrier_kind: production_service_method
minimum_side_effect_or_blocker: service triggers DB write
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason: core entry only
production_boundary: example-core/src/main/java/com/acme/ExistingCoreFlowService.java
expected_production_diff: ExistingCoreFlowService behavior
red_expectation: assertion failure before implementation
green_minimum_implementation: implement real service behavior
proof_kind: real_entry_behavior
forbidden_substitute_proof: no helper/static/mock/test-only carrier
fail_closed_condition: block unless service is exercised
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: ExistingCoreFlowService.process
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "ExistingCoreFlowService" example-core
'@

$missingRoot = Join-Path $TestRoot 'missing-selected-real-entry'
New-PlanFixture -Root $missingRoot -ProofText $baseProofWithoutEntry

$verifyPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -ReplayRoot $missingRoot -Stage Plan | Out-Null
$verify = Get-Content -LiteralPath (Join-Path $missingRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$issues = @($verify.issues | ForEach-Object { [string]$_ })
Assert-True ($issues -contains 'first_slice_proof_schema_missing:selected_real_entry') "Verify-PlanContract must reject missing selected_real_entry; issues=$($issues -join ';')"

$dryRunPath = Join-Path $PSScriptRoot 'ReplayDryRunGate.ps1'
$dry = & powershell -NoProfile -ExecutionPolicy Bypass -File $dryRunPath -ReplayRoot $missingRoot -Mode FirstSliceProofPlan | ConvertFrom-Json
$missingFields = @($dry.missing_fields | ForEach-Object { [string]$_ })
Assert-True ($dry.status -eq 'BLOCKED_PLAN_MISMATCH') "Dry-run must block missing selected_real_entry; status=$($dry.status)"
Assert-True ($missingFields -contains 'selected_real_entry') "Dry-run missing fields must include selected_real_entry; missing=$($missingFields -join ';')"

$validRoot = Join-Path $TestRoot 'valid-selected-real-entry'
$validProof = $baseProofWithoutEntry -replace 'first_red_test:', "selected_real_entry: ExistingCoreFlowService.process`nfirst_red_test:"
New-PlanFixture -Root $validRoot -ProofText $validProof
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -ReplayRoot $validRoot -Stage Plan | Out-Null
$verifyValid = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$validIssues = @($verifyValid.issues | ForEach-Object { [string]$_ })
Assert-True ($validIssues -notcontains 'first_slice_proof_schema_missing:selected_real_entry') "Valid selected_real_entry should not be reported missing; issues=$($validIssues -join ';')"

$runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
Assert-True ($runnerText.Contains('selected_real_entry: <Phase0 selected_real_entry>')) 'Plan repair prompt must list selected_real_entry exact key'
Assert-True ($runnerText.Contains('first_slice_proof_schema_missing:selected_real_entry')) 'Plan repair prompt must handle missing selected_real_entry issue'

[ordered]@{
    status = 'PASS'
    assertions = 5
    cases = @(
        'plan_verifier_rejects_missing_selected_real_entry',
        'dry_run_blocks_missing_selected_real_entry',
        'valid_selected_real_entry_allowed',
        'repair_prompt_lists_selected_real_entry',
        'repair_prompt_routes_missing_selected_real_entry'
    )
} | ConvertTo-Json -Depth 5
