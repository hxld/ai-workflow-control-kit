# Test-v431-ExecutableEvidenceExperiments.ps1
# Tests for the three experiments from example-feature NEXT_EXPERIMENT_PLAN.md

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$autopilotRoot = Split-Path -Parent $scriptRoot

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Experiment 1: DESIGN-Phase Layer Validation - pre-flight-check.ps1, TEST_CHARTER_TEMPLATE.md',
            'Experiment 2: Mandatory Side Effect Ledger - verify-slice.ps1, SIDE_EFFECT_LEDGER_TEMPLATE.md',
            'Experiment 3: RED Phase Hard Gate - phase0-precheck.ps1, RED_PHASE_CHECKLIST.md'
        )
    } | Format-List
    exit 0
}

Write-Host "=== v431 Executable Evidence Experiments Test ===" -ForegroundColor Cyan

$allPassed = $true

# Test 1: Check pre-flight-check.ps1 exists and is valid
Write-Host "`n[Test 1] Verifying pre-flight-check.ps1..." -ForegroundColor Yellow
$preFlightScript = Join-Path $scriptRoot 'pre-flight-check.ps1'
if (-not (Test-Path -LiteralPath $preFlightScript)) {
    Write-Host "FAILED: pre-flight-check.ps1 not found" -ForegroundColor Red
    $allPassed = $false
} else {
    $content = Get-Content -LiteralPath $preFlightScript -Raw -Encoding UTF8
    if ($content -match 'function Test-CharterLayer' -and $content -match 'Invoke-LayerValidationGate') {
        Write-Host "PASSED: pre-flight-check.ps1 has Test-CharterLayer function" -ForegroundColor Green
    } else {
        Write-Host "FAILED: pre-flight-check.ps1 missing Test-CharterLayer function" -ForegroundColor Red
        $allPassed = $false
    }
}

# Test 2: Check verify-slice.ps1 exists and is valid
Write-Host "`n[Test 2] Verifying verify-slice.ps1..." -ForegroundColor Yellow
$verifySliceScript = Join-Path $scriptRoot 'verify-slice.ps1'
if (-not (Test-Path -LiteralPath $verifySliceScript)) {
    Write-Host "FAILED: verify-slice.ps1 not found" -ForegroundColor Red
    $allPassed = $false
} else {
    $content = Get-Content -LiteralPath $verifySliceScript -Raw -Encoding UTF8
    if ($content -match 'function Test-SideEffectLedger' -and $content -match 'Invoke-SideEffectVerificationGate') {
        Write-Host "PASSED: verify-slice.ps1 has Test-SideEffectLedger function" -ForegroundColor Green
    } else {
        Write-Host "FAILED: verify-slice.ps1 missing Test-SideEffectLedger function" -ForegroundColor Red
        $allPassed = $false
    }
}

# Test 3: Check phase0-precheck.ps1 exists and is valid
Write-Host "`n[Test 3] Verifying phase0-precheck.ps1..." -ForegroundColor Yellow
$phase0Precheck = Join-Path $scriptRoot 'phase0-precheck.ps1'
if (-not (Test-Path -LiteralPath $phase0Precheck)) {
    Write-Host "FAILED: phase0-precheck.ps1 not found" -ForegroundColor Red
    $allPassed = $false
} else {
    $content = Get-Content -LiteralPath $phase0Precheck -Raw -Encoding UTF8
    if ($content -match 'function Test-TestFramework' -and $content -match 'function Test-RedPhaseAuthorized') {
        Write-Host "PASSED: phase0-precheck.ps1 has required functions" -ForegroundColor Green
    } else {
        Write-Host "FAILED: phase0-precheck.ps1 missing required functions" -ForegroundColor Red
        $allPassed = $false
    }
}

# Test 4: Check prompt templates exist
Write-Host "`n[Test 4] Verifying prompt templates..." -ForegroundColor Yellow
$promptsPath = Join-Path $autopilotRoot 'prompts'

$templateTests = @(
    @{ Path = Join-Path $promptsPath 'TEST_CHARTER_TEMPLATE.md'; Name = 'TEST_CHARTER_TEMPLATE.md' },
    @{ Path = Join-Path $promptsPath 'SIDE_EFFECT_LEDGER_TEMPLATE.md'; Name = 'SIDE_EFFECT_LEDGER_TEMPLATE.md' },
    @{ Path = Join-Path $promptsPath 'RED_PHASE_CHECKLIST.md'; Name = 'RED_PHASE_CHECKLIST.md' }
)

foreach ($test in $templateTests) {
    if (Test-Path -LiteralPath $test.Path) {
        $content = Get-Content -LiteralPath $test.Path -Raw -Encoding UTF8
        if ($content.Length -gt 500) {
            Write-Host "PASSED: $($test.Name) exists and has content" -ForegroundColor Green
        } else {
            Write-Host "FAILED: $($test.Name) exists but appears empty" -ForegroundColor Red
            $allPassed = $false
        }
    } else {
        Write-Host "FAILED: $($test.Name) not found" -ForegroundColor Red
        $allPassed = $false
    }
}

# Test 5: Validate script execution
Write-Host "`n[Test 5] Validating script execution..." -ForegroundColor Yellow
$validateResult = & powershell -NoProfile -Command "& '$preFlightScript' -ValidateOnly" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASSED: pre-flight-check.ps1 ValidateOnly mode works" -ForegroundColor Green
} else {
    Write-Host "FAILED: pre-flight-check.ps1 ValidateOnly mode failed" -ForegroundColor Red
    $allPassed = $false
}

$validateResult = & powershell -NoProfile -Command "& '$verifySliceScript' -ValidateOnly" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASSED: verify-slice.ps1 ValidateOnly mode works" -ForegroundColor Green
} else {
    Write-Host "FAILED: verify-slice.ps1 ValidateOnly mode failed" -ForegroundColor Red
    $allPassed = $false
}

$validateResult = & powershell -NoProfile -Command "& '$phase0Precheck' -ValidateOnly" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASSED: phase0-precheck.ps1 ValidateOnly mode works" -ForegroundColor Green
} else {
    Write-Host "FAILED: phase0-precheck.ps1 ValidateOnly mode failed" -ForegroundColor Red
    $allPassed = $false
}

# Test 6: Check for existing enforcement integration
Write-Host "`n[Test 6] Verifying existing enforcement integration..." -ForegroundColor Yellow
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
if (Test-Path -LiteralPath $runSliceLoop) {
    $content = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8

    # Check if test charter prevalidator is already integrated
    if ($content -match 'Invoke-TestCharterPrevalidator') {
        Write-Host "INFO: Invoke-TestCharterPrevalidator already integrated in Run-SliceLoop.ps1" -ForegroundColor Cyan
    }

    # Check if RED phase hard gate is integrated
    if ($content -match 'Invoke-RedPhaseHardGate') {
        Write-Host "INFO: Invoke-RedPhaseHardGate already integrated in Run-SliceLoop.ps1" -ForegroundColor Cyan
    }

    # Check if validate_side_effects.py exists
    $validateSideEffects = Join-Path $scriptRoot 'validate_side_effects.py'
    if (Test-Path -LiteralPath $validateSideEffects) {
        Write-Host "INFO: validate_side_effects.py already exists" -ForegroundColor Cyan
    }
}

# Final result
Write-Host "`n=== Test Result ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "v431 Executable Evidence Experiments: ALL PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "v431 Executable Evidence Experiments: SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
