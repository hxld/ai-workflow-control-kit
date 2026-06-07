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

$runLoop = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1')

$cases = New-Object System.Collections.Generic.List[string]
$cases.Add((Assert-True -Name 'evolution_helper_uses_argument_list_parameter' -Condition ($runLoop -match 'function\s+Invoke-EvolutionWithRetry[\s\S]+param\([\s\S]+\[object\[\]\]\$ArgumentList'))) | Out-Null
$cases.Add((Assert-True -Name 'evolution_helper_splats_argument_list' -Condition ($runLoop -match '&\s+powershell\s+@ArgumentList'))) | Out-Null
$cases.Add((Assert-True -Name 'evolution_helper_does_not_declare_args_parameter' -Condition ($runLoop -notmatch '\[object\[\]\]\$Args'))) | Out-Null
$cases.Add((Assert-True -Name 'evolution_calls_use_argument_list' -Condition (($runLoop | Select-String -Pattern 'Invoke-EvolutionWithRetry -ArgumentList' -AllMatches).Matches.Count -ge 5))) | Out-Null
$cases.Add((Assert-True -Name 'evolution_calls_do_not_use_args_switch' -Condition ($runLoop -notmatch 'Invoke-EvolutionWithRetry\s+-Args\b'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
