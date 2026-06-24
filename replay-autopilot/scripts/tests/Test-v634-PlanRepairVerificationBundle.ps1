#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for v634 Plan contract repair re-verification.

.DESCRIPTION
Validates that Plan contract repair does not stop at a stale verifier result.
The runner must record repair execution evidence and then re-run the full
post-repair verification bundle: machine contract sync, test-compile evidence,
schema fail-fast, PowerShell contract verification, and Python contract
verification.
#>

$ErrorActionPreference = 'Stop'
$testScriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $testScriptRoot
$runnerPath = Join-Path $repoRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Get-Block {
    param([string]$Text, [string]$Start, [string]$End)
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "FAIL: block start not found: $Start" }
    $endIndex = $Text.IndexOf($End, $startIndex, [System.StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "FAIL: block end not found: $End" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

$assertionCount = 0

$pythonHelper = Get-Block `
    -Text $runnerText `
    -Start 'function Invoke-PlanPythonContractVerification' `
    -End 'function Invoke-PlanVerificationBundle'

Assert-True ($pythonHelper.Contains('plan_contract_verify.py')) 'python helper must invoke plan_contract_verify.py'
Assert-True ($pythonHelper.Contains('--enable_carrier_verify')) 'python helper must keep carrier verification enabled'
Assert-True ($pythonHelper.Contains('--enable_exact_contract_verify')) 'python helper must keep exact contract verification enabled'
$assertionCount += 3

$bundle = Get-Block `
    -Text $runnerText `
    -Start 'function Invoke-PlanVerificationBundle' `
    -End 'function Repair-Phase0ManualOracleWaitText'

Assert-True ($bundle.Contains('Sync-PlanMachineContract.ps1')) 'bundle must sync machine contract before final verifier decision'
Assert-True ($bundle.Contains('Ensure-PlanTestCompileEvidence')) 'bundle must refresh test-compile evidence'
Assert-True ($bundle.Contains('Invoke-PlanSchemaFailFast.ps1')) 'bundle must run schema fail-fast after repair'
Assert-True ($bundle.Contains('Verify-PlanContract.ps1')) 'bundle must rerun PowerShell plan verifier'
Assert-True ($bundle.Contains('Invoke-PlanPythonContractVerification')) 'bundle must rerun Python plan verifier'
Assert-True ($bundle.Contains("verification_status = 'PASS'")) 'bundle must compute a final PASS status only after all gates pass'
$assertionCount += 6

$repairBlock = Get-Block `
    -Text $runnerText `
    -Start 'Plan contract verification failed. Starting contract repair pass.' `
    -End 'if ($planContractVerifyExit -ne 0)'

Assert-True ($repairBlock.Contains('PLAN_CONTRACT_REPAIR_EXECUTION_VERIFY.json')) 'repair block must record executor/proof evidence'
Assert-True ($repairBlock.Contains('PLAN_CONTRACT_REPAIR_VERIFY.json')) 'repair block must write post-repair verification summary'
Assert-True ($repairBlock.Contains('Invoke-PlanVerificationBundle')) 'repair block must use the full verification bundle'
Assert-True ($repairBlock.Contains('Post-repair plan verification status')) 'repair block must report final bundle status'
$assertionCount += 4

Assert-True ($runnerText.Contains('$planResultJsonForPython = Join-Path $replayRoot ''PLAN_RESULT.json''')) 'initial Python verifier must use a dedicated PLAN_RESULT.json variable'
Assert-True (-not ($runnerText -match '\$planResultPath\s*=\s*Join-Path\s+\$replayRoot\s+''PLAN_RESULT\.json''')) 'runner must not overwrite markdown planResultPath with PLAN_RESULT.json'
$assertionCount += 2

Write-Host ''
Write-Host "=== v634 PLAN REPAIR VERIFICATION BUNDLE: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
exit 0
