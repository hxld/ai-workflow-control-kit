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

Assert-True -Name 'cycle_helper_preserves_error_action_preference' -Condition ($controllerText -match '\$previousErrorActionPreference\s*=\s*\$ErrorActionPreference')
Assert-True -Name 'cycle_helper_allows_native_stderr' -Condition ($controllerText.Contains('$ErrorActionPreference = ''Continue''') -and $controllerText.Contains('& powershell.exe @ArgumentList > $StdoutPath 2> $StderrPath'))
Assert-True -Name 'cycle_helper_restores_error_action_preference' -Condition ($controllerText -match '\$ErrorActionPreference\s*=\s*\$previousErrorActionPreference')

$validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $controller `
    -ConfigPath $config `
    -CycleRounds 3 `
    -MaxCycles 1 `
    -Executor claude `
    -RequireExecutor claude `
    -RunEvolution `
    -UseLatestKnowledgeVersion `
    -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw "Run-UnattendedReplayControl ValidateOnly failed: $LASTEXITCODE" }
$validate = $validateJson | ConvertFrom-Json

Assert-True -Name 'controller_validate_still_valid' -Condition ($validate.status -eq 'VALID')

Write-Host 'PASS: v429 control cycle native stderr handling'
[ordered]@{ status = 'PASS'; assertions = 4 } | ConvertTo-Json -Depth 4
