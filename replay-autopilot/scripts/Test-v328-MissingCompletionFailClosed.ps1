<#
.SYNOPSIS
    Regression tests for v328 missing completion handling.

.DESCRIPTION
    Ensures Invoke-AgentPrompt does not treat an executor exit code 0 as
    success when the required completion file was not written. This protects
    unattended Claude runs from conversational "what do you want me to do?"
    responses that produce no PHASE0_RESULT/PLAN_RESULT/etc.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$invokePath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'

Write-Host "=== v328 Missing Completion Fail-Closed Test ===" -ForegroundColor Cyan

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-missing-completion-v328-" + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $tempRoot 'bin'
$work = Join-Path $tempRoot 'work'
$logs = Join-Path $tempRoot 'logs'
New-Item -ItemType Directory -Force -Path $bin, $work, $logs | Out-Null

try {
    $fakeClaude = Join-Path $bin 'claude.cmd'
    @"
@echo off
echo fake claude accepted prompt but wrote no completion
exit /b 0
"@ | Set-Content -LiteralPath $fakeClaude -Encoding ASCII

    $prompt = Join-Path $tempRoot 'prompt.md'
    'Write DONE.md' | Set-Content -LiteralPath $prompt -Encoding UTF8
    $completion = Join-Path $tempRoot 'DONE.md'

    $oldPath = $env:PATH
    $env:PATH = "$bin;$env:PATH"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $invokePath `
            -PromptPath $prompt `
            -WorkDir $work `
            -LogDir $logs `
            -Executor claude `
            -TimeoutMinutes 1 `
            -Name phase0 `
            -CompletionPath $completion `
            -CompletionQuietSeconds 15 *> (Join-Path $tempRoot 'invoke.out')
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($exit -eq 88) "expected exit 88 for missing completion, got $exit"
    $meta = Get-Content -LiteralPath (Join-Path $logs 'phase0.exec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($meta.failure_category -eq 'missing_completion') 'expected missing_completion failure category'
    Assert-True ($meta.exit_code -eq 88) 'expected metadata exit_code 88'

    $invokeText = Get-Content -LiteralPath $invokePath -Raw -Encoding UTF8
    Assert-True ($invokeText.Contains('Do not ask clarification questions')) 'automation guard must forbid clarification questions'
    Assert-True ($invokeText.Contains('write the requested completion file with BLOCKED status')) 'automation guard must require completion file for blockers'

    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
