param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v295-executable-first-slice-plan'),
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
    param(
        [string]$Root,
        [string]$FirstSlice = 'S1_CoreTracerBullet',
        [string]$MinimumSideEffect = 'CoreFlowService.process writes case status through mapper and test asserts persisted status value',
        [string]$ProductionBoundary = 'claim-core/src/main/java/com/acme/CoreFlowService.java#process',
        [string]$ExpectedProductionDiff = 'CoreFlowService behavior change and mapper status write',
        [string]$GreenMinimum = 'Implement CoreFlowService.process minimum production path and make CoreFlowServiceTest pass',
        [switch]$OmitMinimumSideEffect
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') (@{
        files = @(
            @{ path = 'claim-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6)
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
plan_status: PROCEED
selected_strategy: core-first
first_slice: S1_CoreTracerBullet
first_red_test: mvn -s D:\maven\settings\settings.xml -f {{WORKTREE}}\pom.xml -pl claim-server -am -Dtest=CoreFlowServiceTest#processWritesStatus test
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 1/1
carrier_search: performed
carrier_search_queries: rg "CoreFlowService" claim-core; rg "processWritesStatus" claim-core; rg "case status" claim-core
existing_production_carriers: CoreFlowService
selected_carrier_from_search: CoreFlowService
new_service_proposed: false
oracle_missing_high_weight_files: none
oracle_expansion_plan: claim-core/src/main/java/com/acme/CoreFlowService.java -> CoreFlowService -> S1/CoreFlowServiceTest
oracle_out_of_scope_files: none
'@
    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $file) 'candidate covers claim-core/src/main/java/com/acme/CoreFlowService.java'
    }
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[]}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') "core_entry CoreFlowService claim-core/src/main/java/com/acme/CoreFlowService.java $FirstSlice"
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') "selected_real_entry: CoreFlowService.process`nGREEN Phase Requirements: complete GREEN in the same executable first slice; Forbidden Substitute Mock Stub InMemory TestOnly Placeholder"
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') "validation closure claim-core/src/main/java/com/acme/CoreFlowService.java"
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction status write via mapper'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED GREEN CoreFlowServiceTest asserts production side effect'

    $minimumLine = if ($OmitMinimumSideEffect) { '' } else { "minimum_side_effect_or_blocker: $MinimumSideEffect`n" }
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: $FirstSlice
highest_weight_open_gate: core_entry
first_red_test: mvn -s D:\maven\settings\settings.xml -f {{WORKTREE}}\pom.xml -pl claim-server -am -Dtest=CoreFlowServiceTest#processWritesStatus test
selected_real_entry: CoreFlowService.process
public_entry_contract_coverage: not_public_entry_with_reason
selected_carrier: CoreFlowService.process
target_subsurface_or_carrier: CoreFlowService.process
production_boundary: $ProductionBoundary
proof_kind: stateful_side_effect
real_carrier_kind: production_service
$minimumLine`nforbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason
expected_production_diff: $ExpectedProductionDiff
red_expectation: CoreFlowServiceTest fails before process writes status
green_minimum_implementation: $GreenMinimum
forbidden_substitute_proof: no helper/static/mock/test-only carrier
fail_closed_condition: block unless RED and GREEN both run against CoreFlowService
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: ExistingStatusService.process
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "ExistingStatusService" claim-core
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

$verifier = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
$runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8

$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($verifier, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Verify-PlanContract.ps1 must parse'
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($runner, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Run-ReplayLoop.ps1 must parse'

Assert-True ($planPrompt.Contains('v295_executable_first_slice_gate')) 'Plan prompt must document the v295 executable first-slice hard gate'
Assert-True ($planPrompt.Contains('GREEN') -and $planPrompt.Contains('S2/S3')) 'Plan prompt must forbid deferring GREEN or side effects'
Assert-True ($runner.Contains('first_slice_proof_invalid:contract_only_first_slice')) 'Repair prompt must mention contract-only first-slice issue'
Assert-True ($runner.Contains('Do not defer GREEN or production side-effect evidence to S2/S3')) 'Repair prompt must forbid deferring GREEN'

$validRoot = Join-Path $TestRoot 'valid'
New-PlanFixture -Root $validRoot
$validVerify = Invoke-Verify -Root $validRoot
Assert-True ($validVerify.verification_status -eq 'PASS') "Executable first slice should PASS, issues=$(@($validVerify.issues) -join ';')"

$contractOnlyRoot = Join-Path $TestRoot 'contract-only'
New-PlanFixture -Root $contractOnlyRoot `
    -FirstSlice 'S1_Contract_and_RED_Tests' `
    -MinimumSideEffect 'contract definition only, no production code' `
    -ProductionBoundary 'NONE - Slice 1 does not touch production code' `
    -ExpectedProductionDiff 'NONE - Slice 1 produces no production code' `
    -GreenMinimum 'Implement CoreFlowService in Slice 2'
$contractOnlyVerify = Invoke-Verify -Root $contractOnlyRoot
Assert-True ((@($contractOnlyVerify.issues) -contains 'first_slice_proof_invalid:contract_only_first_slice')) 'Contract-only first slice must fail'
Assert-True ((@($contractOnlyVerify.issues) -contains 'first_slice_proof_invalid:minimum_side_effect_or_blocker')) 'Contract-only minimum side effect must fail'
Assert-True ((@($contractOnlyVerify.issues) -contains 'first_slice_proof_invalid:expected_production_diff_none')) 'NONE expected production diff must fail'

$missingMinimumRoot = Join-Path $TestRoot 'missing-minimum'
New-PlanFixture -Root $missingMinimumRoot -OmitMinimumSideEffect
$missingMinimumVerify = Invoke-Verify -Root $missingMinimumRoot
Assert-True ((@($missingMinimumVerify.issues) -contains 'first_slice_proof_missing:minimum_side_effect_or_blocker') -or (@($missingMinimumVerify.issues) -contains 'first_slice_proof_schema_missing:minimum_side_effect_or_blocker')) 'Missing minimum side effect key must fail'

[ordered]@{
    status = 'PASS'
    assertions = 11
    cases = @(
        'scripts_parse',
        'plan_prompt_executable_first_slice_gate',
        'repair_prompt_contract_only_gate',
        'executable_first_slice_passes',
        'contract_only_first_slice_fails',
        'missing_minimum_side_effect_fails'
    )
} | ConvertTo-Json -Depth 5
