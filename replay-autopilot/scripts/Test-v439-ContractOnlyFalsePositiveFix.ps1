# Test-v439-ContractOnlyFalsePositiveFix.ps1
# Regression test for v439 contract-only pattern refinement
# Tests that the refined pattern avoids false positives on legitimate slice names

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $PSScriptRoot '.tmp'
$testReplayRoot = Join-Path $testRoot 'test-v439-contract-only-false-positive'
$testCount = 0
$passCount = 0
$failCount = 0

function Test-Scenario {
    param(
        [string]$Name,
        [string]$FirstSlice,
        [string]$ProductionBoundary,
        [string]$ExpectedProductionDiff,
        [string]$MinimumSideEffect,
        [string]$GreenMinimum,
        [bool]$ShouldPass
    )

    $script:testCount++

    # Create test artifacts
    $null = New-Item -ItemType Directory -Force -Path $testReplayRoot

    $planResult = @"
# PLAN_RESULT.md

plan_status: PROCEED
first_slice: $FirstSlice
golden_slice_binding: oracle_overlap -> TestService -> TestServiceTest.testMethod -> GREEN: Service handles logic -> DB verifies state
"@

    $firstSliceProof = @"
# FIRST_SLICE_PROOF_PLAN.md

first_slice: $FirstSlice
first_red_test: TestServiceTest.testMethod
golden_slice_binding: oracle_overlap -> TestService -> TestServiceTest.testMethod -> GREEN: Service handles logic -> DB verifies state
highest_weight_open_gate: config_service_facade
selected_real_entry: TestService.handle()
selected_carrier: TestService
target_subsurface_or_carrier: TTestConfig.testField
production_boundary: $ProductionBoundary
proof_kind: stateful_side_effect
real_carrier_kind: production_service
public_entry_contract_coverage: facade_save_query_by_id
forbidden_substitute_check: passed
minimum_side_effect_or_blocker: $MinimumSideEffect
required_sibling_surfaces: TestMapper; TestFacade
expected_production_diff: $ExpectedProductionDiff
red_expectation: Exception before implementation
green_minimum_implementation: $GreenMinimum
forbidden_substitute_proof: Service uses real dependencies
fail_closed_condition: Service must persist state
coverage_cap_if_not_closed: 30
coverage_cap_if_missing: 0
"@

    $planResultPath = Join-Path $testReplayRoot 'PLAN_RESULT.md'
    $firstSliceProofPath = Join-Path $testReplayRoot 'FIRST_SLICE_PROOF_PLAN.md'

    Set-Content -LiteralPath $planResultPath -Value $planResult -Encoding UTF8
    Set-Content -LiteralPath $firstSliceProofPath -Value $firstSliceProof -Encoding UTF8

    # Run verification
    $verifyScript = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $testReplayRoot -Stage Plan | Out-Null
    $exitCode = $LASTEXITCODE

    $verifyPath = Join-Path $testReplayRoot 'PLAN_CONTRACT_VERIFY.json'
    $verifyText = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8
    $verifyData = $verifyText | ConvertFrom-Json

    $hasContractOnlyIssue = $verifyData.issues -match 'contract_only_first_slice'

    # Determine if test passed
    $passed = if ($ShouldPass) {
        -not $hasContractOnlyIssue
    } else {
        $hasContractOnlyIssue
    }

    if ($passed) {
        $script:passCount++
        Write-Host "PASS: $Name"
        if ($Verbose) {
            Write-Host "  Expected: $(if ($ShouldPass) { 'PASS' } else { 'FAIL (contract_only)' })"
            Write-Host "  Got: Exit code $exitCode, issues: $($verifyData.issues -join ', ')"
        }
    } else {
        $script:failCount++
        Write-Host "FAIL: $Name" -ForegroundColor Red
        Write-Host "  Expected: $(if ($ShouldPass) { 'PASS' } else { 'FAIL (contract_only)' })"
        Write-Host "  Got: Exit code $exitCode, issues: $($verifyData.issues -join ', ')"
        Write-Host "  first_slice: $FirstSlice"
        Write-Host "  production_boundary: $ProductionBoundary"
    }

    # Clean up
    Remove-Item -LiteralPath $testReplayRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Testing v439 contract-only pattern refinement..." -ForegroundColor Cyan
Write-Host ""

# Scenario 1: v438 false positive - should PASS now
Test-Scenario -Name "Schema & Contract Definition (v438 false positive)" `
    -FirstSlice "S1 - Schema & Contract Definition" `
    -ProductionBoundary "Service layer - TestService.handle() method" `
    -ExpectedProductionDiff "TTestEntity.java; TestService.java" `
    -MinimumSideEffect "DB UPDATE verifies flow executed" `
    -GreenMinimum "Create TestService with handle() method" `
    -ShouldPass $true

# Scenario 2: Schema & Contract with implementation - should PASS
Test-Scenario -Name "Schema & Contract Definition with DB migration" `
    -FirstSlice "S1 - Schema & Contract Definition with DB migration" `
    -ProductionBoundary "Service layer - TestService.handle() method" `
    -ExpectedProductionDiff "TTestEntity.java; TestService.java" `
    -MinimumSideEffect "DB UPDATE verifies flow executed" `
    -GreenMinimum "Create TestService with handle() method" `
    -ShouldPass $true

# Scenario 3: CONTRACT_ONLY - should FAIL (true positive)
Test-Scenario -Name "CONTRACT_ONLY (true positive)" `
    -FirstSlice "CONTRACT_ONLY" `
    -ProductionBoundary "CONTRACT_ONLY" `
    -ExpectedProductionDiff "none" `
    -MinimumSideEffect "deferred to S2" `
    -GreenMinimum "to be implemented in Slice 2" `
    -ShouldPass $false

# Scenario 4: contract & RED only - should FAIL (true positive)
Test-Scenario -Name "contract & RED only (true positive)" `
    -FirstSlice "contract & RED only" `
    -ProductionBoundary "contract & RED only" `
    -ExpectedProductionDiff "deferred to S2" `
    -MinimumSideEffect "to be implemented in Slice 2" `
    -GreenMinimum "deferred to S2" `
    -ShouldPass $false

# Scenario 5: Contract Definition only - should FAIL (true positive)
Test-Scenario -Name "Contract Definition only (true positive)" `
    -FirstSlice "S1 - Contract Definition only" `
    -ProductionBoundary "contract definition only" `
    -ExpectedProductionDiff "none" `
    -MinimumSideEffect "deferred to S2" `
    -GreenMinimum "deferred to S2" `
    -ShouldPass $false

# Scenario 6: tests only - should FAIL (true positive)
Test-Scenario -Name "tests only (true positive)" `
    -FirstSlice "S1 - tests only" `
    -ProductionBoundary "tests only" `
    -ExpectedProductionDiff "none" `
    -MinimumSideEffect "deferred to S2" `
    -GreenMinimum "deferred to S2" `
    -ShouldPass $false

# Scenario 7: Standard implementation slice - should PASS
Test-Scenario -Name "Standard implementation slice" `
    -FirstSlice "S1 - Core Implementation" `
    -ProductionBoundary "Service layer - TestService.handle() method" `
    -ExpectedProductionDiff "TTestEntity.java; TestService.java" `
    -MinimumSideEffect "DB UPDATE verifies flow executed" `
    -GreenMinimum "Create TestService with handle() method" `
    -ShouldPass $true

# Scenario 8: S1 with Schema definition - should PASS
Test-Scenario -Name "S1 - Schema Definition and Migration" `
    -FirstSlice "S1 - Schema Definition and Migration" `
    -ProductionBoundary "Service layer - TestService.handle() method" `
    -ExpectedProductionDiff "TTestEntity.java; TestService.java" `
    -MinimumSideEffect "DB UPDATE verifies flow executed" `
    -GreenMinimum "Create TestService with handle() method" `
    -ShouldPass $true

Write-Host ""
Write-Host "Test Results: $passCount/$testCount passed" -ForegroundColor $(if ($passCount -eq $testCount) { 'Green' } else { 'Yellow' })
if ($failCount -gt 0) {
    Write-Host "Failed tests: $failCount" -ForegroundColor Red
}

# Clean up test directory
Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue

exit $(if ($passCount -eq $testCount) { 0 } else { 1 })
