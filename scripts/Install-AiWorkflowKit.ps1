param(
    [string]$AgentsHome = (Join-Path $HOME '.agents'),
    [string]$CodexHome = (Join-Path $HOME '.codex'),
    [string]$ClaudeHome = (Join-Path $HOME '.claude'),
    [string]$ReplayAutopilotRoot = (Join-Path $HOME '.ai-workflow-control-kit\replay-autopilot'),
    [string]$ClaimProjectRoot = '',
    [string]$KnowledgeRepo = '.',
    [switch]$BackupExisting,
    [switch]$DryRun,
    [switch]$SkipCcSwitchConfig
)

$ErrorActionPreference = 'Stop'

function Resolve-Root {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-Step {
    param([string]$Message)
    Write-Host "[workflow-kit] $Message"
}

function Convert-ToSlashPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function Convert-ToEscapedBackslashPath {
    param([string]$Path)
    return ($Path -replace '\\', '\\')
}

function Get-PlaceholderMap {
    return @{
        '<USERPROFILE>' = $HOME
        '<USERPROFILE_SLASH>' = Convert-ToSlashPath $HOME
        '<USERPROFILE_ESCAPED>' = Convert-ToEscapedBackslashPath $HOME
        '<AGENTS_HOME>' = $AgentsHome
        '<AGENTS_HOME_SLASH>' = Convert-ToSlashPath $AgentsHome
        '<CODEX_HOME>' = $CodexHome
        '<CODEX_HOME_SLASH>' = Convert-ToSlashPath $CodexHome
        '<CLAUDE_HOME>' = $ClaudeHome
        '<CLAUDE_HOME_SLASH>' = Convert-ToSlashPath $ClaudeHome
        '<CLAIM_PROJECT_ROOT>' = $ClaimProjectRoot
        '<CLAIM_PROJECT_ROOT_SLASH>' = Convert-ToSlashPath $ClaimProjectRoot
        '<KNOWLEDGE_REPO>' = $KnowledgeRepo
        '<KNOWLEDGE_REPO_SLASH>' = Convert-ToSlashPath $KnowledgeRepo
        '<REPLAY_AUTOPILOT_ROOT>' = $ReplayAutopilotRoot
        '<REPLAY_AUTOPILOT_ROOT_SLASH>' = Convert-ToSlashPath $ReplayAutopilotRoot
    }
}

function Expand-TemplateText {
    param([string]$Text)
    $expanded = $Text
    foreach ($entry in (Get-PlaceholderMap).GetEnumerator()) {
        $expanded = $expanded.Replace($entry.Key, $entry.Value)
    }
    return $expanded
}

function Test-TextTemplateFile {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return $ext -in @('.cmd', '.json', '.md', '.ps1', '.rules', '.toml', '.txt', '.yaml', '.yml')
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Text
    )
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Expand-PlaceholdersInFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-TextTemplateFile -Path $Path)) { return }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $expanded = Expand-TemplateText -Text $text
    if ($expanded -ne $text) {
        Write-Step "Expand placeholders in $Path"
        if (-not $DryRun) {
            Write-Utf8NoBom -Path $Path -Text $expanded
        }
    }
}

function Backup-Path {
    param(
        [string]$Path,
        [switch]$PassThru
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not $BackupExisting) {
        throw "Target exists and -BackupExisting was not supplied: $Path"
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path.backup-$stamp"
    Write-Step "Backup $Path -> $backup"
    if (-not $DryRun) {
        Move-Item -LiteralPath $Path -Destination $backup
    }
    if ($PassThru) {
        return $backup
    }
}

function Copy-Tree {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Replace,
        [switch]$PreserveSystemSkills
    )
    if (-not (Test-Path -LiteralPath $Source)) { return }
    $backup = $null
    $restoreSystemSkills = $PreserveSystemSkills -and (Test-Path -LiteralPath (Join-Path $Destination '.system'))
    if ($Replace -and (Test-Path -LiteralPath $Destination)) {
        $backup = Backup-Path -Path $Destination -PassThru
    }
    Write-Step "Copy $Source -> $Destination"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
        if ($restoreSystemSkills -and $backup) {
            $systemBackup = Join-Path $backup '.system'
            $systemDestination = Join-Path $Destination '.system'
            if (Test-Path -LiteralPath $systemBackup) {
                Write-Step "Restore Codex runtime system skills $systemBackup -> $systemDestination"
                Copy-Item -LiteralPath $systemBackup -Destination $systemDestination -Recurse -Force
            }
        }
    }
}

function Copy-File {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Replace
    )
    if (-not (Test-Path -LiteralPath $Source)) { return }
    if ($Replace -and (Test-Path -LiteralPath $Destination)) {
        Backup-Path -Path $Destination
    }
    Write-Step "Copy $Source -> $Destination"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        if (Test-TextTemplateFile -Path $Source) {
            $text = Get-Content -LiteralPath $Source -Raw -Encoding UTF8
            Write-Utf8NoBom -Path $Destination -Text (Expand-TemplateText -Text $text)
        } else {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
        }
    }
}

function Test-LinkTarget {
    param(
        [string]$Path,
        [string]$Target
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.LinkType -or -not $item.Target) { return $false }

    $expected = if (Test-Path -LiteralPath $Target) {
        (Resolve-Path -LiteralPath $Target).Path
    } else {
        $Target
    }
    foreach ($actualTarget in @($item.Target)) {
        $actual = if (Test-Path -LiteralPath $actualTarget) {
            (Resolve-Path -LiteralPath $actualTarget).Path
        } else {
            $actualTarget
        }
        if ($actual -ieq $expected) { return $true }
    }
    return $false
}

function Link-Directory {
    param(
        [string]$Target,
        [string]$Destination,
        [switch]$Replace
    )
    if (-not (Test-Path -LiteralPath $Target)) {
        throw "Link target does not exist: $Target"
    }
    if (Test-LinkTarget -Path $Destination -Target $Target) {
        Write-Step "Link already exists $Destination -> $Target"
        return
    }
    if ($Replace -and (Test-Path -LiteralPath $Destination)) {
        Backup-Path -Path $Destination
    }
    if ((Test-Path -LiteralPath $Destination) -and -not $Replace) {
        throw "Target exists and -BackupExisting was not supplied: $Destination"
    }

    Write-Step "Link $Destination -> $Target"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        try {
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Target -Force | Out-Null
        } catch {
            New-Item -ItemType Junction -Path $Destination -Target $Target -Force | Out-Null
        }
    }
}

function Disable-LegacyCodexHooksJson {
    param([string]$CodexHomePath)

    $legacyHooks = Join-Path $CodexHomePath 'hooks.json'
    if (-not (Test-Path -LiteralPath $legacyHooks)) { return }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $disabled = "$legacyHooks.disabled-$stamp"
    Write-Step "Disable legacy Codex hooks.json -> $disabled"
    if (-not $DryRun) {
        Move-Item -LiteralPath $legacyHooks -Destination $disabled
    }
}

$repo = Resolve-Root
Write-Step "Repository: $repo"
if ($DryRun) { Write-Step 'DryRun enabled; no files will be written.' }

# .agents
Copy-File "$repo\agents\AGENTS.md" "$AgentsHome\AGENTS.md" -Replace
Copy-File "$repo\agents\.skill-lock.json" "$AgentsHome\.skill-lock.json" -Replace
Copy-Tree "$repo\agents\hooks" "$AgentsHome\hooks" -Replace
Copy-Tree "$repo\agents\skills" "$AgentsHome\skills" -Replace -PreserveSystemSkills
Copy-Tree "$repo\agents\templates" "$AgentsHome\templates" -Replace

# .codex
Copy-File "$repo\codex\AGENTS.md" "$CodexHome\AGENTS.md" -Replace
Copy-File "$repo\codex\RTK.md" "$CodexHome\RTK.md" -Replace
Copy-File "$repo\codex\skill-rules.json" "$CodexHome\skill-rules.json" -Replace
Copy-Tree "$repo\codex\hooks" "$CodexHome\hooks" -Replace
Disable-LegacyCodexHooksJson -CodexHomePath $CodexHome
Copy-Tree "$repo\codex\rules" "$CodexHome\rules" -Replace
Link-Directory "$AgentsHome\skills" "$CodexHome\skills" -Replace
if (-not (Test-Path -LiteralPath "$CodexHome\config.toml") -and (Test-Path -LiteralPath "$repo\codex\config.toml.example")) {
    Copy-File "$repo\codex\config.toml.example" "$CodexHome\config.toml"
} else {
    Write-Step "Skip Codex config.toml; merge manually from codex/config.toml.example"
}

# .claude
Copy-File "$repo\claude\config.json" "$ClaudeHome\config.json" -Replace
Copy-Tree "$repo\claude\agents" "$ClaudeHome\agents" -Replace
Copy-Tree "$repo\claude\commands" "$ClaudeHome\commands" -Replace
Copy-Tree "$repo\claude\hooks" "$ClaudeHome\hooks" -Replace
Copy-Tree "$repo\claude\rules" "$ClaudeHome\rules" -Replace
Link-Directory "$AgentsHome\skills" "$ClaudeHome\skills" -Replace
Copy-Tree "$repo\claude\templates" "$ClaudeHome\templates" -Replace
Copy-Tree "$repo\claude\output-styles" "$ClaudeHome\output-styles" -Replace
if (-not (Test-Path -LiteralPath "$ClaudeHome\settings.json") -and (Test-Path -LiteralPath "$repo\claude\settings.example.json")) {
    Copy-File "$repo\claude\settings.example.json" "$ClaudeHome\settings.json"
} else {
    Write-Step "Skip Claude settings.json; merge manually from claude/settings.example.json"
}

# cc-switch common config
$ccSwitchDb = Join-Path (Join-Path $HOME '.cc-switch') 'cc-switch.db'
$ccSwitchInstaller = Join-Path $repo 'scripts\Install-CcSwitchCommonConfig.ps1'
if ($SkipCcSwitchConfig) {
    Write-Step 'Skip cc-switch common config by request.'
} elseif ((Test-Path -LiteralPath $ccSwitchDb) -and (Test-Path -LiteralPath $ccSwitchInstaller) -and ($BackupExisting -or $DryRun)) {
    Write-Step 'Apply cc-switch common config from templates.'
    $ccArgs = @(
        '-CcSwitchHome', (Join-Path $HOME '.cc-switch')
    )
    if (-not [string]::IsNullOrWhiteSpace($ClaimProjectRoot)) {
        $ccArgs += @('-ClaimProjectRoot', $ClaimProjectRoot)
    }
    if ($BackupExisting) { $ccArgs += '-BackupExisting' }
    if ($DryRun) { $ccArgs += '-DryRun' }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ccSwitchInstaller @ccArgs
} elseif (Test-Path -LiteralPath $ccSwitchDb) {
    Write-Step 'Skip cc-switch common config; pass -BackupExisting to update cc-switch.db with a backup.'
} else {
    Write-Step 'Skip cc-switch common config; cc-switch.db was not found.'
}

# Replay autopilot
Copy-Tree "$repo\replay-autopilot" $ReplayAutopilotRoot -Replace
Expand-PlaceholdersInFile (Join-Path $ReplayAutopilotRoot 'config.yaml')

Write-Step 'Install completed.'
Write-Step 'Manual step: restore auth tokens and credential placeholders from your password manager, not from this repo.'
