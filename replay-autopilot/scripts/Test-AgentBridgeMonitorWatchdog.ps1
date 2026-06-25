param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Set-State {
    param(
        [string]$Path,
        [string]$Status,
        [int]$Cycle
    )
    $state = Read-JsonFile -Path $Path
    $state.status = $Status
    $state.cycle = $Cycle
    $state.updated_at = (Get-Date).AddMinutes(-10).ToUniversalTime().ToString('o')
    Write-JsonFile -Path $Path -Value $state
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridgeScript = Join-Path $scriptRoot 'Start-AgentBridge.ps1'
$monitorScript = Join-Path $scriptRoot 'Start-AgentBridgeMonitor.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-bridge-monitor-watchdog-{0}' -f ([guid]::NewGuid().ToString('N')))
$bridgeRoot = Join-Path $tempRoot 'current'
$archiveRoot = Join-Path $tempRoot 'runs'
$reportRoot = Join-Path $tempRoot 'monitor'
$promptPath = Join-Path $tempRoot 'initial.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        bridge_script = $bridgeScript
        monitor_script = $monitorScript
        temp_root = $tempRoot
        default_executor = ((& powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript -BridgeRoot $bridgeRoot -ArchiveRoot $archiveRoot -ReportRoot $reportRoot -ValidateOnly | ConvertFrom-Json).executor)
    } | ConvertTo-Json -Depth 6
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Set-Content -LiteralPath $promptPath -Value 'Run one bridge step.' -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $promptPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Init should succeed'

    $statePath = Join-Path $bridgeRoot 'STATE.json'

    $monitorValidate = & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -ValidateOnly | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'Monitor ValidateOnly should succeed'
    Assert-True ($monitorValidate.executor -eq 'codex') 'Monitor should default to codex executor'
    Assert-True ($monitorValidate.bridge_primary_executor -eq 'codex') 'Monitor bridge primary executor should default to codex'
    Assert-True ($monitorValidate.bridge_review_executor -eq 'codex') 'Monitor bridge review executor should default to codex'

    $monitorCodexOnly = & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -Executor claude `
        -BridgePrimaryExecutor claude `
        -BridgeReviewExecutor claude `
        -CodexOnly `
        -ValidateOnly | ConvertFrom-Json
    Assert-True ($LASTEXITCODE -eq 0) 'Monitor CodexOnly ValidateOnly should succeed'
    Assert-True ($monitorCodexOnly.executor -eq 'codex') 'CodexOnly should force monitor executor to codex'
    Assert-True ($monitorCodexOnly.bridge_primary_executor -eq 'codex') 'CodexOnly should force bridge primary executor to codex'
    Assert-True ($monitorCodexOnly.bridge_review_executor -eq 'codex') 'CodexOnly should force bridge review executor to codex'

    # Case 1: stale primary done state is auto-advanced into review.
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_RESULT.md') -Value '# Claude result' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_DONE.flag') -Value 'done' -Encoding UTF8
    New-Item -ItemType File -Force -Path (Join-Path $bridgeRoot 'LOCK') | Out-Null
    Set-State -Path $statePath -Status 'CLAUDE_RUNNING' -Cycle 1

    & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -Executor none `
        -Once `
        -AutoAdvanceStaleDone `
        -AutoAdvanceStaleMinutes 0 `
        -ProtectedGitRoots $tempRoot `
        -NoAutoRestartRunLoop | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Monitor primary auto-advance should succeed'
    $state1 = Read-JsonFile -Path $statePath
    Assert-True ($state1.status -eq 'WAITING_CODEX_REVIEW') 'Primary auto-advance should set WAITING_CODEX_REVIEW'
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_REVIEW_PROMPT.md') -Raw -Encoding UTF8) -match 'DECISION.json') 'Review prompt should be prepared'

    # Case 2: stale review done state is auto-advanced into the next primary cycle.
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_REVIEW.md') -Value '# Codex review' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'NEXT_CLAUDE_PROMPT.md') -Value 'Continue next step.' -Encoding UTF8
    [ordered]@{
        decision = 'CONTINUE'
        reason = 'more work'
        next_actor = 'primary'
        coverage_signal = ''
        blocker = ''
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $bridgeRoot 'DECISION.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_DONE.flag') -Value 'done' -Encoding UTF8
    New-Item -ItemType File -Force -Path (Join-Path $bridgeRoot 'LOCK') | Out-Null
    Set-State -Path $statePath -Status 'CODEX_REVIEWING' -Cycle 1

    & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -Executor none `
        -Once `
        -AutoAdvanceStaleDone `
        -AutoAdvanceStaleMinutes 0 `
        -ProtectedGitRoots $tempRoot `
        -NoAutoRestartRunLoop | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Monitor review auto-advance should succeed'
    $state2 = Read-JsonFile -Path $statePath
    Assert-True ($state2.status -eq 'WAITING_CLAUDE') 'Review auto-advance should set WAITING_CLAUDE'
    Assert-True ([int]$state2.cycle -eq 2) 'Review CONTINUE should increment cycle'
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_PROMPT.md') -Raw -Encoding UTF8) -match 'Continue next step') 'Next primary prompt should be installed'

    $watchdogFiles = @(Get-ChildItem -LiteralPath $reportRoot -Filter 'watchdog-auto-advance-*.json')
    Assert-True ($watchdogFiles.Count -ge 2) 'Watchdog should write auto-advance evidence files'

    # Case 3: protected-root dirtiness stops the bridge and writes evidence.
    $protectedRoot = Join-Path $tempRoot 'protected-root'
    New-Item -ItemType Directory -Force -Path $protectedRoot | Out-Null
    & git -C $protectedRoot init | Out-Null
    Set-Content -LiteralPath (Join-Path $protectedRoot 'pollution.txt') -Value 'dirty' -Encoding UTF8
    Set-State -Path $statePath -Status 'CLAUDE_RUNNING' -Cycle 2

    & powershell -NoProfile -ExecutionPolicy Bypass -File $monitorScript `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ReportRoot $reportRoot `
        -Executor none `
        -Once `
        -ProtectedGitRoots $protectedRoot `
        -NoAutoRestartRunLoop | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Monitor protected-root watchdog should succeed'
    $state3 = Read-JsonFile -Path $statePath
    Assert-True ($state3.status -eq 'STOPPED') 'Protected root violation should stop the bridge'
    $violationDirs = @(Get-ChildItem -LiteralPath $reportRoot -Directory -Filter 'protected-root-violation-*')
    Assert-True ($violationDirs.Count -ge 1) 'Protected root violation evidence should be written'

    [ordered]@{
        status = 'PASS'
        assertions = 17
        cases = @(
            'monitor_defaults_to_codex',
            'codex_only_forces_monitor_and_bridge_executors',
            'stale_primary_done_advances_to_review',
            'stale_review_done_advances_to_next_primary',
            'watchdog_writes_evidence',
            'protected_root_dirty_stops_bridge'
        )
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 8
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolved = Resolve-AbsolutePath $tempRoot
        $tempBase = Resolve-AbsolutePath ([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refuse to delete temp outside temp root: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
