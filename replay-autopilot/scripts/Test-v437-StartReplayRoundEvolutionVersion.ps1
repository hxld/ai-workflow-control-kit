param()

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$startReplayRound = Join-Path $scriptRoot 'Start-ReplayRound.ps1'
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

$text = Get-Content -LiteralPath $startReplayRound -Raw -Encoding UTF8

$scriptRootIndex = $text.IndexOf('$scriptRoot = Resolve-AbsolutePath')
$versionIndex = $text.IndexOf('# Evolution Version Verification')
Assert-True ($scriptRootIndex -ge 0) 'Start-ReplayRound must initialize scriptRoot'
Assert-True ($versionIndex -ge 0) 'Start-ReplayRound must contain evolution version verification section'
Assert-True ($scriptRootIndex -lt $versionIndex) 'scriptRoot must be initialized before evolution version verification'

Assert-True ($text.Contains("Get-ConfigValueOrDefault -Config `$config -Key 'knowledge_repo'")) 'Start-ReplayRound must read knowledge_repo from config'
Assert-True ($text.Contains("Join-Path `$knowledgeRoot 'CURRENT_VERSION.md'")) 'Start-ReplayRound must prefer knowledge_repo CURRENT_VERSION.md'
Assert-True ($text.Contains('$evolutionFileCandidates += ')) 'Start-ReplayRound must use candidate paths for CURRENT_VERSION.md'
Assert-True ($text.Contains('$env:EVOLUTION_VERSION = $evolutionVersion')) 'Start-ReplayRound must expose EVOLUTION_VERSION'

$validate = & powershell -NoProfile -ExecutionPolicy Bypass -File $runReplayLoop -ConfigPath (Join-Path $repoRoot 'config.yaml') -ValidateOnly -UseLatestKnowledgeVersion -RequireExecutor claude 2>&1
Assert-True ($LASTEXITCODE -eq 0) ('Run-ReplayLoop ValidateOnly failed: {0}' -f ($validate -join "`n"))

Write-Host 'Test-v437-StartReplayRoundEvolutionVersion PASS'
