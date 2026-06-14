param(
    [string]$BaseConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [string]$FeatureName = '',
    [string]$EvidenceRoot = 'D:\opt\replay-evidence',
    [string]$OutPath = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') { throw "Unsupported config line: $line" }
        $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
    return $result
}

function Write-SimpleYaml {
    param([hashtable]$Config, [string]$Path)
    $preferred = @(
        'project_root',
        'feature_name',
        'requirement_source',
        'base_commit',
        'oracle_branch',
        'oracle_commit',
        'replay_root_base',
        'run_label',
        'target_coverage',
        'max_rounds',
        'max_no_improvement_rounds',
        'stop_loss_lookback',
        'stop_loss_min_oracle_improvement',
        'stop_loss_low_cap_threshold',
        'stop_loss_low_cap_rounds',
        'stop_loss_repeated_gap_threshold',
        'executor',
        'executor_timeout_minutes',
        'codex_sandbox',
        'codex_approval',
        'codex_model',
        'codex_reasoning_effort',
        'claude_model',
        'claude_max_budget_usd',
        'system_context_dir',
        'plan_candidate_count',
        'phase0_model',
        'phase0_reasoning_effort',
        'plan_model',
        'plan_reasoning_effort',
        'phase1_model',
        'phase1_reasoning_effort',
        'phase1_max_slices',
        'phase2_model',
        'phase2_reasoning_effort',
        'deep_review_model',
        'deep_review_reasoning_effort',
        'evolution_model',
        'evolution_reasoning_effort',
        'auto_evolution',
        'skill_source_root',
        'knowledge_repo'
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $preferred) {
        if ($Config.ContainsKey($key)) {
            $lines.Add(('{0}: {1}' -f $key, $Config[$key]))
        }
    }
    foreach ($key in ($Config.Keys | Sort-Object)) {
        if ($preferred -notcontains $key) {
            $lines.Add(('{0}: {1}' -f $key, $Config[$key]))
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value ($lines -join "`n") -Encoding UTF8
}

function Read-RepoBinding {
    param([string]$RequirementPath)
    $text = Get-Content -LiteralPath $RequirementPath -Raw -Encoding UTF8
    $binding = @{}
    foreach ($key in @('git_branch', 'git_head', 'related_commit', 'feature_commit_grep')) {
        $m = [regex]::Match($text, "(?m)^\s*${key}\s*:\s*`"?([^`"\r\n]+)`"?\s*$")
        if ($m.Success) {
            $binding[$key] = $m.Groups[1].Value.Trim()
        }
    }
    return $binding
}

function Get-ChangedFileCount {
    param([string]$Repo, [string]$Commit)
    $files = @(& git -C $Repo show --name-only --pretty=format: --no-renames $Commit -- 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($LASTEXITCODE -ne 0) { return 9999 }
    return $files.Count
}

$baseConfigFull = Resolve-AbsolutePath $BaseConfigPath
$config = Read-SimpleYaml $baseConfigFull
$projectRoot = Resolve-AbsolutePath $config['project_root']
$docRoot = Join-Path $projectRoot '.doc'
$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot

$preferredFeatures = @('xmlpSlowFix', 'policy-num-extension', 'skip-task-transform-case', 'xiebao')
$candidates = New-Object System.Collections.Generic.List[object]
foreach ($dir in @(Get-ChildItem -LiteralPath $docRoot -Directory)) {
    if ($dir.Name -in @('aiClaimV2', 'claim-system-context', 'automation', 'template', '_template')) { continue }
    $requirementPath = Join-Path $dir.FullName 'requirements.md'
    if (-not (Test-Path -LiteralPath $requirementPath)) { continue }
    $binding = Read-RepoBinding -RequirementPath $requirementPath
    $oracle = ''
    if ($binding.ContainsKey('related_commit')) {
        $oracle = $binding['related_commit']
    } elseif ($binding.ContainsKey('git_head')) {
        $oracle = $binding['git_head']
    }
    if ([string]::IsNullOrWhiteSpace($oracle)) { continue }
    & git -C $projectRoot rev-parse --verify "$oracle^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { continue }
    $base = (& git -C $projectRoot rev-parse "$oracle^").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($base)) { continue }
    $changed = Get-ChangedFileCount -Repo $projectRoot -Commit $oracle
    $rank = [Array]::IndexOf($preferredFeatures, $dir.Name)
    if ($rank -lt 0) { $rank = 100 }
    $candidates.Add([pscustomobject]@{
        FeatureName = $dir.Name
        RequirementSource = $requirementPath
        BaseCommit = $base
        OracleCommit = $oracle
        OracleBranch = if ($binding.ContainsKey('git_branch')) { $binding['git_branch'] } else { $oracle }
        ChangedFileCount = $changed
        Rank = $rank
    })
}

if ($candidates.Count -eq 0) {
    throw "No small replay canary candidate found under $docRoot"
}

if (-not [string]::IsNullOrWhiteSpace($FeatureName)) {
    $selected = @($candidates | Where-Object { $_.FeatureName -eq $FeatureName } | Select-Object -First 1)
    if ($selected.Count -eq 0) { throw "Feature candidate not found or missing oracle metadata: $FeatureName" }
    $selected = $selected[0]
} else {
    $selected = $candidates | Sort-Object Rank, ChangedFileCount, FeatureName | Select-Object -First 1
}

$date = Get-Date -Format 'yyyyMMdd'
$featureEvidenceRoot = Join-Path $evidenceRootFull $selected.FeatureName
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path (Resolve-AbsolutePath (Join-Path $PSScriptRoot '..\.tmp')) ('config-canary-{0}.yaml' -f $selected.FeatureName)
}

$config['feature_name'] = $selected.FeatureName
$config['requirement_source'] = $selected.RequirementSource
$config['base_commit'] = $selected.BaseCommit
$config['oracle_branch'] = $selected.OracleBranch
$config['oracle_commit'] = $selected.OracleCommit
$config['replay_root_base'] = (Join-Path $featureEvidenceRoot ('claim-codex-replay-v000-autopilot-canary-{0}' -f $date))
$config['run_label'] = ('{0}-v000-autopilot-canary' -f $selected.FeatureName)
$config['max_rounds'] = '1'
$config['max_no_improvement_rounds'] = '1'
$config['stop_loss_lookback'] = '3'
$config['phase1_max_slices'] = '4'

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        SelectedFeature = $selected.FeatureName
        RequirementSource = $selected.RequirementSource
        BaseCommit = $selected.BaseCommit
        OracleBranch = $selected.OracleBranch
        OracleCommit = $selected.OracleCommit
        ChangedFileCount = $selected.ChangedFileCount
        OutPath = (Resolve-AbsolutePath $OutPath)
    } | Format-List
    exit 0
}

Write-SimpleYaml -Config $config -Path (Resolve-AbsolutePath $OutPath)
[pscustomobject]@{
    Status = 'WROTE'
    SelectedFeature = $selected.FeatureName
    RequirementSource = $selected.RequirementSource
    BaseCommit = $selected.BaseCommit
    OracleBranch = $selected.OracleBranch
    OracleCommit = $selected.OracleCommit
    ChangedFileCount = $selected.ChangedFileCount
    ConfigPath = (Resolve-AbsolutePath $OutPath)
} | Format-List
