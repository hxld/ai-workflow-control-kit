param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8

Assert-True ($runnerText -match 'function\s+Resolve-EvolutionWorkDir') 'Runner should define an explicit evolution WorkDir resolver'
Assert-True ($runnerText -match 'evolution_workdir_must_not_equal_project_root') 'Runner should fail closed if evolution WorkDir equals project root'
Assert-True ($runnerText -match '\$evolutionWorkDir\s*=\s*Resolve-EvolutionWorkDir\s+-ScriptRoot\s+\$scriptRoot\s+-ProjectRoot\s+\$projectRoot') 'Main loop should resolve evolution WorkDir from autopilot root'
Assert-True ($runnerText -match '\$evolutionWorkDir\s*=\s*Resolve-EvolutionWorkDir\s+-ScriptRoot\s+\$autopilotRootForPrompt\s+-ProjectRoot\s+\$ProjectRoot') 'Evolution repair helper should resolve evolution WorkDir from autopilot root'

$forbiddenWorkDirCount = ([regex]::Matches($runnerText, '''-WorkDir'',\s*\$projectRoot')).Count
Assert-True ($forbiddenWorkDirCount -eq 0) 'Evolution agent calls must never use projectRoot as WorkDir'

$evolutionWorkDirCount = ([regex]::Matches($runnerText, '''-WorkDir'',\s*\$evolutionWorkDir')).Count
Assert-True ($evolutionWorkDirCount -ge 7) 'All evolution and evolution-repair calls should use evolutionWorkDir'

$worktreeWorkDirCount = ([regex]::Matches($runnerText, '''-WorkDir'',\s*\$worktree')).Count
Assert-True ($worktreeWorkDirCount -ge 1) 'Replay implementation calls should still run inside isolated worktrees'

Write-Host 'PASS: v421 evolution WorkDir isolation tests passed'
[ordered]@{ status = 'PASS'; assertions = 7 } | ConvertTo-Json -Depth 4
