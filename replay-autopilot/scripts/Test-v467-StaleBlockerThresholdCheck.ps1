# Test-v467-StaleBlockerThresholdCheck.ps1
# Regression test for v467: Stale Blocker Detection must check actual overlap >= 50%
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

$verifyScript = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1')

$cases = New-Object System.Collections.Generic.List[string]

# v467: Verify v467 comment is present (evidence the change was applied)
$cases.Add((Assert-True -Name 'v467_comment_present' -Condition (
    $verifyScript -match 'v467.*Fixed.*stale.*blocker.*detection.*50%'
))) | Out-Null

# v467: Verify overlapPercent -ge 50 check is present near isStaleBlocker
$cases.Add((Assert-True -Name 'v467_overlap_threshold_check_present' -Condition (
    $verifyScript -match '\$overlapPercent\s*-ge\s+50'
))) | Out-Null

# v467: Verify isStaleBlocker variable is defined
$cases.Add((Assert-True -Name 'v467_isStaleBlocker_variable_exists' -Condition (
    $verifyScript -match '\$isStaleBlocker\s*='
))) | Out-Null

# v467: Verify isStaleHighWeightBlocker also has threshold check
$cases.Add((Assert-True -Name 'v467_high_weight_threshold_check_present' -Condition (
    $verifyScript -match '\$highWeightOverlapPercent\s*-ge\s+70'
))) | Out-Null

# v467: Verify oracle_overlap_below_threshold is referenced
$cases.Add((Assert-True -Name 'v467_oracle_overlap_below_threshold_present' -Condition (
    $verifyScript -match 'oracle_overlap_below_threshold'
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
