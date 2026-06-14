param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8

Assert-True 'retry_function_supports_non_retry_exit_codes' (
    $runLoopText.Contains('[int[]]$NonRetryExitCodes = @()') -and
    $runLoopText.Contains('$NonRetryExitCodes -contains $exitCodeNow')
)

Assert-True 'phase0_command_guard_summary_reads_jsonl' (
    $runLoopText.Contains('function Get-AgentCommandGuardSummary') -and
    $runLoopText.Contains('"{0}.command-guard.jsonl" -f $Name') -and
    $runLoopText.Contains('command_line')
)

Assert-True 'phase0_command_guard_repair_prompt_exists' (
    $runLoopText.Contains('function Write-Phase0CommandGuardRepairPrompt') -and
    $runLoopText.Contains('PHASE0_COMMAND_GUARD_REPAIR_PROMPT.md') -and
    $runLoopText.Contains('Phase 0 Command-Guard Repair')
)

Assert-True 'phase0_repair_prompt_forbids_build_commands' (
    $runLoopText.Contains('Do not run Maven') -and
    $runLoopText.Contains('Do not run any command containing mvn') -and
    $runLoopText.Contains('Do not run tests. Do not compile. Do not build. Do not install. Do not deploy.')
)

Assert-True 'phase0_primary_does_not_retry_command_guard_exit' (
    $runLoopText -match '(?s)\$phase0Succeeded\s*=\s*Invoke-WithRetry\s+-Label ''Phase 0''.*?-NonRetryExitCodes @\(93\)'
)

Assert-True 'phase0_command_guard_repair_is_single_attempt' (
    $runLoopText -match '(?s)Phase 0 command guard repair.*?-MaxRetries 0.*?-NonRetryExitCodes @\(93\)'
)

Assert-True 'phase0_command_guard_repair_uses_phase0_completion_path' (
    $runLoopText.Contains("'-Name', 'phase0-command-guard-repair'") -and
    $runLoopText.Contains("'-CompletionPath', $phase0ResultPath")
)

Assert-True 'phase0_failure_blocker_uses_actual_failed_attempt_logs' (
    $runLoopText.Contains('$phase0FailureLogDir') -and
    $runLoopText.Contains('$phase0FailureName') -and
    $runLoopText.Contains('$phase0FailureStage')
)

Write-Host 'PASS: v488 phase0 command guard repair'
