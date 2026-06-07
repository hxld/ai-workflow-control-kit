$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autopilotRoot = Split-Path -Parent $scriptRoot
$tempRoot = Join-Path $env:TEMP ('replay-v252-tooling-test-{0}' -f ([guid]::NewGuid().ToString('N')))

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
    $replayRoot = Join-Path $tempRoot 'claim-codex-replay-v252-tooling-r01'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Set-Content -LiteralPath (Join-Path $replayRoot 'PHASE0_RESULT.md') -Encoding UTF8 -Value @'
# Phase 0

- phase0_status: PROCEED
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'ROUND_RESULT.md') -Encoding UTF8 -Value @'
# Round Result

- oracle_used: false
- blind_self_assessed_coverage: 74%
- verification_capped_coverage: 68%
- final_status: PARTIAL
'@
    Set-Content -LiteralPath (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md') -Encoding UTF8 -Value @'
# Final Replay Report

| **Oracle Adjusted Coverage** | 75% |

Formula examples that must not win:

Oracle Adjusted Coverage = 100% x 80% + 0% x 20%
Final Oracle Adjusted Coverage = min(60%, 80%) = **60%**
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $replayRoot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Parse-ReplayReport.ps1 exited with $LASTEXITCODE"
    }
    $summaryText = Get-Content -LiteralPath (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
    Assert-True ($summaryText -match '(?m)^- oracle_adjusted_coverage: 75\s*$') 'oracle adjusted coverage parser should prefer the anchored table value 75, not formula numbers'

    $verifyScriptText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
    Assert-True ($verifyScriptText.Contains('$proofKindTablePattern')) 'Verify-PlanContract must accept proof_kind table rows'
    Assert-True ($verifyScriptText.Contains('production_service_method')) 'Verify-PlanContract must accept production_service_method carrier kind'

    $planPromptText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8
    Assert-True ($planPromptText.Contains('production_service_method')) 'phase plan prompt must list verifier-accepted real carrier kinds'
    Assert-True ($planPromptText.Contains('coverage_cap_if_missing:')) 'phase plan prompt must keep exact first-slice schema fields'

    $invokeText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1') -Raw -Encoding UTF8
    Assert-True (($invokeText -match '\$stderrText') -and ($invokeText -match 'Set-Content -LiteralPath \$StderrLogInner')) 'Invoke-AgentPrompt must persist executor stderr for failures'

    $sliceLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($sliceLoopText.Contains('$retryExitCode = $LASTEXITCODE')) 'Run-SliceLoop must preserve retry executor exit code'
    Assert-True ($sliceLoopText.Contains('missing_slice_result_after_retry | exit_code={3}')) 'Run-SliceLoop must report actual retry exit code in missing result blocker'

    $runLoopText = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runLoopText.Contains("-StopStage 'Phase1'")) 'Run-ReplayLoop must generate evolution-ready artifacts for Phase1 executor failures'
    Assert-True ($runLoopText.Contains('Phase 1 executor failed before producing a complete ROUND_RESULT.md')) 'Run-ReplayLoop must classify Phase1 executor failure as an early stop reason'

    Write-Host 'Test-v252-ExecutorFailureAndCoverageParsing passed'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
