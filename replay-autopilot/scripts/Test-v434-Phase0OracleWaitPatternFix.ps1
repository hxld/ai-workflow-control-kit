# Regression test for v434 Phase0 Oracle Wait Pattern Fix
#
# This test validates that the $manualOracleWaitPattern in Verify-PlanContract.ps1
# correctly distinguishes between:
# 1. Manual oracle wait language (should be flagged)
# 2. Legitimate "Next Steps" planning content (should NOT be flagged)

param(
    [Parameter(Mandatory=$true)]
    [string]$ReplayRoot
)

$ErrorActionPreference = 'Stop'
$testRoot = $ReplayRoot
$testsPassed = 0
$testsFailed = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        Write-Host "PASS: $Name" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "FAIL: $Name" -ForegroundColor Red
        $script:testsFailed++
    }
}

# Test 1: Legitimate Next Steps should NOT trigger phase0_manual_oracle_wait
$legitimateNextSteps = @'
## Immediate Next Steps

1. **Implement S1**: TExampleModuleConfig.freeReviewAmount
   - Add field to entity
   - Update mapper XML

2. **Implement S2**: ExampleFlowService (NEW oracle service)
   - Create service class (not in baseline)
   - Derive method signature from requirement

3. **Implement S3**: ClaimCalculationBookService (NEW oracle service)
   - Create service for PNG generation
'@

# Import the pattern from Verify-PlanContract.ps1
$verifyScript = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$verifyContent = Get-Content -LiteralPath $verifyScript -Raw -Encoding UTF8

# Extract the pattern from the script
if ($verifyContent -match '\$manualOracleWaitPattern\s*=\s*[''"](?<pattern>[^''"]+)[''"]') {
    $pattern = $matches['pattern']
    Write-Host "Extracted pattern from Verify-PlanContract.ps1" -ForegroundColor Cyan
} else {
    Write-Error "Failed to extract pattern from Verify-PlanContract.ps1"
    exit 1
}

# Test 1: Legitimate Next Steps should NOT match
Assert-True -Name 'Legitimate_Next_Steps_Does_Not_Trigger' -Condition ($legitimateNextSteps -notmatch $pattern)

# Test 2: Manual oracle wait language SHOULD match
$manualOracleWaitText = @'
# Phase 0 Planning

The next step requires Oracle verification before proceeding.
Next action: waiting for Oracle to provide access.
'@
Assert-True -Name 'Manual_Oracle_Wait_Does_Trigger' -Condition ($manualOracleWaitText -match $pattern)

# Test 3: "After Oracle Post-Hoc" should match
$afterOraclePostHoc = @'
# Planning Notes

After Oracle Post-Hoc verification, we can proceed.
'@
Assert-True -Name 'After_Oracle_PostHoc_Does_Trigger' -Condition ($afterOraclePostHoc -match $pattern)

# Test 4: "Oracle commit pending" should match
$oracleCommitPending = @'
# Status

Oracle commit pending before next step.
'@
Assert-True -Name 'Oracle_Commit_Pending_Does_Trigger' -Condition ($oracleCommitPending -match $pattern)

# Test 5: Full Phase0 artifact should verify successfully
$phase0Path = Join-Path $ReplayRoot 'PHASE0_RESULT.md'
$explorationPath = Join-Path $ReplayRoot 'EXPLORATION_REPORT.md'
$contractPath = Join-Path $ReplayRoot 'ROUND_CONTRACT.md'

if ((Test-Path -LiteralPath $phase0Path) -and
    (Test-Path -LiteralPath $explorationPath) -and
    (Test-Path -LiteralPath $contractPath)) {

    $phase0Text = Get-Content -LiteralPath $phase0Path -Raw -Encoding UTF8
    $explorationText = Get-Content -LiteralPath $explorationPath -Raw -Encoding UTF8
    $contractText = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8

    # The pattern is applied to $phase0Text only (not combined text)
    Assert-True -Name 'Phase0_Artifact_Does_Not_Have_False_Positive' -Condition ($phase0Text -notmatch $pattern)
} else {
    Write-Host "SKIP: Full artifact test - missing artifacts" -ForegroundColor Yellow
}

# Test 6: Pattern should not match "NEW_ORACLE_SERVICE" description
$newServiceDescription = @'
- **required_flags**: ["NEW_ORACLE_SERVICE", "exact_contract_gap", "schema_verification_gap"]
- **carrier_status**: "NEW"
- **coverage_cap**: 40% (NEW_ORACLE_SERVICE, signature uncertainty)
'@
Assert-True -Name 'New_Oracle_Service_Description_Does_Not_Trigger' -Condition ($newServiceDescription -notmatch $pattern)

# Test 7: Verify the full pattern check in Verify-PlanContract.ps1
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $ReplayRoot -Stage Phase0 | Out-Null
$verifyExitCode = $LASTEXITCODE
Assert-True -Name 'Full_Verify_PlanContract_Passes' -Condition ($verifyExitCode -eq 0)

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red

exit $testsFailed
