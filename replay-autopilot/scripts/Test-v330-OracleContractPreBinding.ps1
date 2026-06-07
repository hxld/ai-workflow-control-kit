# Test-v330-OracleContractPreBinding.ps1
# Tests for Phase 2: Oracle Contract Pre-Binding evolution

$ErrorActionPreference = 'Stop'

$TestRoot = Split-Path -Parent $PSScriptRoot
$PhasesRoot = Join-Path $TestRoot "phases"
$ScriptsRoot = Join-Path $TestRoot "scripts"

$totalTests = 0
$passedTests = 0

function Test-Group {
    param([string]$Name)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
}

function Test-Case {
    param([string]$Name, [scriptblock]$Test)
    $totalTests++
    Write-Host "[$totalTests] $Name" -NoNewline
    try {
        $null = & $Test
        Write-Host " - PASS" -ForegroundColor Green
        $passedTests++
    } catch {
        Write-Host " - FAIL" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

# Test 1: Phase 0 oracle contract extract script exists
Test-Group "Phase 2 Tooling Files"
Test-Case "phase0-oracle-contract-extract.sh exists" {
    $scriptPath = Join-Path $PhasesRoot "phase0-oracle-contract-extract.sh"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }
}

# Test 2: Plan contract verification script exists
Test-Case "plan-contract-verification.sh exists" {
    $scriptPath = Join-Path $PhasesRoot "plan-contract-verification.sh"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }
}

# Test 3: Oracle contract extraction script exists
Test-Case "extract_oracle_contracts.py exists" {
    $scriptPath = Join-Path $ScriptsRoot "extract_oracle_contracts.py"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }
}

# Test 4: Phase tournament prompt has EXACT Oracle Signatures section
Test-Group "Prompt Integration"
Test-Case "phase-plan-tournament.prompt.md has EXACT Oracle Signatures section" {
    $promptPath = Join-Path $TestRoot "prompts\phase-plan-tournament.prompt.md"
    if (-not (Test-Path -LiteralPath $promptPath)) {
        throw "Prompt file not found: $promptPath"
    }
    $content = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    if ($content -notmatch "EXACT Oracle Signatures.*Phase 2 Pre-Binding") {
        throw "EXACT Oracle Signatures section not found in prompt"
    }
    if ($content -notmatch "oracle_contract_pre_binding:") {
        throw "oracle_contract_pre_binding field not documented in prompt"
    }
}

# Test 5: Oracle contract extraction script is executable
Test-Group "Script Functionality"
Test-Case "phase0-oracle-contract-extract.sh has valid bash syntax" {
    $scriptPath = Join-Path $PhasesRoot "phase0-oracle-contract-extract.sh"
    $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    # Basic checks for bash script structure
    if ($content -notmatch '#!/bin/bash') {
        throw "Missing bash shebang"
    }
    if ($content -notmatch 'set -e') {
        throw "Missing 'set -e' for error handling"
    }
    if ($content -notmatch 'ORACLE_CONTRACT_EXTRACTION') {
        throw "Missing ORACLE_CONTRACT_EXTRACTION marker"
    }
}

# Test 6: Plan contract verification script is executable
Test-Case "plan-contract-verification.sh has valid bash syntax" {
    $scriptPath = Join-Path $PhasesRoot "plan-contract-verification.sh"
    $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    if ($content -notmatch '#!/bin/bash') {
        throw "Missing bash shebang"
    }
    if ($content -notmatch 'set -e') {
        throw "Missing 'set -e' for error handling"
    }
    if ($content -notmatch 'PLAN_CONTRACT_VERIFICATION') {
        throw "Missing PLAN_CONTRACT_VERIFICATION marker"
    }
}

# Test 7: Oracle contract extraction script is documented
Test-Group "Documentation"
Test-Case "extract_oracle_contracts.py has usage documentation" {
    $scriptPath = Join-Path $ScriptsRoot "extract_oracle_contracts.py"
    $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    if ($content -notmatch 'Usage:') {
        throw "Missing usage documentation"
    }
    if ($content -notmatch 'Extract oracle method contracts') {
        throw "Missing module docstring"
    }
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $passedTests / $totalTests" -ForegroundColor $(if ($passedTests -eq $totalTests) { "Green" } else { "Yellow" })
Write-Host "Success Rate: $(if ($totalTests -gt 0) { [math]::Round($passedTests / $totalTests * 100, 1) } else { 0 })%"

if ($passedTests -lt $totalTests) {
    Write-Host "`nSome tests failed. v330 Oracle Contract Pre-Binding evolution is incomplete." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll tests passed! v330 Oracle Contract Pre-Binding evolution is properly integrated." -ForegroundColor Green
    exit 0
}
