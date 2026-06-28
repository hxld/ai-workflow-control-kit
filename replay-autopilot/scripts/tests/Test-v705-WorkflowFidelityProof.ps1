#!/usr/bin/env pwsh
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

function New-SkillSet {
    param([string]$Root)
    foreach ($skill in @('pre-flight-check', 'replay-tdd-enforcer', 'replay-test-charter-validator')) {
        Write-Utf8 (Join-Path $Root (Join-Path $skill 'SKILL.md')) "---`nname: $skill`n---`n# $skill`n"
    }
}

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v705-workflow-fidelity-' + [guid]::NewGuid().ToString('N'))

try {
    $sourceRoot = Join-Path $tempRoot 'source-skills'
    $runtimeRoot = Join-Path $tempRoot 'runtime-skills'
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    $logDir = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Force -Path $sourceRoot, $runtimeRoot, $replayRoot, $worktree, $logDir | Out-Null
    New-SkillSet -Root $sourceRoot
    New-SkillSet -Root $runtimeRoot
    Write-Utf8 (Join-Path $worktree 'prompt.md') 'Say done.'

    $proofPath = Join-Path $tempRoot 'workflow-proof.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Write-WorkflowFidelityProof.ps1') `
        -OutputPath $proofPath `
        -Executor codex `
        -CommandSource 'codex.cmd' `
        -WorkDir $worktree `
        -LogDir $logDir `
        -Stage 'test' `
        -SkillSourceRoot $sourceRoot `
        -RuntimeSkillRoot $runtimeRoot `
        -CodexHooksEnabled $false | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'workflow fidelity writer should exit zero'
    $proof = Get-Content -LiteralPath $proofPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$proof.status -eq 'PASS') 'workflow fidelity proof should pass when required source and runtime skills exist'
    Assert-True (-not [bool]$proof.skill_usage_proven) 'workflow fidelity proof must not overclaim actual skill activation'
    Assert-True ([string]$proof.proof_scope -eq 'runtime_skill_visibility_and_hashes_only') 'workflow fidelity proof must disclose its proof scope'
    Assert-True (@($proof.skill_checks).Count -eq 3) 'workflow fidelity proof should include required skill checks'
    Assert-True ([string]$proof.skill_checks[0].source_sha256 -match '^[0-9a-f]{64}$') 'skill checks should include source sha256'

    Remove-Item -LiteralPath (Join-Path $runtimeRoot 'replay-tdd-enforcer\SKILL.md') -Force
    $blockedPath = Join-Path $tempRoot 'workflow-proof-blocked.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Write-WorkflowFidelityProof.ps1') `
        -OutputPath $blockedPath `
        -Executor codex `
        -SkillSourceRoot $sourceRoot `
        -RuntimeSkillRoot $runtimeRoot | Out-Null
    $blocked = Get-Content -LiteralPath $blockedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$blocked.status -eq 'BLOCKED') 'workflow fidelity proof should block when a runtime skill is missing'
    $missingRuntimeIssues = @(@($blocked.issues) | Where-Object { $_.code -eq 'missing_runtime_skill' -and $_.skill -eq 'replay-tdd-enforcer' })
    Assert-True ($missingRuntimeIssues.Count -eq 1) 'blocked proof should name the missing runtime skill'

    New-SkillSet -Root $runtimeRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceToolAvailabilityGate.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -Executor codex `
        -SkillSourceRoot $sourceRoot `
        -RuntimeSkillRoot $runtimeRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'pre-slice availability gate should pass when workflow fidelity passes'
    $availability = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_TOOL_AVAILABILITY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$availability.workflow_fidelity_status -eq 'PASS') 'availability gate should disclose PASS workflow fidelity status'
    Assert-True (Test-Path -LiteralPath $availability.workflow_fidelity_path -PathType Leaf) 'availability gate should preserve workflow fidelity evidence path'

    Remove-Item -LiteralPath (Join-Path $runtimeRoot 'pre-flight-check\SKILL.md') -Force
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-PreSliceToolAvailabilityGate.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -Executor codex `
        -SkillSourceRoot $sourceRoot `
        -RuntimeSkillRoot $runtimeRoot | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'pre-slice availability gate should fail closed when workflow fidelity is blocked'
    $blockedAvailability = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_TOOL_AVAILABILITY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$blockedAvailability.status -eq 'BLOCKED') 'availability gate should write BLOCKED status for missing runtime skills'

    New-SkillSet -Root $runtimeRoot
    $fakeBin = Join-Path $tempRoot 'bin'
    New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
    @'
@echo off
if "%~1"=="exec" exit /b 0
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeBin 'codex.cmd') -Encoding ASCII
    $oldPath = $env:PATH
    $env:PATH = "$fakeBin;$oldPath"
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-AgentPrompt.ps1') `
            -PromptPath (Join-Path $worktree 'prompt.md') `
            -WorkDir $worktree `
            -LogDir $logDir `
            -Executor codex `
            -CodexHooksEnabled true `
            -SkillSourceRoot $sourceRoot `
            -RuntimeSkillRoot $runtimeRoot `
            -ValidateOnly | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) 'Invoke-AgentPrompt ValidateOnly should pass when workflow fidelity passes'
    } finally {
        $env:PATH = $oldPath
    }
    $meta = Get-Content -LiteralPath (Join-Path $logDir 'agent.exec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([bool]$meta.CodexHooksEnabled) 'Invoke-AgentPrompt metadata should expose configured Codex hooks state'
    Assert-True ([string]$meta.WorkflowFidelityStatus -eq 'PASS') 'Invoke-AgentPrompt metadata should expose workflow fidelity PASS status'
    Assert-True (Test-Path -LiteralPath $meta.WorkflowFidelityPath -PathType Leaf) 'Invoke-AgentPrompt should write workflow fidelity proof beside exec metadata'

    Remove-Item -LiteralPath (Join-Path $runtimeRoot 'replay-test-charter-validator\SKILL.md') -Force
    $blockedLogDir = Join-Path $tempRoot 'blocked-agent-logs'
    $env:PATH = "$fakeBin;$oldPath"
    try {
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Invoke-AgentPrompt.ps1') `
                -PromptPath (Join-Path $worktree 'prompt.md') `
                -WorkDir $worktree `
                -LogDir $blockedLogDir `
                -Executor codex `
                -SkillSourceRoot $sourceRoot `
                -RuntimeSkillRoot $runtimeRoot `
                -ValidateOnly *> (Join-Path $tempRoot 'blocked-agent.out')
        } catch {
            # Expected for this scenario; keep LASTEXITCODE for the fail-closed assertion below.
        }
        $blockedAgentExit = $LASTEXITCODE
    } finally {
        $env:PATH = $oldPath
    }
    Assert-True ($blockedAgentExit -ne 0) 'Invoke-AgentPrompt should fail closed when workflow fidelity is blocked'
    $blockedAgentMeta = Get-Content -LiteralPath (Join-Path $blockedLogDir 'agent.exec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ([string]$blockedAgentMeta.Status -eq 'WORKFLOW_FIDELITY_BLOCKED') 'blocked Invoke-AgentPrompt should still write diagnostic exec metadata'
    Assert-True ([string]$blockedAgentMeta.WorkflowFidelityStatus -eq 'BLOCKED') 'blocked Invoke-AgentPrompt metadata should expose BLOCKED workflow fidelity status'

    Write-Host ''
    Write-Host 'v705 Workflow Fidelity Proof: PASS'
    exit 0
} catch {
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
