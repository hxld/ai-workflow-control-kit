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

Assert-True -Name 'controller_backup_sync_uses_start_process' -Condition ($controllerText -match '\$syncProcess\s*=\s*Start-Process -FilePath powershell\.exe')
Assert-True -Name 'controller_backup_sync_redirects_stdout' -Condition ($controllerText -match 'sync-\$syncStamp\.stdout\.log' -and $controllerText -match 'RedirectStandardOutput \$syncStdout')
Assert-True -Name 'controller_backup_sync_redirects_stderr' -Condition ($controllerText -match 'sync-\$syncStamp\.stderr\.log' -and $controllerText -match 'RedirectStandardError \$syncStderr')
Assert-True -Name 'controller_backup_sync_uses_exit_code_only' -Condition ($controllerText -match '\$syncExitCode\s*=\s*\$syncProcess\.ExitCode')
Assert-True -Name 'controller_backup_sync_logs_paths' -Condition ($controllerText -match 'knowledge_backup_sync_stdout=\$syncStdout stderr=\$syncStderr exit=\$syncExitCode')
Assert-True -Name 'controller_backup_sync_no_2to1_capture' -Condition ($controllerText -notmatch '\$syncOutput\s*=\s*& powershell @args 2>&1')

Write-Host 'PASS: v386 controller backup sync warning tolerance'
