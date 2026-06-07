param(
    [string]$AgentsHome = (Join-Path $HOME '.agents'),
    [string]$CodexHome = (Join-Path $HOME '.codex'),
    [string]$ClaudeHome = (Join-Path $HOME '.claude'),
    [string]$ReplayAutopilotRoot = (Join-Path $HOME '.ai-workflow-control-kit\replay-autopilot')
)

$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:Warnings = 0

function Write-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail = '',
        [switch]$Warning
    )

    $prefix = if ($Ok) { 'PASS' } elseif ($Warning) { 'WARN' } else { 'FAIL' }
    $message = if ([string]::IsNullOrWhiteSpace($Detail)) { "$prefix $Name" } else { "$prefix $Name - $Detail" }
    Write-Host $message

    if ($Warning -and -not $Ok) { $script:Warnings++ }
    if (-not $Warning -and -not $Ok) { $script:Failures++ }
}

function Test-CommandAvailable {
    param(
        [string]$Name,
        [switch]$Required
    )
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Required) {
        Write-Check "command:$Name" ([bool]$cmd) 'required'
    } else {
        Write-Check "command:$Name" ([bool]$cmd) 'recommended' -Warning
    }
}

function Test-PathExists {
    param([string]$Name, [string]$Path)
    Write-Check $Name (Test-Path -LiteralPath $Path) $Path
}

function Test-DirectoryLink {
    param([string]$Name, [string]$Path, [string]$Target)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Check $Name $false "missing: $Path"
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.LinkType -or -not $item.Target) {
        Write-Check $Name $false "not a link: $Path"
        return
    }

    $expected = if (Test-Path -LiteralPath $Target) { (Resolve-Path -LiteralPath $Target).Path } else { $Target }
    $ok = $false
    foreach ($actualTarget in @($item.Target)) {
        $actual = if (Test-Path -LiteralPath $actualTarget) { (Resolve-Path -LiteralPath $actualTarget).Path } else { $actualTarget }
        if ($actual -ieq $expected) { $ok = $true }
    }

    Write-Check $Name $ok "$Path -> $($item.Target)"
}

Test-CommandAvailable powershell -Required
Test-CommandAvailable git -Required
Test-CommandAvailable node -Required
Test-CommandAvailable python
Test-CommandAvailable rtk

$agentsSkills = Join-Path $AgentsHome 'skills'
Test-PathExists 'agents:skills' $agentsSkills
Test-PathExists 'agents:skill-rules' (Join-Path $agentsSkills 'skill-rules.json')
Test-PathExists 'agents:hooks' (Join-Path $AgentsHome 'hooks')
Test-PathExists 'agents:skill-receipt-hook' (Join-Path $AgentsHome 'hooks\skill-execution-receipt.js')
Test-PathExists 'agents:workflow-sync-hook' (Join-Path $AgentsHome 'hooks\workflow-sync-state.js')

Test-PathExists 'codex:AGENTS' (Join-Path $CodexHome 'AGENTS.md')
Test-PathExists 'codex:RTK' (Join-Path $CodexHome 'RTK.md')
Test-PathExists 'codex:skill-rules' (Join-Path $CodexHome 'skill-rules.json')
Test-PathExists 'codex:hook-scripts' (Join-Path $CodexHome 'hooks\scripts')
Test-DirectoryLink 'codex:skills-link' (Join-Path $CodexHome 'skills') $agentsSkills

$legacyCodexHooks = Join-Path $CodexHome 'hooks.json'
Write-Check 'codex:no-active-hooks-json' (-not (Test-Path -LiteralPath $legacyCodexHooks)) $legacyCodexHooks

Test-PathExists 'claude:config' (Join-Path $ClaudeHome 'config.json')
Test-PathExists 'claude:hooks' (Join-Path $ClaudeHome 'hooks')
Test-PathExists 'claude:skill-activation-hook' (Join-Path $ClaudeHome 'hooks\skill-activation-prompt.ps1')
Test-DirectoryLink 'claude:skills-link' (Join-Path $ClaudeHome 'skills') $agentsSkills

$replayControl = Join-Path $ReplayAutopilotRoot 'scripts\Run-UnattendedReplayControl.ps1'
Test-PathExists 'replay:control-script' $replayControl
if (Test-Path -LiteralPath $replayControl) {
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $replayControl -ValidateOnly 2>&1
        $ok = ($LASTEXITCODE -eq 0) -and (($output | Out-String) -match '"status"\s*:\s*"VALID"')
        Write-Check 'replay:validate-only' $ok (($output | Out-String).Trim())
    } catch {
        Write-Check 'replay:validate-only' $false $_.Exception.Message
    }
}

if ($script:Failures -gt 0) {
    Write-Host "Verification failed with $script:Failures failure(s) and $script:Warnings warning(s)."
    exit 1
}

Write-Host "Verification passed with $script:Warnings warning(s)."
