param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'

$TestRoot = Join-Path $PSScriptRoot '.tmp\v289-debug'
if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$validRoot = Join-Path $TestRoot 'valid-plan'
New-Item -ItemType Directory -Force -Path $validRoot | Out-Null

Set-Content -LiteralPath (Join-Path $validRoot 'PLAN_RESULT.md') -Value @"
- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "ExistingCoreFlowService" example-core; rg "CoreFlowService" example-core; rg "process" example-core
- existing_production_carriers: ExistingCoreFlowService.process
- selected_carrier_from_search: ExistingCoreFlowService.process
- new_service_proposed: false
- new_service_justification: none
- oracle_production_file_overlap: 100%
"@ -Encoding UTF8

# All required plan files
Set-Content -LiteralPath (Join-Path $validRoot 'PLAN_CANDIDATE_1.md') 'candidate mentions CoreFlowService.java and ExistingCoreFlowService.process' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'PLAN_CANDIDATE_2.md') 'candidate mentions CoreFlowService.java and ExistingCoreFlowService.process' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'PLAN_CANDIDATE_3.md') 'candidate mentions CoreFlowService.java and ExistingCoreFlowService.process' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'PLAN_SELECTION.md') 'selected core_path' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'REPLAY_PLAN.md') 'CoreFlowService.java through ExistingCoreFlowService.process' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'IMPLEMENTATION_CONTRACT.md') @"
selected_real_entry: ExistingCoreFlowService.process
first_red_test: mvn -pl example-server -Dtest=ExistingCoreFlowServiceTest test
Forbidden Substitute: Mock Stub InMemory TestOnly Placeholder.
"@ -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'EXPECTED_DIFF_MATRIX.md') 'requirement -> CoreFlowService.java -> validation -> closure' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'SIDE_EFFECT_LEDGER.md') @"
ExistingCoreFlowService.process -> DB write -> transaction proof
shallow-green-ban: GREEN Cannot Claim Core DONE without running test
"@ -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'TEST_CHARTER.md') @"
RED: mvn -pl example-server -Dtest=ExistingCoreFlowServiceTest test
GREEN: CoreFlowService.java behavior change closes real entry
"@ -Encoding UTF8
Set-Content -LiteralPath (Join-Path $validRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: CoreFlowService via ExistingCoreFlowService.process
highest_weight_open_gate: core_path
first_red_test: mvn -pl example-server -Dtest=ExistingCoreFlowServiceTest test
selected_real_entry: ExistingCoreFlowService.process
selected_carrier: ExistingCoreFlowService.process
target_subsurface_or_carrier: ExistingCoreFlowService.process
real_carrier_kind: production_service
minimum_side_effect_or_blocker: service triggers DB write
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason: core-only test fixture
production_boundary: example-core/src/main/java/com/acme/CoreFlowService.java
expected_production_diff: CoreFlowService.java behavior change
red_expectation: assertion failure before implementation
green_minimum_implementation: production service closes real entry behavior
proof_kind: real_entry_behavior
forbidden_substitute_proof: no Mock/Stub/InMemory/TestOnly used
fail_closed_condition: block if ExistingCoreFlowService.process is not exercised
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
target_carrier_file_path: example-core/src/main/java/com/acme/CoreFlowService.java
target_carrier_line_number: NEW
expected_test_class: ExistingCoreFlowServiceTest
expected_test_method: testProcess
expected_assertions: assertNotNull(result), assertEquals(PROCEED, status), assertTrue(sideEffect.verified())
expected_side_effects: DB write verified, side effect ledger proof
"@ -Encoding UTF8

Set-Content -LiteralPath (Join-Path $validRoot 'ORACLE_DIFF_ANALYSIS.json') (@{
    files = @(
        @{ path = 'example-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH'; additions = 150 }
    )
} | ConvertTo-Json -Depth 6) -Encoding UTF8

# mock worktree so carrier check would not add noise even without skip
New-Item -ItemType Directory -Force -Path (Join-Path $validRoot 'worktree') | Out-Null

$verifyScript = Join-Path $PSScriptRoot '..\..\Verify-PlanContract.ps1'
Write-Host "verify: $verifyScript"
Write-Host "validRoot: $validRoot"

$result = & $verifyScript -ReplayRoot $validRoot -Stage Plan -SkipCarrierAndOracleChecks 2>&1
Write-Host "exit: $LASTEXITCODE"

$verifyJson = Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json'
if (Test-Path $verifyJson) {
    $raw = Get-Content $verifyJson -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json
    Write-Host "status: $($data.verification_status)"
    Write-Host "issues: $($data.issues -join ', ')"
    Write-Host "warnings: $($data.warnings -join ', ')"
} else {
    Write-Host "MISSING VERIFY JSON"
    Write-Host "raw stdout: $result"
}

Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
