# Test-v347-OracleFeatureDomainPreCheck.ps1
#
# Regression test for v347/v578 Oracle Feature Domain Pre-Check evolution.
#
# Purpose: Validate that the Invoke-OracleFeatureDomainCheck.ps1 script
# detects primary-domain mismatches without blocking legitimate supporting
# domain surfaces before domain-filtered planning can run.
#
# Version: v347/v578

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FixtureDir = Join-Path $ScriptDir "tests\fixtures"
$ScriptPath = Join-Path $ScriptDir "Invoke-OracleFeatureDomainCheck.ps1"

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
    $supportingDomainOracle = Join-Path $FixtureDir "v578-primary-ai-with-supporting-domains.json"
    $requirement = Join-Path $FixtureDir "v347-ai-autoflow-requirement.md"

    $TestRoot = Join-Path $env:TEMP ("Test-v347-OracleFeatureDomain-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    try {
        # Test 1: primary-domain mismatch detection
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

        # Test 2: compatible single-domain oracle
        $out2 = Join-Path $TestRoot "result2.json"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -OracleDiffAnalysis $compatibleOracle -RequirementSource $requirement -OutPath $out2

        $result2 = Get-Content -LiteralPath $out2 -Raw | ConvertFrom-Json

        if ($result2.domain_compatibility -ne 'COMPATIBLE') {
            throw "Test 2 failed: Expected COMPATIBLE, got $($result2.domain_compatibility)"
        }

        if ($result2.check_status -ne 'PASS') {
            throw "Test 2 failed: Expected PASS status, got $($result2.check_status)"
        }

        if ([bool]$result2.supporting_domain_review_required) {
            throw "Test 2 failed: Expected supporting_domain_review_required=false for single-domain oracle"
        }

        if ($result2.foreign_domain_ratio -ne 0) {
            throw "Test 2 failed: Expected foreign_domain_ratio=0, got '$($result2.foreign_domain_ratio)'"
        }

        # Test 3: ai primary domain with multiple supporting domains remains compatible.
        $outSupporting = Join-Path $TestRoot "result-supporting.json"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -OracleDiffAnalysis $supportingDomainOracle -RequirementSource $requirement -OutPath $outSupporting

        $supportingResult = Get-Content -LiteralPath $outSupporting -Raw | ConvertFrom-Json

        if ($supportingResult.domain_compatibility -ne 'COMPATIBLE') {
            throw "Test 3 failed: Expected COMPATIBLE for primary ai with supporting domains, got $($supportingResult.domain_compatibility)"
        }

        if ($supportingResult.check_status -ne 'PASS') {
            throw "Test 3 failed: Expected PASS for primary ai with supporting domains, got $($supportingResult.check_status)"
        }

        if ($supportingResult.oracle_primary_domain -ne 'ai') {
            throw "Test 3 failed: Expected oracle_primary_domain='ai', got '$($supportingResult.oracle_primary_domain)'"
        }

        if (-not [bool]$supportingResult.supporting_domain_review_required) {
            throw "Test 3 failed: Expected supporting_domain_review_required=true"
        }

        if (@($supportingResult.supporting_domain_evidence).Count -lt 3) {
            throw "Test 3 failed: Expected supporting_domain_evidence for supporting surfaces"
        }

        # Test 4: SKIP on missing oracle analysis
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
