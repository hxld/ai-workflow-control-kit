param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v296-plan-early-evolution-core-tracer'),
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

function New-CoreFixture {
    param(
        [string]$Root,
        [string]$SelectedCarrier = 'CoreFlowService.process',
        [string]$ProofKind = 'stateful_side_effect',
        [string]$RealCarrierKind = 'production_service_method',
        [string]$ProductionBoundary = 'example-core/src/main/java/com/acme/CoreFlowService.java#process',
        [string]$ExpectedProductionDiff = 'CoreFlowService behavior change and status write',
        [string]$MinimumSideEffect = 'CoreFlowService.process writes status through mapper and test asserts status value'
    )
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') (@{
        files = @(
            @{ path = 'example-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6)
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
plan_status: PROCEED
selected_strategy: core-first
first_slice: S1_CoreTracerBullet
first_red_test: mvn -s <maven-settings> -f {{WORKTREE}}\pom.xml -pl example-server -am -Dtest=CoreFlowServiceTest#processWritesStatus test
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 1/1
carrier_search: performed
carrier_search_queries: rg "CoreFlowService" example-core; rg "processWritesStatus" example-core; rg "case status" example-core
existing_production_carriers: CoreFlowService
selected_carrier_from_search: CoreFlowService
new_service_proposed: false
oracle_missing_high_weight_files: none
oracle_expansion_plan: example-core/src/main/java/com/acme/CoreFlowService.java -> CoreFlowService -> S1/CoreFlowServiceTest
oracle_out_of_scope_files: none
'@
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $file) 'candidate covers example-core/src/main/java/com/acme/CoreFlowService.java'
    }
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[]}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'core_entry CoreFlowService example-core/src/main/java/com/acme/CoreFlowService.java'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: CoreFlowService.process; GREEN Phase Requirements; Forbidden Substitute Mock Stub InMemory TestOnly Placeholder'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'validation closure example-core/src/main/java/com/acme/CoreFlowService.java'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED GREEN CoreFlowServiceTest asserts production side effect'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1_CoreTracerBullet
highest_weight_open_gate: core_entry
first_red_test: mvn -s <maven-settings> -f {{WORKTREE}}\pom.xml -pl example-server -am -Dtest=CoreFlowServiceTest#processWritesStatus test
selected_real_entry: CoreFlowService.process
public_entry_contract_coverage: not_public_entry_with_reason
selected_carrier: $SelectedCarrier
target_subsurface_or_carrier: CoreFlowService.process
production_boundary: $ProductionBoundary
proof_kind: $ProofKind
real_carrier_kind: $RealCarrierKind
minimum_side_effect_or_blocker: $MinimumSideEffect
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason
expected_production_diff: $ExpectedProductionDiff
red_expectation: CoreFlowServiceTest fails before process writes status
green_minimum_implementation: Implement CoreFlowService.process minimum production path and make CoreFlowServiceTest pass
forbidden_substitute_proof: no helper/static/mock/test-only carrier
fail_closed_condition: block unless RED and GREEN both run against CoreFlowService
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: ExistingStatusService.process
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "ExistingStatusService" example-core
"@
}

function Invoke-Verify {
    param([string]$Root)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $Root -Stage Plan | Out-Null
    return (Get-Content -LiteralPath (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
$verifier = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8

$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($runner, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Run-ReplayLoop.ps1 must parse'
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($verifier, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Verify-PlanContract.ps1 must parse'

Assert-True ($planPrompt.Contains('v296_core_executable_tracer_selection')) 'Plan prompt must contain v296 core tracer selection anchor'
Assert-True ($runner.Contains('Do not set plan_status: BLOCKED to bypass v295') -or $runner.Contains('do not leave the plan BLOCKED as a bypass')) 'Repair prompt must forbid BLOCKED bypass'
Assert-True ($runner.Contains('Knowledge version refreshed for next round after plan early-stop evolution')) 'Early Plan stop must run evolution and refresh version'
Assert-True ($runner.Contains('continue')) 'Early Plan stop evolution path must continue to the next round'

$validRoot = Join-Path $TestRoot 'valid-core'
New-CoreFixture -Root $validRoot
$validVerify = Invoke-Verify -Root $validRoot
Assert-True ($validVerify.verification_status -eq 'PASS') "Core executable tracer should PASS, issues=$(@($validVerify.issues) -join ';')"

$staticRoot = Join-Path $TestRoot 'static-core'
New-CoreFixture -Root $staticRoot `
    -SelectedCarrier 'ExampleClaimConstant + TExampleModuleConfigDto' `
    -ProofKind 'payload_shape_behavior' `
    -RealCarrierKind 'production_enum; production_dto' `
    -MinimumSideEffect 'payload shape definition only'
$staticVerify = Invoke-Verify -Root $staticRoot
Assert-True ((@($staticVerify.issues) -contains 'first_slice_proof_invalid:core_entry_static_carrier')) 'Core-entry static/DTO carrier must fail'

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'scripts_parse',
        'plan_prompt_core_tracer_anchor',
        'repair_prompt_blocks_blocked_bypass',
        'plan_early_stop_evolution_continue',
        'core_executable_tracer_passes',
        'core_static_carrier_fails'
    )
} | ConvertTo-Json -Depth 5
