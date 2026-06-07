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
$config = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'

$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
$configText = Get-Content -LiteralPath $config -Raw -Encoding UTF8

Assert-True -Name 'config_push_failure_non_blocking_default' -Condition ($configText -match '(?m)^knowledge_backup_push_failure_is_blocking:\s*false\s*$')
Assert-True -Name 'config_push_retries_present' -Condition ($configText -match '(?m)^knowledge_backup_push_retries:\s*\d+\s*$')
Assert-True -Name 'config_push_retry_delay_present' -Condition ($configText -match '(?m)^knowledge_backup_push_retry_delay_seconds:\s*\d+\s*$')

Assert-True -Name 'runner_push_pending_marker' -Condition ($runnerText -match 'KNOWLEDGE_BACKUP_PENDING\.json')
Assert-True -Name 'runner_push_status_marker' -Condition ($runnerText -match 'KNOWLEDGE_BACKUP_PUSH_STATUS\.json')
Assert-True -Name 'runner_push_failure_blocking_flag' -Condition ($runnerText -match 'knowledge_backup_push_failure_is_blocking')
Assert-True -Name 'runner_push_retry_loop' -Condition ($runnerText -match 'knowledge_backup_push_retries' -and $runnerText -match 'Start-Sleep')
Assert-True -Name 'runner_sync_does_not_delegate_push_to_sync_script' -Condition ($runnerText -notmatch "\`$args\s*\+=\s*'-Push'")
Assert-True -Name 'runner_pushes_after_successful_sync' -Condition ($runnerText -match 'git -C \$knowledgeRepo push origin \$branch')

Write-Host 'PASS: v375 knowledge backup push resilience'
