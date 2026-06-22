param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw $Name }
        throw "$Name :: $Detail"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

$schemaBranchPattern = '(?s)Invoke-PlanSchemaFailFast\.ps1.*?if \(\$LASTEXITCODE -ne 0\) \{(?<branch>.*?)\n\s*\}\s*\n\s*\$planText = Read-TextIfExists'
$match = [regex]::Match($runnerText, $schemaBranchPattern)
Assert-True 'plan_schema_failfast_branch_found' $match.Success

$branch = $match.Groups['branch'].Value
Assert-True 'plan_schema_failfast_writes_evolution_artifacts' ($branch -match 'Write-PlanEarlyStopEvolutionArtifacts')
Assert-True 'plan_schema_failfast_invokes_early_stop_evolution' ($branch -match 'Invoke-EarlyStopEvolutionAndRefresh')
Assert-True 'plan_schema_failfast_uses_latest_knowledge_refresh_flag' ($branch -match 'UseLatestKnowledgeVersionActual')
Assert-True 'plan_schema_failfast_records_refresh_reason' ($branch -match "plan schema fail-fast evolution")
Assert-True 'plan_schema_failfast_continues_after_successful_evolution' ($branch -match '(?s)Invoke-EarlyStopEvolutionAndRefresh.*?\{\s*\r?\n\s*continue\s*\r?\n\s*\}')
Assert-True 'plan_schema_failfast_writes_blocker_after_failed_evolution' ($branch -match '# Autopilot Blocker')

[ordered]@{
    status = 'PASS'
    version = 'v591'
    assertions = @(
        'plan_schema_failfast_branch_found',
        'plan_schema_failfast_writes_evolution_artifacts',
        'plan_schema_failfast_invokes_early_stop_evolution',
        'plan_schema_failfast_uses_latest_knowledge_refresh_flag',
        'plan_schema_failfast_continues_after_successful_evolution',
        'plan_schema_failfast_writes_blocker_after_failed_evolution'
    )
} | ConvertTo-Json -Depth 5
