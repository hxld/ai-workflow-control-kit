<#
.SYNOPSIS
    Regression tests for v351 STOP_AND_EVOLVE enforcement strengthening.

.DESCRIPTION
    Validates that the conditional enforcement bypass conditions have been removed
    from the horizontal slice gate, making it apply to ALL S1 slices with implemented
    files, not just "complex" ones (requiredFamilyCount >= 3).
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== v351 STOP_AND_EVOLVE Enforcement Strengthening Test ===" -ForegroundColor Cyan

$runnerPath = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) {
    Write-Host "FAIL: Run-SliceLoop.ps1 not found" -ForegroundColor Red
    exit 1
}

$content = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

Write-Host "`n[Test 1] Horizontal slice bypass condition removed..."
if ($content -match '\$requiredFamilyCount\s*-ge\s+3.*\{') {
    Write-Host "FAIL: Horizontal slice gate still has \$requiredFamilyCount -ge 3 bypass condition" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: \$requiredFamilyCount -ge 3 bypass condition removed" -ForegroundColor Green

Write-Host "`n[Test 2] Horizontal slice applies to all S1 with implemented files..."
if ($content -notmatch 'if\s*\(\$SliceIndex\s+-eq\s+1\s+-and\s+\$implementedFiles\.Count\s+-gt\s+0\)\s*\{') {
    Write-Host "FAIL: Horizontal slice gate condition is not 'S1 with implemented files only'" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Horizontal slice applies to all S1 with implemented files" -ForegroundColor Green

Write-Host "`n[Test 3] Horizontal slice gate is still invoked..."
if ($content -notmatch 'verify-horizontal-slice\.ps1') {
    Write-Host "FAIL: verify-horizontal-slice.ps1 invocation missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Horizontal slice gate invocation present" -ForegroundColor Green

Write-Host "`n[Test 4] Horizontal slice minimum still enforced..."
if ($content -notmatch 'horizontal_slice_minimum_not_met') {
    Write-Host "FAIL: horizontal_slice_minimum_not_met blocker missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Horizontal slice minimum enforcement present" -ForegroundColor Green

Write-Host "`n[Test 5] v351 comment present documenting the change..."
if ($content -notmatch 'v351.*Strengthened enforcement.*removed.*bypass') {
    Write-Host "FAIL: v351 comment documenting the bypass removal is missing" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: v351 change documented in code" -ForegroundColor Green

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
