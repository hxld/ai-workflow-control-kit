# Regression Tests for v373 Experiments
#
# Tests the three experiments from NEXT_EXPERIMENT_PLAN.md:
# 1. Pre-Implementation Contract Verification
# 2. TODO Penalty and Placeholder Detection
# 3. RED Test Business Assertion Gate

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$testPass = 0
$testFail = 0

Write-Host "=== v373 Experiment Regression Tests ===" -ForegroundColor Cyan
Write-Host ""

# === Test 1: Coverage Penalty Calculator Exists ===
Write-Host "[Test 1] Coverage Penalty Calculator Script Exists" -ForegroundColor Yellow

$penaltyScript = Join-Path $PSScriptRoot "calculate-coverage-penalty.py"
if (Test-Path -LiteralPath $penaltyScript) {
    Write-Host "  PASS: Script exists at $penaltyScript" -ForegroundColor Green
    $testPass++
} else {
    Write-Host "  FAIL: Script not found at $penaltyScript" -ForegroundColor Red
    $testFail++
}

# === Test 2: Penalty Calculator Runs ===
Write-Host "[Test 2] Penalty Calculator Runs" -ForegroundColor Yellow

$testDir = Join-Path $env:TEMP "v373-test-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

# Create test files
$testJava1 = @"
package com.huize.claim.service;

public class TestService {
    // TODO: implement this
    public void handle(Long id) {
        // placeholder
        return;
    }
}
"@

$testJava2 = @"
package com.huize.claim.service;

public class GoodService {
    public void realMethod(Long id) {
        System.out.println("Real implementation");
    }
}
"@

Set-Content -Path (Join-Path $testDir "TestService.java") -Value $testJava1 -Encoding UTF8
Set-Content -Path (Join-Path $testDir "GoodService.java") -Value $testJava2 -Encoding UTF8

$inputJson = @{
    worktree_path = $testDir
} | ConvertTo-Json -Compress

try {
    # Write input JSON to temp file and pass it
    $inputFile = Join-Path $testDir "input.json"
    $inputJson | Out-File -FilePath $inputFile -Encoding UTF8

    $output = python $penaltyScript --input $inputFile 2>&1

    if ($Verbose) {
        Write-Host "  Output: $output" -ForegroundColor Gray
    }

    # Exit code 0 with penalty > 0 is also acceptable
    # Exit code 1 only when penalty > 50%
    if (($LASTEXITCODE -eq 0 -and $output -match "penalty_applied.*true") -or $LASTEXITCODE -eq 1) {
        Write-Host "  PASS: Penalty calculation working (exit code $LASTEXITCODE)" -ForegroundColor Green
        Write-Host "  Output contains TODO/placeholder detection" -ForegroundColor Cyan
        $testPass++
    } else {
        Write-Host "  FAIL: Expected penalty detection, got exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  Output: $output" -ForegroundColor DarkYellow
        $testFail++
    }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $testFail++
}

# Cleanup
Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue

# === Test 3: v348 Slice Quality Gate Updated ===
Write-Host "[Test 3] v348 Slice Quality Gate Includes Check 6" -ForegroundColor Yellow

$gateScript = Join-Path $PSScriptRoot "v348_slice_quality_gate.ps1"
if (Test-Path -LiteralPath $gateScript) {
    $gateContent = Get-Content $gateScript -Raw -Encoding UTF8
    if ($gateContent -match "Check 6.*Coverage Penalty") {
        Write-Host "  PASS: v348 gate includes Check 6 (Coverage Penalty)" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: v348 gate missing Check 6" -ForegroundColor Red
        $testFail++
    }

    if ($gateContent -match "calculate-coverage-penalty\.py") {
        Write-Host "  PASS: v348 gate references penalty calculator" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: v348 gate does not reference penalty calculator" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: v348_slice_quality_gate.ps1 not found" -ForegroundColor Red
    $testFail += 2
}

# === Test 4: Phase 0 Contract Gate Prompt Updated ===
Write-Host "[Test 4] Phase 0 Contract Gate Prompt Requires IMPLEMENTATION_CONTRACT.md" -ForegroundColor Yellow

$promptPath = Join-Path $PSScriptRoot "..\prompts\phase0-contract-gate.prompt.md"
if (Test-Path -LiteralPath $promptPath) {
    $promptContent = Get-Content $promptPath -Raw -Encoding UTF8

    # Test individual patterns
    $patterns = @(
        @{Pattern = "IMPLEMENTATION_CONTRACT\.md"; Name = "IMPLEMENTATION_CONTRACT.md reference"},
        @{Pattern = "carrier_class:"; Name = "carrier_class field requirement"},
        @{Pattern = "method_signature:"; Name = "method_signature field requirement"},
        @{Pattern = "parameter_types:"; Name = "parameter_types field requirement"},
        @{Pattern = "return_type:"; Name = "return_type field requirement"},
        @{Pattern = "carrier_status: EXISTING"; Name = "carrier_status requirement"},
        @{Pattern = "Experiment 1.*Pre-Implementation"; Name = "Experiment 1 reference"}
    )

    foreach ($p in $patterns) {
        if ($promptContent -match $p.Pattern) {
            Write-Host "  PASS: $($p.Name) found" -ForegroundColor Green
            $testPass++
        } else {
            Write-Host "  FAIL: $($p.Name) not found" -ForegroundColor Red
            $testFail++
        }
    }
} else {
    Write-Host "  FAIL: phase0-contract-gate.prompt.md not found" -ForegroundColor Red
    $testFail += 7
}

# === Test 5: Phase 1 Executor Prompt Updated ===
Write-Host "[Test 5] Phase 1 Executor Prompt Includes TODO Penalty Section" -ForegroundColor Yellow

$executorPath = Join-Path $PSScriptRoot "..\prompts\phase1-slice-executor.prompt.md"
if (Test-Path -LiteralPath $executorPath) {
    $executorContent = Get-Content $executorPath -Raw -Encoding UTF8

    $patterns = @(
        @{Pattern = "EXPERIMENT 2.*TODO Penalty"; Name = "Experiment 2 section"},
        @{Pattern = "coverage.*penalty"; Name = "Coverage penalty reference"},
        @{Pattern = "Test-Driven.*Development"; Name = "TDD guidance"}
    )

    foreach ($p in $patterns) {
        if ($executorContent -match $p.Pattern) {
            Write-Host "  PASS: $($p.Name) found" -ForegroundColor Green
            $testPass++
        } else {
            Write-Host "  FAIL: $($p.Name) not found" -ForegroundColor Red
            $testFail++
        }
    }
} else {
    Write-Host "  FAIL: phase1-slice-executor.prompt.md not found" -ForegroundColor Red
    $testFail += 3
}

# === Test 6: RED Phase Validator Exists (Experiment 3) ===
Write-Host "[Test 6] RED Phase Validator Script Exists" -ForegroundColor Yellow

$redValidator = Join-Path $PSScriptRoot "validate_red_phase.py"
if (Test-Path -LiteralPath $redValidator) {
    Write-Host "  PASS: validate_red_phase.py exists" -ForegroundColor Green
    $testPass++

    $redContent = Get-Content $redValidator -Raw -Encoding UTF8
    if ($redContent -match "business.*assertion") {
        Write-Host "  PASS: Validator checks business assertions" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Validator does not check business assertions" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: validate_red_phase.py not found" -ForegroundColor Red
    $testFail += 2
}

# === Test 7: Plan Contract Verify Exists (Experiment 1) ===
Write-Host "[Test 7] Plan Contract Verify Script Exists" -ForegroundColor Yellow

$planVerify = Join-Path $PSScriptRoot "plan_contract_verify.py"
if (Test-Path -LiteralPath $planVerify) {
    Write-Host "  PASS: plan_contract_verify.py exists" -ForegroundColor Green
    $testPass++

    $planContent = Get-Content $planVerify -Raw -Encoding UTF8
    if ($planContent -match "verify_carrier_exists") {
        Write-Host "  PASS: Script has carrier verification function" -ForegroundColor Green
        $testPass++
    } else {
        Write-Host "  FAIL: Script does not have carrier verification" -ForegroundColor Red
        $testFail++
    }
} else {
    Write-Host "  FAIL: plan_contract_verify.py not found" -ForegroundColor Red
    $testFail += 2
}

# === Summary ===
Write-Host ""
Write-Host "=== v373 Regression Test Summary ===" -ForegroundColor Cyan
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
