#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for bounded executor resource preflight.

.DESCRIPTION
The live preflight must fail closed quickly when the executor process hangs
without output. This prevents unattended replay from spending the full phase
timeout on a gateway/channel outage before Phase0 starts.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v638-executor-preflight-timeout-' + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $fakeBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Force -Path $evidenceRoot, $fakeBin | Out-Null

    @'
@echo off
ping -n 6 127.0.0.1 >nul
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'claude.cmd') -Encoding ASCII

    $oldPath = $env:PATH
    $env:PATH = "$fakeBin;$oldPath"
    try {
        $started = Get-Date
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\Invoke-ExecutorResourcePreflight.ps1') `
            -EvidenceRoot $evidenceRoot `
            -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
            -Executor claude `
            -RequireExecutor claude `
            -Model claude-sonnet-4-6 `
            -Probe `
            -ProbeTimeoutSeconds 1 `
            -Quiet *> (Join-Path $tempRoot 'preflight.out')
        $exitCode = $LASTEXITCODE
        $elapsed = [int]((Get-Date) - $started).TotalSeconds
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($exitCode -eq 86) "timeout probe must exit 86, got $exitCode"
    Assert-True ($elapsed -lt 10) "timeout probe must be bounded, elapsed=$elapsed"

    $preflightPath = Join-Path $evidenceRoot '_control\EXECUTOR_RESOURCE_PREFLIGHT.json'
    Assert-True (Test-Path -LiteralPath $preflightPath) 'preflight JSON must be written'
    $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($preflight.decision -eq 'BLOCK') "expected BLOCK, got $($preflight.decision)"
    Assert-True ($preflight.failure_category -eq 'executor_resource_blocker') "expected executor_resource_blocker, got $($preflight.failure_category)"

    $meta = Get-Content -LiteralPath $preflight.source -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($meta.completion_mode -eq 'probe_timeout') "expected probe_timeout, got $($meta.completion_mode)"
    Assert-True ([int]$meta.timeout_seconds -eq 1) "expected timeout_seconds=1, got $($meta.timeout_seconds)"

    Write-Host ''
    Write-Host '=== v638 EXECUTOR RESOURCE PREFLIGHT TIMEOUT: PASS ===' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
