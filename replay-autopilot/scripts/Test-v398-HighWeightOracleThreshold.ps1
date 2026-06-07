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
$cases.Add((Assert-True -Name 'high_weight_threshold_check_exists' -Condition ($verifierContent -match 'oracle_high_weight_overlap_below_threshold'))) | Out-Null
$cases.Add((Assert-True -Name 'high_weight_threshold_is_70_percent' -Condition ($verifierContent -match 'highWeightOverlapPercent.*lt.*highWeightThreshold' -and $verifierContent -match '\$highWeightThreshold\s*=\s*70'))) | Out-Null
$cases.Add((Assert-True -Name 'high_weight_repair_ledger_required' -Condition ($verifierContent -match 'oracle_high_weight_repair_ledger_missing'))) | Out-Null
$cases.Add((Assert-True -Name 'v398_comment_present' -Condition ($verifierContent -match '# v398:'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
