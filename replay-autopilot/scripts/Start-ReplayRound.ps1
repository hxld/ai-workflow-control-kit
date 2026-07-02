param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [int]$Round = 1,
    [switch]$DryRun,
    [switch]$ValidateOnly,
    [switch]$ReuseExisting
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-GitStatusText {
    param([string]$Repo)
    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Test-Path -LiteralPath $Repo)) {
        return ''
    }
    $status = & git -C $Repo status --short 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return (($status | Sort-Object) -join "`n")
}

function Read-SimpleYaml {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config not found: $Path"
    }

    $result = @{}
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') {
            throw "Unsupported config line: $line"
        }
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $value = $value.Trim('"').Trim("'")
        $result[$key] = $value
    }
    return $result
}

function Require-Key {
    param(
        [hashtable]$Config,
        [string]$Key
    )
    if (-not $Config.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Config[$Key])) {
        throw "Missing required config key: $Key"
    }
    return $Config[$Key]
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

function Get-MavenSettingsCommandSegment {
    param([string]$MavenSettings)
    if ([string]::IsNullOrWhiteSpace($MavenSettings)) { return '' }
    $escaped = $MavenSettings -replace '"', '\"'
    return ('-s "{0}"' -f $escaped)
}

function Convert-ToBool {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1', 'true', 'yes', 'y', 'on') -contains $Value.Trim().ToLowerInvariant()
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

function Test-BaseCommitIsolation {
    param(
        [string]$Repo,
        [string]$FeatureName,
        [string]$BaseCommit,
        [string[]]$ForbiddenCommits
    )
    if ($null -eq $ForbiddenCommits -or $ForbiddenCommits.Count -eq 0) { return }
    foreach ($forbiddenCommit in @($ForbiddenCommits)) {
        if ([string]::IsNullOrWhiteSpace($forbiddenCommit)) { continue }
        & git -C $Repo merge-base --is-ancestor $forbiddenCommit $BaseCommit 2>$null
        if ($LASTEXITCODE -eq 0) {
            throw "BASE_ISOLATION_VIOLATION: feature='$FeatureName' base_commit='$BaseCommit' contains forbidden commit '$forbiddenCommit'. Replay aborted to prevent contaminated Source-of-Truth."
        }
    }
}

function Expand-Template {
    param(
        [string]$Template,
        [hashtable]$Values
    )
    $output = $Template
    foreach ($key in $Values.Keys) {
        $output = $output.Replace('{{' + $key + '}}', [string]$Values[$key])
    }
    return $output
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-SurfaceCarrierSpecs {
    return @(
        [pscustomobject]@{
            id = 'core_entry'
            title = 'Core real entry'
            pattern = '(?i)(processor|task|controller|facade|worker|job|handler|listener).*\.java$'
            priority = '(?i)(example-core/.*/ai/.*/task|example-core/.*/ai/.*/service|example-web/.*/controller|example-server/.*/processor|/ai/)'
        },
        [pscustomobject]@{
            id = 'stateful_side_effect'
            title = 'Stateful side effects'
            pattern = '(?i)(service|mapper|dao|provider|task|progress|log|compensate|claim|case|status|transaction|xml).*(\.java|\.xml)$'
            priority = '(?i)(example-core/.*/service|example-core/.*/mapper|example-provider|compensate|progress|task|log|status|/ai/)'
        },
        [pscustomobject]@{
            id = 'deploy_export_page'
            title = 'Deploy-facing page/export surface'
            pattern = '(?i)(controller|report|export|excel|timeline|case|route|mapper|page|view|jsp|js|ftl|html|download|notify|event|message|mq|push).*(\.java|\.xml|\.jsp|\.js|\.ftl|\.html)$'
            priority = '(?i)(example-web|reportTable|caseinfo|GenerateExcel|CaseRoute|CaseTimeline|Notify|Event|Message|Rabbit|push|mq|\.jsp$|\.js$)'
        },
        [pscustomobject]@{
            id = 'wire_payload_api_contract'
            title = 'Wire/API exact contract'
            pattern = '(?i)(api|dto|request|response|payload|body|json|type|ocr|processor|client|adapter|service|notify|event|message|mq).*(\.java|\.xml)$'
            priority = '(?i)(/ai/|ocr|dto|request|response|processor|api|payload|notify|event|message|mq)'
        },
        [pscustomobject]@{
            id = 'config_policy_threshold'
            title = 'Configurable policy/threshold'
            pattern = '(?i)(config|module|threshold|amount|validator|validate|mapper|controller|dto|entity|service).*(\.java|\.xml)$'
            priority = '(?i)(config|module|validator|threshold|amount|/ai/)'
        },
        [pscustomobject]@{
            id = 'generated_artifact_template_upload'
            title = 'Generated artifact/template/upload'
            pattern = '(?i)(template|ftl|pdf|png|image|book|calculation|upload|attachment|message|builder|scan).*(\.java|\.xml|\.ftl|\.vm)$'
            priority = '(?i)(ftl|template|calculation|book|upload|attachment|builder|scan|message)'
        },
        [pscustomobject]@{
            id = 'external_integration'
            title = 'External integration surface'
            pattern = '(?i)(ocr|facade|client|provider|insure|insurance|integration|dock|report|push|callback|notify|event|message|mq|rabbit|producer|service).*(\.java|\.xml)$'
            priority = '(?i)(insure|insurance|dock|push|callback|provider|client|facade|ocr|notify|event|message|mq|rabbit|producer)'
        },
        [pscustomobject]@{
            id = 'automation_test_interface'
            title = 'Automation/test interface contract'
            pattern = '(?i)(agent|automation|auto|test|case|query|response|project|facade|service).*(\.java|\.xml)$'
            priority = '(?i)(agent|automation|AutoTest|project|query|response|/ai/)'
        },
        [pscustomobject]@{
            id = 'lifecycle_cleanup_retention'
            title = 'Lifecycle cleanup/retention'
            pattern = '(?i)(report|ocr|log|cleanup|delete|remove|retention|expire|task|service).*(\.java|\.xml)$'
            priority = '(?i)(report|ocr|log|cleanup|delete|remove|task|lifecycle|retention)'
        }
    )
}

function Get-RequirementAwareSurfaceScore {
    param(
        [string]$Path,
        [string]$RequirementText
    )

    if ([string]::IsNullOrWhiteSpace($RequirementText)) { return 0 }

    $callbackZh = ([string][char]0x56DE) + ([string][char]0x8C03)
    $insurerZh = ([string][char]0x4FDD) + ([string][char]0x53F8)
    $thirdZh = ([string][char]0x7B2C) + ([string][char]0x4E09) + ([string][char]0x65B9)
    $externalZh = ([string][char]0x5916) + ([string][char]0x90E8)
    $dockZh = ([string][char]0x5BF9) + ([string][char]0x63A5)
    $messageZh = ([string][char]0x6D88) + ([string][char]0x606F)
    $pushZh = ([string][char]0x63A8) + ([string][char]0x9001)
    $broadcastZh = ([string][char]0x5E7F) + ([string][char]0x64AD)
    $wechatZh = ([string][char]0x5FAE) + ([string][char]0x4FE1)
    $officialAccountZh = ([string][char]0x516C) + ([string][char]0x4F17) + ([string][char]0x53F7)
    $statusZh = ([string][char]0x72B6) + ([string][char]0x6001)
    $flowZh = ([string][char]0x6D41) + ([string][char]0x8F6C)

    $hasCallback = ($RequirementText -match '(?i)(callback|insurer|insurance|partner)') -or
        $RequirementText.Contains($callbackZh) -or
        $RequirementText.Contains($insurerZh) -or
        $RequirementText.Contains($thirdZh) -or
        $RequirementText.Contains($externalZh) -or
        $RequirementText.Contains($dockZh)
    $hasMq = ($RequirementText -match '(?i)(MQ|Rabbit|Exchange|Queue|producer|publish)') -or
        $RequirementText.Contains($messageZh) -or
        $RequirementText.Contains($pushZh) -or
        $RequirementText.Contains($broadcastZh)
    $hasWx = ($RequirementText -match '(?i)(openid|wxId|wx_id)') -or
        $RequirementText.Contains($wechatZh) -or
        $RequirementText.Contains($officialAccountZh)
    $hasStatus = ($RequirementText -match '(?i)(status|transition)') -or
        $RequirementText.Contains($statusZh) -or
        $RequirementText.Contains($flowZh)

    $score = 0
    if ($hasCallback -and $Path -match '(?i)(callback|insure|insurance|partner|dock|provider|client|company|push)') {
        $score += 180
    }
    if ($hasMq -and $Path -match '(?i)(notify|event|message|rabbit|mq|push|producer|exchange)') {
        $score += 170
    }
    if ($hasWx -and $Path -match '(?i)(wx|open|report|notify|push|dto|param|message)') {
        $score += 160
    }
    if ($hasStatus -and $Path -match '(?i)(status|flow|route|case|transition)') {
        $score += 120
    }
    return $score
}

function Write-SurfaceCarrierScan {
    param(
        [string]$Worktree,
        [string]$OutPath,
        [string]$RequirementSnapshot = ''
    )

    $requirementText = Read-TextIfExists -Path $RequirementSnapshot
    $trackedFiles = @(& git -C $Worktree ls-files 2>$null | Where-Object {
        $_ -match '\.(java|xml|ftl|jsp|js|html|vm)$' -and
        $_ -notmatch '(^|/)target/' -and
        $_ -notmatch '(^|/)src/test/'
    })
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed for surface scan: $Worktree"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Surface Carrier Scan')
    $lines.Add('')
    $lines.Add("- generated_at: $((Get-Date).ToString('s'))")
    $lines.Add('- purpose: neutral code-surface carrier hints for blind planning; not oracle evidence')
    $lines.Add('- discipline: prefer existing production carriers from this scan before creating new helper/service files; if no carrier fits, record the search terms and blocker')
    $lines.Add('')
    foreach ($spec in Get-SurfaceCarrierSpecs) {
        $matches = @($trackedFiles | Where-Object { $_ -match $spec.pattern } | ForEach-Object {
            $score = 0
            if ($_ -match $spec.priority) { $score += 100 }
            if ($_ -match '(?i)(example-core|example-web|example-server|example-domain)') { $score += 20 }
            if ($_ -match '(?i)(/ai/|\\ai\\|ocr|report|export|case|compensate|config)') { $score += 20 }
            $score += Get-RequirementAwareSurfaceScore -Path $_ -RequirementText $requirementText
            if ($_ -match '(?i)(pom\.xml|example-api/src/main/java/com/example/project/api/system)') { $score -= 50 }
            [pscustomobject]@{ Path = $_; Score = $score }
        } | Sort-Object @{Expression='Score'; Descending=$true}, @{Expression='Path'; Ascending=$true} | Select-Object -First 35 | ForEach-Object { $_.Path })
        $lines.Add("## $($spec.id) - $($spec.title)")
        if ($matches.Count -eq 0) {
            $lines.Add('- no neutral candidate found; run targeted rg in worktree and disclose search terms')
        } else {
            foreach ($file in $matches) {
                $lines.Add("- ``$file``")
            }
        }
        $lines.Add('')
    }

    Set-Content -LiteralPath $OutPath -Value ($lines -join "`n") -Encoding UTF8
}

$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml -Path $configPathFull

$projectRoot = Resolve-AbsolutePath (Require-Key $config 'project_root')
$featureName = if ($config.ContainsKey('feature_name') -and -not [string]::IsNullOrWhiteSpace($config['feature_name'])) { $config['feature_name'] } else { 'feature' }
$mavenSettings = Get-ConfigValueOrDefault -Config $config -Key 'maven_settings' -DefaultValue ''
$mavenSettingsArg = Get-MavenSettingsCommandSegment -MavenSettings $mavenSettings
$requirementSource = Resolve-AbsolutePath (Require-Key $config 'requirement_source')
$baseCommit = Require-Key $config 'base_commit'
$oracleBranch = Require-Key $config 'oracle_branch'
$oracleCommit = Require-Key $config 'oracle_commit'
$replayRootBase = Resolve-AbsolutePath (Require-Key $config 'replay_root_base')
$runLabel = if ($config.ContainsKey('run_label')) { $config['run_label'] } else { 'replay-autopilot' }
$knowledgeVersion = if ($config.ContainsKey('knowledge_version')) { $config['knowledge_version'] } else { '' }
$knowledgeVersionSource = if ($config.ContainsKey('knowledge_version_source')) { $config['knowledge_version_source'] } else { '' }
$systemContextDir = if ($config.ContainsKey('system_context_dir') -and -not [string]::IsNullOrWhiteSpace($config['system_context_dir'])) { Resolve-AbsolutePath $config['system_context_dir'] } else { '' }
$planCandidateCount = if ($config.ContainsKey('plan_candidate_count') -and -not [string]::IsNullOrWhiteSpace($config['plan_candidate_count'])) { [int]$config['plan_candidate_count'] } else { 3 }
$goldenSamplePromptSource = ''
$goldenSamplePromptSnapshot = ''
$goldenDeliverySliceSource = ''
$goldenDeliverySliceSnapshot = ''
$externalPracticeSopSource = ''
$externalPracticeSopSnapshot = ''

$configuredEvidenceRoot = Get-ConfigValueOrDefault -Config $config -Key 'evidence_root' -DefaultValue ''
$evidenceRootForControlAssets = if (-not [string]::IsNullOrWhiteSpace($configuredEvidenceRoot)) {
    Resolve-AbsolutePath $configuredEvidenceRoot
} else {
    Resolve-EvidenceRootFromReplayBase $replayRootBase
}

if (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'golden_sample_auto_apply' -DefaultValue 'true')) {
    $evidenceRootForGoldenSample = $evidenceRootForControlAssets
    if (-not [string]::IsNullOrWhiteSpace($evidenceRootForGoldenSample)) {
        $candidateGoldenPrompt = Join-Path $evidenceRootForGoldenSample '_golden-samples\GOLDEN_SAMPLE_PROMPT.md'
        if (Test-Path -LiteralPath $candidateGoldenPrompt) {
            $goldenSamplePromptSource = Resolve-AbsolutePath $candidateGoldenPrompt
        }
    }
}

if (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'golden_delivery_slice_auto_apply' -DefaultValue 'true')) {
    if (-not [string]::IsNullOrWhiteSpace($evidenceRootForControlAssets)) {
        $candidateGoldenDeliverySlice = Join-Path $evidenceRootForControlAssets '_golden-samples\GOLDEN_DELIVERY_SLICE_PROMPT.md'
        if (Test-Path -LiteralPath $candidateGoldenDeliverySlice) {
            $goldenDeliverySliceSource = Resolve-AbsolutePath $candidateGoldenDeliverySlice
        }
    }
}

if (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'external_practice_auto_apply' -DefaultValue 'true')) {
    if (-not [string]::IsNullOrWhiteSpace($evidenceRootForControlAssets)) {
        $candidateExternalSop = Join-Path $evidenceRootForControlAssets '_external-practice\EXTERNAL_PRACTICE_SOP.md'
        $candidateExternalDecision = Join-Path $evidenceRootForControlAssets '_external-practice\EXTERNAL_PRACTICE_DECISION.json'
        if ((Test-Path -LiteralPath $candidateExternalSop) -and (Test-Path -LiteralPath $candidateExternalDecision)) {
            try {
                $externalDecision = Get-Content -LiteralPath $candidateExternalDecision -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([bool]$externalDecision.safe_for_auto_apply) {
                    $externalPracticeSopSource = Resolve-AbsolutePath $candidateExternalSop
                }
            } catch {
                $externalPracticeSopSource = ''
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $projectRoot)) {
    throw "Project root not found: $projectRoot"
}
if (-not (Test-Path -LiteralPath $requirementSource)) {
    throw "Requirement source not found: $requirementSource"
}
if (-not [string]::IsNullOrWhiteSpace($systemContextDir) -and -not (Test-Path -LiteralPath $systemContextDir)) {
    throw "System context dir not found: $systemContextDir"
}

# Fail-closed base isolation guard: read forbidden commits from config if present
$forbiddenCommitsRaw = if ($config.ContainsKey('base_must_not_contain_commits')) { $config['base_must_not_contain_commits'] } else { '' }
$forbiddenCommits = @()
if (-not [string]::IsNullOrWhiteSpace($forbiddenCommitsRaw)) {
    $forbiddenCommits = @($forbiddenCommitsRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
}
if ($forbiddenCommits.Count -gt 0) {
    Test-BaseCommitIsolation -Repo $projectRoot -FeatureName $featureName -BaseCommit $baseCommit -ForbiddenCommits $forbiddenCommits
}

$roundId = 'r{0:D2}' -f $Round
$replayRoot = "$replayRootBase-$roundId"
$worktree = Join-Path $replayRoot 'worktree'
$requirementSnapshotOut = Join-Path $replayRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md'
$baselineIndexOut = Join-Path $replayRoot 'BASELINE_INDEX.md'
$contextManifestOut = Join-Path $replayRoot 'CONTEXT_MANIFEST.md'
$systemContextSnapshotDir = Join-Path $replayRoot 'SYSTEM_CONTEXT_SNAPSHOT'
$systemContextDirForPrompt = ''
$surfaceCarrierScanOut = Join-Path $replayRoot 'SURFACE_CARRIER_SCAN.md'
$oracleDiffAnalysisOut = Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json'
$featureClassificationOut = Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json'
$protectedRootStatusBefore = Get-GitStatusText -Repo $projectRoot

$repoCheck = & git -C $projectRoot rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Project root is not a git repository: $projectRoot"
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')

# Evolution Version Verification (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)
$evolutionVersion = 'unknown'
$evolutionFileCandidates = @()
$knowledgeRoot = Get-ConfigValueOrDefault -Config $config -Key 'knowledge_repo' -DefaultValue ''
if (-not [string]::IsNullOrWhiteSpace($knowledgeRoot)) {
    $evolutionFileCandidates += (Join-Path $knowledgeRoot 'workflow-history\latest.json')
    $evolutionFileCandidates += (Join-Path $knowledgeRoot 'CURRENT_VERSION.md')
}
$evolutionFileCandidates += (Join-Path $scriptRoot 'CURRENT_VERSION.md')
$evolutionFile = $evolutionFileCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($evolutionFile)) {
    $evolutionFile = $evolutionFileCandidates | Select-Object -First 1
}
if (Test-Path -LiteralPath $evolutionFile) {
    if ((Split-Path -Leaf $evolutionFile) -ieq 'latest.json') {
        try {
            $workflowLatest = Get-Content -LiteralPath $evolutionFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$workflowLatest.latest -match '^v[0-9]+$') {
                $evolutionVersion = [string]$workflowLatest.latest
                Write-Host "Loaded evolution version: $evolutionVersion"
            } else {
                Write-Warning "workflow-history latest.json found but latest version pattern not matched"
            }
        } catch {
            Write-Warning "workflow-history latest.json found but could not be parsed"
        }
    } else {
        $versionMatch = Select-String -Path $evolutionFile -Pattern "^\*\*Version\*\*:\s*v(\d+)" -ErrorAction SilentlyContinue
        if ($null -ne $versionMatch) {
            $evolutionVersion = 'v{0}' -f $versionMatch.Matches[0].Groups[1].Value
            Write-Host "Loaded evolution version: $evolutionVersion"
        } else {
            Write-Warning "CURRENT_VERSION.md found but version pattern not matched"
        }
    }
} else {
    Write-Warning "Evolution version source not found at $evolutionFile"
}
$env:EVOLUTION_VERSION = $evolutionVersion

$phase0TemplatePath = Join-Path $scriptRoot 'prompts\phase0-contract-gate.prompt.md'
$planTemplatePath = Join-Path $scriptRoot 'prompts\phase-plan-tournament.prompt.md'
$phase1TemplatePath = Join-Path $scriptRoot 'prompts\phase1-strict-blind.prompt.md'
$phase2TemplatePath = Join-Path $scriptRoot 'prompts\phase2-oracle-posthoc.prompt.md'
if (-not (Test-Path -LiteralPath $phase0TemplatePath)) {
    throw "Phase 0 template missing: $phase0TemplatePath"
}
if (-not (Test-Path -LiteralPath $phase1TemplatePath)) {
    throw "Phase 1 template missing: $phase1TemplatePath"
}
if (-not (Test-Path -LiteralPath $planTemplatePath)) {
    throw "Phase plan template missing: $planTemplatePath"
}
if (-not (Test-Path -LiteralPath $phase2TemplatePath)) {
    throw "Phase 2 template missing: $phase2TemplatePath"
}

$values = @{
    PROJECT_ROOT = '<protected-main-workspace-redacted; use isolated worktree only>'
    FEATURE_NAME = $featureName
    REQUIREMENT_SOURCE = $requirementSnapshotOut
    ORIGINAL_REQUIREMENT_SOURCE = $requirementSource
    BASE_COMMIT = $baseCommit
    ORACLE_BRANCH = $oracleBranch
    ORACLE_COMMIT = $oracleCommit
    REPLAY_ROOT = $replayRoot
    WORKTREE = $worktree
    BASELINE_INDEX = $baselineIndexOut
    CONTEXT_MANIFEST = $contextManifestOut
    SURFACE_CARRIER_SCAN = $surfaceCarrierScanOut
    ORACLE_DIFF_ANALYSIS = $oracleDiffAnalysisOut
    FEATURE_CLASSIFICATION = $featureClassificationOut
    SYSTEM_CONTEXT_DIR = $systemContextDirForPrompt
    MAVEN_SETTINGS_ARG = $mavenSettingsArg
    PLAN_CANDIDATE_COUNT = $planCandidateCount
    RUN_LABEL = $runLabel
    ROUND_ID = $roundId
}

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        ProjectRoot = $projectRoot
        RequirementSource = $requirementSource
        ReplayRoot = $replayRoot
        Worktree = $worktree
        BaselineIndex = $baselineIndexOut
        ContextManifest = $contextManifestOut
        SurfaceCarrierScan = $surfaceCarrierScanOut
        SystemContextDir = $systemContextDir
        GoldenSamplePromptSource = $goldenSamplePromptSource
        GoldenDeliverySliceSource = $goldenDeliverySliceSource
        ExternalPracticeSopSource = $externalPracticeSopSource
        Phase0Template = $phase0TemplatePath
        PlanTemplate = $planTemplatePath
        Phase1Template = $phase1TemplatePath
        Phase2Template = $phase2TemplatePath
    } | Format-List
    exit 0
}

if ((Test-Path -LiteralPath $replayRoot) -and -not $ReuseExisting) {
    throw "Replay root already exists. Use -ReuseExisting if intentional: $replayRoot"
}

New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

if (-not (Test-Path -LiteralPath $worktree)) {
    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create git worktree: $worktree @ $baseCommit"
    } else {
        & git -C $projectRoot worktree add $worktree $baseCommit
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add failed for $worktree"
        }
    }
} elseif (-not $ReuseExisting) {
    throw "Worktree path already exists. Use -ReuseExisting if intentional: $worktree"
}

if (-not $DryRun) {
    Copy-Item -LiteralPath $requirementSource -Destination $requirementSnapshotOut -Force
    if (-not [string]::IsNullOrWhiteSpace($systemContextDir) -and (Test-Path -LiteralPath $systemContextDir)) {
        New-Item -ItemType Directory -Force -Path $systemContextSnapshotDir | Out-Null
        Get-ChildItem -LiteralPath $systemContextDir -File -Filter '*.md' | Sort-Object Name | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $systemContextSnapshotDir $_.Name) -Force
        }
        $systemContextDirForPrompt = $systemContextSnapshotDir
        $values['SYSTEM_CONTEXT_DIR'] = $systemContextDirForPrompt
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-BaselineIndex.ps1') `
        -Worktree $worktree `
        -RequirementSource $requirementSnapshotOut `
        -OutPath $baselineIndexOut `
        -ProjectRoot $projectRoot `
        -BaseCommit $baseCommit `
        -RunLabel $runLabel `
        -RoundId $roundId
    if ($LASTEXITCODE -ne 0) {
        throw "New-BaselineIndex failed for $replayRoot"
    }
    Write-SurfaceCarrierScan -Worktree $worktree -OutPath $surfaceCarrierScanOut -RequirementSnapshot $requirementSnapshotOut
    $carrierIndexScript = Join-Path $PSScriptRoot 'Generate-CarrierIndex.ps1'
    if (Test-Path -LiteralPath $carrierIndexScript) {
        $carrierIndexOut = Join-Path $replayRoot 'SURFACE_CARRIER_INDEX.md'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $carrierIndexScript `
            -ProjectRoot $worktree `
            -OutputPath $carrierIndexOut | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Generate-CarrierIndex failed for $replayRoot"
        }
        if (Test-Path -LiteralPath $carrierIndexOut) {
            Add-Content -LiteralPath $surfaceCarrierScanOut -Encoding UTF8 -Value @(
                '',
                '---',
                '',
                '## Executable Carrier Index',
                '',
                '- source_script: Generate-CarrierIndex.ps1',
                '- purpose: exhaustive Facade/Controller/FacadeImpl index used by planning prompts',
                ''
            )
            Add-Content -LiteralPath $surfaceCarrierScanOut -Encoding UTF8 -Value (Get-Content -LiteralPath $carrierIndexOut -Raw -Encoding UTF8)
        }
    }

    # v465: Build facade carrier index for layer validation
    $facadeCarrierIndexPath = Join-Path $replayRoot 'VALID_FACADE_CARRIERS.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-FacadeCarrierIndex.ps1') `
        -BaselineRoot $worktree `
        -OutputPath $facadeCarrierIndexPath `
        -BaselineCommit $baseCommit | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $facadeCarrierIndexPath)) {
        Add-Content -LiteralPath $surfaceCarrierScanOut -Encoding UTF8 -Value @(
            '',
            '---',
            '',
            '## Facade Carrier Index',
            '',
            '- source_script: Build-FacadeCarrierIndex.ps1',
            '- purpose: v465 pre-execution constraint gate uses this to validate Facade layer carriers',
            ''
        )
        Add-Content -LiteralPath $surfaceCarrierScanOut -Encoding UTF8 -Value "See $facadeCarrierIndexPath for detailed JSON index."
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Get-OracleDiffAnalysis.ps1') `
        -Worktree $worktree `
        -BaseCommit $baseCommit `
        -OracleCommit $oracleCommit `
        -OutPath $oracleDiffAnalysisOut
    if ($LASTEXITCODE -ne 0) {
        throw "Get-OracleDiffAnalysis failed for $replayRoot"
    }
    $featureClassifierScript = Join-Path $PSScriptRoot 'Classify-Feature.ps1'
    if (Test-Path -LiteralPath $featureClassifierScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $featureClassifierScript `
            -ReplayRoot $replayRoot `
            -Worktree $worktree `
            -RequirementSource $requirementSnapshotOut `
            -OutPath $featureClassificationOut | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Classify-Feature failed for $replayRoot"
        }
    }
}

$contextLines = New-Object System.Collections.Generic.List[string]
$contextLines.Add('# Context Manifest')
$contextLines.Add('')
$contextLines.Add("- generated_at: $((Get-Date).ToString('s'))")
$contextLines.Add("- system_context_dir: $systemContextDir")
$contextLines.Add("- system_context_snapshot_dir: $systemContextDirForPrompt")
$contextLines.Add("- feature_classification: $featureClassificationOut")
$contextLines.Add("- usage: read-only project/system context; neutral aid for exploration and planning; not oracle evidence")
$contextLines.Add('')
$contextLines.Add('## Allowed Context Files')
$contextLines.Add('')
if (-not [string]::IsNullOrWhiteSpace($systemContextDirForPrompt) -and (Test-Path -LiteralPath $systemContextDirForPrompt)) {
    Get-ChildItem -LiteralPath $systemContextDirForPrompt -File -Filter '*.md' | Sort-Object Name | ForEach-Object {
        $relative = $_.FullName.Substring($systemContextDirForPrompt.Length).TrimStart('\')
        $contextLines.Add(("- `{0}` | bytes={1} | updated={2}" -f $relative, $_.Length, $_.LastWriteTime.ToString('s')))
    }
} else {
    $contextLines.Add('- none configured')
}
$contextLines.Add('')
$contextLines.Add('## Use Discipline')
$contextLines.Add('')
$contextLines.Add('- Allowed before oracle post-hoc: only as generic project context.')
$contextLines.Add('- Forbidden before oracle post-hoc: old replay reports, oracle branch/diff, prior final implementation summaries, feature-specific post-hoc gap conclusions, or the original feature document directory outside the named requirement snapshot.')
$contextLines.Add('- If a context file conflicts with requirement_source or code facts, requirement_source/code facts win and the conflict must be disclosed.')
Set-Content -LiteralPath $contextManifestOut -Value ($contextLines -join "`n") -Encoding UTF8

$phase0 = Expand-Template -Template (Get-Content -LiteralPath $phase0TemplatePath -Raw -Encoding UTF8) -Values $values
$plan = Expand-Template -Template (Get-Content -LiteralPath $planTemplatePath -Raw -Encoding UTF8) -Values $values
$phase1 = Expand-Template -Template (Get-Content -LiteralPath $phase1TemplatePath -Raw -Encoding UTF8) -Values $values
$phase2 = Expand-Template -Template (Get-Content -LiteralPath $phase2TemplatePath -Raw -Encoding UTF8) -Values $values

$phase0Out = Join-Path $replayRoot 'PHASE0_PROMPT.md'
$planOut = Join-Path $replayRoot 'PLAN_PROMPT.md'
$phase1Out = Join-Path $replayRoot 'PHASE1_PROMPT.md'
$phase2Out = Join-Path $replayRoot 'PHASE2_PROMPT.md'
if (-not [string]::IsNullOrWhiteSpace($goldenSamplePromptSource)) {
    $goldenSamplePromptSnapshot = Join-Path $replayRoot 'GOLDEN_SAMPLE_PROMPT_SNAPSHOT.md'
    $goldenSamplePromptText = Read-TextIfExists $goldenSamplePromptSource
    if (-not [string]::IsNullOrWhiteSpace($goldenSamplePromptText)) {
        Set-Content -LiteralPath $goldenSamplePromptSnapshot -Value $goldenSamplePromptText -Encoding UTF8
        $goldenSampleAppend = @"

---

# Mined Golden Sample Control

Source snapshot: $goldenSamplePromptSnapshot

The following content is generic workflow control mined from prior replay evidence. It is not oracle evidence and must not provide feature-specific implementation facts.

$goldenSamplePromptText
"@
        $phase0 = $phase0 + $goldenSampleAppend
        $plan = $plan + $goldenSampleAppend
        $phase1 = $phase1 + $goldenSampleAppend
    }
}
if (-not [string]::IsNullOrWhiteSpace($goldenDeliverySliceSource)) {
    $goldenDeliverySliceSnapshot = Join-Path $replayRoot 'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md'
    $goldenDeliverySliceText = Read-TextIfExists $goldenDeliverySliceSource
    if (-not [string]::IsNullOrWhiteSpace($goldenDeliverySliceText)) {
        Set-Content -LiteralPath $goldenDeliverySliceSnapshot -Value $goldenDeliverySliceText -Encoding UTF8
        $goldenDeliveryAppend = @"

---

# Golden Delivery Slice Control

Source snapshot: $goldenDeliverySliceSnapshot

The following content is generic positive first-slice guidance mined from prior replay control evidence. It is not oracle evidence and must not provide feature-specific implementation facts.

$goldenDeliverySliceText
"@
        $phase0 = $phase0 + $goldenDeliveryAppend
        $plan = $plan + $goldenDeliveryAppend
        $phase1 = $phase1 + $goldenDeliveryAppend
    }
}
if (-not [string]::IsNullOrWhiteSpace($externalPracticeSopSource)) {
    $externalPracticeSopSnapshot = Join-Path $replayRoot 'EXTERNAL_PRACTICE_SOP_SNAPSHOT.md'
    $externalPracticeSopText = Read-TextIfExists $externalPracticeSopSource
    if (-not [string]::IsNullOrWhiteSpace($externalPracticeSopText)) {
        Set-Content -LiteralPath $externalPracticeSopSnapshot -Value $externalPracticeSopText -Encoding UTF8
        $externalPracticeAppend = @"

---

# External Practice SOP Control

Source snapshot: $externalPracticeSopSnapshot

The following content is generic workflow control synthesized from public external practices after stagnation. It is not oracle evidence and must not provide feature-specific implementation facts.

$externalPracticeSopText
"@
        $phase0 = $phase0 + $externalPracticeAppend
        $plan = $plan + $externalPracticeAppend
        $phase1 = $phase1 + $externalPracticeAppend
    }
}
Set-Content -LiteralPath $phase0Out -Value $phase0 -Encoding UTF8
Set-Content -LiteralPath $planOut -Value $plan -Encoding UTF8
Set-Content -LiteralPath $phase1Out -Value $phase1 -Encoding UTF8
Set-Content -LiteralPath $phase2Out -Value $phase2 -Encoding UTF8

$metadata = [ordered]@{
    generated_at = (Get-Date).ToString('s')
    round = $roundId
    run_label = $runLabel
    knowledge_version = $knowledgeVersion
    knowledge_version_source = $knowledgeVersionSource
    evolution_version = $evolutionVersion
    feature_name = $featureName
    project_root = $projectRoot
    requirement_source = $requirementSnapshotOut
    original_requirement_source = $requirementSource
    base_commit = $baseCommit
    oracle_branch = $oracleBranch
    oracle_commit = $oracleCommit
    replay_root = $replayRoot
    worktree = $worktree
    baseline_index = $baselineIndexOut
    context_manifest = $contextManifestOut
    surface_carrier_scan = $surfaceCarrierScanOut
    oracle_diff_analysis = $oracleDiffAnalysisOut
    feature_classification = $featureClassificationOut
    system_context_dir = $systemContextDir
    system_context_snapshot_dir = $systemContextDirForPrompt
    golden_sample_prompt_source = $goldenSamplePromptSource
    golden_sample_prompt_snapshot = $goldenSamplePromptSnapshot
    golden_delivery_slice_source = $goldenDeliverySliceSource
    golden_delivery_slice_snapshot = $goldenDeliverySliceSnapshot
    external_practice_sop_source = $externalPracticeSopSource
    external_practice_sop_snapshot = $externalPracticeSopSnapshot
    phase0_prompt = $phase0Out
    plan_prompt = $planOut
    phase1_prompt = $phase1Out
    phase2_prompt = $phase2Out
    dry_run = [bool]$DryRun
}
$metadataPath = Join-Path $replayRoot 'AUTOPILOT_RUN.json'
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

$protectedRootStatusAfter = Get-GitStatusText -Repo $projectRoot
if ($protectedRootStatusAfter -ne $protectedRootStatusBefore) {
    $violationPath = Join-Path $replayRoot 'PROTECTED_ROOT_STATUS_VIOLATION.md'
    @(
        '# Protected Root Status Violation',
        '',
        'Replay preparation changed the protected project root git status.',
        '',
        "protected_root: $projectRoot",
        '',
        '## Before',
        '```',
        $protectedRootStatusBefore,
        '```',
        '',
        '## After',
        '```',
        $protectedRootStatusAfter,
        '```'
    ) | Set-Content -LiteralPath $violationPath -Encoding UTF8
    throw "protected_root_status_changed_during_replay_prepare: $violationPath"
}

Write-Host "Replay round prepared."
Write-Host "Replay root: $replayRoot"
Write-Host "Worktree: $worktree"
Write-Host "Baseline index: $baselineIndexOut"
Write-Host "Context manifest: $contextManifestOut"
Write-Host "Surface carrier scan: $surfaceCarrierScanOut"
Write-Host "Oracle diff analysis: $oracleDiffAnalysisOut"
Write-Host "Feature classification: $featureClassificationOut"
Write-Host "Phase 0 prompt: $phase0Out"
Write-Host "Plan prompt: $planOut"
Write-Host "Phase 1 prompt: $phase1Out"
Write-Host "Phase 2 prompt: $phase2Out"
Write-Host ""
Write-Host "Next step for direct/manual use. If this script was called by Run-ReplayLoop.ps1, the parent runner may continue automatically."
Write-Host "1. Manual mode: open a fresh agent session with PHASE0_PROMPT.md; continue with PLAN_PROMPT.md only if PHASE0_RESULT is PROCEED; legacy direct use may continue with PHASE1_PROMPT.md only if PLAN_RESULT is PROCEED; then PHASE2_PROMPT.md."
Write-Host "2. Autopilot mode: scripts\Run-ReplayLoop.ps1 -StartRound $Round -Rounds 1 -ReuseExisting. Autopilot Phase 1 uses Run-SliceLoop.ps1, not the legacy one-shot PHASE1_PROMPT.md."
Write-Host "3. Parse results manually with scripts\Parse-ReplayReport.ps1 -ReplayRoot `"$replayRoot`""
