param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$controllerPath = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$loopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$promptPath = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\skill-evolution.prompt.md'

$controllerText = Get-Content -LiteralPath $controllerPath -Raw -Encoding UTF8
$loopText = Get-Content -LiteralPath $loopPath -Raw -Encoding UTF8
$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

Assert-True ($controllerText -match 'Validate-VerifiableRuleClosure\.ps1') 'Unattended controller must invoke rule closure validator.'
Assert-True ($controllerText -match 'RULE_CLOSURE_REQUIRED') 'Unattended controller must expose RULE_CLOSURE_REQUIRED status.'
Assert-True ($controllerText -match 'verifiable_rule_closure_required') 'Unattended controller must stop with verifiable_rule_closure_required.'
Assert-True ($controllerText -match 'ruleClosureFailed') 'Unattended controller must include rule closure in continuation decision.'
Assert-True ($loopText -match 'VERIFIABLE_RULES = Get-VerifiableRulesPath') 'Replay loop must pass verifiable rules path into evolution prompt.'
Assert-True ($promptText -match 'verifiable rules: \{\{VERIFIABLE_RULES\}\}') 'Evolution prompt must expose verifiable rules input.'
Assert-True ($promptText -match 'closed_machine_gates') 'Evolution prompt must require closed_machine_gates output.'

Write-Host 'Test-v599-UnattendedControlUsesRuleClosureGate PASS'
