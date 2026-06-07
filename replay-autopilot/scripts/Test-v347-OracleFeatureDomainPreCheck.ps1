# Test-v347-OracleFeatureDomainPreCheck.ps1
#
# Regression test for v347 Oracle Feature Domain Pre-Check evolution.
#
# Purpose: Validate that the Invoke-OracleFeatureDomainCheck.ps1 script
# correctly detects oracle-feature domain mismatches before planning.
#
# Version: v347

$ErrorActionPreference = 'Stop'

$FixtureDir = "D:\opt\replay-autopilot\scripts\tests\fixtures"
$ScriptPath = "D:\opt\replay-autopilot\scripts\Invoke-OracleFeatureDomainCheck.ps1"

function Test-ScriptExists {
    $testName = "Invoke-OracleFeatureDomainCheck.ps1 exists"

    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath $ScriptPath -Raw), [ref]$null)

    Write-Host "✓ Script exists and has valid syntax" -ForegroundColor Green
    return $true
}

function Test-OracleDomainCompatibility {
    $testName = "Oracle domain compatibility detection"

    $mismatchOracle = Join-Path $FixtureDir "v347-oracle-mismatch.json"
    $compatibleOracle = Join-Path $FixtureDir "v347-oracle-compatible.json"
    $requirement = Join-Path $FixtureDir "v347-ai-autoflow-requirement.md"

    $TestRoot = Join-Path $env:TEMP "Test-v347-OracleFeatureDomain-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    try {
        # Test 1: MISMATCH detection
        $out1 = Join-Path $TestRoot "result1.json"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -OracleDiffAnalysis $mismatchOracle -RequirementSource $requirement -OutPath $out1

        $result1 = Get-Content -LiteralPath $out1 -Raw | ConvertFrom-Json

        if ($result1.domain_compatibility -ne 'MISMATCH') {
            throw "Test 1 failed: Expected MISMATCH, got $($result1.domain_compatibility)"
        }

        if ($result1.check_status -ne 'BLOCK') {
            throw "Test 1 failed: Expected BLOCK status, got $($result1.check_status)"
        }

        if ($result1.oracle_primary_domain -ne 'examine') {
            throw "Test 1 failed: Expected oracle_primary_domain='examine', got '$($result1.oracle_primary_domain)'"
        }

        if ($result1.requirement_primary_domain -ne 'ai') {
            throw "Test 1 failed: Expected requirement_primary_domain='ai', got '$($result1.requirement_primary_domain)'"
        }

        # Test 2: COMPATIBLE detection
        $out2 = Join-Path $TestRoot "result2.json"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -OracleDiffAnalysis $compatibleOracle -RequirementSource $requirement -OutPath $out2

        $result2 = Get-Content -LiteralPath $out2 -Raw | ConvertFrom-Json

        if ($result2.domain_compatibility -ne 'COMPATIBLE') {
            throw "Test 2 failed: Expected COMPATIBLE, got $($result2.domain_compatibility)"
        }

        if ($result2.check_status -ne 'PASS') {
            throw "Test 2 failed: Expected PASS status, got $($result2.check_status)"
        }

        # Test 3: SKIP on missing oracle analysis
        $out3 = Join-Path $TestRoot "result3.json"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -OracleDiffAnalysis "nonexistent.json" -RequirementSource $requirement -OutPath $out3

        $result3 = Get-Content -LiteralPath $out3 -Raw | ConvertFrom-Json

        if ($result3.check_status -ne 'SKIP') {
            throw "Test 3 failed: Expected SKIP status, got $($result3.check_status)"
        }

        Write-Host "✓ Oracle domain compatibility detection - PASS" -ForegroundColor Green
        return $true
    }
    finally {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Run all tests
$totalTests = 2
$passedTests = 0

try {
    Test-ScriptExists
    $passedTests++
} catch {
    Write-Host "✗ Script exists test failed: $_" -ForegroundColor Red
}

try {
    Test-OracleDomainCompatibility
    $passedTests++
} catch {
    Write-Host "✗ Oracle domain compatibility test failed: $_" -ForegroundColor Red
}

Write-Host "`nTest Results: $passedTests/$totalTests passed"

if ($passedTests -eq $totalTests) {
    Write-Host "v347 Oracle Feature Domain Pre-Check: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "v347 Oracle Feature Domain Pre-Check: FAIL" -ForegroundColor Red
    exit 1
}
