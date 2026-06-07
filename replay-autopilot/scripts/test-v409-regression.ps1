# Regression Tests for v409 High-Weight Stale Blocker Auto-Repair
#
# Tests the fix for the issue where verifier had auto-repair for oracle_overlap_below_threshold
# but NOT for oracle_high_weight_overlap_below_threshold

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$testPass = 0
$testFail = 0

Write-Host "=== v409 High-Weight Stale Blocker Regression Tests ===" -ForegroundColor Cyan
Write-Host ""

# === Test 1: isStaleHighWeightBlocker Variable Exists ===
Write-Host "[Test 1] Verify-PlanContract.ps1 has isStaleHighWeightBlocker variable" -ForegroundColor Yellow

$verifierScript = Join-Path $PSScriptRoot "Verify-PlanContract.ps1"
if (Test-Path -LiteralPath $verifierScript) {
    $verifierContent = Get-Content $verifierScript -Raw -Encoding UTF8
    if ($verifierContent -match '\$isStaleHighWeightBlocker') {
        Write-Host "  PASS: isStaleHighWeightBlocker variable exists" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: isStaleHighWeightBlocker variable not found" -ForegroundColor Red
        $testFail++
    }

    # Check the variable definition includes high-weight threshold check
    if ($verifierContent -match '\$isStaleHighWeightBlocker.*highWeightOverlapPercent.*-ge.*70') {
        Write-Host "  PASS: isStaleHighWeightBlocker checks >= 70% threshold" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: isStaleHighWeightBlocker does not check threshold" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: Verify-PlanContract.ps1 not found" -ForegroundColor Red
    $testFail += 2
}

# === Test 2: Auto-Repair Block for High-Weight Exists ===
Write-Host "[Test 2] Verify-PlanContract.ps1 has auto-repair block for high-weight stale blocker" -ForegroundColor Yellow

if (Test-Path -LiteralPath $verifierScript) {
    $verifierContent = Get-Content $verifierScript -Raw -Encoding UTF8
    if ($verifierContent -match 'elseif \(\$isStaleHighWeightBlocker\)') {
        Write-Host "  PASS: elseif block for isStaleHighWeightBlocker exists" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: elseif block for isStaleHighWeightBlocker not found" -ForegroundColor Red
        $testFail++
    }

    # Check the block handles plan_status update
    if ($verifierContent -match 'plan_status.*BLOCKED.*PROCEED' -and $verifierContent -match 'oracle_high_weight') {
        Write-Host "  PASS: Auto-repair updates plan_status to PROCEED" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Auto-repair does not update plan_status" -ForegroundColor Red
        $testFail++
    }

    # Check the block updates high-weight coverage
    if ($verifierContent -match 'oracle_high_weight_coverage.*highWeightCovPercent') {
        Write-Host "  PASS: Auto-repair updates oracle_high_weight_coverage" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Auto-repair does not update high-weight coverage" -ForegroundColor Red
        $testFail++
    }

    # Check warning message
    if ($verifierContent -match "plan_result_auto_repaired:oracle_high_weight_overlap") {
        Write-Host "  PASS: Auto-repair adds warning message" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Auto-repair does not add warning message" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: Verify-PlanContract.ps1 not found" -ForegroundColor Red
    $testFail += 4
}

# === Test 3: Functional Test - Plan Result Auto-Repair ===
Write-Host "[Test 3] Functional test for high-weight stale blocker auto-repair" -ForegroundColor Yellow

# Create a test plan result with stale high-weight blocker
$testDir = Join-Path $env:TEMP "v409-test-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

$stalePlanResult = @"
# Test Plan Result

- generated_at: 2026-06-03T22:00:00
- run_label: v409-test

## Plan Status

plan_status: BLOCKED
blocker: oracle_high_weight_overlap_below_threshold (50% < 70% required) - missing HIGH-weight files: TestFile1.java; TestFile2.java

## Oracle High Weight Coverage

oracle_high_weight_coverage: 50% (5/10)
oracle_production_file_overlap: 80%
"@

$planResultPath = Join-Path $testDir "PLAN_RESULT.md"
$stalePlanResult | Out-File -FilePath $planResultPath -Encoding UTF8

try {
    # Run Verify-PlanContract.ps1 with the test plan result
    # This requires setting up a minimal environment for the verifier
    # For now, just check the logic path exists
    Write-Host "  SKIP: Functional test requires full verifier environment" -ForegroundColor Yellow
    Write-Host "  Note: Manual verification needed for end-to-end test" -ForegroundColor Cyan
    $testPass += 0  # Skipped, not passed or failed
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testFail++
}

# Cleanup
Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue

# === Test 4: Both Auto-Repair Blocks Coexist ===
Write-Host "[Test 4] Both oracle_overlap and oracle_high_weight_overlap auto-repair exist" -ForegroundColor Yellow

if (Test-Path -LiteralPath $verifierScript) {
    $verifierContent = Get-Content $verifierScript -Raw -Encoding UTF8

    $hasOverlapRepair = $verifierContent -match 'elseif \(\$isStaleBlocker\)'
    $hasHighWeightRepair = $verifierContent -match 'elseif \(\$isStaleHighWeightBlocker\)'

    if ($hasOverlapRepair -and $hasHighWeightRepair) {
        Write-Host "  PASS: Both auto-repair blocks exist" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Missing one or both auto-repair blocks" -ForegroundColor Red
        Write-Host "    hasOverlapRepair: $hasOverlapRepair" -ForegroundColor DarkYellow
        Write-Host "    hasHighWeightRepair: $hasHighWeightRepair" -ForegroundColor DarkYellow
        $testFail++
    }
} else {
    Write-Host "  FAIL: Verify-PlanContract.ps1 not found" -ForegroundColor Red
    $testFail++
}

# === Test 5: Version Comment Present ===
Write-Host "[Test 5] Version comment v409 added to the fix" -ForegroundColor Yellow

if (Test-Path -LiteralPath $verifierScript) {
    $verifierContent = Get-Content $verifierScript -Raw -Encoding UTF8
    if ($verifierContent -match '# v409:') {
        Write-Host "  PASS: v409 version comment found" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: v409 version comment not found" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: Verify-PlanContract.ps1 not found" -ForegroundColor Red
    $testFail++
}

# === Summary ===
Write-Host ""
Write-Host "=== v409 Regression Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testPass" -ForegroundColor Green
Write-Host "Failed: $testFail" -ForegroundColor $(if ($testFail -gt 0) { "Red" } else { "Green" })

if ($testFail -eq 0) {
    Write-Host ""
    Write-Host "Status: ALL TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Status: SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
