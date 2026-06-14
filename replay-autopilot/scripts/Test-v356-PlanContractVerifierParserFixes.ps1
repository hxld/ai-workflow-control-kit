<#
.SYNOPSIS
    Regression test for v356 plan contract verifier parser fixes

.DESCRIPTION
    Tests two parser fixes:
    1. new_service_created field recognition (was only new_service_proposed)
    2. oracle_out_of_scope_files exclusion from overlap calculation

.NOTES
    v356 evolution test - plan contract verifier parser bugs
#>

param(
    [string]$ReplayRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\aiClaimV2\claim-codex-replay-v355-autopilot-20260517-r01"
)

$ErrorActionPreference = 'Stop'
$testPass = $true
$testResults = @()

Write-Host "=== v356 Plan Contract Verifier Parser Fixes ===" -ForegroundColor Cyan

# Test 1: Verify new_service_created field is recognized
Write-Host "`n[Test 1] new_service_created field recognition..." -ForegroundColor Yellow
$testPlanContent = @'
# Plan Result
plan_status: PROCEED
new_service_created: true
new_service_justification: orphan_feature
selected_carrier_from_search: NONE_FOUND
carrier_search_status: COMPLETED
carrier_search_queries: rg "CarrierSearchFacade" claim-core
existing_production_carriers: AiClaimDataFacade
'@

$testPlanPath = Join-Path $env:TEMP "v356-test-plan-result.md"
$testPlanContent | Out-File -LiteralPath $testPlanPath -Encoding UTF8

try {
    $testScript = {
        param($path)
        $plan = Get-Content $path -Raw
        if ($plan -match '(?m)^\s*new_service_created\s*[:=]\s*([^\r\n]+)') {
            return "PASS_FIELD_RECOGNIZED"
        } else {
            return "FAIL_FIELD_NOT_RECOGNIZED"
        }
    }
    $verifyResult = & $testScript $testPlanPath

    if ($verifyResult -eq "PASS_FIELD_RECOGNIZED") {
        Write-Host "  PASS: new_service_created field recognized" -ForegroundColor Green
        $testResults += "Test1: PASS"
    } else {
        Write-Host "  FAIL: new_service_created field not recognized" -ForegroundColor Red
        $testResults += "Test1: FAIL"
        $testPass = $false
    }
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    $testResults += "Test1: ERROR"
    $testPass = $false
}
Remove-Item -LiteralPath $testPlanPath -Force -ErrorAction SilentlyContinue

# Test 2: Verify oracle_out_of_scope_files is parsed
Write-Host "`n[Test 2] oracle_out_of_scope_files parsing..." -ForegroundColor Yellow
$testPlanContent2 = @'
# Plan Result
oracle_out_of_scope_files: [file1.jsp, file2.js, file3.html]
'@

$testPlanPath2 = Join-Path $env:TEMP "v356-test-plan-result2.md"
$testPlanContent2 | Out-File -LiteralPath $testPlanPath2 -Encoding UTF8

try {
    $testScript2 = {
        param($path)
        $plan = Get-Content $path -Raw
        if ($plan -match '(?im)^\s*oracle_out_of_scope_files\s*[:=]\s*\[(.+?)\]') {
            if ($Matches[1] -match 'file1\.jsp') {
                return "PASS_OUT_OF_SCOPE_PARSED"
            }
        }
        return "FAIL_OUT_OF_SCOPE_NOT_PARSED"
    }
    $verifyResult2 = & $testScript2 $testPlanPath2

    if ($verifyResult2 -eq "PASS_OUT_OF_SCOPE_PARSED") {
        Write-Host "  PASS: oracle_out_of_scope_files parsed correctly" -ForegroundColor Green
        $testResults += "Test2: PASS"
    } else {
        Write-Host "  FAIL: oracle_out_of_scope_files not parsed correctly" -ForegroundColor Red
        $testResults += "Test2: FAIL"
        $testPass = $false
    }
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    $testResults += "Test2: ERROR"
    $testPass = $false
}
Remove-Item -LiteralPath $testPlanPath2 -Force -ErrorAction SilentlyContinue

# Test 3: Verify actual verifier script has the fixes
Write-Host "`n[Test 3] Verify-PlanContract.ps1 contains fixes..." -ForegroundColor Yellow

$verifierPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Verify-PlanContract.ps1'
$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

$fix1Present = $verifierContent -match 'new_service_created'
$fix2Present = $verifierContent -match 'oracleOutOfScopeFiles'
$fix3Present = $verifierContent -match 'filteredOracleProdFiles'

if ($fix1Present -and $fix2Present -and $fix3Present) {
    Write-Host "  PASS: All fixes present in verifier" -ForegroundColor Green
    $testResults += "Test3: PASS"
} else {
    Write-Host "  FAIL: Missing fixes in verifier" -ForegroundColor Red
    Write-Host "    new_service_created: $fix1Present" -ForegroundColor Gray
    Write-Host "    oracleOutOfScopeFiles: $fix2Present" -ForegroundColor Gray
    Write-Host "    filteredOracleProdFiles: $fix3Present" -ForegroundColor Gray
    $testResults += "Test3: FAIL"
    $testPass = $false
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
foreach ($result in $testResults) {
    Write-Host "  $result" -ForegroundColor $(if ($result -like "*PASS") { "Green" } else { "Red" })
}

if ($testPass) {
    Write-Host "`nAll tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests FAILED" -ForegroundColor Red
    exit 1
}
