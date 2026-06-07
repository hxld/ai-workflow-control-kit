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
$controllerText = Get-Content -LiteralPath $controller -Raw -Encoding UTF8

Assert-True -Name 'controller_push_uses_start_process' -Condition ($controllerText -match '\$pushProcess\s*=\s*Start-Process -FilePath git')
Assert-True -Name 'controller_push_redirects_stdout' -Condition ($controllerText -match 'push-\$pushStamp-attempt-\$attempt\.stdout\.log' -and $controllerText -match 'RedirectStandardOutput \$pushStdout')
Assert-True -Name 'controller_push_redirects_stderr' -Condition ($controllerText -match 'push-\$pushStamp-attempt-\$attempt\.stderr\.log' -and $controllerText -match 'RedirectStandardError \$pushStderr')
Assert-True -Name 'controller_push_uses_exit_code_only' -Condition ($controllerText -match '\$pushExitCode\s*=\s*\$pushProcess\.ExitCode')
Assert-True -Name 'controller_push_logs_paths' -Condition ($controllerText -match 'knowledge_backup_push_stdout=\$pushStdout stderr=\$pushStderr exit=\$pushExitCode attempt=\$attempt')
Assert-True -Name 'controller_push_status_records_logs' -Condition ($controllerText -match 'stdout\s*=\s*\$pushStdout' -and $controllerText -match 'stderr\s*=\s*\$pushStderr')
Assert-True -Name 'controller_push_no_2to1_capture' -Condition ($controllerText -notmatch '\$pushOutput\s*=\s*& git -C \$knowledgeRepoForPush push origin \$branch 2>&1')

Write-Host 'PASS: v389 controller push warning tolerance'
