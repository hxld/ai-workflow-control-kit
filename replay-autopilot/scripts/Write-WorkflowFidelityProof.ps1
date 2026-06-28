param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$Executor = 'codex',
    [string]$CommandSource = '',
    [string]$WorkDir = '',
    [string]$LogDir = '',
    [string]$Stage = '',
    [string]$SkillSourceRoot = '',
    [string]$RuntimeSkillRoot = '',
    [string[]]$RequiredSkills = @('pre-flight-check', 'replay-tdd-enforcer', 'replay-test-charter-validator'),
    [string]$CodexHooksEnabled = 'false',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePathOrEmpty {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-ExistingFileHash {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RootInfo {
    param([string]$Path)
    $full = Resolve-AbsolutePathOrEmpty $Path
    $exists = -not [string]::IsNullOrWhiteSpace($full) -and (Test-Path -LiteralPath $full)
    $linkType = ''
    $target = ''
    if ($exists) {
        try {
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            $linkType = [string]$item.LinkType
            if ($null -ne $item.Target) {
                $target = (@($item.Target) -join ';')
            }
        } catch {
            $linkType = ''
            $target = ''
        }
    }
    return [ordered]@{
        path = $full
        exists = [bool]$exists
        link_type = $linkType
        target = $target
    }
}

function Add-UniquePath {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    $full = Resolve-AbsolutePathOrEmpty $Path
    if ([string]::IsNullOrWhiteSpace($full)) { return }
    foreach ($existing in $List) {
        if ($existing -ieq $full) { return }
    }
    $List.Add($full) | Out-Null
}

function ConvertTo-BoolConfig {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1', 'true', 'yes', 'y', 'on') -contains $Value.Trim().ToLowerInvariant()
}

$scriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot '..\..'))
$homeAgentsRoot = Join-Path $HOME '.agents\skills'
$homeCodexRoot = Join-Path $HOME '.codex\skills'
$homeClaudeRoot = Join-Path $HOME '.claude\skills'

if ([string]::IsNullOrWhiteSpace($SkillSourceRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:AI_WORKFLOW_SKILL_SOURCE_ROOT)) {
        $SkillSourceRoot = $env:AI_WORKFLOW_SKILL_SOURCE_ROOT
    } else {
        $repoSkillRoot = Join-Path $repoRoot 'agents\skills'
        if (Test-Path -LiteralPath $repoSkillRoot) {
            $SkillSourceRoot = $repoSkillRoot
        } else {
            $SkillSourceRoot = $homeAgentsRoot
        }
    }
}

if ([string]::IsNullOrWhiteSpace($RuntimeSkillRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:REPLAY_RUNTIME_SKILL_ROOT)) {
        $RuntimeSkillRoot = $env:REPLAY_RUNTIME_SKILL_ROOT
    } elseif ($Executor -eq 'codex') {
        $RuntimeSkillRoot = $homeCodexRoot
    } elseif ($Executor -eq 'claude') {
        $RuntimeSkillRoot = $homeClaudeRoot
    }
}

$skillSourceRootFull = Resolve-AbsolutePathOrEmpty $SkillSourceRoot
$runtimeSkillRootFull = Resolve-AbsolutePathOrEmpty $RuntimeSkillRoot
$codexHooksEnabledActual = ConvertTo-BoolConfig -Value $CodexHooksEnabled
$requiresRuntimeVisibility = @('codex', 'claude') -contains $Executor
$issues = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$skillChecks = New-Object System.Collections.Generic.List[object]

foreach ($skill in $RequiredSkills) {
    if ([string]::IsNullOrWhiteSpace($skill)) { continue }

    $sourceSkillPath = if (-not [string]::IsNullOrWhiteSpace($skillSourceRootFull)) { Join-Path $skillSourceRootFull (Join-Path $skill 'SKILL.md') } else { '' }
    $runtimeSkillPath = if (-not [string]::IsNullOrWhiteSpace($runtimeSkillRootFull)) { Join-Path $runtimeSkillRootFull (Join-Path $skill 'SKILL.md') } else { '' }
    $agentsSkillPath = Join-Path $homeAgentsRoot (Join-Path $skill 'SKILL.md')

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    Add-UniquePath -List $candidatePaths -Path $sourceSkillPath
    Add-UniquePath -List $candidatePaths -Path $runtimeSkillPath
    Add-UniquePath -List $candidatePaths -Path $agentsSkillPath

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $candidatePaths) {
        $exists = Test-Path -LiteralPath $candidate -PathType Leaf
        $candidates.Add([ordered]@{
            path = $candidate
            exists = [bool]$exists
            sha256 = Get-ExistingFileHash -Path $candidate
        }) | Out-Null
    }

    $sourceExists = -not [string]::IsNullOrWhiteSpace($sourceSkillPath) -and (Test-Path -LiteralPath $sourceSkillPath -PathType Leaf)
    $runtimeExists = -not $requiresRuntimeVisibility -or (-not [string]::IsNullOrWhiteSpace($runtimeSkillPath) -and (Test-Path -LiteralPath $runtimeSkillPath -PathType Leaf))
    $sourceHash = Get-ExistingFileHash -Path $sourceSkillPath
    $runtimeHash = Get-ExistingFileHash -Path $runtimeSkillPath

    if (-not $sourceExists) {
        $issues.Add([ordered]@{
            code = 'missing_skill_source'
            skill = $skill
            expected_path = $sourceSkillPath
        }) | Out-Null
    }
    if (-not $runtimeExists) {
        $issues.Add([ordered]@{
            code = 'missing_runtime_skill'
            skill = $skill
            expected_path = $runtimeSkillPath
            executor = $Executor
        }) | Out-Null
    }
    if ($sourceExists -and $runtimeExists -and -not [string]::IsNullOrWhiteSpace($sourceHash) -and -not [string]::IsNullOrWhiteSpace($runtimeHash) -and $sourceHash -ne $runtimeHash) {
        $warnings.Add([ordered]@{
            code = 'skill_source_runtime_hash_mismatch'
            skill = $skill
            source_path = $sourceSkillPath
            runtime_path = $runtimeSkillPath
            source_sha256 = $sourceHash
            runtime_sha256 = $runtimeHash
        }) | Out-Null
    }

    $skillChecks.Add([ordered]@{
        skill = $skill
        source_path = $sourceSkillPath
        source_exists = [bool]$sourceExists
        source_sha256 = $sourceHash
        runtime_path = $runtimeSkillPath
        runtime_visible = [bool]$runtimeExists
        runtime_sha256 = $runtimeHash
        candidates = @($candidates.ToArray())
    }) | Out-Null
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'BLOCKED' }
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $outputFull
if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
}

$result = [ordered]@{
    schema = 'workflow_fidelity_proof.v1'
    status = $status
    stage = $Stage
    executor = $Executor
    command_source = $CommandSource
    work_dir = Resolve-AbsolutePathOrEmpty $WorkDir
    log_dir = Resolve-AbsolutePathOrEmpty $LogDir
    codex_hooks_enabled = $codexHooksEnabledActual
    skill_usage_proven = $false
    proof_scope = 'runtime_skill_visibility_and_hashes_only'
    usage_receipt_required = $true
    required_skills = @($RequiredSkills)
    skill_roots = [ordered]@{
        configured_source = Get-RootInfo -Path $skillSourceRootFull
        runtime = Get-RootInfo -Path $runtimeSkillRootFull
        home_agents = Get-RootInfo -Path $homeAgentsRoot
        home_codex = Get-RootInfo -Path $homeCodexRoot
        home_claude = Get-RootInfo -Path $homeClaudeRoot
    }
    skill_checks = @($skillChecks.ToArray())
    issues = @($issues.ToArray())
    warnings = @($warnings.ToArray())
    generated_at = (Get-Date).ToString('s')
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputFull -Encoding UTF8

if ($PassThru) {
    $result | ConvertTo-Json -Depth 12
}

exit 0
