#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for Codex executor preflight when no explicit model is configured.

.DESCRIPTION
Codex-primary replay can intentionally leave model fields empty and let the Codex
CLI use its configured default. The replay loop must not pass an empty native
PowerShell command-line argument after -Model, because powershell.exe can parse
that as a missing parameter before the executor preflight script starts.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runnerPath = Join-Path $scriptRoot '..\Run-ReplayLoop.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

try {
    $pattern = "(?s)\`$executorResourcePreflightArgs\s*=\s*@\((?<block>.*?)\)\s*if\s*\(-not\s+\[string\]::IsNullOrWhiteSpace\(\`$phase1Model\)\)\s*\{\s*\`$executorResourcePreflightArgs\s*\+=\s*@\('-Model',\s*\`$phase1Model\)\s*\}"
    $match = [regex]::Match($runnerText, $pattern)
    Assert-True $match.Success 'executor preflight args append -Model only under non-empty phase1Model guard'

    $baseArgsBlock = $match.Groups['block'].Value
    Assert-True (-not ($baseArgsBlock -match "'-Model'\s*,\s*\`$phase1Model")) 'executor preflight base args must not contain unconditional empty -Model'

    Write-Host ''
    Write-Host '=== v640 CODEX PREFLIGHT EMPTY MODEL: PASS ===' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
}
