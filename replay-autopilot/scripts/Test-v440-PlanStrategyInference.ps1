# Test-v440-PlanStrategyInference.ps1
# v440: Robust selected_strategy inference from PLAN_SELECTION.md

$testRoot = Join-Path $PSScriptRoot ".tmp\v440-plan-strategy-inference-test"
$testValid = Join-Path $testRoot "valid-strategy-inference"
$testMissing = Join-Path $testRoot "missing-strategy-name"

function Test-PlanStrategyInference {
    <#
    .SYNOPSIS
    Tests that selected_strategy can be inferred from PLAN_SELECTION.md formats

    .DESCRIPTION
    Validates multiple PLAN_SELECTION.md formats:
    - strategy_name: direct field (preferred)
    - Selected Candidate: X - Strategy Name (legacy)
    - Selected Candidate: X (fallback)

    .EXAMPLE
    Test-v440-PlanStrategyInference.ps1
    #>

    # Clean up previous test artifacts
    if (Test-Path $testRoot) {
        Remove-Item $testRoot -Recurse -Force
    }
    New-Item $testValid -ItemType Directory -Force | Out-Null
    New-Item $testMissing -ItemType Directory -Force | Out-Null

    # Test Case 1: Valid with strategy_name field (preferred format)
    $planSelection1 = @"
# Plan Selection

## Winner Selection

**Selected Candidate**: Candidate 1 - Core-Transaction-First Strategy

**Rationale**:
- Highest weight coverage

## Final Strategy Declaration

**strategy_name**: core-transaction-first

**first_slice**: S1
"@
    $planResult1 = @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: Candidate 1 - Core-Transaction-First
- first_slice: S1 - Core Transaction
- first_red_test: TestClass.testMethod
"@
    Set-Content (Join-Path $testValid "PLAN_SELECTION.md") $planSelection1 -Encoding UTF8
    Set-Content (Join-Path $testValid "PLAN_RESULT.md") $planResult1 -Encoding UTF8

    # Test Case 2: Valid with legacy Selected Candidate format
    $planSelection2 = @"
# Plan Selection

## Winner Selection

**Selected Candidate**: 2 - Exact-Contract-Test-First Strategy

**Rationale**:
- TDD discipline
"@
    $planResult2 = @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 2 - Exact-Contract-Test-First
- first_slice: S1 - Contract First
- first_red_test: TestContract.testExact
"@
    Set-Content (Join-Path $testMissing "PLAN_SELECTION.md") $planSelection2 -Encoding UTF8
    Set-Content (Join-Path $testMissing "PLAN_RESULT.md") $planResult2 -Encoding UTF8

    # Test Case 3: Missing strategy_name but has Selected Candidate with "Candidate X - Name" format
    $testAlt = Join-Path $testRoot "alt-candidate-format"
    New-Item $testAlt -ItemType Directory -Force | Out-Null
    $planSelection3 = @"
# Plan Selection

## Winner Selection

**Selected Candidate**: Candidate 3 - Deploy-Facing-Balanced

**Rationale**:
- Surface coverage balanced
"@
    $planResult3 = @"
# Plan Result

- plan_status: PROCEED
- first_slice: S1 - Deploy Surface
- first_red_test: TestDeploy.testSurface
"@
    Set-Content (Join-Path $testAlt "PLAN_SELECTION.md") $planSelection3 -Encoding UTF8
    Set-Content (Join-Path $testAlt "PLAN_RESULT.md") $planResult3 -Encoding UTF8

    # Test Case 4: No strategy information at all (should fail)
    $testNone = Join-Path $testRoot "no-strategy-info"
    New-Item $testNone -ItemType Directory -Force | Out-Null
    $planSelection4 = @"
# Plan Selection

## Summary

Some content but no strategy info.
"@
    $planResult4 = @"
# Plan Result

- plan_status: PROCEED
- first_slice: S1
- first_red_test: Test.test
"@
    Set-Content (Join-Path $testNone "PLAN_SELECTION.md") $planSelection4 -Encoding UTF8
    Set-Content (Join-Path $testNone "PLAN_RESULT.md") $planResult4 -Encoding UTF8

    # Run verification on each test case
    $scriptPath = $PSScriptRoot
    $verifyScript = Join-Path $scriptPath "Verify-PlanContract.ps1"

    Write-Host "`n=== v440 Plan Strategy Inference Test ===" -ForegroundColor Cyan

    $testCases = @(
        @{ Path = $testValid; Name = "strategy_name field (preferred)"; ShouldPass = $true }
        @{ Path = $testMissing; Name = "legacy Selected Candidate (number only)"; ShouldPass = $true }
        @{ Path = $testAlt; Name = "Candidate X - Strategy Name format"; ShouldPass = $true }
        @{ Path = $testNone; Name = "no strategy info"; ShouldPass = $false }
    )

    $passed = 0
    $failed = 0

    foreach ($tc in $testCases) {
        Write-Host "`nTest: $($tc.Name)" -ForegroundColor Yellow

        # Create minimal ORACLE_DIFF_ANALYSIS.json to satisfy verifier
        $oracleJson = '{"oracle_primary_domain": "test/", "oracle_production_files": [], "oracle_high_weight_files": []}'
        Set-Content (Join-Path $tc.Path "ORACLE_DIFF_ANALYSIS.json") $oracleJson -Encoding UTF8

        # Create minimal FAMILY_CONTRACT.json
        $familyJson = '{"families": [], "detected_families": []}'
        Set-Content (Join-Path $tc.Path "FAMILY_CONTRACT.json") $familyJson -Encoding UTF8

        $result = & $verifyScript -ReplayRoot $tc.Path -Verbose:$false 2>&1
        $jsonResult = $result | ConvertFrom-Json

        # Check if selected_strategy was found (no plan_result_field_missing:selected_strategy issue)
        $hasMissingField = $jsonResult.issues -contains "plan_result_field_missing:selected_strategy"
        $hasInferred = $jsonResult.warnings -contains "plan_result_field_inferred:selected_strategy"

        if ($tc.ShouldPass) {
            # Should have strategy (either directly or inferred)
            if (-not $hasMissingField) {
                Write-Host "  PASS: selected_strategy available" -ForegroundColor Green
                $passed++
            } else {
                Write-Host "  FAIL: selected_strategy still missing" -ForegroundColor Red
                Write-Host "  Issues: $($jsonResult.issues -join ', ')" -ForegroundColor Red
                $failed++
            }
        } else {
            # Should fail to find strategy
            if ($hasMissingField) {
                Write-Host "  PASS: correctly detected missing strategy" -ForegroundColor Green
                $passed++
            } else {
                Write-Host "  FAIL: should have detected missing strategy" -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host "`n=== Results: $passed passed, $failed failed ===" -ForegroundColor Cyan

    if ($failed -eq 0) {
        Write-Host "v440 Plan Strategy Inference: PASS ($($testCases.Count) tests)" -ForegroundColor Green
        return 0
    } else {
        Write-Host "v440 Plan Strategy Inference: FAIL ($failed of $($testCases.Count))" -ForegroundColor Red
        return 1
    }
}

# Run test if executed directly
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    exit (Test-PlanStrategyInference)
}
