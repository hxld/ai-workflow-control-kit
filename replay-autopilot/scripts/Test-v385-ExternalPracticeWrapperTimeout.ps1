param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$search = Join-Path $scriptRoot 'Start-ExternalPracticeSearch.ps1'
$config = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'

$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
$searchText = Get-Content -LiteralPath $search -Raw -Encoding UTF8
$configText = Get-Content -LiteralPath $config -Raw -Encoding UTF8

Assert-True -Name 'config_external_practice_wrapper_timeout_present' -Condition ($configText -match '(?m)^external_practice_wrapper_timeout_minutes:\s*\d+\s*$')
Assert-True -Name 'runner_uses_wrapper_timeout_config' -Condition ($runnerText -match 'external_practice_wrapper_timeout_minutes')
Assert-True -Name 'runner_runs_external_search_with_start_process' -Condition ($runnerText -match 'Start-Process -FilePath powershell\.exe' -and $runnerText -match 'external-practice-wrapper')
Assert-True -Name 'runner_waits_for_external_search_with_timeout' -Condition ($runnerText -match '\.WaitForExit\(\$timeoutMs\)')
Assert-True -Name 'runner_kills_timed_out_external_search' -Condition ($runnerText -match 'Stop-Process -Id \$process\.Id -Force')
Assert-True -Name 'runner_returns_existing_decision_after_timeout' -Condition ($runnerText -match 'if \(Test-Path -LiteralPath \$decisionPath\)' -and $runnerText -match 'return \$decisionPath')
Assert-True -Name 'external_search_exits_explicitly' -Condition ($searchText -match '(?m)^exit 0\s*$')

Write-Host 'PASS: v385 external practice wrapper timeout'
