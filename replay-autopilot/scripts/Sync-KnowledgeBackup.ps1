param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [string]$ReplayAutopilotRoot = '',
    [string]$KnowledgeRepo = '',
    [string]$EvidenceRoot = '',
    [ValidateSet('None', 'Milestone', 'Always')]
    [string]$EvidenceMode = 'None',
    [switch]$IncludeAutopilot,
    [switch]$IncludeKnowledge,
    [switch]$Push,
    [switch]$ValidateOnly,
    [string]$CommitMessage = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') { throw "Unsupported config line: $line" }
        $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
    return $result
}

function Convert-ToBool {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1', 'true', 'yes', 'y', 'on') -contains $Value.Trim().ToLowerInvariant()
}

function Get-ConfigValueOrDefault {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$DefaultValue = ''
    )
    if ($Config.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($Config[$Key])) {
        return $Config[$Key]
    }
    return $DefaultValue
}

function Resolve-EvidenceRootFromReplayBase {
    param([string]$ReplayRootBase)
    if ([string]::IsNullOrWhiteSpace($ReplayRootBase)) { return '' }
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($ReplayRootBase))
    $grandParent = Split-Path -Parent $parent
    if (-not [string]::IsNullOrWhiteSpace($grandParent) -and (Split-Path -Leaf $grandParent) -ieq 'replay-evidence') {
        return $grandParent
    }
    if ((Split-Path -Leaf $parent) -ieq 'replay-evidence') {
        return $parent
    }
    return $parent
}

function Get-GitRoot {
    param([string]$Path)
    $root = (& git -C $Path rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        throw "Git root not found for path: $Path"
    }
    return (Resolve-AbsolutePath $root.Trim())
}

function Get-GitRelativePath {
    param(
        [string]$GitRoot,
        [string]$Path
    )
    $root = Resolve-AbsolutePath $GitRoot
    $full = Resolve-AbsolutePath $Path
    $prefix = $root.TrimEnd('\') + '\'
    if ($full -ne $root -and -not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside git root. root=$root path=$full"
    }
    return ($full.Substring($root.Length).TrimStart('\') -replace '\\', '/')
}

function Clear-BackupDirectory {
    param(
        [string]$Path,
        [string]$SourcesRoot,
        [string[]]$AllowedLeafNames
    )
    $full = Resolve-AbsolutePath $Path
    $root = (Resolve-AbsolutePath $SourcesRoot).TrimEnd('\') + '\'
    $leaf = Split-Path -Leaf $full
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear path outside sources root: $full"
    }
    if ($AllowedLeafNames -notcontains $leaf) {
        throw "Refusing to clear unexpected backup leaf '$leaf': $full"
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $full | Out-Null
}

function Copy-FilteredTree {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeDirs,
        [string[]]$ExcludeExtensions,
        [string[]]$ExcludeNamePatterns
    )
    $sourceFull = Resolve-AbsolutePath $Source
    $destinationFull = Resolve-AbsolutePath $Destination
    $files = Get-ChildItem -Path $sourceFull -Recurse -File -Force | Where-Object {
        $relative = $_.FullName.Substring($sourceFull.Length).TrimStart('\')
        $parts = $relative -split '\\'
        $dirAllowed = -not ($parts | Where-Object { $ExcludeDirs -contains $_ })
        $extensionAllowed = -not ($ExcludeExtensions -contains $_.Extension.ToLowerInvariant())
        $nameAllowed = $true
        foreach ($pattern in $ExcludeNamePatterns) {
            if ($_.Name -like $pattern) { $nameAllowed = $false; break }
        }
        $dirAllowed -and $extensionAllowed -and $nameAllowed
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceFull.Length).TrimStart('\')
        $target = Join-Path $destinationFull $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
    return @($files).Count
}

function Copy-EvidenceLite {
    param(
        [string]$EvidenceRoot,
        [string]$Destination
    )
    $sourceRoot = Resolve-AbsolutePath $EvidenceRoot
    $destinationFull = Resolve-AbsolutePath $Destination
    $includeNames = @(
        'REPLAY_AUTOPILOT_SESSION_SUMMARY.md',
        'ROUND_RESULT.md',
        'FINAL_REPLAY_REPORT.md',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'EVOLUTION_PROPOSAL.md',
        'EVOLUTION_PROMPT.md',
        'EVOLUTION_RESULT.md',
        'EVOLUTION_RESULT_VERIFY.json',
        'DEEP_REVIEW_REPORT.md',
        'ROOT_CAUSE_LEDGER.json',
        'NEXT_EXPERIMENT_PLAN.md',
        'STOP_LOSS_DECISION.md',
        'STOP_OR_CONTINUE_DECISION.md',
        'CROSS_FEATURE_REPLAY_LEDGER.md',
        'GOLDEN_SAMPLE_LEDGER.json',
        'GOLDEN_SAMPLE_SOP.md',
        'GOLDEN_SAMPLE_PROMPT.md',
        'GOLDEN_SAMPLE_PROMPT_SNAPSHOT.md',
        'GOLDEN_SAMPLE_SUMMARY.md',
        'GOLDEN_SAMPLE_AI_REVIEW.md',
        'EXTERNAL_PRACTICE_RESEARCH_PROMPT.md',
        'EXTERNAL_PRACTICE_RESEARCH.md',
        'EXTERNAL_PRACTICE_SOP.md',
        'EXTERNAL_PRACTICE_SOP_SNAPSHOT.md',
        'EXTERNAL_PRACTICE_DECISION.json',
        'RUN_CONTROL_SUMMARY.md',
        'RUN_CONTROL_SUMMARY.json',
        'BLOCKER_FINGERPRINTS.json',
        'STAGNATION_DECISION.json',
        'RUN_CONTROL_LATEST.md',
        'RUN_CONTROL_LATEST.json',
        'BLOCKER_REGISTRY.json',
        'MORNING_BRIEF.md',
        'GOLDEN_DELIVERY_SLICE.md',
        'GOLDEN_DELIVERY_SLICE.json',
        'GOLDEN_DELIVERY_SLICE_PROMPT.md',
        'NEXT_GOLDEN_DELIVERY_SLICE.md',
        'NEXT_GOLDEN_DELIVERY_SLICE.json',
        'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md'
    )
    $files = New-Object System.Collections.Generic.List[string]
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        $args = @('--files', $sourceRoot)
        foreach ($name in $includeNames) { $args += @('-g', $name) }
        $args += @(
            '-g', '!**/worktree/**',
            '-g', '!**/logs/**',
            '-g', '!**/.git/**',
            '-g', '!**/.tmp/**'
        )
        $rgFiles = & rg @args
        if ($LASTEXITCODE -le 1 -and $rgFiles) {
            foreach ($path in $rgFiles) { if (-not [string]::IsNullOrWhiteSpace($path)) { $files.Add($path) | Out-Null } }
        }
    } else {
        Get-ChildItem -Path $sourceRoot -Recurse -File -Force | Where-Object {
            $includeNames -contains $_.Name
        } | ForEach-Object { $files.Add($_.FullName) | Out-Null }
    }

    $reportsRoot = Join-Path $sourceRoot '_reports'
    if (Test-Path -LiteralPath $reportsRoot) {
        Get-ChildItem -Path $reportsRoot -File -Force | Where-Object {
            $_.Extension -in @('.png', '.pptx', '.md', '.py')
        } | ForEach-Object { $files.Add($_.FullName) | Out-Null }
    }

    $copied = 0
    foreach ($file in ($files | Sort-Object -Unique)) {
        if ((Split-Path -Leaf $file) -like '~$*') { continue }
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $item = Get-Item -LiteralPath $file -ErrorAction Stop
        $relative = $item.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $parts = $relative -split '\\'
        if ($parts -contains 'worktree' -or $parts -contains 'logs' -or $parts -contains '.git' -or $parts -contains '.tmp') { continue }
        if ($item.Extension.ToLowerInvariant() -in @('.log', '.class', '.jar', '.pyc')) { continue }
        if ($item.Name -like '~$*') { continue }
        $target = Join-Path $destinationFull $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        $copied++
    }
    return $copied
}

function Assert-NoBackupPollution {
    param(
        [string]$Path,
        [switch]$Evidence
    )
    $bad = Get-ChildItem -Path $Path -Recurse -File -Force | Where-Object {
        $_.FullName -match '\\(worktree|logs|run-logs|\.tmp|\.git)\\' -or
        $_.Extension.ToLowerInvariant() -in @('.log', '.class', '.jar', '.pyc') -or
        $_.Name -like '~$*' -or
        ($Evidence -and $_.Extension.ToLowerInvariant() -in @('.java', '.xml', '.properties', '.sql'))
    }
    if ($bad) {
        $sample = ($bad | Select-Object -First 20 | ForEach-Object { $_.FullName }) -join "`n"
        throw "Backup pollution detected under $Path.`n$sample"
    }
}

function Write-AutopilotManifest {
    param(
        [string]$Destination,
        [int]$IncludedFiles
    )
    $manifest = @"
# Replay Autopilot Backup Manifest

- source: D:\opt\replay-autopilot
- backup_target: learning/raw/sources/replay-autopilot
- generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
- included_source_files: $IncludedFiles
- excluded: logs/, run-logs/, .tmp/, .git/, *.log, *.err.log, *.out.log, *.pyc, __pycache__/
- purpose: portable backup of the productized automation evaluation/control system; replay evidence and claim worktrees stay outside GitHub backup.

## Restore

Copy this folder back to D:\opt\replay-autopilot on a new machine, then adjust local paths in config.yaml as needed.
"@
    Set-Content -LiteralPath (Join-Path $Destination 'BACKUP_MANIFEST.md') -Value $manifest -Encoding UTF8
    @"
logs/
run-logs/
.tmp/
*.log
*.err.log
*.out.log
*.pyc
__pycache__/
"@ | Set-Content -LiteralPath (Join-Path $Destination '.gitignore') -Encoding UTF8
}

function Write-EvidenceManifest {
    param(
        [string]$Destination
    )
    $allFiles = Get-ChildItem -Path $Destination -Recurse -File -Force
    $evidenceFiles = $allFiles | Where-Object { $_.Name -notin @('EVIDENCE_MANIFEST.md', '.gitignore') }
    $byExt = $allFiles | Group-Object Extension | Sort-Object Count -Descending | ForEach-Object { "| $($_.Name) | $($_.Count) |" }
    $buckets = $allFiles | ForEach-Object { ($_.FullName.Substring($Destination.Length).TrimStart('\') -split '\\')[0] } | Group-Object | Sort-Object Name | ForEach-Object { "| $($_.Name) | $($_.Count) |" }
    $manifest = @"
# Replay Evidence Lite Manifest

- source: D:\opt\replay-evidence
- backup_target: learning/raw/sources/replay-evidence-lite
- generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
- evidence_files: $($evidenceFiles.Count)
- total_files_after_generation: $($allFiles.Count)
- total_size_mb: $([math]::Round((($allFiles | Measure-Object Length -Sum).Sum / 1MB), 2))
- purpose: lightweight evidence package for AI-driven R&D automation control system research and migration.

## Included

- session-level replay summary
- final replay reports
- round results
- autopilot summaries and decisions
- evolution proposals/results
- deep review reports
- stop-loss decisions
- generated presentation/report assets under `_reports/`

## Excluded

- `worktree/`
- `logs/`
- `.tmp/`
- `.git/`
- `*.log`, `*.class`, `*.jar`, `*.pyc`
- Office temp files `~$*`
- full company source trees and replay implementation worktrees

## File Types

| Extension | Count |
| --- | ---: |
$($byExt -join "`n")

## Top-Level Buckets

| Bucket | Files |
| --- | ---: |
$($buckets -join "`n")
"@
    Set-Content -LiteralPath (Join-Path $Destination 'EVIDENCE_MANIFEST.md') -Value $manifest -Encoding UTF8
    @"
worktree/
logs/
.tmp/
.git/
*.log
*.class
*.jar
*.pyc
__pycache__/
"@ | Set-Content -LiteralPath (Join-Path $Destination '.gitignore') -Encoding UTF8
}

function Invoke-Git {
    param(
        [string]$GitRoot,
        [string[]]$Arguments
    )
    & git -C $GitRoot @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$config = Read-SimpleYaml (Resolve-AbsolutePath $ConfigPath)
if (-not $IncludeAutopilot -and -not $IncludeKnowledge -and $EvidenceMode -eq 'None') {
    $IncludeAutopilot = $true
    $IncludeKnowledge = $true
}

if ([string]::IsNullOrWhiteSpace($ReplayAutopilotRoot)) {
    $ReplayAutopilotRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
} else {
    $ReplayAutopilotRoot = Resolve-AbsolutePath $ReplayAutopilotRoot
}
if ([string]::IsNullOrWhiteSpace($KnowledgeRepo)) {
    $KnowledgeRepo = Get-ConfigValueOrDefault -Config $config -Key 'knowledge_repo' -DefaultValue ''
}
if ([string]::IsNullOrWhiteSpace($KnowledgeRepo)) {
    throw "Knowledge repo is required. Set knowledge_repo in config or pass -KnowledgeRepo."
}
$KnowledgeRepo = Resolve-AbsolutePath $KnowledgeRepo
if (-not (Test-Path -LiteralPath $KnowledgeRepo)) {
    throw "Knowledge repo path not found: $KnowledgeRepo"
}
$gitRoot = Get-GitRoot -Path $KnowledgeRepo
$sourcesRoot = Split-Path -Parent $KnowledgeRepo
if (-not (Test-Path -LiteralPath $sourcesRoot)) {
    throw "Knowledge sources root not found: $sourcesRoot"
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBase (Get-ConfigValueOrDefault -Config $config -Key 'replay_root_base' -DefaultValue '')
}
if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Resolve-AbsolutePath $EvidenceRoot
}

$autopilotDestination = Join-Path $sourcesRoot 'replay-autopilot'
$evidenceDestination = Join-Path $sourcesRoot 'replay-evidence-lite'
$stagePaths = New-Object System.Collections.Generic.List[string]
$result = [ordered]@{
    status = 'VALID'
    config = (Resolve-AbsolutePath $ConfigPath)
    replay_autopilot_root = $ReplayAutopilotRoot
    knowledge_repo = $KnowledgeRepo
    git_root = $gitRoot
    sources_root = $sourcesRoot
    evidence_root = $EvidenceRoot
    evidence_mode = $EvidenceMode
    include_autopilot = [bool]$IncludeAutopilot
    include_knowledge = [bool]$IncludeKnowledge
    push = [bool]$Push
    validate_only = [bool]$ValidateOnly
}

if ($ValidateOnly) {
    [pscustomobject]$result | Format-List
    exit 0
}

if ($IncludeAutopilot) {
    Clear-BackupDirectory -Path $autopilotDestination -SourcesRoot $sourcesRoot -AllowedLeafNames @('replay-autopilot')
    $count = Copy-FilteredTree -Source $ReplayAutopilotRoot -Destination $autopilotDestination -ExcludeDirs @('logs', 'run-logs', '.tmp', '.git') -ExcludeExtensions @('.log', '.pyc') -ExcludeNamePatterns @('*.err.log', '*.out.log')
    Write-AutopilotManifest -Destination $autopilotDestination -IncludedFiles $count
    Assert-NoBackupPollution -Path $autopilotDestination
    $stagePaths.Add((Get-GitRelativePath -GitRoot $gitRoot -Path $autopilotDestination)) | Out-Null
    $result.autopilot_files = $count
}

if ($EvidenceMode -ne 'None') {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot)) {
        throw "Evidence mode '$EvidenceMode' requires an existing evidence root. Resolved value: $EvidenceRoot"
    }
    Clear-BackupDirectory -Path $evidenceDestination -SourcesRoot $sourcesRoot -AllowedLeafNames @('replay-evidence-lite')
    $count = Copy-EvidenceLite -EvidenceRoot $EvidenceRoot -Destination $evidenceDestination
    Write-EvidenceManifest -Destination $evidenceDestination
    Assert-NoBackupPollution -Path $evidenceDestination -Evidence
    $stagePaths.Add((Get-GitRelativePath -GitRoot $gitRoot -Path $evidenceDestination)) | Out-Null
    $result.evidence_files = $count
}

if ($IncludeKnowledge) {
    $stagePaths.Add((Get-GitRelativePath -GitRoot $gitRoot -Path $KnowledgeRepo)) | Out-Null
}

foreach ($stagePath in ($stagePaths | Sort-Object -Unique)) {
    if (-not [string]::IsNullOrWhiteSpace($stagePath)) {
        Invoke-Git -GitRoot $gitRoot -Arguments @('add', '--', $stagePath)
    }
}

& git -C $gitRoot diff --cached --quiet
$hasStagedChanges = ($LASTEXITCODE -ne 0)
if ($hasStagedChanges) {
    if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
        $CommitMessage = 'chore(knowledge): sync replay automation backups'
    }
    Invoke-Git -GitRoot $gitRoot -Arguments @('commit', '-m', $CommitMessage)
    $commit = (& git -C $gitRoot rev-parse --short HEAD).Trim()
    $result.committed = $true
    $result.commit = $commit
} else {
    $result.committed = $false
    $result.commit = ''
}

if ($Push) {
    $branch = (& git -C $gitRoot branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Cannot push because current knowledge repo branch is empty."
    }
    Invoke-Git -GitRoot $gitRoot -Arguments @('push', 'origin', $branch)
    $result.pushed = $true
    $result.branch = $branch
} else {
    $result.pushed = $false
}

[pscustomobject]$result | ConvertTo-Json -Depth 6
