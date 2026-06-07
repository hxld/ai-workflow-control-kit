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
$controller = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$config = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'

$validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller `
    -ConfigPath $config `
    -CycleRounds 3 `
    -MaxCycles 3 `
    -Executor claude `
    -RequireExecutor claude `
    -RunEvolution `
    -UseLatestKnowledgeVersion `
    -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Run-UnattendedReplayControl ValidateOnly failed: $LASTEXITCODE" }
$validate = $validateJson | ConvertFrom-Json

Assert-True -Name 'validate_exposes_zero_cap_stop' -Condition ([string]$validate.zero_cap_stop_enabled -eq 'True')
Assert-True -Name 'validate_zero_cap_stop_cycle_one' -Condition ([int]$validate.zero_cap_stop_cycles -eq 1)
Assert-True -Name 'validate_zero_cap_next_action_golden_slice' -Condition ($validate.zero_cap_next_action -eq 'golden_slice')

$controllerText = Get-Content -LiteralPath $controller -Raw -Encoding UTF8
$configText = Get-Content -LiteralPath $config -Raw -Encoding UTF8

Assert-True -Name 'config_zero_cap_stop_enabled' -Condition ($configText -match '(?m)^control_zero_cap_stop_enabled:\s*true\s*$')
Assert-True -Name 'config_zero_cap_stop_cycles' -Condition ($configText -match '(?m)^control_zero_cap_stop_cycles:\s*1\s*$')
Assert-True -Name 'config_zero_cap_next_action' -Condition ($configText -match '(?m)^control_zero_cap_next_action:\s*golden_slice\s*$')

Assert-True -Name 'controller_has_max_cycle_guard_for_continue' -Condition ($controllerText -match '\$hasNextCycle\s*=\s*\$cycle\s+-lt\s+\$maxCyclesActual' -and $controllerText -match 'will_continue\s*=\s*\$shouldContinue')
Assert-True -Name 'controller_tracks_zero_cap_streak' -Condition ($controllerText -match '\$zeroCapStreak\+\+' -and $controllerText -match '\$zeroCapStopTriggered')
Assert-True -Name 'controller_parses_percent_coverage' -Condition ($controllerText -match '\^\(-\?\\d\+\)\(\?:\\\.\\d\+\)\?%\?\$')
Assert-True -Name 'controller_writes_zero_cap_stopline' -Condition ($controllerText -match "status\s*=\s*'ZERO_CAP_STOPLINE'" -and $controllerText -match 'stop_reason\s*=\s*\$stopReason')
Assert-True -Name 'controller_invokes_golden_slice_recovery' -Condition ($controllerText -match 'Invoke-GoldenSliceRecoverySafe' -and $controllerText -match 'Write-GoldenDeliverySlice\.ps1')
Assert-True -Name 'controller_records_golden_recovery_marker' -Condition ($controllerText -match 'ZERO_CAP_GOLDEN_RECOVERY\.json')
Assert-True -Name 'controller_final_status_survives_backup_error' -Condition ($controllerText -match 'DONE_WITH_BACKUP_ERROR' -and $controllerText -match 'backup_sync_status')
Assert-True -Name 'controller_sync_does_not_delegate_push_to_sync_script' -Condition ($controllerText -notmatch "\`$args\s*\+=\s*'-Push'")

Write-Host 'PASS: v384 unattended zero-cap stopline'
