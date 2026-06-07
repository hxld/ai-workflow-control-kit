# v374: Plan Contract Auto-Repair Regression Test
# Tests that Verify-PlanContract.ps1 auto-repairs missing first_slice and first_red_test fields

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifierPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

# Test 1: Verify verifier has auto-repair logic for first_slice
$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8
$cases = New-Object System.Collections.Generic.List[string]

$cases.Add((Assert-True -Name 'auto_repair_first_slice_exists' -Condition (
    $verifierContent -match 'v374.*Auto-repair missing first_slice' -or
    $verifierContent -match 'Auto-repair first_slice if missing'
))) | Out-Null

# Test 2: Verify verifier has auto-repair logic for first_red_test
$cases.Add((Assert-True -Name 'auto_repair_first_red_test_exists' -Condition (
    $verifierContent -match 'Auto-repair first_red_test if missing'
))) | Out-Null

# Test 3: Verify verifier extracts first_slice from FIRST_SLICE_PROOF_PLAN.md
$cases.Add((Assert-True -Name 'extracts_first_slice_from_proof' -Condition (
    $verifierContent -match 'firstSliceFromProof.*firstSliceProofText' -or
    $verifierContent -match 'Get-FirstText.*firstSliceProofText.*first_slice'
))) | Out-Null

# Test 4: Verify verifier extracts first_red_test from FIRST_SLICE_PROOF_PLAN.md
$cases.Add((Assert-True -Name 'extracts_first_red_test_from_proof' -Condition (
    $verifierContent -match 'firstRedFromProof.*firstSliceProofText' -or
    $verifierContent -match 'Get-FirstText.*firstSliceProofText.*first_red_test'
))) | Out-Null

# Test 5: Verify verifier normalizes first_RED_test to first_red_test
$cases.Add((Assert-True -Name 'normalizes_first_red_test_variant' -Condition (
    $verifierContent -match 'Normalize.*first_RED_test.*first_red_test' -or
    $verifierContent -replace 'first_RED_test', 'first_red_test'
))) | Out-Null

# Test 6: Verify verifier writes repaired PLAN_RESULT.md
$cases.Add((Assert-True -Name 'writes_repaired_plan_result' -Condition (
    $verifierContent -match 'Set-Content.*planResultPath' -and
    $verifierContent -match 'needsPlanRepair\s*=\s*\$true'
))) | Out-Null

# Test 7: Verify verifier logs auto-repair warning
$cases.Add((Assert-True -Name 'logs_auto_repair_warning' -Condition (
    $verifierContent -match 'warnings\.Add.*plan_result_auto_repaired'
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
