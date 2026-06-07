$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw $Name }
        throw "$Name :: $Details"
    }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('v232-stoploss-recheck-{0}' -f ([Guid]::NewGuid().ToString('N')))
$history = Join-Path $root 'history'
$replay = Join-Path $history 'claim-codex-replay-v232-autopilot-r01'
New-Item -ItemType Directory -Force -Path $replay | Out-Null

try {
    Write-Text -Path (Join-Path $replay 'AUTOPILOT_SUMMARY.md') -Value @'
# Replay Autopilot Summary

- oracle_adjusted_coverage: 3
- verification_capped_coverage: 3
- final_status: BLOCKED

## Gap Flags

- exact_contract_gap: 4
- side_effect_ledger_gap: 2
'@
    Write-Text -Path (Join-Path $replay 'STOP_OR_CONTINUE_DECISION.md') -Value @'
# Stop Or Continue Decision

- decision: `STOP_AND_EVOLVE`
'@
    Write-Text -Path (Join-Path $replay 'EVOLUTION_RESULT.md') -Value @'
# EVOLUTION_RESULT

- final_status: `TOOLING_CHANGE_ONLY_VALIDATED_AND_PUSHED`
- actual_knowledge_version_after_push: `v232`
'@
    $decision = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ReplayStopLoss.ps1') `
        -ReplayRoot $replay `
        -HistoryRoot $history `
        -Lookback 2 | Out-String
    $json = Get-Content -LiteralPath (Join-Path $replay 'STOP_LOSS_DECISION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'validated evolution result authorizes one continuation' -Condition ([string]$json.decision -eq 'CONTINUE_AFTER_VALIDATED_EVOLUTION') -Details ($json | ConvertTo-Json -Depth 8)
    Assert-True -Name 'validated evolution recheck should not stop' -Condition (-not [bool]$json.should_stop) -Details ($json | ConvertTo-Json -Depth 8)
    Assert-True -Name 'validated evolution flag is present' -Condition ([bool]$json.evolution_result_validated -and [bool]$json.stopped_for_evolution) -Details ($json | ConvertTo-Json -Depth 8)
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS Test-v232-StopLossEvolutionRecheck'
