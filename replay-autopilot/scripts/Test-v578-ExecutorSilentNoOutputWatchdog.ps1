<#
.SYNOPSIS
    Regression test for executor silent-no-output watchdog.

.DESCRIPTION
    Verifies Invoke-AgentPrompt fails closed when an executor stays alive but
    produces no stdout, stderr, last-message, completion file, or stage artifact.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$invokePath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'

Write-Host "=== v578 Executor Silent No-Output Watchdog Test ===" -ForegroundColor Cyan

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-silent-watchdog-v578-" + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $tempRoot 'bin'
$work = Join-Path $tempRoot 'work'
$logs = Join-Path $tempRoot 'logs'
New-Item -ItemType Directory -Force -Path $bin, $work, $logs | Out-Null

try {
    $fakeClaude = Join-Path $bin 'claude.cmd'
    @"
@echo off
ping 127.0.0.1 -n 30 >nul
exit /b 0
"@ | Set-Content -LiteralPath $fakeClaude -Encoding ASCII

    $prompt = Join-Path $tempRoot 'prompt.md'
    'Write DONE.md' | Set-Content -LiteralPath $prompt -Encoding UTF8
    $completion = Join-Path $tempRoot 'DONE.md'
    $invokeOut = Join-Path $tempRoot 'invoke.out'

    $oldPath = $env:PATH
    $env:PATH = "$bin;$env:PATH"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $invokePath `
            -PromptPath $prompt `
            -WorkDir $work `
            -LogDir $logs `
            -Executor claude `
            -TimeoutMinutes 5 `
            -Name phase0 `
            -CompletionPath $completion `
            -CompletionQuietSeconds 15 `
            -SilentNoOutputTimeoutSeconds 2 *> $invokeOut
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($exit -eq 88) "expected exit 88 for silent no-output watchdog, got $exit"
    Assert-True (-not (Test-Path -LiteralPath $completion)) 'completion file must not be synthesized by watchdog'

    $metaPath = Join-Path $logs 'phase0.exec.json'
    Assert-True (Test-Path -LiteralPath $metaPath) 'exec metadata must be written'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($meta.failure_category -eq 'executor_silent_no_output') 'expected executor_silent_no_output failure category'
    Assert-True ($meta.completion_mode -eq 'silent_no_output_timeout') 'expected silent_no_output_timeout completion mode'
    Assert-True ([int]$meta.exit_code -eq 88) 'expected metadata exit_code 88'
    Assert-True ([int]$meta.silent_no_output_timeout_seconds -eq 2) 'expected metadata silent timeout seconds'
    Assert-True ([bool]$meta.executor_produced_no_output) 'expected executor_produced_no_output true'

    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
