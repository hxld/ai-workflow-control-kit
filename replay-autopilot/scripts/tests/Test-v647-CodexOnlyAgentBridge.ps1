#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for Codex-only AgentBridge compatibility.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..\..')
$bridgeScript = Join-Path $repoRoot 'scripts\Start-AgentBridge.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-bridge-codex-only-v647-' + [guid]::NewGuid().ToString('N'))

try {
    $bridgeRoot = Join-Path $tempRoot 'current'
    $archiveRoot = Join-Path $tempRoot 'runs'
    $projectRoot = Join-Path $tempRoot 'protected-project'
    New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null
    & git -C $projectRoot init | Out-Null

    $text = Get-Content -LiteralPath $bridgeScript -Raw -Encoding UTF8
    Assert-True ($text -match "\[string\]\`$ClaudeExecutor\s*=\s*'codex'") 'legacy ClaudeExecutor parameter must default to codex'
    Assert-True ($text -match "\[string\]\`$PrimaryExecutor\s*=\s*''") 'PrimaryExecutor alias parameter must exist'
    Assert-True ($text -match "\[string\]\`$ReviewExecutor\s*=\s*''") 'ReviewExecutor alias parameter must exist'
    Assert-True ($text -match "\[switch\]\`$CodexOnly") 'CodexOnly switch must exist'
    Assert-True ($text -match "\`$script:BridgePrimaryExecutor\s*=\s*if\s*\(\`$CodexOnly\)") 'CodexOnly must force primary executor resolution'
    Assert-True ($text -match "\`$script:BridgeReviewExecutor\s*=\s*if\s*\(\`$CodexOnly\)") 'CodexOnly must force review executor resolution'
    Assert-True ($text -match "Invoke-AgentBridgePrompt[\s\S]+-Actor 'primary'[\s\S]+-Executor \`$script:BridgePrimaryExecutor") 'RunLoop must invoke primary executor through resolved primary alias'
    Assert-True ($text -match "Invoke-AgentBridgePrompt[\s\S]+-Actor 'review'[\s\S]+-Executor \`$script:BridgeReviewExecutor") 'RunLoop must invoke review executor through resolved review alias'
    Assert-True ($text -match "The ``CLAUDE_\*`` filenames are protocol compatibility names only") 'primary prompt must document CLAUDE_* compatibility naming'
    Assert-True ($text -match "next_actor`": `"primary`"") 'review prompt schema must point next_actor to primary'
    Assert-True ($text -match "'PrimaryDone'") 'PrimaryDone compatibility action must be accepted'
    Assert-True ($text -match "'ReviewDone'") 'ReviewDone compatibility action must be accepted'

    $validateRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ValidateOnly `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -PrimaryExecutor claude `
        -ReviewExecutor manual `
        -CodexOnly `
        -ProtectedGitRoots $projectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "ValidateOnly failed: $($validateRaw | Out-String)"
    }
    $validate = ($validateRaw | Out-String) | ConvertFrom-Json
    Assert-True ($validate.primary_executor -eq 'codex') "CodexOnly must override primary executor, got $($validate.primary_executor)"
    Assert-True ($validate.review_executor -eq 'codex') "CodexOnly must override review executor, got $($validate.review_executor)"
    Assert-True ([bool]$validate.codex_only) 'ValidateOnly must disclose codex_only=true'
    Assert-True (@($validate.actions) -contains 'PrimaryDone') 'ValidateOnly actions must include PrimaryDone'
    Assert-True (@($validate.actions) -contains 'ReviewDone') 'ValidateOnly actions must include ReviewDone'
    Assert-True ($validate.compatibility_actions.primary_done -eq 'ClaudeDone') 'PrimaryDone must preserve ClaudeDone compatibility'
    Assert-True ($validate.compatibility_files.primary_result -eq 'CLAUDE_RESULT.md') 'Primary result compatibility file must remain CLAUDE_RESULT.md'

    $promptPath = Join-Path $tempRoot 'initial.md'
    Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value 'Run one Codex-only bridge canary and write the compatibility result files.'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $promptPath `
        -CodexOnly `
        -ProtectedGitRoots $projectRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'CodexOnly Init must exit 0'
    $state = Get-Content -LiteralPath (Join-Path $bridgeRoot 'STATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($state.active_actor -eq 'primary') "Init active_actor must be primary, got $($state.active_actor)"
    Assert-True ($state.expected_files.primary_result -match 'CLAUDE_RESULT\.md$') 'state must expose primary_result alias'
    $agentPrompt = Get-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_AGENT_PROMPT.md') -Raw -Encoding UTF8
    Assert-True ($agentPrompt -match 'primary executor for this run is codex') 'primary agent prompt must disclose codex executor'
    Assert-True ($agentPrompt -match 'compatibility names only') 'primary agent prompt must document compatibility filenames'

    Write-Host ''
    Write-Host '=== v647 CODEX-ONLY AGENT BRIDGE: PASS ===' -ForegroundColor Green
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
