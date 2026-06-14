# Test v406: Carrier Name Normalization for Method-Level Selection
# Purpose: Verify that selected carriers with method names (e.g., "ClassName.method")
# correctly match file-level results (e.g., "ClassName.java")

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

$scriptRoot = $PSScriptRoot
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

# Test 1: Parse the verifier to ensure v406 guard is present
$verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
Assert-True ($verifierText -match 'v406:.*Normalize carrier name') 'Verifier should contain v406 carrier name normalization comment'
Assert-True ($verifierText -match '\$carrierBaseNameForMatch') 'Verifier should define $carrierBaseNameForMatch variable'

# Test 2: Create minimal fixture and verify carrier matching works
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v406-carrier-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    # Create minimal PLAN_RESULT.md with method-level carrier selection
    $planResult = @"
plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg "class ExampleModuleConfigService" --glob "*.java"; rg "class ExamineFlowFacadeImpl" --glob "*.java"
existing_production_carriers: TExampleModuleConfig.java (example-domain) | ExampleModuleConfigService.java (example-core) | ExamineFlowFacadeImpl.java (example-core)
selected_carrier_from_search: ExampleModuleConfigService.save (example-core)
new_service_proposed: false
new_service_justification: N/A
oracle_production_file_overlap: 50%
selected_strategy: exact-contract-and-test-first
implementation_model_recommendation: gpt-5.3-codex
first_slice: S1 - AI Module Config Field Addition
first_red_test: ExampleModuleConfigServiceTest.testSave_FreeReviewAmount
"@
    $planResultPath = Join-Path $tempRoot 'PLAN_RESULT.md'
    $planResult | Out-File -FilePath $planResultPath -Encoding UTF8

    # Create minimal FIRST_SLICE_PROOF_PLAN.md
    $firstSliceProof = @"
first_slice: S1 - AI Module Config Field Addition
target_family: core_entry
existing_production_carrier: ExampleModuleConfigService
real_carrier_kind: existing_service
production_boundary: TExampleModuleConfigMapper.insert
proof_kind: db_persistence
expected_production_diff: 4 files (2 domain, 1 core, 1 mapper)
RED: ExampleModuleConfigServiceTest.testSave_withNegativeAmount_throwsException
GREEN: Add field to TExampleModuleConfig, validation in save()
fail_closed_condition: DB insert verifies free_review_amount column
coverage cap: 100%
"@
    $firstSliceProofPath = Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md'
    $firstSliceProof | Out-File -FilePath $firstSliceProofPath -Encoding UTF8

    # Create minimal REPLAY_PLAN.md
    $replayPlan = @"
# Replay Plan

## Slice Sequencing

| Slice | Requirement | Contract | RED Test | Status |
|-------|-------------|----------|----------|--------|
| S1 | AI Module Config Field Addition | TExampleModuleConfig.freeReviewAmount | testSave_withNegativeAmount | READY |

## First Slice
S1 - AI Module Config Field Addition
Entry: ExampleModuleConfigService.save
Carrier: ExampleModuleConfigService (existing)
Coverage Cap: 100%
"@
    $replayPlanPath = Join-Path $tempRoot 'REPLAY_PLAN.md'
    $replayPlan | Out-File -FilePath $replayPlanPath -Encoding UTF8

    # Run verifier
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $tempRoot -Stage Plan | Out-Null
    $verifyPath = Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json'

    if (-not (Test-Path -LiteralPath $verifyPath)) {
        throw "PLAN_CONTRACT_VERIFY.json not found at $verifyPath"
    }

    $verify = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # v406: The selected carrier "ExampleModuleConfigService.save" should match
    # "ExampleModuleConfigService.java" in existing_production_carriers
    # after normalizing to base class name "ExampleModuleConfigService"
    $hasNotInResultsIssue = 'carrier_search_selected_carrier_not_in_results' -in $verify.issues

    if ($hasNotInResultsIssue) {
        $allIssues = $verify.issues -join '; '
        throw "v406 carrier name normalization failed: 'ExampleModuleConfigService.save' should match 'ExampleModuleConfigService.java' after normalization. All issues: $allIssues"
    }

    Write-Host "PASS: v406 carrier name normalization allows method-level selection to match file-level results"
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: v406 carrier name normalization tests passed'
[ordered]@{
    status = 'PASS'
    assertions = 3
    cases = @(
        'v406_guard_present',
        'carrier_name_normalization_variable',
        'method_level_to_file_level_matching'
    )
} | ConvertTo-Json -Depth 5
