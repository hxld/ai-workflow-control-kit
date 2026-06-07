# Test-v393-GoldenSliceBindingRepairPrompt.ps1
# Regression test for golden_slice_binding repair prompt enhancement (v393)

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$testVerbose = $Verbose

# Test helper function
function Test-RegexMatch {
    param(
        [string]$Pattern,
        [string]$Text,
        [string]$Description
    )
    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($testVerbose) {
        Write-Host "  Testing: $Description" -ForegroundColor DarkGray
        Write-Host "    Matched: $($match.Success)" -ForegroundColor $(if ($match.Success) { 'Green' } else { 'Red' })
    }
    return $match.Success
}

# Read the Run-ReplayLoop.ps1 script
$runnerPath = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) {
    Write-Host "FAIL: Run-ReplayLoop.ps1 not found at $runnerPath" -ForegroundColor Red
    exit 1
}
$runnerContent = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

# Read the Verify-PlanContract.ps1 script
$verifierPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
if (-not (Test-Path -LiteralPath $verifierPath)) {
    Write-Host "FAIL: Verify-PlanContract.ps1 not found at $verifierPath" -ForegroundColor Red
    exit 1
}
$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

$totalTests = 0
$passedTests = 0

Write-Host ""
Write-Host "=== Test-v393: Golden Slice Binding Repair Prompt Enhancement ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Repair prompt contains explicit keyword list
$totalTests++
Write-Host "Test 1: Repair prompt contains explicit fingerprint keyword list" -ForegroundColor White
$p1 = "MUST contain one of.*side_effect_ledger_gap"
if (Test-RegexMatch -Pattern $p1 -Text $runnerContent -Description "Explicit keyword list") {
    Write-Host "  PASS" -ForegroundColor Green
    $passedTests++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 2: All required keywords listed
$totalTests++
Write-Host "Test 2: All 10 required fingerprint keywords found" -ForegroundColor White
$keywords = @("side_effect_ledger_gap", "exact_contract_gap", "schema_contract_discovery_gap", "low_verification_cap", "oracle_overlap", "positive_first_slice", "first_slice_contract", "stateful_side_effect", "literal_contract", "real_entry")
$foundCount = 0
foreach ($k in $keywords) {
    if ($runnerContent -match [regex]::Escape($k)) { $foundCount++ }
}
if ($foundCount -eq 10) {
    Write-Host "  PASS: All 10 keywords found" -ForegroundColor Green
    $passedTests++
} else {
    Write-Host "  FAIL: Found $foundCount / 10 keywords" -ForegroundColor Red
}

# Test 3: Verifier warning for FIRST_SLICE_PROOF_PLAN
$totalTests++
Write-Host "Test 3: Verifier adds warning for FIRST_SLICE_PROOF_PLAN.md" -ForegroundColor White
$p3 = "golden_slice_binding_weak:first_slice_proof"
if (Test-RegexMatch -Pattern $p3 -Text $verifierContent -Description "Verifier warning") {
    Write-Host "  PASS" -ForegroundColor Green
    $passedTests++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 4: Verifier warning for PLAN_RESULT
$totalTests++
Write-Host "Test 4: Verifier adds warning for PLAN_RESULT.md" -ForegroundColor White
$p4 = "golden_slice_binding_weak:plan_result"
if (Test-RegexMatch -Pattern $p4 -Text $verifierContent -Description "Verifier warning PLAN_RESULT") {
    Write-Host "  PASS" -ForegroundColor Green
    $passedTests++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Test 5: Verifier includes helpful error message with all keywords
$totalTests++
Write-Host "Test 5: Verifier includes helpful error message" -ForegroundColor White
$p5 = "must contain one of these fingerprint keywords"
if (Test-RegexMatch -Pattern $p5 -Text $verifierContent -Description "Helpful error message") {
    Write-Host "  PASS" -ForegroundColor Green
    $passedTests++
} else {
    Write-Host "  FAIL" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $passedTests / $totalTests" -ForegroundColor $(if ($passedTests -eq $totalTests) { 'Green' } else { 'Yellow' })
Write-Host ""

if ($passedTests -eq $totalTests) {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests FAILED" -ForegroundColor Red
    exit 1
}
