param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\agent-prompt-completion-{0}' -f $PID)
$invokeScript = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        invoke_script = $invokeScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

$fakeBin = Join-Path $tempRoot 'bin'
$workDir = Join-Path $tempRoot 'work'
$logDir = Join-Path $tempRoot 'logs'
$sleepLogDir = Join-Path $tempRoot 'logs-sleep'
$usageLogDir = Join-Path $tempRoot 'logs-usage'
$capacityLogDir = Join-Path $tempRoot 'logs-capacity'
$promptPath = Join-Path $tempRoot 'PROMPT.md'
$completionPath = Join-Path $tempRoot 'DONE.md'
$sleepCompletionPath = Join-Path $tempRoot 'DONE-SLEEP.md'
$usageCompletionPath = Join-Path $tempRoot 'DONE-USAGE.md'
$capacityCompletionPath = Join-Path $tempRoot 'DONE-CAPACITY.md'
$sleepPidPath = Join-Path $tempRoot 'sleep-pid.txt'
New-Item -ItemType Directory -Force -Path $fakeBin, $workDir, $logDir, $sleepLogDir, $usageLogDir, $capacityLogDir | Out-Null
Set-Content -LiteralPath $promptPath -Value 'write completion then exit nonzero' -Encoding UTF8

$fakeCodexPath = Join-Path $fakeBin 'codex.cmd'
$fakeCodex = @'
@echo off
if "%1"=="exec" if "%2"=="--help" (
  echo Usage: codex exec --dangerously-bypass-approvals-and-sandbox --ask-for-approval
  exit /b 0
)
if "%FAKE_CODEX_MODE%"=="sleep-after-completion" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$marker='%FAKE_WORKDIR_MARK%'; Set-Content -LiteralPath $env:FAKE_SLEEP_PID_PATH -Value $PID -Encoding UTF8; Set-Content -LiteralPath $env:FAKE_COMPLETION_PATH -Value 'completed while executor still running' -Encoding UTF8; Start-Sleep -Seconds 120"
  exit /b 0
)
if "%FAKE_CODEX_MODE%"=="usage-limit" (
  echo ERROR: You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at May 18th, 2026 12:01 AM.
  exit /b 1
)
if "%FAKE_CODEX_MODE%"=="capacity" (
  echo Selected model is at capacity. Please try a different model.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Content -LiteralPath $env:FAKE_COMPLETION_PATH -Value 'completed despite executor exit' -Encoding UTF8"
echo fake codex wrote completion and exits nonzero
exit /b 7
'@
Set-Content -LiteralPath $fakeCodexPath -Value $fakeCodex -Encoding ASCII

$oldPath = $env:PATH
$oldCompletion = $env:FAKE_COMPLETION_PATH
$oldMode = $env:FAKE_CODEX_MODE
$oldSleepPid = $env:FAKE_SLEEP_PID_PATH
$oldWorkdirMark = $env:FAKE_WORKDIR_MARK
$sentinel = $null
try {
    $env:PATH = "$fakeBin;$oldPath"
    $env:FAKE_COMPLETION_PATH = $completionPath
    Remove-Item Env:\FAKE_CODEX_MODE -ErrorAction SilentlyContinue
    & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $logDir `
        -Executor codex `
        -CompletionPath $completionPath `
        -CompletionQuietSeconds 15 `
        -TimeoutMinutes 1 `
        -Name fake | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Invoke-AgentPrompt returned exit code $LASTEXITCODE despite completion file"
    }

    $env:FAKE_COMPLETION_PATH = $sleepCompletionPath
    $env:FAKE_CODEX_MODE = 'sleep-after-completion'
    $env:FAKE_SLEEP_PID_PATH = $sleepPidPath
    $env:FAKE_WORKDIR_MARK = $workDir
    $sentinelCommand = "`$marker='$workDir'; Start-Sleep -Seconds 120"
    $sentinel = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $sentinelCommand) -WindowStyle Hidden -PassThru
    & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $sleepLogDir `
        -Executor codex `
        -CompletionPath $sleepCompletionPath `
        -CompletionQuietSeconds 15 `
        -TimeoutMinutes 2 `
        -Name fake-sleep | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Invoke-AgentPrompt returned exit code $LASTEXITCODE when stopping job after completion file"
    }
    if (-not (Test-Path -LiteralPath $sleepPidPath)) {
        throw "Sleep child process did not write pid file: $sleepPidPath"
    }
    $sleepPid = [int](Get-Content -LiteralPath $sleepPidPath -Raw -Encoding UTF8)
    Start-Sleep -Seconds 1
    if (Get-Process -Id $sleepPid -ErrorAction SilentlyContinue) {
        throw "Completion-file cleanup left child process running: $sleepPid"
    }
    if (-not (Get-Process -Id $sentinel.Id -ErrorAction SilentlyContinue)) {
        throw "Completion-file cleanup killed a non-descendant process that only matched WorkDir text: $($sentinel.Id)"
    }
    Stop-Process -Id $sentinel.Id -Force -ErrorAction SilentlyContinue
    $sentinel = $null

    $env:FAKE_COMPLETION_PATH = $usageCompletionPath
    $env:FAKE_CODEX_MODE = 'usage-limit'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $usageLogDir `
        -Executor codex `
        -CompletionPath $usageCompletionPath `
        -CompletionQuietSeconds 15 `
        -TimeoutMinutes 1 `
        -Name fake-usage | Out-Null

    if ($LASTEXITCODE -ne 86) {
        throw "Invoke-AgentPrompt expected usage-limit exit code 86, got $LASTEXITCODE"
    }

    $env:FAKE_COMPLETION_PATH = $capacityCompletionPath
    $env:FAKE_CODEX_MODE = 'capacity'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
        -PromptPath $promptPath `
        -WorkDir $workDir `
        -LogDir $capacityLogDir `
        -Executor codex `
        -CompletionPath $capacityCompletionPath `
        -CompletionQuietSeconds 15 `
        -TimeoutMinutes 1 `
        -Name fake-capacity | Out-Null

    if ($LASTEXITCODE -ne 86) {
        throw "Invoke-AgentPrompt expected capacity exit code 86, got $LASTEXITCODE"
    }
} finally {
    if ($null -ne $sentinel) {
        Stop-Process -Id $sentinel.Id -Force -ErrorAction SilentlyContinue
    }
    $env:PATH = $oldPath
    if ($null -eq $oldCompletion) {
        Remove-Item Env:\FAKE_COMPLETION_PATH -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_COMPLETION_PATH = $oldCompletion
    }
    if ($null -eq $oldMode) {
        Remove-Item Env:\FAKE_CODEX_MODE -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_CODEX_MODE = $oldMode
    }
    if ($null -eq $oldSleepPid) {
        Remove-Item Env:\FAKE_SLEEP_PID_PATH -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_SLEEP_PID_PATH = $oldSleepPid
    }
    if ($null -eq $oldWorkdirMark) {
        Remove-Item Env:\FAKE_WORKDIR_MARK -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_WORKDIR_MARK = $oldWorkdirMark
    }
}

$metaPath = Join-Path $logDir 'fake.exec.json'
if (-not (Test-Path -LiteralPath $completionPath)) {
    throw "Completion file was not written: $completionPath"
}
if (-not (Test-Path -LiteralPath $metaPath)) {
    throw "Execution metadata was not written: $metaPath"
}

$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($meta.exit_code -ne 0) {
    throw "Expected wrapper exit_code 0, got $($meta.exit_code)"
}
if ($meta.executor_exit_code -ne 7) {
    throw "Expected original executor_exit_code 7, got $($meta.executor_exit_code)"
}
if ($meta.completion_mode -ne 'completion_file_after_process_exit') {
    throw "Expected completion_file_after_process_exit, got $($meta.completion_mode)"
}

$sleepMetaPath = Join-Path $sleepLogDir 'fake-sleep.exec.json'
if (-not (Test-Path -LiteralPath $sleepCompletionPath)) {
    throw "Sleep completion file was not written: $sleepCompletionPath"
}
if (-not (Test-Path -LiteralPath $sleepMetaPath)) {
    throw "Sleep execution metadata was not written: $sleepMetaPath"
}

$sleepMeta = Get-Content -LiteralPath $sleepMetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($sleepMeta.exit_code -ne 0) {
    throw "Expected sleep wrapper exit_code 0, got $($sleepMeta.exit_code)"
}
if ($sleepMeta.completion_mode -ne 'completion_file') {
    throw "Expected completion_file for running executor stop path, got $($sleepMeta.completion_mode)"
}

$usageMetaPath = Join-Path $usageLogDir 'fake-usage.exec.json'
if (-not (Test-Path -LiteralPath $usageMetaPath)) {
    throw "Usage-limit execution metadata was not written: $usageMetaPath"
}
$usageMeta = Get-Content -LiteralPath $usageMetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($usageMeta.failure_category -ne 'usage_limit') {
    throw "Expected usage_limit failure_category, got $($usageMeta.failure_category)"
}

$capacityMetaPath = Join-Path $capacityLogDir 'fake-capacity.exec.json'
if (-not (Test-Path -LiteralPath $capacityMetaPath)) {
    throw "Capacity execution metadata was not written: $capacityMetaPath"
}
$capacityMeta = Get-Content -LiteralPath $capacityMetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($capacityMeta.failure_category -ne 'usage_limit') {
    throw "Expected usage_limit failure_category for capacity, got $($capacityMeta.failure_category)"
}

[ordered]@{
    status = 'PASS'
    cases = @(
        'completion_file_overrides_nonzero_executor_exit_after_process_exit',
        'completion_file_stops_running_job_without_unsupported_force_parameter',
        'completion_file_kills_matching_executor_child_processes',
        'completion_file_does_not_kill_matching_non_descendant_processes',
        'usage_limit_exits_with_resource_code',
        'capacity_exits_with_resource_code'
    )
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 6

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
