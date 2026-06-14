<#
.SYNOPSIS
    Regression test for v524 executor credit-required fail-closed handling.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$invokePath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
$controlPath = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$failureAuditPath = Join-Path $scriptRoot 'Write-FailureAuditPack.ps1'
$sliceLoopPath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'

Write-Host "=== v524 Executor Credit Required Fail-Closed Test ===" -ForegroundColor Cyan

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("executor-credit-v524-" + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $tempRoot 'bin'
$work = Join-Path $tempRoot 'work'
$logs = Join-Path $tempRoot 'logs'
$replayRoot = Join-Path $tempRoot 'replay-root'
$controlRoot = Join-Path $tempRoot '_control'
New-Item -ItemType Directory -Force -Path $bin, $work, $logs, $replayRoot, $controlRoot | Out-Null

try {
    $fakeClaude = Join-Path $bin 'claude.cmd'
    @'
@echo off
echo API Error: 402 Credit required. To prevent abuse, a positive balance is required for this model.
exit /b 1
'@ | Set-Content -LiteralPath $fakeClaude -Encoding ASCII

    $prompt = Join-Path $tempRoot 'PROMPT.md'
    $completion = Join-Path $tempRoot 'SLICE_RESULT_01.json'
    'Write the required completion file.' | Set-Content -LiteralPath $prompt -Encoding UTF8

    $oldPath = $env:PATH
    $env:PATH = "$bin;$oldPath"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $invokePath `
            -PromptPath $prompt `
            -WorkDir $work `
            -LogDir $logs `
            -Executor claude `
            -Model claude-sonnet-4-6 `
            -CompletionPath $completion `
            -CompletionQuietSeconds 15 `
            -TimeoutMinutes 1 `
            -Name phase1-slice01 *> (Join-Path $tempRoot 'invoke.out')
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($exit -eq 86) "expected resource exit 86 for Claude credit blocker, got $exit"
    $meta = Get-Content -LiteralPath (Join-Path $logs 'phase1-slice01.exec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($meta.failure_category -eq 'executor_credit_required') "expected executor_credit_required, got $($meta.failure_category)"
    Assert-True (-not (Test-Path -LiteralPath $completion)) 'credit blocker must not fabricate completion evidence'

    @'
# Autopilot Blocker

- verification_capped_coverage: 0
- blocker: Phase 2 completed without FINAL_REPLAY_REPORT.md.
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') -Encoding UTF8
    @'
# Round Result

- final_status: BLOCKED
- verification_capped_coverage: 0
- executor_failure_category: executor
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'ROUND_RESULT.md') -Encoding UTF8
    $nestedLogDir = Join-Path $replayRoot 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $nestedLogDir | Out-Null
    $nestedStdout = Join-Path $nestedLogDir 'phase1-slice01.stdout.log'
    'API Error: 402 Credit required. To prevent abuse, a positive balance is required for this model.' |
        Set-Content -LiteralPath $nestedStdout -Encoding UTF8
    ([ordered]@{
        executor = 'claude'
        stdout_log = $nestedStdout
        stderr_log = Join-Path $nestedLogDir 'phase1-slice01.stderr.log'
        exit_code = 1
        executor_exit_code = 1
        failure_category = 'executor'
    } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $nestedLogDir 'phase1-slice01.exec.json') -Encoding UTF8
    ([ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $replayRoot 'EXECUTOR_AUDIT.json') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $controlPath `
        -EvidenceRoot $tempRoot `
        -ReplayRoot $replayRoot `
        -OutputRoot $controlRoot `
        -Quiet
    Assert-True ($LASTEXITCODE -eq 0) "control summary failed with exit $LASTEXITCODE"

    $summary = Get-Content -LiteralPath (Join-Path $replayRoot 'RUN_CONTROL_SUMMARY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($summary.latest.fingerprints) -contains 'executor_credit_required') 'control summary must fingerprint executor_credit_required'
    Assert-True ($summary.control_decision.decision_kind -eq 'STOPLINE') "expected STOPLINE, got $($summary.control_decision.decision_kind)"
    Assert-True (($summary.control_decision.recommended_next_step -join ' ') -match 'credit') 'recommended next step must mention credit restoration'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $failureAuditPath `
        -EvidenceRoot $tempRoot `
        -ReplayRoot $replayRoot `
        -ControlSummaryPath (Join-Path $controlRoot 'RUN_CONTROL_LATEST.json') `
        -BlockerRegistryPath (Join-Path $controlRoot 'BLOCKER_REGISTRY.json') `
        -Quiet
    Assert-True ($LASTEXITCODE -eq 0) "failure audit failed with exit $LASTEXITCODE"

    $audit = Get-Content -LiteralPath (Join-Path $replayRoot 'FAILURE_AUDIT_PACK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($audit.must_fix_before_next_replay) -contains 'executor_credit_required') 'failure audit must require fixing executor credit before next replay'
    Assert-True (($audit.diagnoses | Where-Object { $_.blocker -eq 'executor_credit_required' }).severity -eq 'P0') 'credit blocker should be P0 resource stopline'

    $sliceText = Get-Content -LiteralPath $sliceLoopPath -Raw -Encoding UTF8
    Assert-True ($sliceText.Contains('Get-PermanentExecutorResourceBlocker')) 'slice loop must inspect permanent executor resource blockers'
    Assert-True ($sliceText.Contains('no retry prompt generated because this requires external executor remediation')) 'slice loop must skip useless retry prompts for permanent resource blockers'

    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
