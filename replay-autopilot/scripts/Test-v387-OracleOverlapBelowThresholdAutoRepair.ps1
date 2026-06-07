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

# v387: Auto-repair when overlap < 50% but plan_status is PROCEED
# This prevents plans with insufficient oracle coverage from proceeding to implementation
$cases.Add((Assert-True -Name 'v387_has_needsBlockerRepair_check' -Condition ($verifyScript -match 'needsBlockerRepair'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_checks_plan_status_not_BLOCKED' -Condition ($verifyScript -match 'planStatus -ne ''BLOCKED'''))) | Out-Null
$cases.Add((Assert-True -Name 'v387_checks_plan_blocker_not_overlap_below_threshold' -Condition ($verifyScript -match 'planBlocker -notmatch ''oracle_overlap_below_threshold'''))) | Out-Null
$cases.Add((Assert-True -Name 'v387_sets_plan_status_to_BLOCKED' -Condition ($verifyScript -match 'plan_status.*\s+BLOCKED'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_sets_blocker_to_oracle_overlap_below_threshold' -Condition ($verifyScript -match 'blocker.*oracle_overlap_below_threshold'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_updates_oracle_production_file_overlap' -Condition ($verifyScript -match 'oracle_production_file_overlap.*overlapPercent'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_updates_oracle_missing_high_weight_files' -Condition ($verifyScript -match 'oracle_missing_high_weight_files.*missingFilesList'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_inside_overlap_lt_50_block' -Condition (
    ($verifyScript -match 'if \(\$overlapPercent -lt 50\)') -and
    ($verifyScript -match 'needsBlockerRepair') -and
    ($verifyScript -match 'elseif \(\$isStaleBlocker\)')
))) | Out-Null
$cases.Add((Assert-True -Name 'v387_adds_warning_after_repair' -Condition ($verifyScript -match 'plan_result_auto_repaired:oracle_overlap_below_threshold'))) | Out-Null
$cases.Add((Assert-True -Name 'v387_recalculates_combined_plan_after_repair' -Condition ($verifyScript -match 'combinedPlanText\s*=\s*"\$planText`n\$replayPlanText'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
