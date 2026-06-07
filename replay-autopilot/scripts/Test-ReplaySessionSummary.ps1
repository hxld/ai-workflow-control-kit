$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$summaryScript = Join-Path $scriptRoot 'Write-ReplaySessionSummary.ps1'
$tempRoot = Join-Path $env:TEMP ('replay-session-summary-test-{0}' -f ([guid]::NewGuid().ToString('N')))
$summaryPath = Join-Path $tempRoot 'REPLAY_AUTOPILOT_SESSION_SUMMARY.md'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

try {
    $replayRoot = Join-Path $tempRoot 'featureA\claim-codex-replay-v999-cross-20260520-r01'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $replayRoot 'PHASE0_RESULT.md') -Encoding UTF8 -Value @'
# Phase 0

**phase0_status**: PROCEED
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.md') -Encoding UTF8 -Value @'
# Plan

**plan_status**: PROCEED
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'ROUND_RESULT.md') -Encoding UTF8 -Value @'
# Round Result

- **Round Status**: PARTIAL
### Blind Self-Assessed Coverage: 66%
### Verification Capped Coverage: 60%
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md') -Encoding UTF8 -Value @'
# Final Replay Report

**final_replay_status**: PARTIAL
| **Oracle Adjusted Coverage** | 44% |
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'EVOLUTION_RESULT.md') -Encoding UTF8 -Value @'
# Evolution Result

- status: DONE
- knowledge_version: v999
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'STOP_LOSS_DECISION.json') -Encoding UTF8 -Value '{"decision":"CONTINUE_IMPROVED","should_stop":false}'

    $crossRun = Join-Path $tempRoot '_cross-feature\cross-run-20260520-test'
    New-Item -ItemType Directory -Force -Path $crossRun | Out-Null
    Set-Content -LiteralPath (Join-Path $crossRun 'CROSS_FEATURE_REPLAY_LEDGER.md') -Encoding UTF8 -Value '# Cross Feature Ledger'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript -EvidenceRoot $tempRoot -OutputPath $summaryPath -MaxRoots 5 -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Write-ReplaySessionSummary.ps1 exited with $LASTEXITCODE"
    }

    Assert-True (Test-Path -LiteralPath $summaryPath) 'summary file was not written'
    $text = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
    Assert-True ($text.Contains('Replay Autopilot Portable Session Summary')) 'summary title missing'
    Assert-True ($text.Contains('featureA')) 'feature name missing'
    Assert-True ($text.Contains('claim-codex-replay-v999-cross-20260520-r01')) 'replay root missing'
    Assert-True ($text.Contains('44')) 'oracle coverage missing'
    Assert-True ($text.Contains('CONTINUE_IMPROVED')) 'stop-loss decision missing'
    Assert-True ($text.Contains('v999')) 'evolution knowledge version missing'
    Assert-True (-not $text.Contains('.claude\projects')) 'summary must not depend on Claude project memory path'
    Assert-True (-not $text.Contains('019e14c6')) 'summary must not depend on a fixed Codex session id'

    Write-Host 'Test-ReplaySessionSummary passed'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
