<#
.SYNOPSIS
    Regression test for Claude default silent watchdog policy.

.DESCRIPTION
    Claude --print does not stream stdout/stderr while it is still working.
    Long replay slices must therefore rely on the stage timeout by default,
    while explicit or environment silent watchdog settings remain honored.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Invoke-ValidateOnly {
    param(
        [string]$Root,
        [string]$Name,
        [string[]]$ExtraArgs = @()
    )

    $scriptRoot = Split-Path -Parent $PSCommandPath
    $invokePath = Join-Path $scriptRoot 'Invoke-AgentPrompt.ps1'
    $prompt = Join-Path $Root 'prompt.md'
    $work = Join-Path $Root 'work'
    $logs = Join-Path $Root $Name
    $completion = Join-Path $Root "$Name.result.md"
    New-Item -ItemType Directory -Force -Path $work, $logs | Out-Null
    'Write the requested completion artifact.' | Set-Content -LiteralPath $prompt -Encoding UTF8

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $invokePath,
        '-PromptPath', $prompt,
        '-WorkDir', $work,
        '-LogDir', $logs,
        '-Executor', 'claude',
        '-TimeoutMinutes', '21',
        '-CompletionPath', $completion,
        '-CompletionQuietSeconds', '15',
        '-Name', $Name,
        '-ValidateOnly'
    ) + $ExtraArgs

    & powershell @args | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "ValidateOnly failed for $Name with exit $LASTEXITCODE"

    $metaPath = Join-Path $logs "$Name.exec.json"
    Assert-True (Test-Path -LiteralPath $metaPath -PathType Leaf) "missing metadata for $Name"
    return (Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

Write-Host "=== v624 Claude Default Silent Watchdog Policy Test ===" -ForegroundColor Cyan

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-silent-policy-v624-" + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $tempRoot 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

try {
    $fakeClaude = Join-Path $bin 'claude.cmd'
    @"
@echo off
exit /b 0
"@ | Set-Content -LiteralPath $fakeClaude -Encoding ASCII

    $oldPath = $env:PATH
    $oldSilent = $env:REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS
    $env:PATH = "$bin;$env:PATH"
    try {
        Remove-Item Env:\REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS -ErrorAction SilentlyContinue

        $defaultMeta = Invoke-ValidateOnly -Root $tempRoot -Name 'claude-default'
        Assert-True ([int]$defaultMeta.SilentNoOutputTimeoutSeconds -eq 0) 'Claude default must not enable silent watchdog'
        Assert-True ([string]$defaultMeta.SilentNoOutputPolicyReason -eq 'default_disabled_for_claude_print_executor') 'Claude default disable reason mismatch'

        $explicitMeta = Invoke-ValidateOnly -Root $tempRoot -Name 'claude-explicit' -ExtraArgs @('-SilentNoOutputTimeoutSeconds', '2')
        Assert-True ([int]$explicitMeta.SilentNoOutputTimeoutSeconds -eq 2) 'explicit silent watchdog must be honored'
        Assert-True ([string]$explicitMeta.SilentNoOutputPolicyReason -eq 'explicit_or_env_override') 'explicit policy reason mismatch'

        $env:REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS = '3'
        $envMeta = Invoke-ValidateOnly -Root $tempRoot -Name 'claude-env'
        Assert-True ([int]$envMeta.SilentNoOutputTimeoutSeconds -eq 3) 'env silent watchdog must be honored'
        Assert-True ([string]$envMeta.SilentNoOutputPolicyReason -eq 'explicit_or_env_override') 'env policy reason mismatch'
    } finally {
        $env:PATH = $oldPath
        if ($null -eq $oldSilent) {
            Remove-Item Env:\REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS -ErrorAction SilentlyContinue
        } else {
            $env:REPLAY_AGENT_SILENT_NO_OUTPUT_TIMEOUT_SECONDS = $oldSilent
        }
    }

    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
