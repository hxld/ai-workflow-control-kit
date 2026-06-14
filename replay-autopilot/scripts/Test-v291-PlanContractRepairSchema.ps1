param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v291-plan-contract-repair-schema'),
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

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8

foreach ($token in @(
    'expected_production_diff',
    'red_expectation',
    'green_minimum_implementation',
    'forbidden_substitute_proof',
    'coverage_cap_if_not_closed',
    'coverage_cap_if_missing',
    'pattern_to_follow',
    'pattern_return_type',
    'pattern_error_handling',
    'pattern_evidence_source'
)) {
    Assert-True ($runner.Contains($token)) "Contract repair prompt must include $token"
}

Assert-True ($runner.Contains('real_entry_behavior | stateful_side_effect') -and $runner.Contains('production_entry_or_service | production_controller_or_route')) 'Contract repair prompt must list allowed proof/carrier enums'
Assert-True ($runner.Contains('oracle_new_service_no_existing_orchestration') -and $planPrompt.Contains('oracle_new_service_no_existing_orchestration')) 'New service justification token must be documented in runner and plan prompt'
Assert-True ($runner.Contains('stale blocker text') -and $runner.Contains('oracle_overlap_percent >= 50')) 'Contract repair prompt must remove stale oracle overlap blockers after successful expansion'

$root = Join-Path $TestRoot 'justification-fixture'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Write-Utf8 (Join-Path $root 'ORACLE_DIFF_ANALYSIS.json') (@{
    files = @(
        @{ path = 'example-core/src/main/java/com/acme/NewOrchestrationService.java'; is_production = $true; weight = 'HIGH' }
    )
} | ConvertTo-Json -Depth 6)
Write-Utf8 (Join-Path $root 'PLAN_RESULT.md') @'
- plan_status: PROCEED
- selected_strategy: core-first
- first_slice: NewOrchestrationService
- first_red_test: mvn -s <maven-settings> -f {{WORKTREE}}\pom.xml test -pl example-server -am -Dtest=NewOrchestrationServiceTest
- oracle_production_file_overlap: 100%
- oracle_high_weight_coverage: 1/1
- carrier_search: performed
- carrier_search_queries: rg "ExistingFlow" example-core; rg "Orchestration" example-core; rg "process" example-core
- existing_production_carriers: ExistingFlowService; ExistingTaskService; ExistingProgressService
- selected_carrier_from_search: NewOrchestrationService (new service in oracle)
- new_service_proposed: true
- new_service_justification: Oracle has NEW service for complete workflow; no existing carrier handles full flow
'@
foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
    Write-Utf8 (Join-Path $root $file) 'candidate covers NewOrchestrationService'
}
Write-Utf8 (Join-Path $root 'FAMILY_CONTRACT.json') '{"families":[]}'
Write-Utf8 (Join-Path $root 'REPLAY_PLAN.md') 'core_entry NewOrchestrationService'
Write-Utf8 (Join-Path $root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: NewOrchestrationService.process; Forbidden Substitute Mock Stub InMemory TestOnly Placeholder'
Write-Utf8 (Join-Path $root 'EXPECTED_DIFF_MATRIX.md') 'validation closure NewOrchestrationService'
Write-Utf8 (Join-Path $root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction'
Write-Utf8 (Join-Path $root 'TEST_CHARTER.md') 'RED GREEN'
Write-Utf8 (Join-Path $root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: mvn -s <maven-settings> -f {{WORKTREE}}\pom.xml test -pl example-server -am -Dtest=NewOrchestrationServiceTest
selected_real_entry: NewOrchestrationService.process
public_entry_contract_coverage: not_public_entry_with_reason
selected_carrier: NewOrchestrationService.process
target_subsurface_or_carrier: NewOrchestrationService.process
real_carrier_kind: production_service
minimum_side_effect_or_blocker: state write through existing services
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason
production_boundary: example-core/src/main/java/com/acme/NewOrchestrationService.java
expected_production_diff: NewOrchestrationService behavior
red_expectation: assertion failure before implementation
green_minimum_implementation: implement real service behavior
proof_kind: real_entry_behavior
forbidden_substitute_proof: no helper/static/mock/test-only carrier
fail_closed_condition: block unless service is exercised
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: ExistingFlowService.process
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "ExistingFlowService" example-core
'@
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $root -Stage Plan | Out-Null
$verify = Get-Content -LiteralPath (Join-Path $root 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ((@($verify.issues) -notcontains 'carrier_search_new_service_unjustified')) "Verifier should accept oracle-new-service/no-existing-flow justification, issues=$(@($verify.issues) -join ';')"

[ordered]@{
    status = 'PASS'
    assertions = 14
    cases = @(
        'contract_repair_full_schema_tokens',
        'contract_repair_allowed_enums',
        'new_service_token_documented',
        'stale_oracle_blocker_removal_instruction',
        'verifier_accepts_oracle_new_service_justification'
    )
} | ConvertTo-Json -Depth 5
