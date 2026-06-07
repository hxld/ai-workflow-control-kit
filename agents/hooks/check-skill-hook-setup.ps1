param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Test-AbsolutePathString {
    param([string]$Value)

    return $Value -match '[A-Za-z]:[\\/]'
}

function New-Keyword {
    param([int[]]$Codes)

    return (-join ($Codes | ForEach-Object { [char]$_ }))
}

function Add-CheckResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$Name,
        [bool]$Passed,
        [string]$Details
    )

    $Results.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Details = $Details
    })
}

function Get-JsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $raw = Get-Content -Path $Path -Encoding UTF8 -Raw
    $sanitized = [regex]::Replace($raw, ',(\s*[}\]])', '$1')
    return $sanitized | ConvertFrom-Json
}

function Test-StrictJsonFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $raw = Get-Content -Path $Path -Encoding UTF8 -Raw
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-NodeCheckFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $node) {
        return $false
    }

    try {
        $null = & $node.Source --check $Path 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-HookCommandText {
    param($HookEntries)

    $commands = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($HookEntries)) {
        if ($null -eq $entry) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$entry.command)) {
            [void]$commands.Add([string]$entry.command)
        }

        foreach ($hook in @($entry.hooks)) {
            if ($null -ne $hook -and -not [string]::IsNullOrWhiteSpace([string]$hook.command)) {
                [void]$commands.Add([string]$hook.command)
            }
        }
    }

    return ($commands -join "`n")
}

$userHome = $env:USERPROFILE
$results = New-Object System.Collections.Generic.List[object]

$paths = @{
    AgentRules = Join-Path $userHome ".agents\skills\skill-rules.json"
    WorkflowSyncState = Join-Path $userHome ".agents\hooks\workflow-sync-state.js"
    SkillHooksDashboard = Join-Path $userHome ".agents\hooks\skill-hooks-dashboard.js"
    SkillExecutionReceipt = Join-Path $userHome ".agents\hooks\skill-execution-receipt.js"
    ClaudeSettings = Join-Path $userHome ".claude\settings.json"
    ClaudePromptHook = Join-Path $userHome ".claude\hooks\skill-activation-prompt.ps1"
    ClaudeTracker = Join-Path $userHome ".claude\hooks\scripts\skill-tracker.js"
    CursorHooks = Join-Path $userHome ".cursor\hooks.json"
    CursorPromptHook = Join-Path $userHome ".cursor\hooks\skill-activation-cursor.ps1"
    CursorRSU = Join-Path $userHome ".cursor\hooks\scripts\cursor-rsu.js"
    CursorTracker = Join-Path $userHome ".cursor\hooks\scripts\skill-tracker.js"
    OpenCodeConfig = Join-Path $userHome ".config\opencode\opencode.json"
    OpenCodePlugin = Join-Path $userHome ".config\opencode\plugins\skill-activation\index.ts"
    ClaudeSkillsRoot = Join-Path $userHome ".claude\skills"
    CursorSkillsRoot = Join-Path $userHome ".cursor\skills"
    OpenCodeSkillsRoot = Join-Path $userHome ".config\opencode\skills\custom"
}

$codexPaths = @{
    CodexHome = Join-Path $userHome ".codex"
    CodexConfig = Join-Path $userHome ".codex\config.toml"
    CodexRules = Join-Path $userHome ".codex\skill-rules.json"
    CodexSkillsRoot = Join-Path $userHome ".codex\skills"
    CodexSystemSkillsRoot = Join-Path $userHome ".codex\skills\.system"
    CodexAdapter = Join-Path $userHome ".agents\hooks\codex-skill-adapter.ps1"
    CcSwitchSettings = Join-Path $userHome ".cc-switch\settings.json"
}

foreach ($entry in $paths.GetEnumerator()) {
    Add-CheckResult -Results $results -Name $entry.Key -Passed (Test-Path $entry.Value) -Details $entry.Value
}

Add-CheckResult -Results $results -Name "WorkflowSyncStateNodeCheck" -Passed (Test-NodeCheckFile -Path $paths.WorkflowSyncState) -Details $paths.WorkflowSyncState
Add-CheckResult -Results $results -Name "SkillHooksDashboardNodeCheck" -Passed (Test-NodeCheckFile -Path $paths.SkillHooksDashboard) -Details $paths.SkillHooksDashboard
Add-CheckResult -Results $results -Name "SkillExecutionReceiptNodeCheck" -Passed (Test-NodeCheckFile -Path $paths.SkillExecutionReceipt) -Details $paths.SkillExecutionReceipt

$codexInstalled = Test-Path $codexPaths.CodexHome
Add-CheckResult -Results $results -Name "CodexHomeOptional" -Passed $true -Details (
    $(if ($codexInstalled) { $codexPaths.CodexHome } else { "not installed, skipped" })
)

if ($codexInstalled) {
    Add-CheckResult -Results $results -Name "CodexConfig" -Passed (Test-Path $codexPaths.CodexConfig) -Details $codexPaths.CodexConfig
    Add-CheckResult -Results $results -Name "CodexRules" -Passed (Test-Path $codexPaths.CodexRules) -Details $codexPaths.CodexRules
    Add-CheckResult -Results $results -Name "CodexSkillsRoot" -Passed (Test-Path $codexPaths.CodexSkillsRoot) -Details $codexPaths.CodexSkillsRoot
    Add-CheckResult -Results $results -Name "CodexSystemSkillsPreserved" -Passed (Test-Path $codexPaths.CodexSystemSkillsRoot) -Details $codexPaths.CodexSystemSkillsRoot
    Add-CheckResult -Results $results -Name "CodexAdapter" -Passed (Test-Path $codexPaths.CodexAdapter) -Details $codexPaths.CodexAdapter
    Add-CheckResult -Results $results -Name "CodexRulesStrictJson" -Passed (Test-StrictJsonFile -Path $codexPaths.CodexRules) -Details $codexPaths.CodexRules

    $codexConfigText = ""
    if (Test-Path $codexPaths.CodexConfig) {
        $codexConfigText = Get-Content -Path $codexPaths.CodexConfig -Encoding UTF8 -Raw
    }

    Add-CheckResult -Results $results -Name "CodexHooksFeatureEnabled" -Passed ($codexConfigText -match '(?m)^\s*hooks\s*=\s*true\s*$') -Details "features.hooks"
    Add-CheckResult -Results $results -Name "CodexUserPromptSubmitHook" -Passed (
        $codexConfigText -match '\[\[hooks\.UserPromptSubmit\]\]' -and
        $codexConfigText -match 'codex-skill-adapter\.ps1'
    ) -Details "hooks.UserPromptSubmit -> codex-skill-adapter.ps1"
    Add-CheckResult -Results $results -Name "CodexStopHook" -Passed (
        $codexConfigText -match '\[\[hooks\.Stop\]\]' -and
        $codexConfigText -match 'skill-execution-receipt\.js'
    ) -Details "hooks.Stop -> skill-execution-receipt.js"
    Add-CheckResult -Results $results -Name "CodexSessionStartHook" -Passed (
        $codexConfigText -match '\[\[hooks\.SessionStart\]\]' -and
        $codexConfigText -match 'workflow-sync-state\.js'
    ) -Details "hooks.SessionStart -> workflow-sync-state.js"
}

$ccSwitchInstalled = Test-Path (Split-Path $codexPaths.CcSwitchSettings -Parent)
Add-CheckResult -Results $results -Name "CcSwitchOptional" -Passed $true -Details (
    $(if ($ccSwitchInstalled) { (Split-Path $codexPaths.CcSwitchSettings -Parent) } else { "not installed, skipped" })
)

if (Test-Path $codexPaths.CcSwitchSettings) {
    $ccSwitchSettings = Get-JsonFile -Path $codexPaths.CcSwitchSettings
    Add-CheckResult -Results $results -Name "CcSwitchCommonConfigConfirmed" -Passed (
        $null -ne $ccSwitchSettings -and $ccSwitchSettings.commonConfigConfirmed -eq $true
    ) -Details $codexPaths.CcSwitchSettings
}

$claudeSettings = Get-JsonFile -Path $paths.ClaudeSettings
if ($null -ne $claudeSettings) {
    $claudeCommand = $claudeSettings.hooks.UserPromptSubmit[0].hooks[0].command
    $claudeFileChangedCommand = $claudeSettings.hooks.FileChanged[0].hooks[0].command
    $claudeStopCommands = Get-HookCommandText -HookEntries $claudeSettings.hooks.Stop
    Add-CheckResult -Results $results -Name "ClaudeSettingsStrictJson" -Passed (Test-StrictJsonFile -Path $paths.ClaudeSettings) -Details $paths.ClaudeSettings
    Add-CheckResult -Results $results -Name "ClaudePromptUsesAbsolutePath" -Passed (Test-AbsolutePathString $claudeCommand) -Details $claudeCommand
    Add-CheckResult -Results $results -Name "ClaudeFileChangedConfigured" -Passed ($claudeFileChangedCommand -match 'workflow-sync-state\.js') -Details $claudeFileChangedCommand
    Add-CheckResult -Results $results -Name "ClaudeStopReceiptHook" -Passed ($claudeStopCommands -match 'skill-execution-receipt\.js') -Details "hooks.Stop -> skill-execution-receipt.js"
}

$cursorHooks = Get-JsonFile -Path $paths.CursorHooks
if ($null -ne $cursorHooks) {
    $cursorBefore = $cursorHooks.hooks.beforeSubmitPrompt[0].command
    $cursorRSU = $cursorHooks.hooks.beforeSubmitPrompt[1].command
    $cursorAfterEdit = $cursorHooks.hooks.afterFileEdit[0].command
    $cursorStopCommands = Get-HookCommandText -HookEntries $cursorHooks.hooks.stop
    Add-CheckResult -Results $results -Name "CursorHooksStrictJson" -Passed (Test-StrictJsonFile -Path $paths.CursorHooks) -Details $paths.CursorHooks
    Add-CheckResult -Results $results -Name "CursorPromptUsesAbsolutePath" -Passed ($cursorBefore -notmatch '\./' -and $cursorBefore -notmatch '~/' ) -Details $cursorBefore
    Add-CheckResult -Results $results -Name "CursorRSUUsesAbsolutePath" -Passed ($cursorRSU -notmatch '\./' -and $cursorRSU -notmatch '~/' ) -Details $cursorRSU
    Add-CheckResult -Results $results -Name "CursorAfterFileEditConfigured" -Passed ($cursorAfterEdit -match 'workflow-sync-state\.js') -Details $cursorAfterEdit
    Add-CheckResult -Results $results -Name "CursorStopReceiptHook" -Passed ($cursorStopCommands -match 'skill-execution-receipt\.js') -Details "hooks.stop -> skill-execution-receipt.js"
}

$opencodeConfig = Get-JsonFile -Path $paths.OpenCodeConfig
if ($null -ne $opencodeConfig) {
    $pluginRegistered = $false
    Add-CheckResult -Results $results -Name "OpenCodeConfigStrictJson" -Passed (Test-StrictJsonFile -Path $paths.OpenCodeConfig) -Details $paths.OpenCodeConfig
    foreach ($plugin in $opencodeConfig.plugin) {
        if ($plugin -eq "./plugins/skill-activation") {
            $pluginRegistered = $true
            break
        }
    }
    Add-CheckResult -Results $results -Name "OpenCodePluginRegistered" -Passed $pluginRegistered -Details "./plugins/skill-activation"
}

$rules = Get-JsonFile -Path $paths.AgentRules
if ($null -ne $rules) {
    $skillNames = $rules.skills.PSObject.Properties.Name
    Add-CheckResult -Results $results -Name "CustomSkillRuleCount" -Passed ($skillNames.Count -ge 27) -Details ("count=" + $skillNames.Count)
    Add-CheckResult -Results $results -Name "ObsidianWikiRulePresent" -Passed ($skillNames -contains "obsidian-wiki") -Details "obsidian-wiki"

    $allKeywords = New-Object System.Collections.Generic.List[string]
    foreach ($skillName in $skillNames) {
        foreach ($keyword in $rules.skills.$skillName.triggers.keywords) {
            [void]$allKeywords.Add([string]$keyword)
        }
    }

    $allowedDuplicateKeywords = @(
        (New-Keyword @(36328,32452,20214,23383,27573,20002,22833)),
        (New-Keyword @(21333,28857,26085,24535,35299,37322,19981,20102))
    )

    $duplicateKeywords = $allKeywords |
        Group-Object { $_.ToLowerInvariant() } |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object { $_.Name } |
        Where-Object { $allowedDuplicateKeywords -notcontains $_ }
    Add-CheckResult -Results $results -Name "NoDuplicateSkillKeywords" -Passed ($duplicateKeywords.Count -eq 0) -Details (
        $(if ($duplicateKeywords.Count -eq 0) { "none" } else { $duplicateKeywords -join ", " })
    )

    $bannedNoisyKeywords = @(
        (New-Keyword @(24110,25105)),
        (New-Keyword @(24635,32467)),
        (New-Keyword @(36827,24230)),
        (New-Keyword @(26085,24535)),
        (New-Keyword @(35843,26597)),
        "review",
        "markdown",
        (New-Keyword @(20195,30721)),
        (New-Keyword @(24320,21457)),
        (New-Keyword @(23454,29616)),
        (New-Keyword @(21151,33021)),
        "log",
        "logs"
    )
    $presentNoisyKeywords = $allKeywords |
        Where-Object { $bannedNoisyKeywords -contains $_ } |
        Sort-Object -Unique
    Add-CheckResult -Results $results -Name "NoBannedNoisyKeywords" -Passed ($presentNoisyKeywords.Count -eq 0) -Details (
        $(if ($presentNoisyKeywords.Count -eq 0) { "none" } else { $presentNoisyKeywords -join ", " })
    )

    $skillLinkPlatforms = @(
        @{ name = "ClaudeSkillLinks"; root = $paths.ClaudeSkillsRoot },
        @{ name = "CursorSkillLinks"; root = $paths.CursorSkillsRoot },
        @{ name = "OpenCodeSkillLinks"; root = $paths.OpenCodeSkillsRoot }
    )
    if (Test-Path $codexPaths.CodexSkillsRoot) {
        $skillLinkPlatforms += @{ name = "CodexSkillLinks"; root = $codexPaths.CodexSkillsRoot }
    }

    foreach ($platform in $skillLinkPlatforms) {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($skillName in $skillNames) {
            $skillPath = Join-Path $platform.root $skillName
            if (-not (Test-Path $skillPath)) {
                [void]$missing.Add($skillName)
            }
        }

        $detailText = "all custom skills available"
        if ($missing.Count -gt 0) {
            $detailText = "missing: " + ($missing -join ", ")
        }

        Add-CheckResult -Results $results -Name $platform.name -Passed ($missing.Count -eq 0) -Details (
            $detailText
        )
    }
}

$failed = @($results | Where-Object { -not $_.Passed })
$passed = @($results | Where-Object { $_.Passed })

Write-Output "HOOK SETUP CHECK"
Write-Output "passed=$($passed.Count)"
Write-Output "failed=$($failed.Count)"

if ($passed.Count -gt 0) {
    Write-Output "PASSED:"
    foreach ($item in $passed) {
        Write-Output "- [OK] $($item.Name): $($item.Details)"
    }
}

if ($failed.Count -gt 0) {
    Write-Output "FAILED:"
    foreach ($item in $failed) {
        Write-Output "- [FAIL] $($item.Name): $($item.Details)"
    }
    Write-Output "SMOKE TESTS:"
    Write-Output "- Claude: send '完整开发人保退票' and check %USERPROFILE%\\.agents\\logs\\skill-hooks.log"
    Write-Output "- Cursor: send '同步进度' and confirm beforeSubmitPrompt has no path error"
    Write-Output "- OpenCode: send '深度规划' and verify system message contains suggestion or block"
    Write-Output "- Codex: confirm config.toml keeps features.hooks + hooks.* after provider switch"
    exit 1
}

exit 0
