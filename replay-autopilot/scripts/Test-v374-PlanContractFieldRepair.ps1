# v374: Plan Contract Field Repair Test
# Tests that the repair prompt includes first_slice and first_red_test fields

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

$runnerScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8

$cases = New-Object System.Collections.Generic.List[string]

# Test 1: Verify PLAN_RESULT.md section includes first_slice
$cases.Add((Assert-True -Name 'plan_result_includes_first_slice' -Condition (
    $runnerScript -match 'first_slice: <S1 identifier, e\.g\., "S1"'
))) | Out-Null

# Test 2: Verify PLAN_RESULT.md section includes first_red_test
$cases.Add((Assert-True -Name 'plan_result_includes_first_red_test' -Condition (
    $runnerScript -match 'first_red_test: <test class\.method, e\.g\., "ExampleFlowServiceTest'
))) | Out-Null

# Test 3: Verify FIRST_SLICE_PROOF_PLAN.md section includes first_slice
$cases.Add((Assert-True -Name 'first_slice_proof_includes_first_slice' -Condition (
    $runnerScript -match 'first_slice: <S1 identifier matching PLAN_RESULT\.md>`'
))) | Out-Null

# Test 4: Verify the fields appear in the correct order (first_slice before highest_weight_open_gate)
$firstSliceIdx = $runnerScript.IndexOf('first_slice: <S1 identifier matching PLAN_RESULT')
$highestWeightIdx = $runnerScript.IndexOf('highest_weight_open_gate: <value>')
$cases.Add((Assert-True -Name 'first_slice_before_highest_weight' -Condition (
    $firstSliceIdx -gt 0 -and $highestWeightIdx -gt 0 -and $firstSliceIdx -lt $highestWeightIdx
))) | Out-Null

# Test 5: Verify the repair prompt template is valid (can be instantiated)
$templateStartIdx = $runnerScript.IndexOf('# Plan Contract Repair Pass')
$templateEndIdx = $runnerScript.IndexOf('Do not create new production files, test files, or worktree changes.')
$cases.Add((Assert-True -Name 'repair_template_complete' -Condition (
    $templateStartIdx -gt 0 -and $templateEndIdx -gt $templateStartIdx
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
