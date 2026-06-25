#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for Codex-primary replay executor policy and bounded preflight.
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
$repoReplayRoot = Resolve-Path (Join-Path $scriptRoot '..\..')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v639-codex-primary-' + [guid]::NewGuid().ToString('N'))

try {
    $configPath = Join-Path $repoReplayRoot 'config.yaml'
    $runLoop = Join-Path $repoReplayRoot 'scripts\Run-ReplayLoop.ps1'
    $controlLoop = Join-Path $repoReplayRoot 'scripts\Run-UnattendedReplayControl.ps1'

    $runValidate = & powershell -NoProfile -ExecutionPolicy Bypass -File $runLoop -ConfigPath $configPath -ValidateOnly 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Run-ReplayLoop validate failed: $runValidate" }
    $runText = ($runValidate | Out-String)
    Assert-True ($runText -match 'Executor\s+:\s+codex') 'Run-ReplayLoop default executor must be codex'
    Assert-True ($runText -match 'RequireExecutor\s+:\s+codex') 'Run-ReplayLoop default require_executor must be codex'
    Assert-True ($runText -match 'AllowCodexExecutor\s+:\s+True') 'Run-ReplayLoop must authorize codex primary'

    $controlValidate = & powershell -NoProfile -ExecutionPolicy Bypass -File $controlLoop -ConfigPath $configPath -ValidateOnly 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Run-UnattendedReplayControl validate failed: $controlValidate" }
    $control = ($controlValidate | Out-String) | ConvertFrom-Json
    Assert-True ($control.executor -eq 'codex') "control executor must be codex, got $($control.executor)"
    Assert-True ($control.require_executor -eq 'codex') "control require_executor must be codex, got $($control.require_executor)"
    Assert-True ([bool]$control.allow_codex_executor) 'control must authorize codex primary'

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $fakeBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Force -Path $evidenceRoot, $fakeBin | Out-Null

    @'
@echo off
ping -n 6 127.0.0.1 >nul
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Encoding ASCII

    $oldPath = $env:PATH
    $env:PATH = "$fakeBin;$oldPath"
    try {
        $started = Get-Date
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoReplayRoot 'scripts\Invoke-ExecutorResourcePreflight.ps1') `
            -EvidenceRoot $evidenceRoot `
            -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
            -Executor codex `
            -RequireExecutor codex `
            -Probe `
            -ProbeTimeoutSeconds 1 `
            -Quiet *> (Join-Path $tempRoot 'preflight.out')
        $exitCode = $LASTEXITCODE
        $elapsed = [int]((Get-Date) - $started).TotalSeconds
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($exitCode -eq 86) "codex timeout probe must exit 86, got $exitCode"
    Assert-True ($elapsed -lt 10) "codex timeout probe must be bounded, elapsed=$elapsed"

    $preflightPath = Join-Path $evidenceRoot '_control\EXECUTOR_RESOURCE_PREFLIGHT.json'
    Assert-True (Test-Path -LiteralPath $preflightPath) 'codex preflight JSON must be written'
    $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($preflight.executor -eq 'codex') "expected executor=codex, got $($preflight.executor)"
    Assert-True ($preflight.decision -eq 'BLOCK') "expected BLOCK, got $($preflight.decision)"
    Assert-True ($preflight.failure_category -eq 'executor_resource_blocker') "expected executor_resource_blocker, got $($preflight.failure_category)"

    $meta = Get-Content -LiteralPath $preflight.source -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($meta.completion_mode -eq 'probe_timeout') "expected probe_timeout, got $($meta.completion_mode)"
    Assert-True ([int]$meta.timeout_seconds -eq 1) "expected timeout_seconds=1, got $($meta.timeout_seconds)"

    @'
@echo off
set last=
:scan
if "%~1"=="" goto done
if "%~1"=="--output-last-message" (
  set last=%~2
  shift
  shift
  goto scan
)
shift
goto scan
:done
echo simulated codex completed
if not "%last%"=="" echo simulated codex completed> "%last%"
exit /b 1
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Encoding ASCII

    $env:PATH = "$fakeBin;$oldPath"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoReplayRoot 'scripts\Invoke-ExecutorResourcePreflight.ps1') `
            -EvidenceRoot $evidenceRoot `
            -ReplayRootBase (Join-Path $evidenceRoot 'feature\round-base') `
            -Executor codex `
            -RequireExecutor codex `
            -Probe `
            -ProbeTimeoutSeconds 5 `
            -Quiet *> (Join-Path $tempRoot 'preflight-completion.out')
        $completionExitCode = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }

    Assert-True ($completionExitCode -eq 0) "codex completion-text probe must exit 0, got $completionExitCode"
    $completionPreflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($completionPreflight.decision -eq 'ALLOW') "expected ALLOW, got $($completionPreflight.decision)"
    $completionMeta = Get-Content -LiteralPath $completionPreflight.source -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($completionMeta.completion_mode -eq 'probe_completion_text') "expected probe_completion_text, got $($completionMeta.completion_mode)"

    Write-Host ''
    Write-Host '=== v639 CODEX PRIMARY EXECUTOR POLICY: PASS ===' -ForegroundColor Green
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
