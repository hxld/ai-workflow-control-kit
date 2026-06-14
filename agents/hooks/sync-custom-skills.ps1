param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-SanitizedJsonObject {
    param([string]$Path)

    $raw = Get-Content -Path $Path -Encoding UTF8 -Raw
    $sanitized = [regex]::Replace($raw, ',(\s*[}\]])', '$1')
    return $sanitized | ConvertFrom-Json
}

function Get-SkillNames {
    param([string]$RulesPath)

    if (-not (Test-Path -LiteralPath $RulesPath)) {
        throw "Rules file not found: $RulesPath"
    }

    $rules = Get-SanitizedJsonObject -Path $RulesPath
    return $rules.skills.PSObject.Properties.Name | Sort-Object
}

function New-Result {
    param(
        [string]$Platform,
        [string]$Skill,
        [string]$Status,
        [string]$Message
    )

    return [pscustomobject]@{
        platform = $Platform
        skill = $Skill
        status = $Status
        message = $Message
    }
}

function Ensure-Junction {
    param(
        [string]$Platform,
        [string]$Skill,
        [string]$TargetPath,
        [string]$SourcePath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return New-Result -Platform $Platform -Skill $Skill -Status "missing_source" -Message "Source missing: $SourcePath"
    }

    if (Test-Path -LiteralPath $TargetPath) {
        $item = Get-Item -LiteralPath $TargetPath -Force
        if ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink") {
            return New-Result -Platform $Platform -Skill $Skill -Status "already_linked" -Message "Link already exists: $TargetPath"
        }

        return New-Result -Platform $Platform -Skill $Skill -Status "existing_directory" -Message "Existing directory retained: $TargetPath"
    }

    New-Item -ItemType Junction -Path $TargetPath -Target $SourcePath | Out-Null
    return New-Result -Platform $Platform -Skill $Skill -Status "created" -Message "Created junction: $TargetPath"
}

function Sync-RulesMirror {
    param(
        [string]$SourceRulesPath,
        [string]$MirrorPath
    )

    Ensure-Directory -Path (Split-Path -Parent $MirrorPath)
    Copy-Item -LiteralPath $SourceRulesPath -Destination $MirrorPath -Force
}

function Sync-DirectoryMirror {
    param(
        [string]$SourcePath,
        [string]$TargetPath
    )

    Ensure-Directory -Path (Split-Path -Parent $TargetPath)
    Ensure-Directory -Path $TargetPath

    $null = robocopy $SourcePath $TargetPath /MIR /NFL /NDL /NJH /NJS /NP
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) {
        throw "robocopy failed: source=$SourcePath target=$TargetPath exitCode=$exitCode"
    }
}

function Sync-BackupMirrorSkill {
    param(
        [string]$Skill,
        [string]$SourcePath,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return New-Result -Platform "backup" -Skill $Skill -Status "missing_source" -Message "Source missing: $SourcePath"
    }

    $targetPath = Join-Path $BackupRoot $Skill
    Sync-DirectoryMirror -SourcePath $SourcePath -TargetPath $targetPath
    return New-Result -Platform "backup" -Skill $Skill -Status "mirrored" -Message "Mirrored to backup: $targetPath"
}

function Get-KnowledgeBackupRoot {
    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($env:AI_WORKFLOW_KNOWLEDGE_ROOT)) {
        $candidates += $env:AI_WORKFLOW_KNOWLEDGE_ROOT
    }

    $scriptParent = Split-Path -Parent $PSScriptRoot
    if (-not [string]::IsNullOrWhiteSpace($scriptParent)) {
        $candidates += $scriptParent
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $guidePath = Join-Path $candidate "custom-skills-guide.md"
        $rulesDir = Join-Path $candidate "rules"
        if ((Test-Path -LiteralPath $guidePath) -and (Test-Path -LiteralPath $rulesDir)) {
            return $candidate
        }
    }

    return $null
}

$userHome = $env:USERPROFILE
$rulesPath = Join-Path $userHome ".agents\skills\skill-rules.json"
$agentsSkillsRoot = Join-Path $userHome ".agents\skills"
$platformTargets = @(
    @{ name = "claude"; root = (Join-Path $userHome ".claude\skills") },
    @{ name = "cursor"; root = (Join-Path $userHome ".cursor\skills") },
    @{ name = "opencode"; root = (Join-Path $userHome ".config\opencode\skills\custom") },
    @{ name = "codex"; root = (Join-Path $userHome ".codex\skills") }
)
$backupMirrorName = "custom-skills-zh"
$knowledgeBackupRoot = Get-KnowledgeBackupRoot
$backupMirrorRoot = if ($null -ne $knowledgeBackupRoot) { Join-Path $knowledgeBackupRoot $backupMirrorName } else { $null }
$rulesMirrors = @(
    (Join-Path $userHome ".claude\skills\skill-rules.json"),
    (Join-Path $userHome ".cursor\hooks\skill-rules.json"),
    (Join-Path $userHome ".codex\skill-rules.json")
)
if ($null -ne $knowledgeBackupRoot) {
    $rulesMirrors = @(
        (Join-Path $backupMirrorRoot "skill-rules.json"),
        (Join-Path $knowledgeBackupRoot "rules\skill-rules.json")
    ) + $rulesMirrors
}

Ensure-Directory -Path $agentsSkillsRoot

$portabilityScript = Join-Path $PSScriptRoot "check-skills-portability.ps1"
if (Test-Path -LiteralPath $portabilityScript) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $portabilityScript -SkillsRoot $agentsSkillsRoot
    if ($LASTEXITCODE -ne 0) {
        throw "check-skills-portability.ps1 failed (exit $LASTEXITCODE). Fix SKILL.md portability violations before sync."
    }
}
else {
    Write-Warning "check-skills-portability.ps1 not found next to sync script; skipping portability gate."
}

foreach ($target in $platformTargets) {
    Ensure-Directory -Path $target.root
}

$skillNames = Get-SkillNames -RulesPath $rulesPath
$results = @()

foreach ($skillName in $skillNames) {
    $sourcePath = Join-Path $agentsSkillsRoot $skillName
    foreach ($target in $platformTargets) {
        $targetPath = Join-Path $target.root $skillName
        $results += Ensure-Junction -Platform $target.name -Skill $skillName -TargetPath $targetPath -SourcePath $sourcePath
    }
    if ($null -ne $backupMirrorRoot) {
        $results += Sync-BackupMirrorSkill -Skill $skillName -SourcePath $sourcePath -BackupRoot $backupMirrorRoot
    }
}

foreach ($mirror in $rulesMirrors) {
    Sync-RulesMirror -SourceRulesPath $rulesPath -MirrorPath $mirror
}

$created = @($results | Where-Object { $_.status -eq "created" }).Count
$linked = @($results | Where-Object { $_.status -eq "already_linked" }).Count
$mirrored = @($results | Where-Object { $_.status -eq "mirrored" }).Count
$warnings = @($results | Where-Object { $_.status -eq "existing_directory" -or $_.status -eq "missing_source" })

Write-Output "SYNC COMPLETE"
Write-Output "skills=$($skillNames.Count)"
Write-Output "created=$created"
Write-Output "already_linked=$linked"
Write-Output "backup_mirrored=$mirrored"
Write-Output "mirrors=$($rulesMirrors.Count)"

if ($warnings.Count -gt 0) {
    Write-Output "WARNINGS:"
    foreach ($warning in $warnings) {
        Write-Output "- [$($warning.platform)] $($warning.skill): $($warning.message)"
    }
}
