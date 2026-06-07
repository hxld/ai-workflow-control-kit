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

# v350: Auto-repair mechanism for stale PLAN_RESULT.md
$cases.Add((Assert-True -Name 'v350_defers_plan_status_check' -Condition ($verifyScript -match 'planStatusCheckDeferred'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_has_auto_repair_logic' -Condition ($verifyScript -match 'isStaleBlocker'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_updates_plan_status_on_repair' -Condition ($verifyScript -match 'BLOCKED.*PROCEED'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_updates_blocker_on_repair' -Condition ($verifyScript -match 'oracle_overlap_below_threshold.*none'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_updates_oracle_overlap_on_repair' -Condition ($verifyScript -match 'oracle_production_file_overlap.*overlapPercent'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_updates_high_weight_coverage_on_repair' -Condition ($verifyScript -match 'oracle_high_weight_coverage.*highWeightMatched'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_recalculates_combined_plan_after_repair' -Condition ($verifyScript -match 'combinedPlanText\s*=\s*"\$planText'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_has_deferred_plan_status_check' -Condition ($verifyScript -match 'Deferred plan_status check after oracle overlap'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_only_repair_when_overlap_gte_50' -Condition ($verifyScript -match 'overlapPercent -lt 50'))) | Out-Null
$cases.Add((Assert-True -Name 'v350_detects_stale_blocker' -Condition ($verifyScript -match 'oracle_overlap_below_threshold'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
