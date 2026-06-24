#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for early-stop evolution invocation.

.DESCRIPTION
Validates that replay early-stop branches do not merely write EVOLUTION_PROMPT.md.
When RunEvolution is enabled, the runner must invoke the shared evolution helper,
validate EVOLUTION_RESULT.md, and refresh the knowledge version before another
unattended cycle can continue.
#>

$ErrorActionPreference = 'Stop'
$testScriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $testScriptRoot
$runnerPath = Join-Path $repoRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Get-Block {
    param([string]$Text, [string]$Start, [string]$End)
    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) { throw "FAIL: block start not found: $Start" }
    $endIndex = $Text.IndexOf($End, $startIndex, [System.StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "FAIL: block end not found after ${Start}: $End" }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

function Assert-EarlyStopHelper {
    param(
        [string]$Block,
        [string]$Name,
        [string]$RefreshReason
    )

    Assert-True ($Block.Contains('Write-PlanEarlyStopEvolutionArtifacts')) "$Name must generate early-stop evolution artifacts"
    Assert-True ($Block.Contains('Invoke-EarlyStopEvolutionAndRefresh')) "$Name must invoke the shared early-stop evolution helper"
    Assert-True ($Block.Contains("-RefreshReason '$RefreshReason'")) "$Name must use refresh reason '$RefreshReason'"
    Assert-True ($Block.Contains('-UseLatestKnowledgeVersionActual ([bool]$UseLatestKnowledgeVersion)')) "$Name must refresh latest knowledge version after validated evolution"
    Assert-True ($Block.Contains('continue')) "$Name must continue the replay loop only after helper success"
}

$assertionCount = 0

$helper = Get-Block `
    -Text $runnerText `
    -Start 'function Invoke-EarlyStopEvolutionAndRefresh' `
    -End '$executorActual ='
Assert-True ($helper.Contains('Invoke-EvolutionResultValidationOrRepair')) 'shared helper must validate or repair EVOLUTION_RESULT.md'
Assert-True ($helper.Contains('EVOLUTION_RESULT.md')) 'shared helper must require a real evolution result'
Assert-True ($helper.Contains('Knowledge version refreshed for next round')) 'shared helper must refresh knowledge version for subsequent rounds'
$assertionCount += 3

$planArtifactBlock = Get-Block `
    -Text $runnerText `
    -Start 'Plan artifacts still missing after repair pass' `
    -End '$planMachineContractPath = Join-Path'
Assert-EarlyStopHelper -Block $planArtifactBlock -Name 'plan artifact repair failure' -RefreshReason 'plan artifact repair-failure evolution'
$assertionCount += 5

$oracleAnalysisBlock = Get-Block `
    -Text $runnerText `
    -Start 'if ($null -ne $oracleGateBlockReason)' `
    -End 'if ($oracleAnalysisValid)'
Assert-EarlyStopHelper -Block $oracleAnalysisBlock -Name 'oracle analysis gate failure' -RefreshReason 'oracle analysis gate evolution'
$assertionCount += 5

$prePhase1CleanBlock = Get-Block `
    -Text $runnerText `
    -Start 'if ($prePhase1DirtyEntries.Count -gt 0 -and (-not $prePhase1DirtyReuseDecision' `
    -End 'if ($prePhase1DirtyEntries.Count -gt 0) {'
Assert-EarlyStopHelper -Block $prePhase1CleanBlock -Name 'pre-Phase1 clean gate failure' -RefreshReason 'pre-phase1 worktree clean evolution'
$assertionCount += 5

$preflightBlock = Get-Block `
    -Text $runnerText `
    -Start 'if ($preflightExitCode -ne 0)' `
    -End 'Write-Host "Preflight test compilation gate passed."'
Assert-EarlyStopHelper -Block $preflightBlock -Name 'preflight test-compilation failure' -RefreshReason 'preflight test-compilation evolution'
$assertionCount += 5

$phase1InitBlock = Get-Block `
    -Text $runnerText `
    -Start 'if ($phase1ExitCode -ne 0)' `
    -End 'if (-not (Test-Path -LiteralPath $roundResultPath)) {'
Assert-EarlyStopHelper -Block $phase1InitBlock -Name 'Phase1 init failure' -RefreshReason 'phase1 init-failure evolution'
Assert-True ($phase1InitBlock.Contains('if (@(86, 87) -notcontains $phase1ExitCode)')) 'Phase1 init branch must not run tooling evolution for executor resource/auth failures'
$assertionCount += 6

$phase1MissingResultBlock = Get-Block `
    -Text $runnerText `
    -Start '$reason = "Phase 1 completed without ROUND_RESULT.md. Inspect logs under $logs."' `
    -End '$phase1Text = Read-TextIfExists $roundResultPath'
Assert-EarlyStopHelper -Block $phase1MissingResultBlock -Name 'Phase1 missing ROUND_RESULT failure' -RefreshReason 'phase1 missing-round-result evolution'
$assertionCount += 5

Write-Host ''
Write-Host "=== v635 EARLY-STOP EVOLUTION INVOCATION: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
exit 0
