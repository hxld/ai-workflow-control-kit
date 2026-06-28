#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') {
            throw "Unsupported config line: $line"
        }
        $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
    return $result
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$repoRoot = Split-Path -Parent $autopilotRoot
$configPath = Join-Path $autopilotRoot 'config.yaml'
$goalPath = Join-Path $repoRoot 'replay-autopilot-goal.md'

$config = Read-SimpleYaml -Path $configPath

Assert-True ([string]$config['feature_name'] -eq 'replay-autopilot') 'default feature_name should target replay-autopilot'
Assert-True ([string]$config['requirement_source'] -eq 'replay-autopilot-goal.md') 'default requirement_source should target replay-autopilot goal'
Assert-True ([string]$config['replay_root_base'] -match 'replay-evidence\\replay-autopilot\\replay-v000') 'default replay evidence root should be replay-autopilot scoped'
Assert-True (Test-Path -LiteralPath $goalPath -PathType Leaf) 'default replay-autopilot goal document should exist'

$goalText = Get-Content -LiteralPath $goalPath -Raw -Encoding UTF8
$sourceDocs = @(Get-ChildItem -LiteralPath $repoRoot -Filter 'replay-autopilot-*.md' |
    Where-Object { $_.Name -ne 'replay-autopilot-goal.md' } |
    Sort-Object Name)
Assert-True ($sourceDocs.Count -ge 2) 'repo should contain replay-autopilot source planning documents'
foreach ($doc in $sourceDocs) {
    Assert-True ($goalText.Contains($doc.Name)) "goal document should reference source planning document $($doc.Name)"
}
Assert-True ($goalText -match 'real coverage can reach 90%') 'goal document should state the real coverage target'
Assert-True ($goalText -match 'Run an evidence review' -and $goalText -match 'Run a code review') 'goal document should preserve the two-review workflow'

Write-Host ''
Write-Host 'v713 Default Replay Autopilot Goal Config: PASS'
exit 0
