param([switch]$ValidateOnly)

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

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$controllerText = Get-Content -LiteralPath $controller -Raw -Encoding UTF8

Assert-True -Name 'cycle_direct_helper_exists' -Condition ($controllerText -match 'function\s+Invoke-CycleReplayLoop')
Assert-True -Name 'cycle_helper_uses_synchronous_invocation' -Condition ($controllerText -match '&\s+powershell\.exe\s+@ArgumentList\s+>\s+\$StdoutPath\s+2>\s+\$StderrPath')
Assert-True -Name 'cycle_uses_direct_helper' -Condition ($controllerText -match '\$exitCode\s*=\s*Invoke-CycleReplayLoop\s+-ArgumentList\s+\$loopArgs')
Assert-True -Name 'cycle_no_longer_uses_start_process_wait_for_replay_loop' -Condition ($controllerText -notmatch 'Start-Process\s+-FilePath\s+powershell\.exe\s+-ArgumentList\s+\$loopArgs[\s\S]+?-Wait')

$validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller `
    -ConfigPath $config `
    -CycleRounds 3 `
    -MaxCycles 2 `
    -Executor claude `
    -RequireExecutor claude `
    -RunEvolution `
    -UseLatestKnowledgeVersion `
    -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Run-UnattendedReplayControl ValidateOnly failed: $LASTEXITCODE" }
$validate = $validateJson | ConvertFrom-Json

Assert-True -Name 'controller_validate_still_valid' -Condition ($validate.status -eq 'VALID')

Write-Host 'PASS: v428 control cycle direct invocation'
[ordered]@{ status = 'PASS'; assertions = 5 } | ConvertTo-Json -Depth 4
