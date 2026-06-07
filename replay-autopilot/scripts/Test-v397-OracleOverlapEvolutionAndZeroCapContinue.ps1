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

$scriptRoot = $PSScriptRoot
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$controlLoop = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'

$runnerText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8
$controlText = Get-Content -LiteralPath $controlLoop -Raw -Encoding UTF8

Assert-True ($runnerText -match 'Oracle overlap gate BLOCKED') 'Runner should keep the oracle-overlap hard gate.'
Assert-True ($runnerText -match '\$runEvolutionActual') 'Runner should branch on RunEvolution for early-stop evolution.'
Assert-True ($runnerText -match 'Invoke-EvolutionWithRetry -ArgumentList \$evolutionArgs') 'Oracle-overlap early stop should execute evolution with retry.'
Assert-True ($runnerText -match 'Invoke-EvolutionResultValidationOrRepair') 'Oracle-overlap evolution should be validated or repaired.'
Assert-True ($runnerText -match 'Knowledge version refreshed for next round after oracle-overlap evolution') 'Runner should refresh knowledge version after oracle-overlap evolution.'

Assert-True ($controlText -match '\$versionAdvancedThisCycle') 'Control loop should detect version advancement per cycle.'
Assert-True ($controlText -match '\$zeroCapStopTriggeredRaw') 'Control loop should preserve raw zero-cap stop signal.'
Assert-True ($controlText -match '\$zeroCapEvolutionContinue') 'Control loop should support zero-cap continue after evolution.'
Assert-True ($controlText -match '\$zeroCapStopTriggered = \$zeroCapStopTriggeredRaw -and -not \$zeroCapEvolutionContinue') 'Version advancement should suppress zero-cap stop.'
Assert-True ($controlText -match 'zero_cap_recovery=.*zero_cap_stop_suppressed=true') 'Control loop should log suppressed zero-cap recovery.'
Assert-True ($controlText -match 'zero_cap_stop_triggered_raw') 'Control status should expose raw zero-cap stop.'
Assert-True ($controlText -match 'zero_cap_evolution_continue') 'Control status should expose evolution-continue state.'

Write-Host 'PASS: v397 oracle-overlap evolution and zero-cap continue tests passed'
[ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4
