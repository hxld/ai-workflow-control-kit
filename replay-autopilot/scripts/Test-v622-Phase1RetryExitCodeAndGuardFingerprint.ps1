param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$sliceLoopScript = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$controlSummaryScript = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v622-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $sliceText = Get-Content -LiteralPath $sliceLoopScript -Raw -Encoding UTF8
    Assert-True 'slice_loop_has_exit_code_normalizer' ($sliceText.Contains('function Convert-ToExecutorExitCode'))
    Assert-True 'retry_exit_code_is_normalized_after_executor_call' ($sliceText -match '\$retryExitCode\s*=\s*Invoke-SliceExecutorWithRetry[\s\S]{0,260}\$retryExitCode\s*=\s*Convert-ToExecutorExitCode\s+\$retryExitCode')
    Assert-True 'final_retry_exit_code_uses_normalizer_not_int_cast' ($sliceText -match '\$finalExecutorExitCode\s*=\s*Convert-ToExecutorExitCode\s+\$retryExitCode')
    Assert-True 'final_executor_exit_code_uses_normalizer_not_int_cast' ($sliceText -match '\$finalExecutorExitCode\s*=\s*Convert-ToExecutorExitCode\s+\$executorExitCode')
    Assert-True 'raw_int_retry_cast_removed' (-not ($sliceText -match '\[int\]\$retryExitCode'))
    Assert-True 'raw_int_executor_cast_removed' (-not ($sliceText -match '\[int\]\$executorExitCode'))

    $controlText = Get-Content -LiteralPath $controlSummaryScript -Raw -Encoding UTF8
    Assert-True 'protected_root_pattern_does_not_match_generic_command_guard' (-not ($controlText -match "'protected_root_isolation_violation'\s*=\s*'[^']*command_guard_violation"))

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $featureRoot = Join-Path $evidenceRoot 'sample-feature'
    $replayRoot = Join-Path $featureRoot 'claim-codex-replay-v622-test-r01'
    $logDir = Join-Path $replayRoot 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') @'
# Replay Autopilot Summary

- phase0_status: PROCEED
- plan_status: PROCEED
- final_status: BLOCKED
- verification_capped_coverage: 0

## Early Stop Reason
executor_failed_without_result
'@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: STOP_BLOCKED
'@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') @'
# Autopilot Blocker

Phase 1 executor failed without result.
'@
    Write-Json (Join-Path $replayRoot 'EXECUTOR_AUDIT.json') ([ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    })
    Write-Json (Join-Path $logDir 'phase1-slice01.exec.json') ([ordered]@{
        failure_category = 'command_guard_violation'
        executor_exit_code = 93
        command_guard_reasons = 'maven_pl_without_am_forbidden:pid=1234'
        stdout_log = ''
        stderr_log = ''
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $controlSummaryScript `
        -EvidenceRoot $evidenceRoot `
        -MaxRoots 5 `
        -RepeatBlockerThreshold 1 `
        -LowCapThreshold 45 `
        -RequireExecutor claude `
        -Quiet
    if ($LASTEXITCODE -ne 0) { throw "Write-ControlPlaneSummary failed: $LASTEXITCODE" }

    $latest = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\RUN_CONTROL_LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $fingerprints = @($latest.latest.fingerprints)
    Assert-True 'maven_pl_without_am_does_not_emit_protected_root_fingerprint' (-not ($fingerprints -contains 'protected_root_isolation_violation')) ($fingerprints -join ',')
    Assert-True 'maven_pl_without_am_still_emits_executor_failure_fingerprint' ($fingerprints -contains 'executor_resource_or_crash') ($fingerprints -join ',')
    Assert-True 'low_cap_fingerprint_still_present' ($fingerprints -contains 'low_verification_cap') ($fingerprints -join ',')

    Write-Host 'PASS: v622 phase1 retry exit code and guard fingerprint'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
