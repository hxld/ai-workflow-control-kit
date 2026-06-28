param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [string]$ReplayRoot = '',
    [string]$EvidenceRoot = '',
    [string]$OutputRoot = '',
    [string]$Reason = 'stagnation_trigger',
    [switch]$RunAgent,
    [switch]$ValidateOnly,
    [switch]$Quiet
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

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-DecisionIfValid {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-ExternalPracticeDecisionComplete {
    param(
        [object]$Decision,
        [string]$SopPath
    )
    if ($null -eq $Decision) { return $false }
    $status = [string]$Decision.final_status
    if ($status -eq 'COMPLETED') {
        if ([bool]$Decision.safe_for_auto_apply) {
            return (Test-Path -LiteralPath $SopPath)
        }
        return $true
    }
    return $false
}

function Invoke-ExternalPracticeAgentAttempt {
    param(
        [string]$Executor,
        [string]$PromptPath,
        [string]$OutputRoot,
        [string]$DecisionPath,
        [string]$SopPath,
        [hashtable]$Config,
        [string]$AttemptName,
        [string]$Model,
        [string]$ReasoningEffort,
        [int]$TimeoutMinutes
    )

    if (Test-Path -LiteralPath $DecisionPath) {
        Remove-Item -LiteralPath $DecisionPath -Force
    }

    $agentArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
        '-PromptPath', $PromptPath,
        '-WorkDir', (Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')),
        '-LogDir', (Join-Path $OutputRoot ("logs\{0}" -f $AttemptName)),
        '-Executor', $Executor,
        '-TimeoutMinutes', $TimeoutMinutes,
        '-Name', $AttemptName,
        '-CompletionPath', $DecisionPath,
        '-CompletionQuietSeconds', '60'
    )
    if ($Executor -eq 'codex') {
        $sandbox = Get-ConfigValueOrDefault -Config $Config -Key 'codex_sandbox' -DefaultValue 'danger-full-access'
        $approval = Get-ConfigValueOrDefault -Config $Config -Key 'codex_approval' -DefaultValue 'never'
        $agentArgs += @('-Sandbox', $sandbox, '-Approval', $approval)
    }
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $agentArgs += @('-Model', $Model)
    }
    if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) {
        $agentArgs += @('-ReasoningEffort', $ReasoningEffort)
    }

    if ($env:REPLAY_AUTOPILOT_SIMULATE_EXTERNAL_AGENT_FAILURE -eq '1') {
        return [pscustomobject]@{
            executor = $Executor
            attempt = $AttemptName
            exit_code = 88
            decision_present = $false
            final_status = 'SIMULATED_MISSING_DECISION'
            safe_for_auto_apply = $false
            complete = $false
        }
    }

    $exitCode = 0
    try {
        & powershell @agentArgs
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
    }

    $decision = Read-DecisionIfValid -Path $DecisionPath
    $complete = Test-ExternalPracticeDecisionComplete -Decision $decision -SopPath $SopPath
    return [pscustomobject]@{
        executor = $Executor
        attempt = $AttemptName
        exit_code = $exitCode
        decision_present = ($null -ne $decision)
        final_status = if ($null -ne $decision) { [string]$decision.final_status } else { 'MISSING_DECISION' }
        safe_for_auto_apply = if ($null -ne $decision) { [bool]$decision.safe_for_auto_apply } else { $false }
        complete = $complete
    }
}

function Resolve-ExternalPracticeDefaultModel {
    param(
        [hashtable]$Config,
        [string]$Executor
    )

    if ($Executor -eq 'codex') {
        return Get-ConfigValueOrDefault -Config $Config -Key 'codex_model' -DefaultValue ''
    }
    if ($Executor -eq 'claude') {
        return Get-ConfigValueOrDefault -Config $Config -Key 'claude_deep_review_model' -DefaultValue (Get-ConfigValueOrDefault -Config $Config -Key 'claude_model' -DefaultValue '')
    }
    return ''
}

function Resolve-ExternalPracticeDefaultReasoningEffort {
    param(
        [hashtable]$Config,
        [string]$Executor
    )

    if ($Executor -eq 'codex') {
        return Get-ConfigValueOrDefault -Config $Config -Key 'codex_reasoning_effort' -DefaultValue 'medium'
    }
    return ''
}

function Write-ExternalPracticePrompt {
    param(
        [string]$Path,
        [string]$OutputRoot,
        [string]$ReplayRoot,
        [string]$Reason,
        [string[]]$SeedUrls
    )

    $deepReviewReport = if ([string]::IsNullOrWhiteSpace($ReplayRoot)) { '' } else { Join-Path $ReplayRoot 'DEEP_REVIEW_REPORT.md' }
    $rootCauseLedger = if ([string]::IsNullOrWhiteSpace($ReplayRoot)) { '' } else { Join-Path $ReplayRoot 'ROOT_CAUSE_LEDGER.json' }
    $nextExperimentPlan = if ([string]::IsNullOrWhiteSpace($ReplayRoot)) { '' } else { Join-Path $ReplayRoot 'NEXT_EXPERIMENT_PLAN.md' }
    $stopLossDecision = if ([string]::IsNullOrWhiteSpace($ReplayRoot)) { '' } else { Join-Path $ReplayRoot 'STOP_LOSS_DECISION.json' }
    $researchOut = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_RESEARCH.md'
    $sopOut = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_SOP.md'
    $decisionOut = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_DECISION.json'
    $seedLines = if ($SeedUrls.Count -gt 0) {
        ($SeedUrls | ForEach-Object { "- $_" }) -join "`n"
    } else {
        '- none'
    }

    $prompt = @"
# External Practice Search Trigger

Reason: $Reason

You are running after replay stagnation. The local system has already found repeated execution symptoms. Your job is to search external public practices and extract generic process assets, especially positive SOP / golden slice / Pre-PR filtering / evaluation-driven AI coding patterns.

## Inputs

- replay_root: $ReplayRoot
- stop_loss_decision: $stopLossDecision
- deep_review_report: $deepReviewReport
- root_cause_ledger: $rootCauseLedger
- next_experiment_plan: $nextExperimentPlan

## Seed Sources

$seedLines

You may search the public web beyond these seeds. Prioritize primary sources, engineering blogs, public repositories, and docs. Do not rely on unsourced summaries.

## Required Analysis

1. Identify whether the local failure pattern is missing negative gates, positive golden samples, execution slicing, review filters, benchmark/eval design, or process ownership.
2. Extract reusable cross-project rules only. Do not copy feature-specific class names, table names, commits, paths, or business details into the SOP.
3. Compare external practices against local repeated gaps such as wrong_test_surface, core_entry_unclosed, side_effect_ledger_gap, helper-only first slices, and high blind / low verification divergence.
4. Convert findings into a machine-actionable SOP that can be appended to future replay prompts.

## Output Files

Write both files:

1. $researchOut
2. $sopOut

Also write:

3. $decisionOut

## Required Research Output Shape

In `$researchOut`, include:

```text
final_status: COMPLETED | BLOCKED_EXTERNAL_SEARCH_UNAVAILABLE
sources:
- <title> | <url> | <why relevant>
local_failure_pattern:
- ...
external_practice_findings:
- ...
recommended_sop_delta:
- ...
```

## Required SOP Output Shape

In `$sopOut`, include:

```text
# External Practice SOP

source_type: external_practice_synthesis
safe_for_blind_replay: true | false

## Trigger
- ...

## Positive Sample Layer
- ...

## Execution Control
- ...

## Review Filter
- ...

## Stop Conditions
- ...

## Do Not Import
- project-specific facts
- oracle implementation details
- unsourced claims
```

## Required Decision JSON

In `$decisionOut`, write valid JSON:

```json
{
  "schema": "external_practice_search.v1",
  "final_status": "COMPLETED",
  "safe_for_auto_apply": true,
  "sources_count": 0,
  "sop_path": "$sopOut",
  "research_path": "$researchOut"
}
```

If web access or source verification is unavailable, write `final_status=BLOCKED_EXTERNAL_SEARCH_UNAVAILABLE`, `safe_for_auto_apply=false`, and explain the blocker in the research file. Do not fabricate sources.
"@
    Set-Content -LiteralPath $Path -Value $prompt -Encoding UTF8
}

$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml -Path $configPathFull

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $configuredEvidenceRoot = Get-ConfigValueOrDefault -Config $config -Key 'evidence_root' -DefaultValue ''
    if (-not [string]::IsNullOrWhiteSpace($configuredEvidenceRoot)) {
        $EvidenceRoot = $configuredEvidenceRoot
    } else {
        $EvidenceRoot = Resolve-EvidenceRootFromReplayBase (Get-ConfigValueOrDefault -Config $config -Key 'replay_root_base' -DefaultValue '')
    }
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    throw "EvidenceRoot is required. Pass -EvidenceRoot or set replay_root_base/evidence_root in config."
}
$EvidenceRoot = Resolve-AbsolutePath $EvidenceRoot
if (-not (Test-Path -LiteralPath $EvidenceRoot)) {
    throw "EvidenceRoot not found: $EvidenceRoot"
}
if (-not [string]::IsNullOrWhiteSpace($ReplayRoot)) {
    $ReplayRoot = Resolve-AbsolutePath $ReplayRoot
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $EvidenceRoot '_external-practice'
}
$OutputRoot = Resolve-AbsolutePath $OutputRoot
$seedRaw = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_seed_urls' -DefaultValue 'https://tech.meituan.com/2026/05/07/agent-ai-coding.html,https://github.com/addyosmani/agent-skills,https://github.com/mattpocock/skills,https://github.com/ruvnet/ruflo'
$seedUrls = @($seedRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        ConfigPath = $configPathFull
        EvidenceRoot = $EvidenceRoot
        ReplayRoot = $ReplayRoot
        OutputRoot = $OutputRoot
        Reason = $Reason
    RunAgent = [bool]$RunAgent
        AllowFallback = (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'external_practice_allow_fallback' -DefaultValue 'true'))
        FallbackExecutor = (Get-ConfigValueOrDefault -Config $config -Key 'external_practice_fallback_executor' -DefaultValue 'codex')
        SeedUrls = $seedUrls
    } | Format-List
    exit 0
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$promptPath = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_RESEARCH_PROMPT.md'
Write-ExternalPracticePrompt -Path $promptPath -OutputRoot $OutputRoot -ReplayRoot $ReplayRoot -Reason $Reason -SeedUrls $seedUrls

if (-not [string]::IsNullOrWhiteSpace($ReplayRoot) -and (Test-Path -LiteralPath $ReplayRoot)) {
    Copy-Item -LiteralPath $promptPath -Destination (Join-Path $ReplayRoot 'EXTERNAL_PRACTICE_RESEARCH_PROMPT.md') -Force
}

$decisionPath = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_DECISION.json'
$researchPath = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_RESEARCH.md'
$sopPath = Join-Path $OutputRoot 'EXTERNAL_PRACTICE_SOP.md'

if ($RunAgent) {
    $executor = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_primary_executor' -DefaultValue (Get-ConfigValueOrDefault -Config $config -Key 'executor' -DefaultValue 'codex')
    $timeoutMinutes = [int](Get-ConfigValueOrDefault -Config $config -Key 'external_practice_timeout_minutes' -DefaultValue (Get-ConfigValueOrDefault -Config $config -Key 'executor_timeout_minutes' -DefaultValue '120'))
    $modelDefault = Resolve-ExternalPracticeDefaultModel -Config $config -Executor $executor
    $reasoningDefault = Resolve-ExternalPracticeDefaultReasoningEffort -Config $config -Executor $executor
    $model = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_model' -DefaultValue $modelDefault
    $reasoningEffort = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_reasoning_effort' -DefaultValue $reasoningDefault
    $attempts = New-Object System.Collections.Generic.List[object]
    $primaryAttempt = Invoke-ExternalPracticeAgentAttempt -Executor $executor -PromptPath $promptPath -OutputRoot $OutputRoot -DecisionPath $decisionPath -SopPath $sopPath -Config $config -AttemptName 'external-practice-search-primary' -Model $model -ReasoningEffort $reasoningEffort -TimeoutMinutes $timeoutMinutes
    $attempts.Add($primaryAttempt) | Out-Null

    if (-not $primaryAttempt.complete -and (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'external_practice_allow_fallback' -DefaultValue 'true'))) {
        $fallbackExecutor = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_fallback_executor' -DefaultValue 'codex'
        if ($fallbackExecutor -ne $executor) {
            $fallbackModelDefault = if ($fallbackExecutor -eq 'codex') {
                Get-ConfigValueOrDefault -Config $config -Key 'codex_model' -DefaultValue ''
            } else {
                Get-ConfigValueOrDefault -Config $config -Key 'claude_deep_review_model' -DefaultValue ''
            }
            $fallbackModel = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_fallback_model' -DefaultValue $fallbackModelDefault
            $fallbackReasoningDefault = if ($fallbackExecutor -eq 'codex') {
                Get-ConfigValueOrDefault -Config $config -Key 'codex_reasoning_effort' -DefaultValue 'medium'
            } else {
                ''
            }
            $fallbackReasoning = Get-ConfigValueOrDefault -Config $config -Key 'external_practice_fallback_reasoning_effort' -DefaultValue $fallbackReasoningDefault
            $fallbackTimeout = [int](Get-ConfigValueOrDefault -Config $config -Key 'external_practice_fallback_timeout_minutes' -DefaultValue $timeoutMinutes)
            $fallbackAttempt = Invoke-ExternalPracticeAgentAttempt -Executor $fallbackExecutor -PromptPath $promptPath -OutputRoot $OutputRoot -DecisionPath $decisionPath -SopPath $sopPath -Config $config -AttemptName 'external-practice-search-fallback' -Model $fallbackModel -ReasoningEffort $fallbackReasoning -TimeoutMinutes $fallbackTimeout
            $attempts.Add($fallbackAttempt) | Out-Null
        }
    }

    $finalDecision = Read-DecisionIfValid -Path $decisionPath
    if (-not (Test-ExternalPracticeDecisionComplete -Decision $finalDecision -SopPath $sopPath)) {
        [ordered]@{
            schema = 'external_practice_search.v1'
            final_status = 'BLOCKED_ALL_EXECUTORS_FAILED'
            safe_for_auto_apply = $false
            primary_executor = $executor
            next_replay_executor = (Get-ConfigValueOrDefault -Config $config -Key 'executor' -DefaultValue 'codex')
            attempts = $attempts.ToArray()
            prompt_path = $promptPath
            research_path = $researchPath
            sop_path = $sopPath
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $decisionPath -Encoding UTF8
    } elseif ($null -ne $finalDecision) {
        $decisionJson = Get-Content -LiteralPath $decisionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $decisionJson | Add-Member -NotePropertyName attempts -NotePropertyValue $attempts.ToArray() -Force
        $decisionJson | Add-Member -NotePropertyName next_replay_executor -NotePropertyValue (Get-ConfigValueOrDefault -Config $config -Key 'executor' -DefaultValue 'codex') -Force
        $decisionJson | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $decisionPath -Encoding UTF8
    }
} else {
    [ordered]@{
        schema = 'external_practice_search.v1'
        final_status = 'QUEUED_AGENT_NOT_RUN'
        safe_for_auto_apply = $false
        reason = 'RunAgent was not enabled'
        prompt_path = $promptPath
        research_path = $researchPath
        sop_path = $sopPath
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $decisionPath -Encoding UTF8
}

if (-not [string]::IsNullOrWhiteSpace($ReplayRoot) -and (Test-Path -LiteralPath $ReplayRoot)) {
    foreach ($name in @('EXTERNAL_PRACTICE_DECISION.json', 'EXTERNAL_PRACTICE_RESEARCH.md', 'EXTERNAL_PRACTICE_SOP.md')) {
        $source = Join-Path $OutputRoot $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $ReplayRoot $name) -Force
        }
    }
}

if (-not $Quiet) {
    Write-Host "External practice search trigger completed."
    Write-Host "Output root: $OutputRoot"
    Write-Host "Prompt: $promptPath"
    Write-Host "Decision: $decisionPath"
}

exit 0
