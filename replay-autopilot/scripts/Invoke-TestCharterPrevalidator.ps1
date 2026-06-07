# Invoke-TestCharterPrevalidator.ps1
# PowerShell wrapper for test_charter_prevalidator.py
# Part of v379 evolution: Test Charter Pre-Validation Gate

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$gateScript = Join-Path $PSScriptRoot 'test_charter_prevalidator.py'
$testCharterPath = Join-Path $WorkDir 'TEST_CHARTER.md'

if (-not (Test-Path -LiteralPath $gateScript)) {
    Write-Host "Test charter prevalidator: script missing at $gateScript" -ForegroundColor Yellow
    if ($PassThru) {
        return @{ can_proceed = $true; verification_status = 'SCRIPT_MISSING' }
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $testCharterPath)) {
    Write-Host "Test charter prevalidator: TEST_CHARTER.md not found (skipping)" -ForegroundColor DarkGray
    if ($PassThru) {
        return @{ can_proceed = $true; verification_status = 'NO_TEST_CHARTER' }
    }
    exit 0
}

Write-Host "Running test charter prevalidation..." -ForegroundColor Cyan

$result = & python3 $gateScript $testCharterPath --output json 2>&1
$exitCode = $LASTEXITCODE

if ($PassThru) {
    $resultObj = $result | ConvertFrom-Json
    return @{
        can_proceed = $resultObj.valid
        verification_status = if ($resultObj.valid) { 'PASSED' } else { 'FAILED' }
        failures = $resultObj.failures
        warnings = $resultObj.warnings
        failure_count = $resultObj.failure_count
        warning_count = $resultObj.warning_count
    }
}

if ($exitCode -eq 0) {
    Write-Host "Test charter prevalidation: PASSED" -ForegroundColor Green
} else {
    Write-Host "Test charter prevalidation: FAILED" -ForegroundColor Red
    $resultObj = $result | ConvertFrom-Json
    if ($resultObj.failures) {
        foreach ($f in $resultObj.failures) {
            Write-Host "  ❌ [$($f.code)]: $($f.message)" -ForegroundColor Red
        }
    }
    if ($resultObj.warnings) {
        foreach ($w in $resultObj.warnings) {
            Write-Host "  ⚠️  [$($w.code)]: $($w.message)" -ForegroundColor Yellow
        }
    }
}

exit $exitCode
