# Test-v352-StopAndEvolveExperiments.ps1
# Regression test for v352 STOP_AND_EVOLVE experiment enforcement
#
# Tests:
# 1. Pre-flight test file existence check (EXPERIMENT_1)
# 2. Behavioral assertion validation in execution mode (EXPERIMENT_3)
# 3. Horizontal slice enforcement remains active (EXPERIMENT_2 - already tested in v351)

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$redGateScript = Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1'
$horizontalScript = Join-Path $PSScriptRoot 'verify-horizontal-slice.ps1'

if (-not (Test-Path -LiteralPath $redGateScript)) {
    Write-Host "FAIL: Invoke-RedPhaseHardGate.ps1 not found" -ForegroundColor Red
    exit 1
}

$redGateContent = Get-Content -LiteralPath $redGateScript -Raw -Encoding UTF8

# Test 1: Verify pre-flight test file existence check (v352 EXPERIMENT_1)
Write-Host "Test 1: Pre-flight test file existence check..."
$hasFileCheck = $redGateContent -match 'Step 1a:.*test file existence'
if (-not $hasFileCheck) {
    Write-Host "FAIL: Test file existence check missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Test file existence check exists" -ForegroundColor Green

# Test 2: Verify behavioral assertion validation in execution mode (v352 EXPERIMENT_3)
Write-Host "Test 2: Behavioral assertion validation in execution mode..."
$hasExecutionModeBehavioralCheck = $redGateContent -match 'Step 1c:.*Behavioral assertion pre-validation'
if (-not $hasExecutionModeBehavioralCheck) {
    Write-Host "FAIL: Behavioral assertion validation missing in execution mode" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Behavioral assertion validation exists in execution mode" -ForegroundColor Green

# Test 3: Verify Test-BehavioralTestCharter function exists (from v334)
Write-Host "Test 3: Test-BehavioralTestCharter function exists..."
$hasBehavioralCharterFunc = $redGateContent -match 'function Test-BehavioralTestCharter'
if (-not $hasBehavioralCharterFunc) {
    Write-Host "FAIL: Test-BehavioralTestCharter function missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Test-BehavioralTestCharter function exists" -ForegroundColor Green

# Test 4: Verify pre-flight calls Test-BehavioralTestCharter
Write-Host "Test 4: Pre-flight calls Test-BehavioralTestCharter..."
$hasPreFlightBehavioralCall = $redGateContent -match 'Test-BehavioralTestCharter.*-TestFilePath.*-TestContent'
if (-not $hasPreFlightBehavioralCall) {
    Write-Host "FAIL: Pre-flight does not call Test-BehavioralTestCharter" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Pre-flight calls Test-BehavioralTestCharter" -ForegroundColor Green

# Test 5: Verify PRE_FLIGHT_BLOCKER on file not found
Write-Host "Test 5: PRE_FLIGHT_BLOCKER on file not found..."
$hasPreFlightBlocker = $redGateContent -match 'PRE_FLIGHT_BLOCKER.*Test class does not exist'
if (-not $hasPreFlightBlocker) {
    Write-Host "FAIL: PRE_FLIGHT_BLOCKER message missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: PRE_FLIGHT_BLOCKER message exists" -ForegroundColor Green

# Test 6: Verify BEHAVIORAL_ASSERTION_FAIL on invalid test
Write-Host "Test 6: BEHAVIORAL_ASSERTION_FAIL on invalid test..."
$hasBehavioralFail = $redGateContent -match 'BEHAVIORAL_ASSERTION_FAIL'
if (-not $hasBehavioralFail) {
    Write-Host "FAIL: BEHAVIORAL_ASSERTION_FAIL message missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: BEHAVIORAL_ASSERTION_FAIL message exists" -ForegroundColor Green

# Test 7: Verify minimum assertion count check
Write-Host "Test 7: Minimum assertion count check..."
$hasMinAssertions = $redGateContent -match 'minAssertions.*=.*3'
if (-not $hasMinAssertions) {
    Write-Host "FAIL: Minimum assertion count check missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Minimum assertion count check exists" -ForegroundColor Green

# Test 8: Verify horizontal slice script exists (EXPERIMENT_2 from v348)
Write-Host "Test 8: Horizontal slice enforcement script exists..."
if (-not (Test-Path -LiteralPath $horizontalScript)) {
    Write-Host "FAIL: verify-horizontal-slice.ps1 not found" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: verify-horizontal-slice.ps1 exists" -ForegroundColor Green

# Test 9: Verify horizontal slice requires 3 categories
Write-Host "Test 9: Horizontal slice requires 3 categories..."
$horizontalContent = Get-Content -LiteralPath $horizontalScript -Raw -Encoding UTF8
$hasThreeCategoryMin = $horizontalContent -match 'minimumRequired.*=.*3'
if (-not $hasThreeCategoryMin) {
    Write-Host "FAIL: Horizontal slice 3-category minimum missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Horizontal slice requires 3 categories" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "=== v352 STOP_AND_EVOLVE Enforcement Tests ===" -ForegroundColor Cyan
Write-Host "All tests passed" -ForegroundColor Green
Write-Host ""
Write-Host "Summary of v352 changes:"
Write-Host "  - EXPERIMENT_1: Added pre-flight test file existence check"
Write-Host "  - EXPERIMENT_3: Added behavioral assertion validation in execution mode"
Write-Host "  - EXPERIMENT_2: Horizontal slice enforcement (existing from v348)"

exit 0
