param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-PlanFixture {
    param([string]$Root, [string]$TestCharter)

    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
# Plan Result

plan_status: PROCEED
carrier_search: performed
carrier_search_queries: GenericConfigService; GenericRuleService; config threshold
existing_production_carriers: GenericConfigService.apply
selected_carrier_from_search: GenericConfigService.apply
new_service_proposed: false
oracle_production_file_overlap: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
golden_slice_binding: exact_contract_gap -> GenericConfigService.apply -> GenericConfigServiceTest.testRule -> minimal GREEN production diff -> executable side effect
first_slice: S1
first_red_test: GenericConfigServiceTest.testRule
source_boundary: generic/config
'@

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.json') @'
{
  "stage": "Plan",
  "plan_status": "PROCEED",
  "carrier_search": "performed",
  "existing_production_carriers": ["GenericConfigService.apply"],
  "selected_carrier_from_search": "GenericConfigService.apply",
  "new_service_proposed": false,
  "oracle_production_file_overlap": "100%",
  "oracle_missing_high_weight_files": "none",
  "oracle_expansion_plan": "none",
  "oracle_out_of_scope_files": "none",
  "first_slice": "S1",
  "first_red_test": "GenericConfigServiceTest.testRule",
  "selected_real_entry": "GenericConfigService.apply",
  "source_boundary": "generic/config"
}
'@

    Write-Utf8 (Join-Path $Root 'ORACLE_FILES.json') '[]'

    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') @'
# Replay Plan

first_slice: S1
first_red_test: GenericConfigServiceTest.testRule
selected_real_entry: GenericConfigService.apply
exact_contract_gap: config threshold rule
stateful_side_effect: captured repository update
real_entry: GenericConfigService.apply
'@

    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @'
# Implementation Contract

selected_real_entry: GenericConfigService.apply
first_slice: S1
first_red_test: GenericConfigServiceTest.testRule
production_boundary: GenericConfigService.apply
shallow: GREEN cannot claim done without executable behavior evidence
forbidden_substitute_check: no mocks as production substitute
'@

    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') @'
# Expected Diff Matrix

closure: exact_contract_gap
status: planned
production: GenericConfigService.apply
test: GenericConfigServiceTest.testRule
'@

    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') @'
# Side Effect Ledger

state: generic config aggregate
task: apply threshold rule
progress: planned
log: test evidence
transaction: mocked repository verification
'@

    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
# First Slice Proof Plan

first_slice: S1
first_red_test: GenericConfigServiceTest.testRule
golden_slice_binding: exact_contract_gap -> GenericConfigService.apply -> GenericConfigServiceTest.testRule -> minimal GREEN production diff -> executable side effect
highest_weight_open_gate: config_policy_threshold
first_slice_family: config_policy_threshold
target_family: config_policy_threshold
existing production carrier: GenericConfigService.apply
selected_real_entry: GenericConfigService.apply
selected_carrier: GenericConfigService.apply
target_subsurface_or_carrier: GenericConfigService.apply
production_boundary: GenericConfigService.apply
proof_kind: real_entry_behavior
real_carrier_kind: production_service_method
minimum_side_effect_or_blocker: repository update captured
forbidden_substitute_check: no mock-only production substitute
expected production diff: GenericConfigService.apply
RED: GenericConfigServiceTest.testRule fails before threshold logic
GREEN: GenericConfigService.apply implements threshold logic
coverage cap: 60
'@

    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') $TestCharter
    return $worktree
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptRoot
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v619-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$assertions = 0
$cases = [System.Collections.Generic.List[string]]::new()

try {
    $redOnlyRoot = Join-Path $tmp 'red-only-charter'
    $redOnlyWorktree = New-PlanFixture -Root $redOnlyRoot -TestCharter @'
# Test Charter

## RED Phase
- Entry Point: GenericConfigService.apply
- Test Class: GenericConfigServiceTest
- DB Verification: ArgumentCaptor captures repository update
- Side Effects:
  - verify repository update command is issued
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $redOnlyRoot -Stage Plan -Worktree $redOnlyWorktree -SkipCarrierAndOracleChecks | Out-Null
    $redOnlyVerify = Get-Content -LiteralPath (Join-Path $redOnlyRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'green_missing_is_warning' (@($redOnlyVerify.warnings) -contains 'test_charter_missing:GREEN') ($redOnlyVerify | ConvertTo-Json -Depth 8)
    $assertions++
    Assert-True 'green_missing_not_issue' (@($redOnlyVerify.issues) -notcontains 'test_charter_missing:GREEN') ($redOnlyVerify | ConvertTo-Json -Depth 8)
    $assertions++
    $cases.Add('red_only_charter_green_warning_non_blocking')

    $missingRedRoot = Join-Path $tmp 'missing-red-charter'
    $missingRedWorktree = New-PlanFixture -Root $missingRedRoot -TestCharter @'
# Test Charter

## Setup
- Entry Point: GenericConfigService.apply
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $missingRedRoot -Stage Plan -Worktree $missingRedWorktree -SkipCarrierAndOracleChecks -ErrorAction SilentlyContinue | Out-Null
    $missingRedVerify = Get-Content -LiteralPath (Join-Path $missingRedRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'red_missing_remains_issue' (@($missingRedVerify.issues) -contains 'test_charter_missing:RED') ($missingRedVerify | ConvertTo-Json -Depth 8)
    $assertions++
    $cases.Add('red_missing_still_blocks')

    $greenPresentRoot = Join-Path $tmp 'green-present-charter'
    $greenPresentWorktree = New-PlanFixture -Root $greenPresentRoot -TestCharter @'
# Test Charter

## RED Phase
- Entry Point: GenericConfigService.apply
- Test Class: GenericConfigServiceTest

## GREEN Phase
- Minimum implementation: GenericConfigService.apply closes threshold logic
- DB Verification: ArgumentCaptor captures repository update
- Side Effects:
  - verify repository update command is issued
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $greenPresentRoot -Stage Plan -Worktree $greenPresentWorktree -SkipCarrierAndOracleChecks | Out-Null
    $greenPresentVerify = Get-Content -LiteralPath (Join-Path $greenPresentRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'green_present_has_no_warning' (@($greenPresentVerify.warnings) -notcontains 'test_charter_missing:GREEN') ($greenPresentVerify | ConvertTo-Json -Depth 8)
    $assertions++
    $redOnlyIssues = @($redOnlyVerify.issues) -join "`n"
    $greenPresentIssues = @($greenPresentVerify.issues) -join "`n"
    Assert-True 'missing_green_does_not_change_blocking_issues' ($redOnlyIssues -eq $greenPresentIssues) "red-only issues=$redOnlyIssues; green-present issues=$greenPresentIssues"
    $assertions++
    $cases.Add('green_present_suppresses_warning')

    $guidancePath = Join-Path $repoRoot 'prompts\TEST_CHARTER_GUIDANCE.md'
    $guidance = Get-Content -LiteralPath $guidancePath -Raw -Encoding UTF8
    Assert-True 'guidance_mentions_phase1_prevalidator' ($guidance.Contains('Invoke-TestCharterPrevalidator.ps1')) ''
    $assertions++
    $projectSpecificPattern = @(
        ('TAi' + 'Claim'),
        ('Ai' + 'ClaimModule'),
        ('Ai' + 'AutoClaim'),
        ('hu' + 'ize'),
        ('li' + 'pei')
    ) -join '|'
    Assert-True 'guidance_has_no_project_pollution' ($guidance -notmatch $projectSpecificPattern) ''
    $assertions++
    $cases.Add('guidance_project_neutral')

    $runSliceText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True 'phase1_prevalidator_blocks_missing_charter' ($runSliceText.Contains('TEST_CHARTER_MISSING') -and $runSliceText.Contains('test_charter_missing_before_implementation')) ''
    $assertions++
    $cases.Add('phase1_prevalidator_remains_hard_gate')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = $assertions
    cases = @($cases.ToArray())
} | ConvertTo-Json -Depth 5
