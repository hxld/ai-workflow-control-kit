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
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8

Assert-True -Name 'runner_has_verify_json_helper' -Condition ($runnerText -match 'function Test-EvolutionVerifyPass')
Assert-True -Name 'helper_reads_verify_json' -Condition ($runnerText -match "EVOLUTION_RESULT_VERIFY\.json" -and $runnerText -match "ConvertFrom-Json")
Assert-True -Name 'helper_requires_pass_and_no_issues' -Condition ($runnerText -match "\[string\]\`$verify\.status -eq 'PASS'" -and $runnerText -match "\`$issues\.Count -eq 0")
Assert-True -Name 'validation_function_uses_verify_helper_before_return' -Condition ($runnerText -match "\`$LASTEXITCODE -eq 0 -and \(Test-EvolutionVerifyPass -ReplayRoot \`$ReplayRoot\)")
Assert-True -Name 'validation_function_blocks_failed_verify_after_repair' -Condition ($runnerText -match "\`$LASTEXITCODE -ne 0 -or -not \(Test-EvolutionVerifyPass -ReplayRoot \`$ReplayRoot\)")
Assert-True -Name 'inline_validation_uses_verify_helper' -Condition ($runnerText -match "\`$evolutionValidationPass = \(\`$LASTEXITCODE -eq 0 -and \(Test-EvolutionVerifyPass -ReplayRoot \`$replayRoot\)\)")
Assert-True -Name 'inline_validation_blocks_failed_verify_after_repair' -Condition ($runnerText -match "\`$LASTEXITCODE -ne 0 -or -not \(Test-EvolutionVerifyPass -ReplayRoot \`$replayRoot\)")
Assert-True -Name 'inline_validation_no_longer_trusts_exitcode_only' -Condition ($runnerText -notmatch "if \(\`$LASTEXITCODE -ne 0\) \{\s*\`$evolutionVerifyPath = Join-Path \`$replayRoot 'EVOLUTION_RESULT_VERIFY\.json'")

Write-Host 'PASS: v390 evolution validation fail-closed'
