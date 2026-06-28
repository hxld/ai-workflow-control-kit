param(
    [switch]$KeepTemp
)

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
$runner = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$launcher = Join-Path $scriptRoot 'Start-UnattendedReplayControl.ps1'
$config = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'

$validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ConfigPath $config `
    -CycleRounds 3 `
    -MaxCycles 2 `
    -Executor codex `
    -RequireExecutor codex `
    -AllowCodexExecutor `
    -RunEvolution `
    -UseLatestKnowledgeVersion `
    -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Run-UnattendedReplayControl ValidateOnly failed: $LASTEXITCODE" }
$validate = $validateJson | ConvertFrom-Json

Assert-True -Name 'runner_validate_valid' -Condition ($validate.status -eq 'VALID')
Assert-True -Name 'runner_cycle_rounds_three' -Condition ([int]$validate.cycle_rounds -eq 3)
Assert-True -Name 'runner_max_cycles_two' -Condition ([int]$validate.max_cycles -eq 2)
Assert-True -Name 'runner_requires_codex' -Condition ($validate.require_executor -eq 'codex')
Assert-True -Name 'runner_authorizes_codex_primary' -Condition ([string]$validate.allow_codex_executor -eq 'True')
Assert-True -Name 'runner_continues_on_evolve' -Condition (@($validate.continue_decision_kinds) -contains 'EVOLVE')
Assert-True -Name 'runner_continues_on_upgrade' -Condition (@($validate.continue_decision_kinds) -contains 'UPGRADE')
Assert-True -Name 'runner_limits_zero_cap_evolution_continue' -Condition ([int]$validate.zero_cap_evolution_continue_limit -eq 1)

$launcherJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $launcher `
    -ConfigPath $config `
    -CycleRounds 3 `
    -MaxCycles 2 `
    -Executor codex `
    -RequireExecutor codex `
    -AllowCodexExecutor `
    -RunEvolution `
    -UseLatestKnowledgeVersion `
    -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Start-UnattendedReplayControl ValidateOnly failed: $LASTEXITCODE" }
$launcherResult = $launcherJson | ConvertFrom-Json

Assert-True -Name 'launcher_validate_valid' -Condition ($launcherResult.status -eq 'VALID')
Assert-True -Name 'launcher_points_to_controller' -Condition ([string]$launcherResult.controller -match 'Run-UnattendedReplayControl\.ps1$')
Assert-True -Name 'launcher_argument_has_cycle_rounds' -Condition (@($launcherResult.argument_list) -contains '-CycleRounds')
Assert-True -Name 'launcher_argument_has_max_cycles' -Condition (@($launcherResult.argument_list) -contains '-MaxCycles')

$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
Assert-True -Name 'runner_invokes_replay_loop' -Condition ($runnerText -match 'Run-ReplayLoop\.ps1')
Assert-True -Name 'runner_uses_control_decision' -Condition ($runnerText -match 'RUN_CONTROL_LATEST\.json')
Assert-True -Name 'runner_continue_kinds_include_evolve' -Condition ($runnerText -match "CONTINUE', 'EVOLVE', 'UPGRADE")
Assert-True -Name 'runner_zero_cap_continue_is_bounded_by_streak' -Condition ($runnerText -match 'zeroCapStreak -le \$zeroCapEvolutionContinueLimit')

Write-Host 'PASS: v372 unattended control loop'
