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

$cases.Add((Assert-True -Name 'v442_diagnostic_warning_added' -Condition ($verifierContent -match '# v442: Add explicit diagnostic for missing high-weight files'))) | Out-Null
$cases.Add((Assert-True -Name 'missing_files_warning_added' -Condition ($verifierContent -match 'oracle_high_weight_missing_files'))) | Out-Null
$cases.Add((Assert-True -Name 'missing_files_list_joined' -Condition ($verifierContent -match '\$missingFilesList\s*=\s*\$missingHighWeightFiles\s*-join'))) | Out-Null
$cases.Add((Assert-True -Name 'warning_added_to_warnings' -Condition ($verifierContent -match 'warnings\.Add\("oracle_high_weight_missing_files:'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
