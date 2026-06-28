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

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v706-control-config-root-' + [guid]::NewGuid().ToString('N'))

try {
    $projectRoot = Join-Path $tempRoot 'project'
    $knowledgeRoot = Join-Path $tempRoot 'knowledge'
    New-Item -ItemType Directory -Force -Path $projectRoot, $knowledgeRoot | Out-Null
    Write-Utf8 (Join-Path $projectRoot 'requirements.md') '# Requirement'
    Write-Utf8 (Join-Path $projectRoot 'docs\context.md') '# Context'
    Write-Utf8 (Join-Path $knowledgeRoot 'custom-skills-history\v706-root.md') '# v706'
    & git -C $projectRoot init -q
    & git -C $projectRoot config user.email 'replay-test@example.invalid'
    & git -C $projectRoot config user.name 'Replay Test'
    & git -C $projectRoot add requirements.md docs/context.md
    & git -C $projectRoot commit -m 'test fixture' -q

    $configPath = Join-Path $tempRoot 'config.yaml'
    @"
project_root: .
feature_name: example-feature
requirement_source: requirements.md
base_commit: HEAD
oracle_branch: main
oracle_commit: HEAD
replay_root_base: .\replay-evidence\example-feature\replay-v000
run_label: v706
target_coverage: 90
max_rounds: 1
control_cycle_rounds: 1
control_max_cycles: 1
control_run_evolution: false
control_use_latest_knowledge_version: true
executor: manual
require_executor: manual
allow_codex_executor: false
codex_sandbox: danger-full-access
codex_approval: never
system_context_dir: .\docs
phase1_max_slices: 1
skill_source_root: .\agents\skills
knowledge_repo: $knowledgeRoot
knowledge_backup_auto_sync: false
knowledge_backup_auto_push: false
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

    Push-Location $projectRoot
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'Run-UnattendedReplayControl.ps1') `
            -ConfigPath $configPath `
            -CycleRounds 1 `
            -MaxCycles 1 `
            -UseLatestKnowledgeVersion `
            -NoExecute *> (Join-Path $tempRoot 'control.out')
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $stderrFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'replay-evidence\_control-runs') -Recurse -File -Filter 'cycle-*.stderr.log' -ErrorAction SilentlyContinue)
    $stderrText = (($stderrFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n")
    Assert-True ($stderrText -notmatch 'No knowledge version found under .*replay-autopilot') 'child replay loop must not resolve knowledge_repo relative to replay-autopilot script root'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot 'replay-evidence\example-feature\replay-v000-r01')) 'child replay loop should pass knowledge version discovery and create the round root before unrelated fixture limits can stop it'

    Write-Host ''
    Write-Host 'v706 Unattended Control Effective Config Root: PASS'
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
