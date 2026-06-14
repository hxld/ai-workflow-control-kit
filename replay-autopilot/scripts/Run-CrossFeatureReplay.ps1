param(
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\features\replay-feature-registry.json'),
    [string]$BaseConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [string]$EvidenceRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT",
    [int]$StartIndex = 0,
    [int]$MaxFeatures = 1,
    [int]$RoundsPerFeature = 1,
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$Executor = '',
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [switch]$AllowCodexExecutor,
    [switch]$UseLatestKnowledgeVersion,
    [switch]$RunEvolution,
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
        'require_executor',
        'allow_codex_executor',
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
            $lines.Add(('{0}: {1}' -f $key, $Config[$key])) | Out-Null
        }
    }
    foreach ($key in ($Config.Keys | Sort-Object)) {
        if ($preferred -notcontains $key) {
            $lines.Add(('{0}: {1}' -f $key, $Config[$key])) | Out-Null
        }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value ($lines -join "`n") -Encoding UTF8
}

function Test-CommitExists {
    param([string]$Repo, [string]$Commit)
    if ([string]::IsNullOrWhiteSpace($Commit)) { return $false }
    & git -C $Repo rev-parse --verify "$Commit^{commit}" 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-BaseCommitIsolation {
    param(
        [string]$Repo,
        [string]$FeatureName,
        [string]$BaseCommit,
        [object[]]$ForbiddenCommits
    )
    if ($null -eq $ForbiddenCommits -or $ForbiddenCommits.Count -eq 0) { return }
    foreach ($entry in @($ForbiddenCommits)) {
        $forbiddenCommit = if ($entry -is [hashtable]) { $entry['commit'] } else { [string]$entry.commit }
        $reason = if ($entry -is [hashtable]) { $entry['reason'] } else { [string]$entry.reason }
        if ([string]::IsNullOrWhiteSpace($forbiddenCommit)) { continue }
        & git -C $Repo merge-base --is-ancestor $forbiddenCommit $BaseCommit 2>$null
        if ($LASTEXITCODE -eq 0) {
            throw "BASE_ISOLATION_VIOLATION: feature='$FeatureName' base_commit='$BaseCommit' contains forbidden commit '$forbiddenCommit'. Reason: $reason"
        }
    }
}

function Write-CrossLedger {
    param(
        [string]$LedgerPath,
        [object[]]$Rows
    )
    $jsonPath = [System.IO.Path]::ChangeExtension($LedgerPath, '.json')
    @($Rows) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cross Feature Replay Ledger') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| index | feature | category | status | replay_root | note |') | Out-Null
    $lines.Add('|---:|---|---|---|---|---|') | Out-Null
    foreach ($row in @($Rows)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $row.index, $row.feature_name, $row.category, $row.status, $row.replay_root, (($row.note -replace '\|','/') -replace "`r?`n",' '))) | Out-Null
    }
    Set-Content -LiteralPath $LedgerPath -Value ($lines -join "`n") -Encoding UTF8
}

$registryFull = Resolve-AbsolutePath $RegistryPath
$baseConfigFull = Resolve-AbsolutePath $BaseConfigPath
$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$runLoop = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'

if (-not (Test-Path -LiteralPath $registryFull)) { throw "Registry not found: $registryFull" }
if (-not (Test-Path -LiteralPath $baseConfigFull)) { throw "Base config not found: $baseConfigFull" }
if (-not (Test-Path -LiteralPath $runLoop)) { throw "Run-ReplayLoop.ps1 not found: $runLoop" }

$registry = Get-Content -LiteralPath $registryFull -Raw -Encoding UTF8 | ConvertFrom-Json
$baseConfig = Read-SimpleYaml $baseConfigFull
$projectRoot = Resolve-AbsolutePath $baseConfig['project_root']
$enabledByName = @{}
foreach ($feature in @($registry.features)) {
    $enabledByName[[string]$feature.feature_name] = $feature
}

$sequence = @($registry.default_sequence | ForEach-Object { [string]$_ })
if ($sequence.Count -eq 0) {
    $sequence = @($registry.features | Where-Object { [bool]$_.enabled } | ForEach-Object { [string]$_.feature_name })
}

$selected = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $sequence.Count -and $selected.Count -lt $MaxFeatures; $i++) {
    $idx = ($StartIndex + $i) % $sequence.Count
    $name = $sequence[$idx]
    if (-not $enabledByName.ContainsKey($name)) { continue }
    $feature = $enabledByName[$name]
    if (-not [bool]$feature.enabled) { continue }
    if ([string]$feature.feature_name -like '京东安联广分*') { continue }
    $selected.Add($feature) | Out-Null
}

if ($selected.Count -eq 0) { throw "No enabled cross-feature replay target selected." }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$crossRunRoot = Join-Path $evidenceRootFull ('_cross-feature\cross-run-{0}' -f $timestamp)
$ledgerPath = Join-Path $crossRunRoot 'CROSS_FEATURE_REPLAY_LEDGER.md'
$rows = New-Object System.Collections.Generic.List[object]

if ($ValidateOnly) {
    foreach ($feature in $selected.ToArray()) {
        $rows.Add([pscustomobject]@{
            index = $rows.Count
            feature_name = [string]$feature.feature_name
            category = [string]$feature.category
            status = 'SELECTED'
            replay_root = ''
            note = [string]$feature.notes
        }) | Out-Null
    }
    [ordered]@{
        status = 'VALID'
        registry = $registryFull
        selected_features = @($rows.ToArray())
        cross_run_root = $crossRunRoot
    } | ConvertTo-Json -Depth 8
    exit 0
}

New-Item -ItemType Directory -Force -Path $crossRunRoot | Out-Null

foreach ($feature in $selected.ToArray()) {
    $featureName = [string]$feature.feature_name
    $requirementSource = Resolve-AbsolutePath ([string]$feature.requirement_source)
    $oracleCommit = [string]$feature.oracle_commit
    $baseCommit = [string]$feature.base_commit
    $oracleBranch = [string]$feature.oracle_branch
    $phase1MaxSlices = if ($null -ne $feature.phase1_max_slices -and "$($feature.phase1_max_slices)" -match '^[0-9]+$') { [string]$feature.phase1_max_slices } else { $baseConfig['phase1_max_slices'] }

    $row = [ordered]@{
        index = $rows.Count
        feature_name = $featureName
        category = [string]$feature.category
        status = 'PENDING'
        replay_root = ''
        note = ''
    }

    if (-not (Test-Path -LiteralPath $requirementSource)) {
        $row.status = 'SKIPPED'
        $row.note = "missing requirement_source: $requirementSource"
        $rows.Add([pscustomobject]$row) | Out-Null
        continue
    }
    if (-not (Test-CommitExists -Repo $projectRoot -Commit $oracleCommit)) {
        $row.status = 'SKIPPED'
        $row.note = "oracle commit not found: $oracleCommit"
        $rows.Add([pscustomobject]$row) | Out-Null
        continue
    }
    if (-not (Test-CommitExists -Repo $projectRoot -Commit $baseCommit)) {
        $row.status = 'SKIPPED'
        $row.note = "base commit not found: $baseCommit"
        $rows.Add([pscustomobject]$row) | Out-Null
        continue
    }

    # Fail-closed: reject contaminated base commits
    $forbiddenCommits = @($feature.PSObject.Properties | Where-Object { $_.Name -eq 'base_must_not_contain_commits' } | ForEach-Object { $_.Value })
    if ($null -ne $forbiddenCommits -and $forbiddenCommits.Count -gt 0) {
        try {
            Test-BaseCommitIsolation -Repo $projectRoot -FeatureName $featureName -BaseCommit $baseCommit -ForbiddenCommits $forbiddenCommits
        } catch {
            $row.status = 'SKIPPED'
            $row.note = "BASE_ISOLATION_VIOLATION: $($_.Exception.Message)"
            $rows.Add([pscustomobject]$row) | Out-Null
            Write-CrossLedger -LedgerPath $ledgerPath -Rows @($rows.ToArray())
            continue
        }
    }

    $featureEvidenceRoot = Join-Path $evidenceRootFull $featureName
    $replayRootBase = Join-Path $featureEvidenceRoot ('claim-codex-replay-v000-cross-{0}' -f $timestamp)
    $config = @{}
    foreach ($key in $baseConfig.Keys) { $config[$key] = $baseConfig[$key] }
    $config['feature_name'] = $featureName
    $config['requirement_source'] = $requirementSource
    $config['base_commit'] = $baseCommit
    $config['oracle_branch'] = $oracleBranch
    $config['oracle_commit'] = $oracleCommit
    $config['replay_root_base'] = $replayRootBase
    $config['run_label'] = ('{0}-v000-cross' -f $featureName)
    $config['max_rounds'] = [string]$RoundsPerFeature
    $config['max_no_improvement_rounds'] = '1'
    $config['stop_loss_lookback'] = '5'
    $config['phase1_max_slices'] = $phase1MaxSlices
    $config['auto_evolution'] = 'false'

    # Pass forbidden commits as comma-separated string so Start-ReplayRound.ps1 can also guard
    $forbiddenFlat = @($forbiddenCommits | ForEach-Object {
        if ($_ -is [hashtable]) { $_['commit'] } else { [string]$_.commit }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($forbiddenFlat.Count -gt 0) {
        $config['base_must_not_contain_commits'] = $forbiddenFlat -join ','
    }

    $configPath = Join-Path $crossRunRoot ('config-{0}.yaml' -f ($featureName -replace '[\\/:*?"<>|（）() ]','_'))
    Write-SimpleYaml -Config $config -Path $configPath

    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runLoop, '-ConfigPath', $configPath, '-StartRound', '1', '-Rounds', [string]$RoundsPerFeature)
    if (-not [string]::IsNullOrWhiteSpace($Executor)) { $args += @('-Executor', $Executor) }
    if (-not [string]::IsNullOrWhiteSpace($RequireExecutor)) { $args += @('-RequireExecutor', $RequireExecutor) }
    if ($AllowCodexExecutor) { $args += '-AllowCodexExecutor' }
    if ($UseLatestKnowledgeVersion) { $args += '-UseLatestKnowledgeVersion' }
    if ($RunEvolution) { $args += '-RunEvolution' }

    $row.status = 'RUNNING'
    $row.replay_root = $replayRootBase
    $row.note = "config=$configPath"
    $rowObject = [pscustomobject]$row
    $rows.Add($rowObject) | Out-Null
    Write-CrossLedger -LedgerPath $ledgerPath -Rows @($rows.ToArray())

    & powershell @args
    $exit = $LASTEXITCODE
    $rowObject.status = if ($exit -eq 0) { 'FINISHED' } else { "FAILED_EXIT_$exit" }
    $effectiveRoot = ''
    $featureRoots = @(Get-ChildItem -LiteralPath $featureEvidenceRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*cross*' } | Sort-Object LastWriteTime -Descending)
    if ($featureRoots.Count -gt 0) {
        $effectiveRoot = $featureRoots[0].FullName
    }
    if (-not [string]::IsNullOrWhiteSpace($effectiveRoot)) {
        $rowObject.replay_root = $effectiveRoot
    }
    $rowObject.note = "exit=$exit"
    Write-CrossLedger -LedgerPath $ledgerPath -Rows @($rows.ToArray())
}

Write-CrossLedger -LedgerPath $ledgerPath -Rows @($rows.ToArray())
$summaryScript = Join-Path $PSScriptRoot 'Write-ReplaySessionSummary.ps1'
if (Test-Path -LiteralPath $summaryScript) {
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript -EvidenceRoot $evidenceRootFull -MaxRoots 80 -Quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Portable replay session summary failed with exit code $LASTEXITCODE"
        }
    } catch {
        Write-Warning "Portable replay session summary failed: $($_.Exception.Message)"
    }
}
Get-Content -LiteralPath $ledgerPath -Encoding UTF8
