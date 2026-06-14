param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v289-test-harness-and-wrapper-safety'),
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
    param([string]$Root, [string]$FirstRedTest)
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    Write-Utf8 (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') (@{
        files = @(
            @{ path = 'example-core/src/main/java/com/acme/CoreFlowService.java'; is_production = $true; weight = 'HIGH' }
        )
    } | ConvertTo-Json -Depth 6)

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @"
- plan_status: PROCEED
- selected_strategy: core-stateful-first
- first_slice: CoreFlowService via ExistingCoreFlowService.process
- first_red_test: $FirstRedTest
- oracle_production_file_overlap: 100%
- oracle_high_weight_coverage: 1/1
- carrier_search: performed
- carrier_search_queries: rg "ExistingCoreFlowService" example-core; rg "CoreFlowService" example-core; rg "process" example-core
- existing_production_carriers: ExistingCoreFlowService.process
- selected_carrier_from_search: ExistingCoreFlowService.process
- new_service_proposed: false
- new_service_justification: none
"@

    foreach ($file in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 (Join-Path $Root $file) 'candidate mentions CoreFlowService.java and ExistingCoreFlowService.process'
    }
    Write-Utf8 (Join-Path $Root 'FAMILY_CONTRACT.json') '{"families":[]}'
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'CoreFlowService.java through ExistingCoreFlowService.process'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') "selected_real_entry: ExistingCoreFlowService.process`nfirst_red_test: $FirstRedTest`nForbidden Substitute: Mock Stub InMemory TestOnly Placeholder."
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'requirement -> CoreFlowService.java -> validation -> closure'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'ExistingCoreFlowService.process -> DB write -> transaction proof'
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') 'RED/GREEN order through ExistingCoreFlowService.process'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @"
first_slice: S1
highest_weight_open_gate: core_path
first_red_test: $FirstRedTest
selected_real_entry: ExistingCoreFlowService.process
public_entry_contract_coverage: none_with_reason: service entry
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
pattern_to_follow: ExistingCoreFlowService.process
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "ExistingCoreFlowService" example-core
"@
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$phase1Prompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8
$preflightWrapper = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-PreflightComprehensive.ps1') -Raw -Encoding UTF8
$sliceWrapper = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-SliceZeroDeltaEvaluation.ps1') -Raw -Encoding UTF8
$carrierWrapper = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-PlanCarrierSearchVerification.ps1') -Raw -Encoding UTF8
$preflightPy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pre_flight_check.py') -Raw -Encoding UTF8

$phase1HasHarnessRule = $phase1Prompt.Contains('example-server/src/test') -and $phase1Prompt.Contains('example-core/src/test')
$phase1HasPomRule = $phase1Prompt.Contains('pom.xml') -and $phase1Prompt.Contains('JUnit/Mockito') -and $phase1Prompt.Contains('-pl example-server -am')
$planHasHarnessRule = $planPrompt.Contains('PLAN_BLOCKED_TEST_HARNESS') -and $planPrompt.Contains('-pl example-server -am')
Assert-True $phase1HasHarnessRule 'Phase1 prompt must force example-server test harness'
Assert-True $phase1HasPomRule 'Phase1 prompt must forbid POM dependency changes and use example-server command'
Assert-True $planHasHarnessRule 'Plan prompt must fail closed on invalid test harness'
Assert-True (($preflightWrapper + $sliceWrapper + $carrierWrapper) -notmatch '<<<') 'PowerShell wrappers must not use Bash here-string redirection'
Assert-True (($preflightWrapper + $preflightPy) -notmatch 'Add JUnit dependency to example-core/pom\.xml') 'Preflight must not recommend adding JUnit to example-core POM'

$validRoot = Join-Path $TestRoot 'valid-plan'
New-PlanFixture -Root $validRoot -FirstRedTest 'mvn -s D:\maven\settings\settings.xml -f {{WORKTREE}}\pom.xml test -pl example-server -am -Dtest=ExistingCoreFlowServiceTest -Dsurefire.failIfNoSpecifiedTests=false'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $validRoot -Stage Plan | Out-Null
$validVerify = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($validVerify.verification_status -eq 'PASS') "Valid example-server harness should pass, issues=$(@($validVerify.issues) -join ';')"

$invalidRoot = Join-Path $TestRoot 'invalid-plan'
New-PlanFixture -Root $invalidRoot -FirstRedTest 'mvn -s D:\maven\settings\settings.xml -f {{WORKTREE}}\pom.xml test -pl example-core -Dtest=ExistingCoreFlowServiceTest -Dsurefire.failIfNoSpecifiedTests=false'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $invalidRoot -Stage Plan | Out-Null
$invalidVerify = Get-Content -LiteralPath (Join-Path $invalidRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ((@($invalidVerify.issues) -contains 'first_slice_proof_invalid:test_harness_claim_core')) 'Verifier must block example-core test harness planning'

$sliceRoot = Join-Path $TestRoot 'slice-zero-delta'
New-Item -ItemType Directory -Force -Path $sliceRoot | Out-Null
$slicePath = Join-Path $sliceRoot 'SLICE_RESULT_01.json'
$phase0Path = Join-Path $sliceRoot 'PHASE0_CONTRACT_VERIFY.json'
Write-Utf8 $phase0Path '{"verification_status":"PASS"}'
Write-Utf8 $slicePath (@{
    slice_id = 'S1'
    slice_status = 'BLOCKED'
    coverage_delta = 0
    implemented_files = @()
    current_slice_changed_files = @('example-core/src/test/java/com/acme/CoreFlowServiceTest.java')
    gap_flags = @()
    tests = @(
        @{ phase = 'RED'; result = 'blocked'; command = 'mvn -pl example-core -Dtest=CoreFlowServiceTest test'; evidence = 'cannot find symbol org.junit.Test' }
    )
} | ConvertTo-Json -Depth 8)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-SliceZeroDeltaEvaluation.ps1') -SliceResultPath $slicePath -Phase0ContractPath $phase0Path | Out-Null
Assert-True ($LASTEXITCODE -eq 1) 'Zero-delta wrapper should block environment RED'
$sliceAfter = Get-Content -LiteralPath $slicePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($sliceAfter.zero_delta_enforced -eq $true -and $sliceAfter.coverage_delta -eq 0) 'Zero-delta wrapper must write enforced zero coverage'

$markdownPlan = Join-Path $TestRoot 'PLAN_RESULT.md'
Write-Utf8 $markdownPlan @'
- plan_status: PROCEED
- new_service_proposed: false
- carrier_search_queries: rg "ExistingCoreFlowService" example-core
'@
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-PlanCarrierSearchVerification.ps1') -PlanResultPath $markdownPlan -Worktree D:\opt\claim -OracleCommit HEAD | Out-Null
Assert-True ($LASTEXITCODE -eq 0) 'Carrier search wrapper should parse Markdown PLAN_RESULT.md'
Assert-True (Test-Path -LiteralPath (Join-Path $TestRoot 'PLAN_RESULT_CARRIER_SEARCH_VERIFY.json')) 'Carrier search wrapper should write verification JSON for Markdown input'

[ordered]@{
    status = 'PASS'
    assertions = 10
    cases = @(
        'phase1_claim_server_harness_prompt',
        'phase1_forbid_pom_dependency_prompt',
        'plan_test_harness_prompt',
        'no_bash_here_string_wrappers',
        'no_add_junit_recommendation',
        'valid_claim_server_plan_passes',
        'claim_core_plan_blocked',
        'zero_delta_wrapper_blocks_env_red',
        'carrier_wrapper_parses_markdown',
        'carrier_wrapper_writes_json'
    )
} | ConvertTo-Json -Depth 5
