param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [int]$TargetVersion = 180,
    [int]$MaxIterations = 12,
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [switch]$AllowCodexExecutor,
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
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') { throw "Unsupported config line: $line" }
        $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
    return $result
}

function Require-Key {
    param([hashtable]$Config, [string]$Key)
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

function Invoke-KnowledgeBackupSyncSafe {
    param(
        [hashtable]$Config,
        [string]$ConfigPath,
        [string]$ReplayRootBase,
        [string]$LogPath
    )

    $autoSync = Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_auto_sync' -DefaultValue 'true')
    if (-not $autoSync) {
        return
    }

    $syncScript = Join-Path $PSScriptRoot 'Sync-KnowledgeBackup.ps1'
    if (-not (Test-Path -LiteralPath $syncScript)) {
        throw "Knowledge backup sync script is missing: $syncScript"
    }

    $evidenceMode = Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_evidence_mode' -DefaultValue 'None'
    if (@('None', 'Milestone', 'Always') -notcontains $evidenceMode) {
        throw "Unsupported knowledge_backup_evidence_mode: $evidenceMode"
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $syncScript,
        '-ConfigPath', $ConfigPath,
        '-IncludeAutopilot',
        '-IncludeKnowledge',
        '-EvidenceMode', $evidenceMode
    )
    if (-not [string]::IsNullOrWhiteSpace($ReplayRootBase)) {
        $evidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $ReplayRootBase
        if (-not [string]::IsNullOrWhiteSpace($evidenceRoot)) {
            $args += @('-EvidenceRoot', $evidenceRoot)
        }
    }
    if (Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_auto_push' -DefaultValue 'true')) {
        $args += '-Push'
    }

    & powershell @args
    if ($LASTEXITCODE -ne 0) {
        throw "Knowledge backup sync failed with exit code $LASTEXITCODE"
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and (Test-Path -LiteralPath (Split-Path -Parent $LogPath))) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_sync=done evidence_mode=$evidenceMode"
    }
}

function Replace-VersionToken {
    param([string]$Value, [string]$VersionToken)
    $match = [regex]::Match($Value, 'v[0-9]+')
    if ($match.Success) {
        return $Value.Substring(0, $match.Index) + $VersionToken + $Value.Substring($match.Index + $match.Length)
    }
    if ([string]::IsNullOrWhiteSpace($Value)) { return $VersionToken }
    return "$Value-$VersionToken"
}

function Get-LatestKnowledgeVersion {
    param([string]$KnowledgeRepo)

    $repo = Resolve-AbsolutePath $KnowledgeRepo
    if (-not (Test-Path -LiteralPath $repo)) {
        throw "Knowledge repo not found: $repo"
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $historyDir = Join-Path $repo 'custom-skills-history'
    if (Test-Path -LiteralPath $historyDir) {
        Get-ChildItem -LiteralPath $historyDir -File -Filter 'v*.md' | ForEach-Object {
            if ($_.Name -match '^v([0-9]+)(?:[-.]|$)') {
                $candidates.Add([pscustomobject]@{
                    Number = [int]$matches[1]
                    Version = ('v{0}' -f $matches[1])
                    Source = $_.FullName
                    LastWriteTime = $_.LastWriteTime
                    Kind = 'history-file'
                })
            }
        }
    }

    $changelogPath = Join-Path $repo 'guide-sections\changelog.md'
    if (Test-Path -LiteralPath $changelogPath) {
        Select-String -LiteralPath $changelogPath -Pattern '^\s*#{1,6}\s*v([0-9]+)\b' -Encoding UTF8 | ForEach-Object {
            $candidates.Add([pscustomobject]@{
                Number = [int]$_.Matches[0].Groups[1].Value
                Version = ('v{0}' -f $_.Matches[0].Groups[1].Value)
                Source = "${changelogPath}:$($_.LineNumber)"
                LastWriteTime = (Get-Item -LiteralPath $changelogPath).LastWriteTime
                Kind = 'changelog-heading'
            })
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No knowledge version found under $repo."
    }

    return $candidates | Sort-Object Number, LastWriteTime -Descending | Select-Object -First 1
}

function Get-NextRound {
    param([string]$ReplayRootBase)
    $parent = Split-Path -Parent $ReplayRootBase
    $leaf = Split-Path -Leaf $ReplayRootBase
    if (-not (Test-Path -LiteralPath $parent)) { return 1 }
    $max = 0
    Get-ChildItem -LiteralPath $parent -Directory -Filter "$leaf-r*" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '-r([0-9]+)$') {
            $n = [int]$matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return ($max + 1)
}

function Write-Status {
    param(
        [string]$Path,
        [object]$Data
    )
    $Data | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-AttemptLogPath {
    param(
        [string]$Path,
        [int]$Attempt
    )
    if ($Attempt -le 1) { return $Path }
    $dir = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    return (Join-Path $dir ("$name.attempt$Attempt$ext"))
}

function Invoke-ProcessWithRetry {
    param(
        [string]$FilePath,
        [object[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath,
        [string]$LogPath,
        [string]$Label = 'process',
        [int]$MaxRetries = 2,
        [int]$DelaySeconds = 60
    )

    # Evolution may hit transient Claude executor errors such as API Error: 400 / 1210 or 429.
    # Retry only a few times; persistent failures still surface as BLOCKED_EVOLUTION_EXIT.
    $attempt = 0
    while ($true) {
        $attempt++
        $attemptOut = Get-AttemptLogPath -Path $StdoutPath -Attempt $attempt
        $attemptErr = Get-AttemptLogPath -Path $StderrPath -Attempt $attempt
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $attemptOut -RedirectStandardError $attemptErr -NoNewWindow -PassThru -Wait
        $exitCode = $process.ExitCode
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) $Label attempt=$attempt exit=$exitCode stdout=$attemptOut stderr=$attemptErr"
        if ($exitCode -eq 0) {
            return [pscustomobject]@{
                ExitCode = 0
                Stdout = $attemptOut
                Stderr = $attemptErr
                Attempts = $attempt
            }
        }
        if ($attempt -le $MaxRetries) {
            Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) $Label retry_after_exit=$exitCode delay_seconds=$DelaySeconds"
            Start-Sleep -Seconds $DelaySeconds
            continue
        }
        return [pscustomobject]@{
            ExitCode = $exitCode
            Stdout = $attemptOut
            Stderr = $attemptErr
            Attempts = $attempt
        }
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml $configPathFull
$projectRoot = Resolve-AbsolutePath (Require-Key $config 'project_root')
$knowledgeRepo = Resolve-AbsolutePath (Require-Key $config 'knowledge_repo')
$replayRootBaseTemplate = Resolve-AbsolutePath (Require-Key $config 'replay_root_base')
$executorActual = if ($config.ContainsKey('executor') -and -not [string]::IsNullOrWhiteSpace($config['executor'])) { $config['executor'] } else { 'claude' }
if (@('codex', 'claude', 'manual') -notcontains $executorActual) {
    throw "Unsupported executor in config: $executorActual"
}
$requiredExecutorActual = if (-not [string]::IsNullOrWhiteSpace($RequireExecutor)) {
    $RequireExecutor
} elseif ($config.ContainsKey('require_executor')) {
    $config['require_executor']
} else {
    ''
}
if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual) -and $executorActual -ne $requiredExecutorActual) {
    throw "Executor policy violation: actual executor '$executorActual' does not match required executor '$requiredExecutorActual'."
}
    $allowCodexExecutorActual = [bool]$AllowCodexExecutor -or (Convert-ToBool $(if ($config.ContainsKey('allow_codex_executor')) { $config['allow_codex_executor'] } else { '' }))
if ($executorActual -eq 'codex' -and -not $allowCodexExecutorActual) {
    throw "Executor policy violation: Codex executor is blocked by default. Use executor: claude, or pass -AllowCodexExecutor / allow_codex_executor:true only for an explicitly approved Codex run."
}
$timeoutMinutes = if ($config.ContainsKey('executor_timeout_minutes') -and -not [string]::IsNullOrWhiteSpace($config['executor_timeout_minutes'])) { [int]$config['executor_timeout_minutes'] } else { 240 }
$sandbox = if ($config.ContainsKey('codex_sandbox')) { $config['codex_sandbox'] } else { 'danger-full-access' }
$approval = if ($config.ContainsKey('codex_approval')) { $config['codex_approval'] } else { 'never' }
$model = if ($executorActual -eq 'codex') {
    if ($config.ContainsKey('codex_model')) { $config['codex_model'] } else { '' }
} else {
    if ($config.ContainsKey('claude_model')) { $config['claude_model'] } else { '' }
}
$defaultReasoningEffort = if ($executorActual -eq 'codex' -and $config.ContainsKey('codex_reasoning_effort')) { $config['codex_reasoning_effort'] } else { '' }
if ($executorActual -eq 'claude') {
    $evolutionModel = Get-ConfigValueOrDefault -Config $config -Key 'claude_evolution_model' -DefaultValue $(Get-ConfigValueOrDefault -Config $config -Key 'claude_model' -DefaultValue 'claude-opus-4-7')
    $evolutionReasoningEffort = ''
} else {
    $evolutionModel = Get-ConfigValueOrDefault -Config $config -Key 'evolution_model' -DefaultValue $model
    $evolutionReasoningEffort = Get-ConfigValueOrDefault -Config $config -Key 'evolution_reasoning_effort' -DefaultValue $defaultReasoningEffort
}

if ($ValidateOnly) {
    $latest = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
    [pscustomobject]@{
        Status = 'VALID'
        Config = $configPathFull
        ProjectRoot = $projectRoot
        KnowledgeRepo = $knowledgeRepo
        LatestKnowledgeVersion = $latest.Version
        LatestKnowledgeSource = $latest.Source
        TargetVersion = ('v{0}' -f $TargetVersion)
        MaxIterations = $MaxIterations
        Executor = $executorActual
        RequireExecutor = $requiredExecutorActual
        AllowCodexExecutor = $allowCodexExecutorActual
        TimeoutMinutes = $timeoutMinutes
        EvolutionModel = $evolutionModel
        EvolutionReasoningEffort = $evolutionReasoningEffort
    } | Format-List
    exit 0
}

$runLogDir = Join-Path $scriptRoot 'run-logs'
New-Item -ItemType Directory -Force -Path $runLogDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = "until-v$TargetVersion-$stamp"
$logPath = Join-Path $runLogDir "$runId.log"
$statusPath = Join-Path $runLogDir "$runId.status.json"

Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) START target=v$TargetVersion max_iterations=$MaxIterations"

for ($i = 1; $i -le $MaxIterations; $i++) {
    $before = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
    $replayRootBase = Replace-VersionToken -Value $replayRootBaseTemplate -VersionToken $before.Version
    $round = Get-NextRound -ReplayRootBase $replayRootBase
    $roundId = 'r{0:D2}' -f $round
    $replayRoot = "$replayRootBase-$roundId"
    $roundLog = Join-Path $runLogDir "$runId-$($before.Version)-$roundId-replay.log"
    $expectedAfterEvolution = 'v{0}' -f ($before.Number + 1)

    Write-Status -Path $statusPath -Data ([ordered]@{
        status = 'RUNNING_REPLAY'
        iteration = $i
        targetVersion = $TargetVersion
        latestVersionBefore = $before.Version
        replayRoot = $replayRoot
        round = $roundId
        log = $logPath
        updatedAt = (Get-Date).ToString('s')
    })
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) ITERATION $i replay latest=$($before.Version) round=$roundId root=$replayRoot"

    $roundErr = [System.IO.Path]::ChangeExtension($roundLog, '.err.log')
    $replayArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'),
        '-UseLatestKnowledgeVersion',
        '-StartRound', [string]$round,
        '-Rounds', '1'
    )
    if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual)) { $replayArgs += @('-RequireExecutor', $requiredExecutorActual) }
    if ($allowCodexExecutorActual) { $replayArgs += '-AllowCodexExecutor' }
    $replayProcess = Start-Process -FilePath powershell.exe -ArgumentList $replayArgs -WorkingDirectory $projectRoot -RedirectStandardOutput $roundLog -RedirectStandardError $roundErr -NoNewWindow -PassThru -Wait
    $replayExit = $replayProcess.ExitCode
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) ITERATION $i replay_exit=$replayExit replay_log=$roundLog replay_err=$roundErr"
    if ($replayExit -ne 0) {
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'BLOCKED_REPLAY_EXIT'
            iteration = $i
            exitCode = $replayExit
            replayRoot = $replayRoot
            replayLog = $roundLog
            updatedAt = (Get-Date).ToString('s')
        })
        exit $replayExit
    }

    $blocker = Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md'
    if (Test-Path -LiteralPath $blocker) {
        $blockedEvolutionPrompt = Join-Path $replayRoot 'EVOLUTION_PROMPT.md'
        if (-not (Test-Path -LiteralPath $blockedEvolutionPrompt)) {
            Write-Status -Path $statusPath -Data ([ordered]@{
                status = 'BLOCKED_REPLAY'
                iteration = $i
                replayRoot = $replayRoot
                blocker = $blocker
                updatedAt = (Get-Date).ToString('s')
            })
            Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) BLOCKED replay blocker=$blocker"
            exit 2
        }
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'REPLAY_BLOCKED_EVOLUTION_PENDING'
            iteration = $i
            replayRoot = $replayRoot
            blocker = $blocker
            evolutionPrompt = $blockedEvolutionPrompt
            updatedAt = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) REPLAY_BLOCKED evolution_prompt_present blocker=$blocker prompt=$blockedEvolutionPrompt"
    }

    $stopLossDecision = Join-Path $replayRoot 'STOP_LOSS_DECISION.json'
    if (Test-Path -LiteralPath $stopLossDecision) {
        $stopLoss = Get-Content -LiteralPath $stopLossDecision -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([bool]$stopLoss.should_stop) {
            $requiredDeepReview = @(
                'DEEP_REVIEW_REPORT.md',
                'ROOT_CAUSE_LEDGER.json',
                'NEXT_EXPERIMENT_PLAN.md',
                'STOP_OR_CONTINUE_DECISION.md'
            )
            $missingDeepReview = @($requiredDeepReview | Where-Object { -not (Test-Path -LiteralPath (Join-Path $replayRoot $_)) })
            if ($missingDeepReview.Count -gt 0) {
                Write-Status -Path $statusPath -Data ([ordered]@{
                    status = 'BLOCKED_STOPLOSS_REVIEW_MISSING'
                    iteration = $i
                    replayRoot = $replayRoot
                    stopLossDecision = $stopLossDecision
                    missing = $missingDeepReview
                    updatedAt = (Get-Date).ToString('s')
                })
                Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) BLOCKED stoploss review missing root=$replayRoot missing=$($missingDeepReview -join ',')"
                exit 7
            }

            Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOPLOSS triggered root=$replayRoot decision=$($stopLoss.decision); proceeding to evolution with deep review inputs"
        }
    }

    $evolutionPrompt = Join-Path $replayRoot 'EVOLUTION_PROMPT.md'
    if (-not (Test-Path -LiteralPath $evolutionPrompt)) {
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'BLOCKED_NO_EVOLUTION_PROMPT'
            iteration = $i
            replayRoot = $replayRoot
            updatedAt = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) BLOCKED no evolution prompt root=$replayRoot"
        exit 3
    }

    $evolutionLogDir = Join-Path $replayRoot 'logs\evolution'
    $evolutionResultPath = Join-Path $replayRoot 'EVOLUTION_RESULT.md'
    if (Test-Path -LiteralPath $evolutionResultPath) {
        Remove-Item -LiteralPath $evolutionResultPath -Force
    }
    $evolutionArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
        '-PromptPath', $evolutionPrompt,
        '-WorkDir', $projectRoot,
        '-LogDir', $evolutionLogDir,
        '-Executor', $executorActual,
        '-Sandbox', $sandbox,
        '-Approval', $approval,
        '-TimeoutMinutes', $timeoutMinutes,
        '-Name', 'evolution',
        '-CompletionPath', $evolutionResultPath,
        '-CompletionQuietSeconds', '90'
    )
    if (-not [string]::IsNullOrWhiteSpace($evolutionModel)) {
        $evolutionArgs += @('-Model', $evolutionModel)
    }
    if (-not [string]::IsNullOrWhiteSpace($evolutionReasoningEffort)) {
        $evolutionArgs += @('-ReasoningEffort', $evolutionReasoningEffort)
    }

    Write-Status -Path $statusPath -Data ([ordered]@{
        status = 'RUNNING_EVOLUTION'
        iteration = $i
        targetVersion = $TargetVersion
        latestVersionBefore = $before.Version
        expectedVersionAfterEvolution = $expectedAfterEvolution
        replayRoot = $replayRoot
        evolutionPrompt = $evolutionPrompt
        log = $logPath
        updatedAt = (Get-Date).ToString('s')
    })
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) ITERATION $i evolution_start prompt=$evolutionPrompt"
    $decisionPath = Join-Path $replayRoot 'AUTOPILOT_DECISION.md'
    if (Test-Path -LiteralPath $decisionPath) {
        Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
            '',
            '## Evolution Execution',
            "- evolution_execution_owner: Run-UntilKnowledgeVersion.ps1",
            "- run_evolution_by_until_runner: true",
            "- evolution_execution_status: RUNNING",
            "- evolution_execution_started_at: $(Get-Date -Format s)"
        )
    }
    $evolutionProcessOut = Join-Path $runLogDir "$runId-$($before.Version)-$roundId-evolution.out.log"
    $evolutionProcessErr = Join-Path $runLogDir "$runId-$($before.Version)-$roundId-evolution.err.log"
    $evolutionProcess = Invoke-ProcessWithRetry `
        -FilePath powershell.exe `
        -ArgumentList $evolutionArgs `
        -WorkingDirectory $projectRoot `
        -StdoutPath $evolutionProcessOut `
        -StderrPath $evolutionProcessErr `
        -LogPath $logPath `
        -Label 'evolution' `
        -MaxRetries 2 `
        -DelaySeconds 60
    $evolutionExit = $evolutionProcess.ExitCode
    $evolutionProcessOut = $evolutionProcess.Stdout
    $evolutionProcessErr = $evolutionProcess.Stderr
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) ITERATION $i evolution_exit=$evolutionExit evolution_attempts=$($evolutionProcess.Attempts) evolution_out=$evolutionProcessOut evolution_err=$evolutionProcessErr"
    if ($evolutionExit -ne 0) {
        if (Test-Path -LiteralPath $decisionPath) {
            Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
                "- evolution_execution_status: FAILED",
                "- evolution_exit_code: $evolutionExit",
                "- evolution_execution_finished_at: $(Get-Date -Format s)"
            )
        }
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'BLOCKED_EVOLUTION_EXIT'
            iteration = $i
            exitCode = $evolutionExit
            replayRoot = $replayRoot
            evolutionLogDir = $evolutionLogDir
            updatedAt = (Get-Date).ToString('s')
        })
        exit $evolutionExit
    }

    $evolutionValidationScript = Join-Path $PSScriptRoot 'Validate-EvolutionResult.ps1'
    if (Test-Path -LiteralPath $evolutionValidationScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $evolutionValidationScript -ReplayRoot $replayRoot
        $evolutionValidationExit = $LASTEXITCODE
        if ($evolutionValidationExit -ne 0) {
            $evolutionVerifyPath = Join-Path $replayRoot 'EVOLUTION_RESULT_VERIFY.json'
            $previousEvolutionResult = Join-Path $replayRoot 'EVOLUTION_RESULT_PRE_REPAIR.md'
            if (Test-Path -LiteralPath $evolutionResultPath) {
                Copy-Item -LiteralPath $evolutionResultPath -Destination $previousEvolutionResult -Force
            }
            $evolutionRepairPrompt = Join-Path $replayRoot 'EVOLUTION_REPAIR_PROMPT.md'
            $nextExperimentPlan = Join-Path $replayRoot 'NEXT_EXPERIMENT_PLAN.md'
            @"
# Evolution Repair Prompt

The previous evolution execution failed validation.

Inputs:
- replay root: $replayRoot
- failed verification: $evolutionVerifyPath
- previous result: $previousEvolutionResult
- original evolution prompt: $evolutionPrompt
- next experiment plan: $nextExperimentPlan
- replay autopilot root: $scriptRoot
- project root: $projectRoot
- knowledge repo: $knowledgeRepo
- expected knowledge version: $expectedAfterEvolution

Mandatory repair:
1. Implement concrete tooling/prompt/verifier/test changes in the existing replay autopilot repository.
2. Prefer existing PowerShell scripts/prompts/tests; do not invent unattached JS filenames unless you add and invoke them.
3. Run the smallest relevant regression tests.
4. Update and push the knowledge repo.
5. Overwrite `$evolutionResultPath` only after side effects are complete.

Required machine lines:
- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: <actual replay-autopilot scripts/prompts/tests changed>
- actual_knowledge_version_after_push: $expectedAfterEvolution
"@ | Set-Content -LiteralPath $evolutionRepairPrompt -Encoding UTF8
            if (Test-Path -LiteralPath $evolutionResultPath) {
                Remove-Item -LiteralPath $evolutionResultPath -Force
            }
            $evolutionRepairLogDir = Join-Path $replayRoot 'logs\evolution-repair'
            $evolutionRepairArgs = @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
                '-PromptPath', $evolutionRepairPrompt,
                '-WorkDir', $projectRoot,
                '-LogDir', $evolutionRepairLogDir,
                '-Executor', $executorActual,
                '-Sandbox', $sandbox,
                '-Approval', $approval,
                '-TimeoutMinutes', $timeoutMinutes,
                '-Name', 'evolution-repair',
                '-CompletionPath', $evolutionResultPath,
                '-CompletionQuietSeconds', '90'
            )
            if (-not [string]::IsNullOrWhiteSpace($evolutionModel)) {
                $evolutionRepairArgs += @('-Model', $evolutionModel)
            }
            if (-not [string]::IsNullOrWhiteSpace($evolutionReasoningEffort)) {
                $evolutionRepairArgs += @('-ReasoningEffort', $evolutionReasoningEffort)
            }
            $evolutionRepairOut = Join-Path $runLogDir "$runId-$($before.Version)-$roundId-evolution-repair.out.log"
            $evolutionRepairErr = Join-Path $runLogDir "$runId-$($before.Version)-$roundId-evolution-repair.err.log"
            $evolutionRepairProcess = Invoke-ProcessWithRetry `
                -FilePath powershell.exe `
                -ArgumentList $evolutionRepairArgs `
                -WorkingDirectory $projectRoot `
                -StdoutPath $evolutionRepairOut `
                -StderrPath $evolutionRepairErr `
                -LogPath $logPath `
                -Label 'evolution-repair' `
                -MaxRetries 2 `
                -DelaySeconds 60
            if ($evolutionRepairProcess.ExitCode -ne 0) {
                Write-Status -Path $statusPath -Data ([ordered]@{
                    status = 'BLOCKED_EVOLUTION_REPAIR_EXIT'
                    iteration = $i
                    exitCode = $evolutionRepairProcess.ExitCode
                    replayRoot = $replayRoot
                    evolutionRepairLogDir = $evolutionRepairLogDir
                    updatedAt = (Get-Date).ToString('s')
                })
                exit $evolutionRepairProcess.ExitCode
            }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $evolutionValidationScript -ReplayRoot $replayRoot
            $evolutionValidationExit = $LASTEXITCODE
            if ($evolutionValidationExit -ne 0) {
                if (Test-Path -LiteralPath $decisionPath) {
                    Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
                        "- evolution_execution_status: VALIDATION_FAILED_AFTER_REPAIR",
                        "- evolution_result_verify: $evolutionVerifyPath",
                        "- evolution_execution_finished_at: $(Get-Date -Format s)"
                    )
                }
                Write-Status -Path $statusPath -Data ([ordered]@{
                    status = 'BLOCKED_EVOLUTION_RESULT_VALIDATION'
                    iteration = $i
                    replayRoot = $replayRoot
                    evolutionResultVerify = $evolutionVerifyPath
                    updatedAt = (Get-Date).ToString('s')
                })
                Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) BLOCKED evolution result validation after repair root=$replayRoot verify=$evolutionVerifyPath"
                exit $evolutionValidationExit
            }
            if (Test-Path -LiteralPath $decisionPath) {
                Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
                    "- evolution_execution_status: VALIDATED_AFTER_REPAIR",
                    "- evolution_result_verify: $evolutionVerifyPath"
                )
            }
        } else {
            if (Test-Path -LiteralPath $decisionPath) {
                Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
                    "- evolution_result_validation: PASS",
                    "- evolution_result_verify: $(Join-Path $replayRoot 'EVOLUTION_RESULT_VERIFY.json')"
                )
            }
        }
    }

    $after = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
    Invoke-KnowledgeBackupSyncSafe -Config $config -ConfigPath $configPathFull -ReplayRootBase $replayRootBase -LogPath $logPath
    $lastMessagePath = Join-Path $evolutionLogDir 'evolution.last-message.md'
    $evolutionLastMessage = if (Test-Path -LiteralPath $lastMessagePath) { Get-Content -LiteralPath $lastMessagePath -Raw -Encoding UTF8 } else { '' }
    if ($evolutionLastMessage -match 'NO_SOURCE_CHANGE') {
        if (Test-Path -LiteralPath $decisionPath) {
            Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
                "- evolution_execution_status: NO_SOURCE_CHANGE",
                "- latest_knowledge_version_after_evolution: $($after.Version)",
                "- evolution_execution_finished_at: $(Get-Date -Format s)"
            )
        }
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'STOP_NO_SOURCE_CHANGE'
            iteration = $i
            targetVersion = $TargetVersion
            latestVersionBefore = $before.Version
            latestVersionAfter = $after.Version
            replayRoot = $replayRoot
            evolutionLastMessage = $lastMessagePath
            log = $logPath
            updatedAt = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP no source change latest_before=$($before.Version) latest_after=$($after.Version) last_message=$lastMessagePath"
        exit 6
    }

    Write-Status -Path $statusPath -Data ([ordered]@{
        status = 'ITERATION_DONE'
        iteration = $i
        targetVersion = $TargetVersion
        latestVersionBefore = $before.Version
        latestVersionAfter = $after.Version
        replayRoot = $replayRoot
        log = $logPath
        updatedAt = (Get-Date).ToString('s')
    })
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) ITERATION $i latest_after=$($after.Version)"
    if (Test-Path -LiteralPath $decisionPath) {
        Add-Content -LiteralPath $decisionPath -Encoding UTF8 -Value @(
            "- evolution_execution_status: COMPLETED",
            "- latest_knowledge_version_after_evolution: $($after.Version)",
            "- evolution_execution_finished_at: $(Get-Date -Format s)"
        )
    }

    if ($after.Number -ge $TargetVersion) {
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'DONE_TARGET_REACHED'
            iteration = $i
            targetVersion = $TargetVersion
            latestVersion = $after.Version
            replayRoot = $replayRoot
            log = $logPath
            updatedAt = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) DONE target reached latest=$($after.Version)"
        exit 0
    }

    if ($after.Number -le $before.Number) {
        $noVersionReason = Join-Path $replayRoot 'NO_VERSION_ADVANCE_REASON.md'
        Write-Status -Path $statusPath -Data ([ordered]@{
            status = 'STOP_NO_VERSION_ADVANCE'
            iteration = $i
            targetVersion = $TargetVersion
            latestVersion = $after.Version
            expectedVersionAfterEvolution = $expectedAfterEvolution
            replayRoot = $replayRoot
            noVersionAdvanceReason = $(if (Test-Path -LiteralPath $noVersionReason) { $noVersionReason } else { $null })
            log = $logPath
            updatedAt = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP no version advance latest=$($after.Version) expected=$expectedAfterEvolution reason=$noVersionReason"
        exit 4
    }
}

$latest = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
Write-Status -Path $statusPath -Data ([ordered]@{
    status = 'STOP_MAX_ITERATIONS'
    maxIterations = $MaxIterations
    targetVersion = $TargetVersion
    latestVersion = $latest.Version
    log = $logPath
    updatedAt = (Get-Date).ToString('s')
})
Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP max iterations latest=$($latest.Version)"
exit 5
