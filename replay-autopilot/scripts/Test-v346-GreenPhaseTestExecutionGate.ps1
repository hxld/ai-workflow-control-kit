<#
.SYNOPSIS
    Regression tests for v346 GREEN phase test execution enforcement.

.DESCRIPTION
    Guards the v345 follow-up fix: implemented files must require an executable
    GREEN test even if touched_requirement_families is missing, and test module
    selection must come from slice evidence instead of a hardcoded project module.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== v346 GREEN Phase Test Execution Gate Test ===" -ForegroundColor Cyan

$runnerPath = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) {
    Write-Host "FAIL: Run-SliceLoop.ps1 not found" -ForegroundColor Red
    exit 1
}

$content = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

Write-Host "`n[Test 1] No touched-family early bypass..."
if ($content -match '\$implementedFiles\.Count\s+-eq\s+0\s+-or\s+\$touchedFamilies\.Count\s+-eq\s+0') {
    Write-Host "FAIL: GREEN gate still bypasses test execution when touched families are missing" -ForegroundColor Red
    exit 1
}
if ($content -notmatch 'if\s*\(\$implementedFiles\.Count\s+-eq\s+0\)') {
    Write-Host "FAIL: GREEN gate no-implementation bypass is missing or malformed" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: touched-family metadata no longer authorizes skipping test execution" -ForegroundColor Green

Write-Host "`n[Test 2] Missing GREEN test fails closed..."
if ($content -notmatch "execution_status\s*=\s*'FAILED'") {
    Write-Host "FAIL: default test execution status is not FAILED" -ForegroundColor Red
    exit 1
}
if ($content -notmatch "reason\s*=\s*'green_test_class_missing'") {
    Write-Host "FAIL: missing GREEN test class reason is not enforced" -ForegroundColor Red
    exit 1
}
if ($content -notmatch "execution_status\s+-ne\s+'PASSED'") {
    Write-Host "FAIL: GREEN gate does not block every non-PASSED test execution result" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: missing or failed GREEN test execution blocks the slice" -ForegroundColor Green

Write-Host "`n[Test 3] Module inference is evidence-based..."
if ($content -notmatch 'function\s+Get-TestModuleFromSliceEvidence') {
    Write-Host "FAIL: module inference helper is missing" -ForegroundColor Red
    exit 1
}
if ($content -notmatch 'src/test/\(java\|resources\)') {
    Write-Host "FAIL: module inference does not inspect src/test/java or src/test/resources paths" -ForegroundColor Red
    exit 1
}
if ($content -match "\$testModule\s*=\s*'example-server'") {
    Write-Host "FAIL: GREEN test execution still hardcodes example-server as the module" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: test module is inferred from test evidence paths" -ForegroundColor Green

Write-Host "`n[Test 4] Test execution artifact is preserved..."
if ($content -notmatch 'GREEN_PHASE_TEST_EXECUTION_\{0:D2\}\.json') {
    Write-Host "FAIL: GREEN_PHASE_TEST_EXECUTION artifact path is missing" -ForegroundColor Red
    exit 1
}
if ($content -notmatch 'test_module_not_inferred') {
    Write-Host "FAIL: missing module inference does not produce a specific blocker" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: test execution evidence and blockers are explicit" -ForegroundColor Green

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0

