# Regression test for v383: IMPLEMENTATION_CONTRACT.md format auto-repair
# This test verifies that the verifier can auto-repair IMPLEMENTATION_CONTRACT.md
# when it's missing the required simple key-value lines at the top.

param(
    [Parameter(Mandatory = $false)]
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\test\evidence\v383-contract-repair')
)

$ErrorActionPreference = 'Stop'

function Test-ContractFormatRepair {
    # Create a temporary test directory
    $testDir = Join-Path $env:TEMP "v383-contract-repair-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null

    try {
        Write-Host "Testing v383: IMPLEMENTATION_CONTRACT.md format auto-repair"

        # Create a broken IMPLEMENTATION_CONTRACT.md (missing simple key-value lines)
        $brokenContract = @'
# Implementation Contract

- generated_at: 2026-06-02T09:51:44
- run_label: v381-autopilot
- round: r03
- feature_name: example-feature
- phase: 0

## Carrier

### Primary Carrier
- **carrier_class**: `ExampleCalculatorApiTaskProcessor`
- **carrier_status**: EXISTING
'@
        Set-Content -LiteralPath (Join-Path $testDir 'IMPLEMENTATION_CONTRACT.md') -Value $brokenContract -Encoding UTF8

        # Create a FIRST_SLICE_PROOF_PLAN.md with the correct values
        $proofPlan = @'
# First Slice Proof Plan

first_slice: S1
selected_real_entry: ExampleCalculatorApiTaskProcessor.handleTaskResponse()
first_red_test: ExampleFlowServiceTest.testTriggerAutoFlowWhenAllConditionsMet
'@
        Set-Content -LiteralPath (Join-Path $testDir 'FIRST_SLICE_PROOF_PLAN.md') -Value $proofPlan -Encoding UTF8

        # Create a PLAN_RESULT.md with first_slice and first_red_test
        # Format must match what the verifier expects for parsing
        $planResult = @'
# Plan Result

## Plan Status
- plan_status: PROCEED

## Key Fields
- **first_slice**: S1
- **first_red_test**: ExampleFlowServiceTest.testTriggerAutoFlowWhenAllConditionsMet
'@
        Set-Content -LiteralPath (Join-Path $testDir 'PLAN_RESULT.md') -Value $planResult -Encoding UTF8

        # Run the verifier
        $verifierPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
        $verifyOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifierPath -ReplayRoot $testDir -Stage Plan 2>&1
        $verifyExitCode = $LASTEXITCODE

        # Check the verification result
        $verifyPath = Join-Path $testDir 'PLAN_CONTRACT_VERIFY.json'
        $verifyResult = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json

        # Read the repaired contract
        $repairedContract = Get-Content -LiteralPath (Join-Path $testDir 'IMPLEMENTATION_CONTRACT.md') -Raw -Encoding UTF8

        # Assertion 1: selected_real_entry should be added
        if ($repairedContract -notmatch '(?m)^selected_real_entry:\s') {
            Write-Host "FAIL: selected_real_entry not added to IMPLEMENTATION_CONTRACT.md" -ForegroundColor Red
            Write-Host "Contract content:" $repairedContract
            return $false
        }
        Write-Host "PASS: selected_real_entry added" -ForegroundColor Green

        # Assertion 2: first_slice should be added
        if ($repairedContract -notmatch '(?m)^first_slice:\s+S1') {
            Write-Host "FAIL: first_slice not added to IMPLEMENTATION_CONTRACT.md" -ForegroundColor Red
            Write-Host "Contract content:" $repairedContract
            return $false
        }
        Write-Host "PASS: first_slice added" -ForegroundColor Green

        # Assertion 3: first_red_test should be added
        if ($repairedContract -notmatch '(?m)^first_red_test:\s+') {
            Write-Host "FAIL: first_red_test not added to IMPLEMENTATION_CONTRACT.md" -ForegroundColor Red
            Write-Host "Contract content:" $repairedContract
            return $false
        }
        Write-Host "PASS: first_red_test added" -ForegroundColor Green

        # Assertion 4: No 'implementation_contract_missing:selected real entry' issue
        if ($verifyResult.issues -contains 'implementation_contract_missing:selected real entry') {
            Write-Host "FAIL: implementation_contract_missing issue still present after repair" -ForegroundColor Red
            return $false
        }
        Write-Host "PASS: No implementation_contract_missing issue" -ForegroundColor Green

        return $true
    }
    finally {
        # Cleanup
        if (Test-Path -LiteralPath $testDir) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Run the test
$result = Test-ContractFormatRepair
if ($result) {
    Write-Host "`nAll v383 contract format repair tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nv383 contract format repair tests FAILED" -ForegroundColor Red
    exit 1
}
