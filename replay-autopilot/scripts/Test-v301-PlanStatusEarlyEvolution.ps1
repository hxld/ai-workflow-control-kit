param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8

Assert-True ($runnerText.Contains('Plan stage stopped replay early: $planStatus')) `
    'Runner must have a non-PROCEED Plan status early-stop branch'
Assert-True ($runnerText.Contains('Knowledge version refreshed for next round after plan status early-stop evolution')) `
    'Plan status early-stop branch must refresh knowledge after evolution'

$planStatusBranchPattern = '(?s)if \(\$planStatus -ne ''PROCEED''\).*?Write-Host "Plan stage stopped replay early: \$planStatus".*?if \(\$runEvolutionActual\).*?& powershell @evolutionArgs.*?continue.*?break'
Assert-True ([regex]::IsMatch($runnerText, $planStatusBranchPattern)) `
    'Plan status non-PROCEED branch must run evolution and continue before final break'

[ordered]@{
    status = 'PASS'
    assertions = 3
    cases = @(
        'plan_status_early_stop_branch_exists',
        'plan_status_early_stop_refreshes_knowledge',
        'plan_status_branch_continues_after_successful_evolution'
    )
} | ConvertTo-Json -Depth 5
