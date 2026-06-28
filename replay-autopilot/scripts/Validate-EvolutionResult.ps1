param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-ActualKnowledgeVersionFromFile {
    param([string]$EvolutionPromptText)
    if ($EvolutionPromptText -match '(?im)knowledge repo\s*:\s*(.+?)\s*$') {
        $knowledgeRoot = $matches[1].Trim()
        $currentVersionPath = Join-Path $knowledgeRoot 'CURRENT_VERSION.md'
        if (Test-Path -LiteralPath $currentVersionPath) {
            $text = Get-Content -LiteralPath $currentVersionPath -Raw -Encoding UTF8
            if ($text -match '(?im)^\s*\*\*Version\*\*\s*:\s*(v\d+)\s*$') {
                return $matches[1]
            }
        }
    }
    return ''
}

function Get-KnowledgeVersionNumber {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    if ($Version -match '^v(\d+)$') { return [int]$matches[1] }
    return $null
}

function Test-KnowledgeVersionAtLeast {
    param([string]$Actual, [string]$Expected)
    $actualNumber = Get-KnowledgeVersionNumber -Version $Actual
    $expectedNumber = Get-KnowledgeVersionNumber -Version $Expected
    if ($null -eq $actualNumber -or $null -eq $expectedNumber) { return $false }
    return $actualNumber -ge $expectedNumber
}

function Get-KnowledgeRepoState {
    param([string]$EvolutionPromptText)

    $state = [ordered]@{
        Path = ''
        IsGitRepo = $false
        Clean = $false
        LocalCommit = ''
        LocalLog = ''
        Diagnostics = @()
    }

    if ($EvolutionPromptText -match '(?im)knowledge repo\s*:\s*(.+?)\s*$') {
        $state.Path = $matches[1].Trim()
    }
    if ([string]::IsNullOrWhiteSpace($state.Path)) {
        $state.Diagnostics = @('_diag_knowledge_repo_path_not_found')
        return [pscustomobject]$state
    }

    $diagnostics = New-Object System.Collections.Generic.List[string]
    try {
        $gitDir = git -C $state.Path rev-parse --git-dir 2>&1
        if ([string]::IsNullOrWhiteSpace(($gitDir | Out-String).Trim()) -or $LASTEXITCODE -ne 0) {
            $diagnostics.Add('_diag_knowledge_repo_not_a_git_repo')
            $state.Diagnostics = @($diagnostics)
            return [pscustomobject]$state
        }

        $state.IsGitRepo = $true
        $localLog = git -C $state.Path log -1 --format='%H %s' 2>&1
        if (-not [string]::IsNullOrWhiteSpace(($localLog | Out-String).Trim())) {
            $state.LocalLog = ($localLog | Out-String).Trim()
            if ($state.LocalLog -match '^([0-9a-f]{7,40})\b') {
                $state.LocalCommit = $matches[1]
            }
            $diagnostics.Add("_diag_local_commit:$($state.LocalLog)")
        }

        $statusText = git -C $state.Path status --porcelain 2>&1
        $state.Clean = ($LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace(($statusText | Out-String).Trim()))
        $diagnostics.Add("_diag_knowledge_repo_clean:$($state.Clean)")
    } catch {
        $diagnostics.Add('_diag_knowledge_repo_state_error')
    }

    $state.Diagnostics = @($diagnostics)
    return [pscustomobject]$state
}

function Get-UninvokedChangedTooling {
    param([string]$EvolutionText)

    $scriptRoot = Split-Path -Parent $PSCommandPath
    $autopilotRoot = Split-Path -Parent $scriptRoot
    $exempt = @(
        'Run-ReplayLoop.ps1',
        'Run-SliceLoop.ps1',
        'SliceVerifier.ps1',
        'Validate-EvolutionResult.ps1',
        'Validate-ExecutableEvidenceGate.ps1',
        'Verify-PlanContract.ps1',
        'Parse-ReplayReport.ps1'
    )
    $changedScriptNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($EvolutionText, '(?i)(?:replay-autopilot[/\\])?scripts[/\\]([A-Za-z0-9_.-]+\.(?:ps1|py))')) {
        [void]$changedScriptNames.Add($match.Groups[1].Value)
    }
    foreach ($match in [regex]::Matches($EvolutionText, '(?im)^\s*-\s*`?(?:D:)?[^`\r\n]*[/\\]scripts[/\\]([A-Za-z0-9_.-]+\.(?:ps1|py))')) {
        [void]$changedScriptNames.Add($match.Groups[1].Value)
    }

    $uninvoked = New-Object System.Collections.Generic.List[string]
    foreach ($name in $changedScriptNames) {
        if ($name -match '^(?i)Test-' -or $exempt -contains $name) { continue }
        $toolPath = Join-Path $scriptRoot $name
        if (-not (Test-Path -LiteralPath $toolPath)) { continue }

        $foundReference = $false
        $searchRoots = @(
            (Join-Path $autopilotRoot 'scripts'),
            (Join-Path $autopilotRoot 'prompts'),
            (Join-Path $autopilotRoot 'contracts')
        ) | Where-Object { Test-Path -LiteralPath $_ }

        foreach ($root in $searchRoots) {
            $matches = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -ne $toolPath -and
                    $_.Name -notmatch '^(?i)Test-' -and
                    $_.Extension -in @('.ps1', '.py', '.md', '.json', '.prompt')
                } |
                Select-String -SimpleMatch -Pattern $name -Encoding UTF8 -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $matches) {
                $foundReference = $true
                break
            }
        }

        if (-not $foundReference) {
            $uninvoked.Add($name) | Out-Null
        }
    }
    return @($uninvoked)
}

function Get-EvolutionFieldValue {
    param(
        [string]$Text,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Name)) { return '' }
    $escapedName = [regex]::Escape($Name)
    foreach ($rawLine in @($Text -split "\r?\n")) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^\s*[-*]\s+(?<body>.+?)\s*$') { continue }

        $body = $matches['body'].Trim()
        if ($body -match ('^(?:\*\*)?`?' + $escapedName + '`?(?:\*\*)?\s*:\s*(?<value>.+?)\s*$')) {
            $value = $matches['value'].Trim()
            if ($value -match '^\*\*(?<inner>.+)\*\*\s*$') {
                $value = $matches['inner'].Trim()
            }
            return $value.Trim().Trim('`').Trim()
        }
    }
    return ''
}

function Test-EvolutionFieldValue {
    param(
        [string]$Text,
        [string]$Name,
        [string]$Pattern
    )

    $value = Get-EvolutionFieldValue -Text $Text -Name $Name
    return (-not [string]::IsNullOrWhiteSpace($value) -and $value -match $Pattern)
}

function Convert-ToBoolValue {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim()
    return ($text -match '^(?i:true|yes|1)$')
}

function Get-RequiredMachineGatesFromRules {
    param([string]$RulesPath)

    if (-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)) { return @() }

    try {
        $raw = Get-Content -LiteralPath $RulesPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $json = $raw | ConvertFrom-Json
    } catch {
        return @('_invalid_verifiable_rules_json')
    }

    $rules = @()
    if ($null -ne $json.rules) {
        $rules = @($json.rules)
    } else {
        $rules = @($json)
    }

    $gates = New-Object System.Collections.Generic.List[string]
    foreach ($rule in $rules) {
        if ($null -eq $rule) { continue }
        if (-not (Convert-ToBoolValue $rule.must_fix)) { continue }
        $machineGate = ([string]$rule.machine_gate).Trim()
        if ([string]::IsNullOrWhiteSpace($machineGate)) { continue }
        $gates.Add($machineGate) | Out-Null
    }
    return @($gates | Select-Object -Unique)
}

function Test-ClosedMachineGateReported {
    param(
        [string]$ClosedMachineGatesValue,
        [string]$MachineGate
    )

    if ([string]::IsNullOrWhiteSpace($ClosedMachineGatesValue) -or [string]::IsNullOrWhiteSpace($MachineGate)) {
        return $false
    }
    $reported = @($ClosedMachineGatesValue -split '[;,]' | ForEach-Object { ([string]$_).Trim().Trim('`') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($entry in $reported) {
        if ($entry -eq $MachineGate) { return $true }
    }
    return $false
}

function Get-ChangedToolingPathEvidence {
    param([string]$EvolutionText)

    $scriptRoot = Split-Path -Parent $PSCommandPath
    $autopilotRoot = Split-Path -Parent $scriptRoot
    $evidence = [ordered]@{
        Entries = @()
        ExistingEntries = @()
        MissingEntries = @()
        ChangedEntries = @()
        UnchangedEntries = @()
    }

    $changedFilesValue = Get-EvolutionFieldValue -Text $EvolutionText -Name 'changed_files'
    if ([string]::IsNullOrWhiteSpace($changedFilesValue)) {
        return [pscustomobject]$evidence
    }

    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($rawEntry in @($changedFilesValue -split '[;,]')) {
        $entry = ([string]$rawEntry).Trim().Trim('`').Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ($entry -match '(?i)\bnone\b|^n/a$|^na$') { continue }
        $entries.Add($entry) | Out-Null
    }

    $existingEntries = New-Object System.Collections.Generic.List[string]
    $missingEntries = New-Object System.Collections.Generic.List[string]
    $changedEntries = New-Object System.Collections.Generic.List[string]
    $unchangedEntries = New-Object System.Collections.Generic.List[string]
    $gitRoot = ''
    try {
        $gitRootText = git -C $autopilotRoot rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $gitRoot = ($gitRootText | Out-String).Trim()
        }
    } catch {
        $gitRoot = ''
    }
    foreach ($entry in $entries) {
        $candidate = $entry
        if ($candidate -match '(?i)^replay-autopilot[/\\](.+)$') {
            $candidate = Join-Path $autopilotRoot $matches[1]
        } elseif ($candidate -match '^(?i)(scripts|prompts|contracts|tests)[/\\]') {
            $candidate = Join-Path $autopilotRoot $candidate
        }

        if ([System.IO.Path]::IsPathRooted($candidate)) {
            $path = $candidate
        } else {
            $path = Join-Path $autopilotRoot $candidate
        }

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $existingEntries.Add($entry) | Out-Null
            $isChanged = $false
            if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
                try {
                    $fullPath = [System.IO.Path]::GetFullPath($path)
                    $fullGitRoot = [System.IO.Path]::GetFullPath($gitRoot)
                    if ($fullPath.StartsWith($fullGitRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $relativePath = $fullPath.Substring($fullGitRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
                        $statusText = git -C $gitRoot status --porcelain -- $relativePath 2>$null
                        $isChanged = ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($statusText | Out-String).Trim()))
                    }
                } catch {
                    $isChanged = $false
                }
            }
            if ($isChanged) {
                $changedEntries.Add($entry) | Out-Null
            } else {
                $unchangedEntries.Add($entry) | Out-Null
            }
        } else {
            $missingEntries.Add($entry) | Out-Null
        }
    }

    $evidence.Entries = @($entries)
    $evidence.ExistingEntries = @($existingEntries)
    $evidence.MissingEntries = @($missingEntries)
    $evidence.ChangedEntries = @($changedEntries)
    $evidence.UnchangedEntries = @($unchangedEntries)
    return [pscustomobject]$evidence
}

function Test-NoneLikeEvolutionValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value.Trim() -match '(?i)^(?:none|n/a|na|null|empty|no new gate artifacts|no_new_gate_artifacts)$')
}

function Write-Result {
    param(
        [string]$ReplayRootFull,
        [string]$Status,
        [object[]]$Issues,
        [object[]]$Warnings = @(),
        [bool]$StopAndEvolveRequired,
        [string]$Reason
    )

    $result = [ordered]@{
        status = $Status
        stop_and_evolve_required = $StopAndEvolveRequired
        reason = $Reason
        issues = @($Issues)
        warnings = @($Warnings)
        generated_at = (Get-Date).ToString('s')
    }
    $out = Join-Path $ReplayRootFull 'EVOLUTION_RESULT_VERIFY.json'
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
    return $out
}

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'STOP_AND_EVOLVE requires validated evolution result',
            'NO_SOURCE_CHANGE cannot satisfy required tooling experiments',
            'tooling_changes_applied and verification_results are required when stop-loss asks for experiments',
            'gate_budget_decision is required so STOP_AND_EVOLVE prefers regression tests, gate consolidation, or existing-gate enforcement before new gates',
            'knowledge push failure is non-blocking only when the expected knowledge version is locally committed and the working tree is clean'
        )
        RequiredFieldsWhenStopAndEvolve = @(
            'final_status - VALIDATED_TOOLING_EVOLUTION or BLOCKED_NEEDS_EVIDENCE',
            'tooling_changes_applied - true',
            'stop_and_evolve_satisfied - true',
            'gate_budget_decision - regression_test, gate_consolidation, existing_gate_enforcement, or new_gate_exception',
            'new_gate_artifacts - none, or a list of new verify/carrier/machine_gate artifacts',
            'verification_results - PASS or VALIDATED',
            'changed_files - actual replay-autopilot files changed',
            'closed_machine_gates - machine_gate values from verifiable rules',
            'pushed_commit - knowledge repo commit hash or local-only:hash',
            'actual_knowledge_version_after_push - must match CURRENT_VERSION.md when an expected version is declared'
        )
        FieldFormatNote = 'Each required field must be a bullet line: `- field_name: value`. Do not use section headings, bold aliases, or display names.'
    } | Format-List
    exit 0
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "Replay root not found: $replayRootFull"
}

$stopDecisionText = Read-TextIfExists (Join-Path $replayRootFull 'STOP_OR_CONTINUE_DECISION.md')
$stopLossText = Read-TextIfExists (Join-Path $replayRootFull 'STOP_LOSS_DECISION.md')
$autopilotDecisionText = Read-TextIfExists (Join-Path $replayRootFull 'AUTOPILOT_DECISION.md')
$nextExperimentPlanText = Read-TextIfExists (Join-Path $replayRootFull 'NEXT_EXPERIMENT_PLAN.md')
$evolutionPromptText = Read-TextIfExists (Join-Path $replayRootFull 'EVOLUTION_PROMPT.md')
$verifiableRulesPath = Join-Path $replayRootFull 'VERIFIABLE_RULES.json'
$requiredMachineGates = @(Get-RequiredMachineGatesFromRules -RulesPath $verifiableRulesPath)
$warnings = New-Object System.Collections.Generic.List[string]

$expectedKnowledgeVersion = ''
if ($autopilotDecisionText -match '(?im)^\s*-\s*expected_knowledge_version_after_evolution\s*:\s*(v\d+)\s*$') {
    $expectedKnowledgeVersion = $matches[1]
} elseif ($evolutionPromptText -match '(?im)expected next knowledge version\s*:\s*(v\d+)') {
    $expectedKnowledgeVersion = $matches[1]
}

if ($evolutionPromptText -match '(?im)^\s*-\s*current knowledge version\s*:\s*(v\d+)\s*$') {
    $promptCurrentFromPrompt = $matches[1]
    $actualCurrentFromFile = Get-ActualKnowledgeVersionFromFile -EvolutionPromptText $evolutionPromptText
    if (-not [string]::IsNullOrWhiteSpace($actualCurrentFromFile) -and $actualCurrentFromFile -ne $promptCurrentFromPrompt) {
        $warnings.Add("version_drift:prompt_says_${promptCurrentFromPrompt}_actual_${actualCurrentFromFile}")
    }
}

$stopAndEvolveRequired = (
    $stopDecisionText -match '(?i)STOP_AND_EVOLVE|Required Before Next Round|Implement Experiment' -or
    $nextExperimentPlanText -match '(?i)Experiment\s+1|Pre-Slice Cap Display|Carrier Search Verification|Executable Assertion Gate' -or
    $autopilotDecisionText -match '(?i)STOP_DEEP_REVIEW_REQUIRED' -or
    ($autopilotDecisionText -match '(?im)^\s*-\s*run_evolution_in_replay_loop\s*:\s*True\s*$' -and
     $autopilotDecisionText -match '(?im)^\s*-\s*decision\s*:\s*STOP_')
)

if (-not $stopAndEvolveRequired) {
    $path = Write-Result -ReplayRootFull $replayRootFull -Status 'PASS' -Issues @() -StopAndEvolveRequired $false -Reason 'no_stop_and_evolve_requirement'
    Write-Host "Evolution result validation PASS: $path"
    exit 0
}

$evolutionResultPath = Join-Path $replayRootFull 'EVOLUTION_RESULT.md'
$evolutionText = Read-TextIfExists $evolutionResultPath
$issues = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($evolutionText)) {
    $issues.Add('evolution_result_missing')
} else {
    $hasStopSatisfied = Test-EvolutionFieldValue -Text $evolutionText -Name 'stop_and_evolve_satisfied' -Pattern '(?i)^true$'
    $hasValidatedStatus = Test-EvolutionFieldValue -Text $evolutionText -Name 'final_status' -Pattern '(?i)VALIDATED'
    $hasToolingChanges = Test-EvolutionFieldValue -Text $evolutionText -Name 'tooling_changes_applied' -Pattern '(?i)^true$'
    $gateBudgetDecision = Get-EvolutionFieldValue -Text $evolutionText -Name 'gate_budget_decision'
    $validGateBudgetDecisions = @('regression_test', 'gate_consolidation', 'existing_gate_enforcement', 'new_gate_exception')
    $hasGateBudgetDecision = -not [string]::IsNullOrWhiteSpace($gateBudgetDecision)
    $gateBudgetDecisionValid = $hasGateBudgetDecision -and ($validGateBudgetDecisions -contains $gateBudgetDecision.Trim().ToLowerInvariant())
    $newGateArtifacts = Get-EvolutionFieldValue -Text $evolutionText -Name 'new_gate_artifacts'
    $hasNewGateArtifactsField = -not [string]::IsNullOrWhiteSpace($newGateArtifacts)
    $declaresNewGateArtifacts = $hasNewGateArtifactsField -and -not (Test-NoneLikeEvolutionValue -Value $newGateArtifacts)
    $newGateExceptionRationale = Get-EvolutionFieldValue -Text $evolutionText -Name 'new_gate_exception_rationale'
    $closedMachineGatesValue = Get-EvolutionFieldValue -Text $evolutionText -Name 'closed_machine_gates'
    $hasPassingVerification = Test-EvolutionFieldValue -Text $evolutionText -Name 'verification_results' -Pattern '(?i)(PASS|VALIDATED)'
    if (-not $hasPassingVerification) {
        $hasPassingVerification = Test-EvolutionFieldValue -Text $evolutionText -Name 'verification_result' -Pattern '(?i)(PASS|VALIDATED)'
    }
    $changedToolingEvidence = Get-ChangedToolingPathEvidence -EvolutionText $evolutionText
    $pushedCommitValue = Get-EvolutionFieldValue -Text $evolutionText -Name 'pushed_commit'
    $hasPushedCommit = (-not [string]::IsNullOrWhiteSpace($pushedCommitValue) -and $pushedCommitValue -notmatch '(?i)^(?:none|n/a|blocked|not attempted|manual|local-only)\b')
    $mentionsToolingDiff = $evolutionText -match '(?i)(replay-autopilot[/\\](scripts|prompts|contracts)|scripts[/\\]|prompts[/\\]|contracts[/\\]|Run-ReplayLoop\.ps1|Run-SliceLoop\.ps1|Verify-|Validate-)'
    $isNoSourceChange = $evolutionText -match '(?i)NO_SOURCE_CHANGE|NO_SKILL_SOURCE_CHANGE|no-source-change|noop-evolution|no source changes required'
    $hasCommitOrPushFailure = $evolutionText -match '(?i)commit\s+(?:blocked|failed)|push\s+status\s*:\s*(?:not attempted|failed|blocked)|remote\s+push\s+(?:failed|blocked)|not attempted \(commit blocked\)|manual commit required|uncommitted|actual_knowledge_version_after_push\s*:\s*v\d+\s*\([^)]*(?:blocked|failed|not attempted)[^)]*\)'
    $verificationValue = Get-EvolutionFieldValue -Text $evolutionText -Name 'verification_results'
    if ([string]::IsNullOrWhiteSpace($verificationValue)) {
        $verificationValue = Get-EvolutionFieldValue -Text $evolutionText -Name 'verification_result'
    }
    $hasManualOnlyVerification = $verificationValue -match '(?i)^.*manual (?:code )?review.*$'
    $hasDeferredRunnerIntegration = $evolutionText -match '(?is)(runner\s+should\s+integrate|should\s+integrate\s+these\s+scripts|next\s+steps.{0,800}integrate\s+these\s+scripts|not\s+yet\s+integrated\s+into\s+runner)'
    $actualKnowledgeVersionMatches = $true
    if (-not [string]::IsNullOrWhiteSpace($expectedKnowledgeVersion)) {
        $actualKnowledgeVersionMatches = $false
        $reportedActualKnowledgeVersion = Get-EvolutionFieldValue -Text $evolutionText -Name 'actual_knowledge_version_after_push'
        if ($reportedActualKnowledgeVersion -match '^(v\d+)\b') {
            $reportedActualKnowledgeVersion = $matches[1]
            $actualKnowledgeVersionMatches = Test-KnowledgeVersionAtLeast -Actual $reportedActualKnowledgeVersion -Expected $expectedKnowledgeVersion
        }
    }
    $actualKnowledgeVersionFromFile = ''
    if (-not [string]::IsNullOrWhiteSpace($expectedKnowledgeVersion)) {
        $actualKnowledgeVersionFromFile = Get-ActualKnowledgeVersionFromFile -EvolutionPromptText $evolutionPromptText
    }
    $actualKnowledgeVersionFileMatches = (
        -not [string]::IsNullOrWhiteSpace($expectedKnowledgeVersion) -and
        -not [string]::IsNullOrWhiteSpace($actualKnowledgeVersionFromFile) -and
        (Test-KnowledgeVersionAtLeast -Actual $actualKnowledgeVersionFromFile -Expected $expectedKnowledgeVersion)
    )
    $reportedLocalCommit = ''
    foreach ($fieldName in @('local_commit', 'knowledge_repo_local_commit', 'pushed_commit')) {
        if (-not [string]::IsNullOrWhiteSpace($reportedLocalCommit)) { break }
        $fieldValue = Get-EvolutionFieldValue -Text $evolutionText -Name $fieldName
        if ($fieldValue -match '(?i)local-only:([0-9a-f]{7,40})') {
            $reportedLocalCommit = $matches[1]
        } elseif ($fieldValue -match '^([0-9a-f]{7,40})\b') {
            $reportedLocalCommit = $matches[1]
        }
    }
    $knowledgeState = Get-KnowledgeRepoState -EvolutionPromptText $evolutionPromptText
    $localCommitMatchesReport = (
        -not [string]::IsNullOrWhiteSpace($reportedLocalCommit) -and
        -not [string]::IsNullOrWhiteSpace($knowledgeState.LocalCommit) -and
        $knowledgeState.LocalCommit.StartsWith($reportedLocalCommit, [System.StringComparison]::OrdinalIgnoreCase)
    )
    $localKnowledgeCommitAccepted = (
        $hasCommitOrPushFailure -and
        -not $hasPushedCommit -and
        -not [string]::IsNullOrWhiteSpace($knowledgeState.LocalCommit) -and
        $knowledgeState.Clean -and
        $actualKnowledgeVersionFileMatches -and
        $localCommitMatchesReport
    )
    $reportsUninvokedPlanContractPython = $false
    if ($evolutionText -match '(?i)plan_contract_verify\.py') {
        $runLoopPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Run-ReplayLoop.ps1'
        $runLoopText = Read-TextIfExists $runLoopPath
        $reportsUninvokedPlanContractPython = $runLoopText -notmatch '(?i)plan_contract_verify\.py'
    }

    if (-not $hasStopSatisfied) { $issues.Add('stop_and_evolve_satisfied_missing_or_false') }
    if (-not $hasValidatedStatus) { $issues.Add('final_status_not_validated') }
    if (-not $hasToolingChanges) { $issues.Add('tooling_changes_applied_missing_or_false') }
    if (-not $hasGateBudgetDecision) {
        $issues.Add('gate_budget_decision_missing')
    } elseif (-not $gateBudgetDecisionValid) {
        $issues.Add("gate_budget_decision_invalid:$gateBudgetDecision")
    }
    if (-not $hasNewGateArtifactsField) {
        $issues.Add('new_gate_artifacts_missing')
    }
    if ($declaresNewGateArtifacts -and $gateBudgetDecision.Trim().ToLowerInvariant() -ne 'new_gate_exception') {
        $issues.Add('new_gate_artifacts_require_new_gate_exception_decision')
    }
    if ($gateBudgetDecision.Trim().ToLowerInvariant() -eq 'new_gate_exception') {
        if ([string]::IsNullOrWhiteSpace($newGateExceptionRationale)) {
            $issues.Add('new_gate_exception_rationale_missing')
        } else {
            if ($newGateExceptionRationale -notmatch '(?i)(existing_gate|existing gate)') {
                $issues.Add('new_gate_exception_existing_gate_gap_missing')
            }
            if ($newGateExceptionRationale -notmatch '(?i)(regression|Test-v)') {
                $issues.Add('new_gate_exception_regression_test_missing')
            }
            if ($newGateExceptionRationale -notmatch '(?i)(runner|Run-ReplayLoop|Run-SliceLoop)') {
                $issues.Add('new_gate_exception_runner_integration_missing')
            }
        }
    }
    if (-not $hasPassingVerification) { $issues.Add('verification_results_missing_or_not_pass') }
    foreach ($requiredMachineGate in $requiredMachineGates) {
        if ($requiredMachineGate -eq '_invalid_verifiable_rules_json') {
            $issues.Add('verifiable_rules_json_invalid')
            continue
        }
        if (-not (Test-ClosedMachineGateReported -ClosedMachineGatesValue $closedMachineGatesValue -MachineGate $requiredMachineGate)) {
            $issues.Add("closed_machine_gate_missing:$requiredMachineGate")
        }
    }
    if (-not $hasPushedCommit -and -not $localKnowledgeCommitAccepted) { $issues.Add('pushed_commit_missing_or_blocked') }
    if (-not $mentionsToolingDiff) { $issues.Add('tooling_changed_files_not_reported') }
    if (@($changedToolingEvidence.ExistingEntries).Count -eq 0) {
        $issues.Add('tooling_changed_files_no_existing_replay_autopilot_file')
    }
    if (@($changedToolingEvidence.ChangedEntries).Count -eq 0) {
        $issues.Add('tooling_changed_files_no_git_diff_entry')
    }
    foreach ($unchangedChangedFile in @($changedToolingEvidence.UnchangedEntries)) {
        $issues.Add("tooling_changed_file_not_in_git_diff:$unchangedChangedFile")
    }
    foreach ($missingChangedFile in @($changedToolingEvidence.MissingEntries)) {
        $issues.Add("tooling_changed_file_missing:$missingChangedFile")
    }
    if ($isNoSourceChange -and -not $hasToolingChanges) { $issues.Add('no_source_change_cannot_satisfy_stop_and_evolve') }
    if ($hasCommitOrPushFailure) {
        if ($localKnowledgeCommitAccepted) {
            $warnings.Add('knowledge_repo_push_failed_local_commit_accepted')
            foreach ($diag in @($knowledgeState.Diagnostics)) { $warnings.Add($diag) }
        } else {
            $issues.Add('knowledge_repo_commit_or_push_blocked')
            foreach ($diag in @($knowledgeState.Diagnostics)) { $issues.Add($diag) }
        }
    }
    if ($hasManualOnlyVerification) { $issues.Add('manual_review_cannot_be_sole_verification') }
    if ($hasDeferredRunnerIntegration) { $issues.Add('tooling_not_integrated_into_runner') }
    if (-not $actualKnowledgeVersionMatches -and -not $localKnowledgeCommitAccepted) { $issues.Add("actual_knowledge_version_after_push_not_expected:$expectedKnowledgeVersion") }
    if (-not [string]::IsNullOrWhiteSpace($expectedKnowledgeVersion)) {
        if (-not [string]::IsNullOrWhiteSpace($actualKnowledgeVersionFromFile) -and -not (Test-KnowledgeVersionAtLeast -Actual $actualKnowledgeVersionFromFile -Expected $expectedKnowledgeVersion)) {
            $issues.Add("actual_knowledge_version_file_not_expected:$expectedKnowledgeVersion")
        }
    }
    if ($reportsUninvokedPlanContractPython) { $issues.Add('changed_tooling_not_runner_invoked:plan_contract_verify.py') }
    foreach ($uninvokedTool in (Get-UninvokedChangedTooling -EvolutionText $evolutionText)) {
        $issues.Add("changed_tooling_not_runner_invoked:$uninvokedTool")
    }
}

if ($issues.Count -gt 0) {
    $path = Write-Result -ReplayRootFull $replayRootFull -Status 'FAIL' -Issues @($issues) -Warnings @($warnings) -StopAndEvolveRequired $true -Reason 'required_stop_and_evolve_not_satisfied'
    Write-Host "Evolution result validation FAIL: $path"
    foreach ($issue in $issues) { Write-Host " - $issue" }
    Write-Host ''
    Write-Host 'The EVOLUTION_RESULT.md file is missing or has incorrect required machine fields.'
    Write-Host 'When STOP_AND_EVOLVE is required, these bullet fields must be present:'
    Write-Host '  - final_status: VALIDATED_TOOLING_EVOLUTION (or BLOCKED_NEEDS_EVIDENCE)'
    Write-Host '  - tooling_changes_applied: true'
    Write-Host '  - stop_and_evolve_satisfied: true'
    Write-Host '  - gate_budget_decision: regression_test | gate_consolidation | existing_gate_enforcement | new_gate_exception'
    Write-Host '  - new_gate_artifacts: none (or list new gate artifacts with new_gate_exception_rationale)'
    Write-Host '  - verification_results: PASS (or VALIDATED)'
    Write-Host '  - changed_files: <actual replay-autopilot scripts/prompts/tests changed>'
    Write-Host '  - closed_machine_gates: <machine_gate values from verifiable rules>'
    Write-Host '  - pushed_commit: <knowledge repo commit hash or local-only:hash>'
    Write-Host '  - actual_knowledge_version_after_push: v<N>'
    Write-Host 'Each field must be a bullet line (`- field_name: value`), not a section heading, bold alias, or display name.'
    Write-Host 'Edit EVOLUTION_RESULT.md to add the missing fields, then re-run Validate-EvolutionResult.ps1.'
    exit 1
}

$passPath = Write-Result -ReplayRootFull $replayRootFull -Status 'PASS' -Issues @() -Warnings @($warnings) -StopAndEvolveRequired $true -Reason 'validated_stop_and_evolve'
Write-Host "Evolution result validation PASS: $passPath"
exit 0
