# v448: HIGH-Weight Out-of-Scope Exemption
# Fixes verifier bug where out-of-scope HIGH-weight files are not properly excluded from coverage calculation

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

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifierPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

$cases = New-Object System.Collections.Generic.List[string]

# v448: Add exemption for high-weight coverage when out-of-scope files are documented
$cases.Add((Assert-True -Name 'v448_highweight_out_of_scope_exemption_added' -Condition (
    $verifierContent -match '# v448.*HIGH-weight.*out-of-scope.*exemption'
))) | Out-Null

# Check that the exemption condition uses highWeightOverlapPercent and hasHonestOutOfScopeExplanation
$cases.Add((Assert-True -Name 'v448_uses_highweight_percent_check' -Condition (
    $verifierContent -match '\$hasHonestOutOfScopeExplanation.*-and.*\$highWeightOverlapPercent.*-ge\s*40'
))) | Out-Null

# Check that blocker repair logic handles high-weight stale blockers with exemption
$cases.Add((Assert-True -Name 'v448_highweight_blocker_repair_added' -Condition (
    $verifierContent -match '\$highWeightOverlapPercent.*-ge\s*70.*-or.*\$hasHonestOutOfScopeExplanation'
))) | Out-Null

# Check that oracle_high_weight_total output uses filtered count
$cases.Add((Assert-True -Name 'v448_oracle_high_weight_total_filtered' -Condition (
    $verifierContent -match 'oracle_high_weight_total.*\$filteredHighWeightFiles\.Count'
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
