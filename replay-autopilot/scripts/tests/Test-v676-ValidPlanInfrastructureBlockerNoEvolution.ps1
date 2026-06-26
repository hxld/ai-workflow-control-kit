#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Message - $Detail"
    }
    Write-Host "  PASS: $Message"
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$runLoopPath = Join-Path $scriptsRoot 'Run-ReplayLoop.ps1'
$proposalPath = Join-Path $scriptsRoot 'New-EvolutionProposal.ps1'

$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
$proposalText = Get-Content -LiteralPath $proposalPath -Raw -Encoding UTF8

Assert-True ($runLoopText -match 'function\s+Test-ValidPlanInfrastructureBlocker') 'Run-ReplayLoop exposes valid plan infrastructure blocker classifier'
Assert-True ($runLoopText -match '\$proposalShouldEvolve\s*=\s*if\s*\(\$validPlanInfrastructureBlocker\)\s*\{\s*''False''\s*\}') 'Plan early-stop proposal can emit should_evolve False'
Assert-True ($runLoopText -match 'if\s*\(\$runEvolutionActual\s+-and\s+-not\s+\$validPlanInfrastructureBlocker\)') 'Plan early-stop evolution invocation is guarded by blocker classifier'
Assert-True ($runLoopText -match 'NO_VERSION_ADVANCE_REASON\.md / EVOLUTION_RESULT\.md') 'No-version completion guidance is emitted for valid infrastructure blockers'
Assert-True ($proposalText -match 'function\s+Test-ValidPlanInfrastructureBlocker') 'New-EvolutionProposal exposes same classifier'
Assert-True ($proposalText -match '\$detected\s*=\s*@\(\)') 'New-EvolutionProposal suppresses stale vocabulary gaps for valid infrastructure blockers'
Assert-True ($proposalText -match 'valid terminal test-infrastructure blocker') 'New-EvolutionProposal records valid blocker reason'

Write-Host 'v676 Valid Plan Infrastructure Blocker No Evolution: PASS'
