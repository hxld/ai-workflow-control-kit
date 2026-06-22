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
            'knowledge push failure is non-blocking only when the expected knowledge version is locally committed and the working tree is clean'
        )
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
    $hasPassingVerification = Test-EvolutionFieldValue -Text $evolutionText -Name 'verification_results' -Pattern '(?i)(PASS|VALIDATED)'
    if (-not $hasPassingVerification) {
        $hasPassingVerification = Test-EvolutionFieldValue -Text $evolutionText -Name 'verification_result' -Pattern '(?i)(PASS|VALIDATED)'
    }
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
    if (-not $hasPassingVerification) { $issues.Add('verification_results_missing_or_not_pass') }
    if (-not $hasPushedCommit -and -not $localKnowledgeCommitAccepted) { $issues.Add('pushed_commit_missing_or_blocked') }
    if (-not $mentionsToolingDiff) { $issues.Add('tooling_changed_files_not_reported') }
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
    exit 1
}

$passPath = Write-Result -ReplayRootFull $replayRootFull -Status 'PASS' -Issues @() -Warnings @($warnings) -StopAndEvolveRequired $true -Reason 'validated_stop_and_evolve'
Write-Host "Evolution result validation PASS: $passPath"
exit 0
