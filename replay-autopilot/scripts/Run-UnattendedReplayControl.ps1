param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [int]$StartRound = 0,
    [int]$CycleRounds = 0,
    [int]$MaxCycles = 0,
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$Executor = '',
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [switch]$AllowCodexExecutor,
    [switch]$NoExecute,
    [switch]$RunEvolution,
    [switch]$UseLatestKnowledgeVersion,
    [switch]$IgnoreStopline,
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

function Convert-ToIntOrDefault {
    param(
        [object]$Value,
        [int]$DefaultValue = 0
    )
    if ($null -eq $Value) { return $DefaultValue }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $DefaultValue }
    if ($text.Trim() -match '^(-?\d+)(?:\.\d+)?%?$') {
        return [int]$matches[1]
    }
    $parsed = 0
    if ([int]::TryParse($text.Trim(), [ref]$parsed)) {
        return $parsed
    }
    return $DefaultValue
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

function Get-VersionNumberFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return -1 }
    $match = [regex]::Match($Text, 'v([0-9]+)')
    if (-not $match.Success) { return -1 }
    return [int]$match.Groups[1].Value
}

function Get-VersionNumberFromReplayRootName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return -1 }
    $match = [regex]::Match($Name, '-v([0-9]+)-')
    if (-not $match.Success) { return -1 }
    return [int]$match.Groups[1].Value
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

function Get-LatestKnowledgeVersion {
    param([string]$KnowledgeRepo)

    $repo = Resolve-AbsolutePath $KnowledgeRepo
    if (-not (Test-Path -LiteralPath $repo)) {
        throw "Knowledge repo not found: $repo"
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $workflowLatestPath = Join-Path $repo 'workflow-history\latest.json'
    if (Test-Path -LiteralPath $workflowLatestPath) {
        try {
            $workflowLatest = Get-Content -LiteralPath $workflowLatestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $latestVersionText = [string]$workflowLatest.latest
            if ($latestVersionText -match '^v([0-9]+)$') {
                $candidates.Add([pscustomobject]@{
                    Number = [int]$matches[1]
                    Version = $latestVersionText
                    Source = $workflowLatestPath
                    LastWriteTime = (Get-Item -LiteralPath $workflowLatestPath).LastWriteTime
                    Kind = 'workflow-history-latest'
                }) | Out-Null
            }
        } catch {
            Write-Warning "Unable to read workflow-history latest version: $workflowLatestPath"
        }
    }

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
                }) | Out-Null
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
            }) | Out-Null
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

function Resolve-CycleReplayRootForSummary {
    param(
        [string]$ReplayRootBase,
        [int]$StartRound,
        [int]$Rounds
    )

    if ([string]::IsNullOrWhiteSpace($ReplayRootBase) -or $StartRound -lt 1 -or $Rounds -lt 1) {
        return ''
    }

    $parent = Split-Path -Parent $ReplayRootBase
    $baseLeaf = Split-Path -Leaf $ReplayRootBase
    if (-not (Test-Path -LiteralPath $parent)) { return '' }
    $baseVersionNumber = Get-VersionNumberFromReplayRootName -Name $baseLeaf

    $candidates = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match ('^' + [regex]::Escape($baseLeaf) + '-r(?<round>[0-9]+)$')
    } | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName
            Round = [int]([regex]::Match($_.Name, '-r([0-9]+)$').Groups[1].Value)
            Version = Get-VersionNumberFromReplayRootName -Name $_.Name
            Updated = $_.LastWriteTime
        }
    } | Where-Object {
        $_.Round -ge $StartRound -and $_.Round -lt ($StartRound + $Rounds)
    } | Sort-Object Version, Round, Updated -Descending)

    $versionMatch = [regex]::Match($baseLeaf, '-v[0-9]+-')
    if ($versionMatch.Success) {
        $prefix = [regex]::Escape($baseLeaf.Substring(0, $versionMatch.Index))
        $suffixStart = $versionMatch.Index + $versionMatch.Length
        $suffix = [regex]::Escape($baseLeaf.Substring($suffixStart))
        $regex = '^' + $prefix + '-v[0-9]+-' + $suffix + '-r(?<round>[0-9]+)$'
    } else {
        $regex = '^' + [regex]::Escape($baseLeaf) + '-r(?<round>[0-9]+)$'
    }
    $fallback = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match $regex
    } | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName
            Round = [int]([regex]::Match($_.Name, '-r([0-9]+)$').Groups[1].Value)
            Version = Get-VersionNumberFromReplayRootName -Name $_.Name
            Updated = $_.LastWriteTime
        }
    } | Where-Object {
        $_.Round -ge $StartRound -and $_.Round -lt ($StartRound + $Rounds) -and
        ($baseVersionNumber -lt 0 -or $_.Version -ge $baseVersionNumber)
    } | Sort-Object Version, Round, Updated -Descending)

    $allCandidates = @($candidates + $fallback | Sort-Object Version, Round, Updated -Descending)
    if ($allCandidates.Count -gt 0) {
        return [System.IO.Path]::GetFullPath([string]$allCandidates[0].Path)
    }
    return ''
}

function Write-JsonStatus {
    param(
        [string]$Path,
        [object]$Data
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-KnowledgeBackupSyncSafe {
    param(
        [hashtable]$Config,
        [string]$ConfigPath,
        [string]$ReplayRootBase,
        [string]$LogPath
    )

    $autoSync = Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_auto_sync' -DefaultValue 'true')
    if (-not $autoSync) { return 'disabled' }

    $syncScript = Join-Path $PSScriptRoot 'Sync-KnowledgeBackup.ps1'
    if (-not (Test-Path -LiteralPath $syncScript)) {
        throw "Knowledge backup sync script is missing: $syncScript"
    }

    $evidenceMode = Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_evidence_mode' -DefaultValue 'Milestone'
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $syncScript,
        '-ConfigPath', $ConfigPath,
        '-IncludeAutopilot',
        '-IncludeKnowledge',
        '-EvidenceMode', $evidenceMode
    )
    $evidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $ReplayRootBase
    if (-not [string]::IsNullOrWhiteSpace($evidenceRoot)) {
        $args += @('-EvidenceRoot', $evidenceRoot)
    }

    $evidenceRootForLogs = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $ReplayRootBase
    $syncLogRoot = if (-not [string]::IsNullOrWhiteSpace($evidenceRootForLogs)) {
        Join-Path $evidenceRootForLogs '_control\knowledge-backup-sync'
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'replay-knowledge-backup-sync'
    }
    New-Item -ItemType Directory -Force -Path $syncLogRoot | Out-Null
    $syncStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $syncStdout = Join-Path $syncLogRoot "sync-$syncStamp.stdout.log"
    $syncStderr = Join-Path $syncLogRoot "sync-$syncStamp.stderr.log"
    $syncProcess = Start-Process -FilePath powershell.exe `
        -ArgumentList $args `
        -WorkingDirectory (Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')) `
        -RedirectStandardOutput $syncStdout `
        -RedirectStandardError $syncStderr `
        -WindowStyle Hidden `
        -PassThru `
        -Wait
    $syncExitCode = $syncProcess.ExitCode
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_sync_stdout=$syncStdout stderr=$syncStderr exit=$syncExitCode"
    }
    if ($syncExitCode -ne 0) {
        throw "Knowledge backup sync failed with exit code $syncExitCode; stdout=$syncStdout stderr=$syncStderr"
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_sync=done"
    }
    if (-not (Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_auto_push' -DefaultValue 'true'))) {
        return 'synced'
    }

    $knowledgeRepoForPush = Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_repo' -DefaultValue ''
    if ([string]::IsNullOrWhiteSpace($knowledgeRepoForPush)) {
        throw "knowledge_backup_auto_push requires knowledge_repo."
    }

    $branch = (& git -C $knowledgeRepoForPush branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Cannot push because current knowledge repo branch is empty."
    }

    $maxRetries = Convert-ToIntOrDefault -Value (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_push_retries' -DefaultValue '2') -DefaultValue 2
    if ($maxRetries -lt 0) { $maxRetries = 0 }
    $retryDelaySeconds = Convert-ToIntOrDefault -Value (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_push_retry_delay_seconds' -DefaultValue '60') -DefaultValue 60
    if ($retryDelaySeconds -lt 0) { $retryDelaySeconds = 0 }
    $pushTimeoutSeconds = Convert-ToIntOrDefault -Value (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_push_timeout_seconds' -DefaultValue '60') -DefaultValue 60
    if ($pushTimeoutSeconds -lt 1) { $pushTimeoutSeconds = 60 }
    $attemptLimit = $maxRetries + 1
    $pushExitCode = 0
    $pushTimedOut = $false

    for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
        $pushStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $pushStdout = Join-Path $syncLogRoot "push-$pushStamp-attempt-$attempt.stdout.log"
        $pushStderr = Join-Path $syncLogRoot "push-$pushStamp-attempt-$attempt.stderr.log"
        $pushProcess = Start-Process -FilePath git `
            -ArgumentList @('-C', $knowledgeRepoForPush, 'push', 'origin', $branch) `
            -WorkingDirectory $knowledgeRepoForPush `
            -RedirectStandardOutput $pushStdout `
            -RedirectStandardError $pushStderr `
            -WindowStyle Hidden `
            -PassThru
        $completed = $pushProcess.WaitForExit($pushTimeoutSeconds * 1000)
        if ($completed) {
            $pushExitCode = $pushProcess.ExitCode
        } else {
            $pushTimedOut = $true
            $pushExitCode = -1
            Stop-Process -Id $pushProcess.Id -Force -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
                Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_push_timeout_seconds=$pushTimeoutSeconds attempt=$attempt pid=$($pushProcess.Id)"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
            Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_push_stdout=$pushStdout stderr=$pushStderr exit=$pushExitCode attempt=$attempt"
        }
        if ($pushExitCode -eq 0) {
            if (-not [string]::IsNullOrWhiteSpace($evidenceRoot)) {
                $statusDir = Join-Path $evidenceRoot '_control'
                New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
                [ordered]@{
                    schema = 'knowledge_backup_push_status.v1'
                    status = 'PUSHED'
                    updated_at = (Get-Date).ToString('s')
                    knowledge_repo = $knowledgeRepoForPush
                    branch = $branch
                    attempts = $attempt
                    stdout = $pushStdout
                    stderr = $pushStderr
                } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $statusDir 'KNOWLEDGE_BACKUP_PUSH_STATUS.json') -Encoding UTF8
            }
            return 'pushed'
        }
        if ($attempt -lt $attemptLimit -and $retryDelaySeconds -gt 0) {
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }

    $blockingPushFailure = Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'knowledge_backup_push_failure_is_blocking' -DefaultValue 'false')
    if (-not [string]::IsNullOrWhiteSpace($evidenceRoot)) {
        $statusDir = Join-Path $evidenceRoot '_control'
        New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
        [ordered]@{
            schema = 'knowledge_backup_push_pending.v1'
            status = 'PENDING_PUSH'
            updated_at = (Get-Date).ToString('s')
            knowledge_repo = $knowledgeRepoForPush
            branch = $branch
            attempts = $attemptLimit
            exit_code = $pushExitCode
            timed_out = $pushTimedOut
            timeout_seconds = $pushTimeoutSeconds
            blocking = $blockingPushFailure
            recovery = "Run git -C `"$knowledgeRepoForPush`" push origin $branch or rerun Sync-KnowledgeBackup.ps1 -Push."
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $statusDir 'KNOWLEDGE_BACKUP_PENDING.json') -Encoding UTF8
    }

    if ($blockingPushFailure) {
        throw "Knowledge backup push failed with exit code $pushExitCode"
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_push=pending exit_code=$pushExitCode"
    }
    return 'push_pending'
}

function Invoke-GoldenSliceRecoverySafe {
    param(
        [hashtable]$Config,
        [string]$ReplayRootBase,
        [string]$LatestReplayRoot,
        [string]$Reason,
        [string]$LogPath
    )

    $autoGenerate = Convert-ToBool (Get-ConfigValueOrDefault -Config $Config -Key 'golden_delivery_slice_auto_generate' -DefaultValue 'true')
    if (-not $autoGenerate) { return 'disabled' }

    $script = Join-Path $PSScriptRoot 'Write-GoldenDeliverySlice.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        return "missing:$script"
    }

    $evidenceRootForGolden = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $ReplayRootBase
    if ([string]::IsNullOrWhiteSpace($evidenceRootForGolden) -or -not (Test-Path -LiteralPath $evidenceRootForGolden)) {
        return "evidence_missing:$evidenceRootForGolden"
    }

    $goldenOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -EvidenceRoot $evidenceRootForGolden -Quiet 2>&1
    $goldenExit = $LASTEXITCODE
    if (-not [string]::IsNullOrWhiteSpace($LogPath) -and $goldenOutput) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value (($goldenOutput | ForEach-Object { "$(Get-Date -Format s) golden_slice_output=$_" }) -join [Environment]::NewLine)
    }
    if ($goldenExit -ne 0) {
        return "failed:$goldenExit"
    }

    $controlDir = Join-Path $evidenceRootForGolden '_control'
    New-Item -ItemType Directory -Force -Path $controlDir | Out-Null
    [ordered]@{
        schema = 'zero_cap_golden_recovery.v1'
        status = 'GOLDEN_SLICE_GENERATED'
        reason = $Reason
        latest_replay_root = $LatestReplayRoot
        evidence_root = $evidenceRootForGolden
        golden_slice = (Join-Path $evidenceRootForGolden '_golden-samples\GOLDEN_DELIVERY_SLICE.md')
        updated_at = (Get-Date).ToString('s')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $controlDir 'ZERO_CAP_GOLDEN_RECOVERY.json') -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "$(Get-Date -Format s) golden_slice_recovery=generated reason=$Reason"
    }
    return 'generated'
}

function Invoke-CycleReplayLoop {
    param(
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StdoutPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StderrPath) | Out-Null

    $pushed = $false
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        Push-Location $WorkingDirectory
        $pushed = $true
        $ErrorActionPreference = 'Continue'
        & powershell.exe @ArgumentList > $StdoutPath 2> $StderrPath
        if ($null -eq $LASTEXITCODE) {
            return 0
        }
        return [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($pushed) {
            Pop-Location
        }
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml $configPathFull
$projectRoot = Resolve-AbsolutePath (Require-Key $config 'project_root')
$knowledgeRepo = Resolve-AbsolutePath (Require-Key $config 'knowledge_repo')
$replayRootBaseTemplate = Resolve-AbsolutePath (Require-Key $config 'replay_root_base')
$cycleRoundsActual = if ($CycleRounds -gt 0) { $CycleRounds } else { [int](Get-ConfigValueOrDefault -Config $config -Key 'control_cycle_rounds' -DefaultValue (Get-ConfigValueOrDefault -Config $config -Key 'max_rounds' -DefaultValue '3')) }
$maxCyclesActual = if ($MaxCycles -gt 0) { $MaxCycles } else { [int](Get-ConfigValueOrDefault -Config $config -Key 'control_max_cycles' -DefaultValue '3') }
$executorActual = if (-not [string]::IsNullOrWhiteSpace($Executor)) { $Executor } else { Get-ConfigValueOrDefault -Config $config -Key 'executor' -DefaultValue 'codex' }
$requiredExecutorActual = if (-not [string]::IsNullOrWhiteSpace($RequireExecutor)) { $RequireExecutor } else { Get-ConfigValueOrDefault -Config $config -Key 'require_executor' -DefaultValue '' }
$allowCodexExecutorActual = [bool]$AllowCodexExecutor -or (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'allow_codex_executor' -DefaultValue 'false'))
$runEvolutionActual = [bool]$RunEvolution -or (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'control_run_evolution' -DefaultValue 'true'))
$useLatestActual = [bool]$UseLatestKnowledgeVersion -or (Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'control_use_latest_knowledge_version' -DefaultValue 'true'))
$targetCoverage = [int](Get-ConfigValueOrDefault -Config $config -Key 'target_coverage' -DefaultValue '90')
$zeroCapStopEnabled = Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'control_zero_cap_stop_enabled' -DefaultValue 'true')
$zeroCapStopCycles = Convert-ToIntOrDefault -Value (Get-ConfigValueOrDefault -Config $config -Key 'control_zero_cap_stop_cycles' -DefaultValue '1') -DefaultValue 1
if ($zeroCapStopCycles -lt 1) { $zeroCapStopCycles = 1 }
$zeroCapEvolutionContinueLimit = Convert-ToIntOrDefault -Value (Get-ConfigValueOrDefault -Config $config -Key 'control_zero_cap_evolution_continue_limit' -DefaultValue '1') -DefaultValue 1
if ($zeroCapEvolutionContinueLimit -lt 0) { $zeroCapEvolutionContinueLimit = 0 }
$zeroCapNextAction = Get-ConfigValueOrDefault -Config $config -Key 'control_zero_cap_next_action' -DefaultValue 'golden_slice'
$reflectionGateEnabled = Convert-ToBool (Get-ConfigValueOrDefault -Config $config -Key 'control_reflection_gate_enabled' -DefaultValue 'true')
$continueKinds = @('CONTINUE', 'EVOLVE', 'UPGRADE')

if (@('codex', 'claude', 'manual') -notcontains $executorActual) {
    throw "Unsupported executor: $executorActual"
}
if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual) -and @('codex', 'claude', 'manual') -notcontains $requiredExecutorActual) {
    throw "Unsupported required executor: $requiredExecutorActual"
}
if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual) -and $executorActual -ne $requiredExecutorActual) {
    throw "Executor policy violation: actual executor '$executorActual' does not match required executor '$requiredExecutorActual'."
}
if ($executorActual -eq 'codex' -and -not $allowCodexExecutorActual) {
    throw "Executor policy violation: Codex executor requires explicit authorization."
}
if ($cycleRoundsActual -lt 1) { throw "CycleRounds must be >= 1." }
if ($maxCyclesActual -lt 1) { throw "MaxCycles must be >= 1." }

$latestVersion = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
$replayRootBaseForLatest = Replace-VersionToken -Value $replayRootBaseTemplate -VersionToken $latestVersion.Version
$initialStartRound = if ($StartRound -gt 0) { $StartRound } else { Get-NextRound -ReplayRootBase $replayRootBaseForLatest }
$evidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $replayRootBaseForLatest
$runRoot = Join-Path $evidenceRoot '_control-runs'
$runId = 'control-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runDir = Join-Path $runRoot $runId
$logPath = Join-Path $runDir 'control.log'
$statusPath = Join-Path $runDir 'CONTROL_LOOP_STATUS.json'
$latestStatePath = Join-Path $runRoot 'LATEST_CONTROL_RUN_STATE.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        config = $configPathFull
        project_root = $projectRoot
        knowledge_repo = $knowledgeRepo
        latest_knowledge_version = $latestVersion.Version
        latest_knowledge_source = $latestVersion.Source
        latest_knowledge_kind = $latestVersion.Kind
        replay_root_base = $replayRootBaseForLatest
        evidence_root = $evidenceRoot
        start_round = $initialStartRound
        cycle_rounds = $cycleRoundsActual
        max_cycles = $maxCyclesActual
        executor = $executorActual
        require_executor = $requiredExecutorActual
        allow_codex_executor = $allowCodexExecutorActual
        run_evolution = $runEvolutionActual
        use_latest_knowledge_version = $useLatestActual
        zero_cap_stop_enabled = $zeroCapStopEnabled
        zero_cap_stop_cycles = $zeroCapStopCycles
        zero_cap_evolution_continue_limit = $zeroCapEvolutionContinueLimit
        zero_cap_next_action = $zeroCapNextAction
        reflection_gate_enabled = $reflectionGateEnabled
        continue_decision_kinds = $continueKinds
    } | ConvertTo-Json -Depth 8
    exit 0
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Write-JsonStatus -Path $latestStatePath -Data ([ordered]@{
    schema = 'unattended_replay_control_state.v1'
    run_id = $runId
    process_id = $PID
    started_at = (Get-Date).ToString('s')
    status_path = $statusPath
    log_path = $logPath
    executor = $executorActual
    require_executor = $requiredExecutorActual
    allow_codex_executor = $allowCodexExecutorActual
    cycle_rounds = $cycleRoundsActual
    max_cycles = $maxCyclesActual
})

Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) START run_id=$runId cycle_rounds=$cycleRoundsActual max_cycles=$maxCyclesActual executor=$executorActual require_executor=$requiredExecutorActual"
$nextStartRound = $initialStartRound
$lastDecisionKind = ''
$lastReplayRoot = ''
$stopReason = ''
$zeroCapStreak = 0

for ($cycle = 1; $cycle -le $maxCyclesActual; $cycle++) {
    $beforeVersion = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
    $cycleReplayRootBase = Replace-VersionToken -Value $replayRootBaseTemplate -VersionToken $beforeVersion.Version
    if ($StartRound -le 0) {
        $nextStartRound = Get-NextRound -ReplayRootBase $cycleReplayRootBase
    }

    $cycleOut = Join-Path $runDir ('cycle-{0:D2}.stdout.log' -f $cycle)
    $cycleErr = Join-Path $runDir ('cycle-{0:D2}.stderr.log' -f $cycle)
    $loopArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'),
        '-ConfigPath', $configPathFull,
        '-StartRound', [string]$nextStartRound,
        '-Rounds', [string]$cycleRoundsActual,
        '-Executor', $executorActual
    )
    if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual)) {
        $loopArgs += @('-RequireExecutor', $requiredExecutorActual)
    }
    if ($allowCodexExecutorActual) { $loopArgs += '-AllowCodexExecutor' }
    if ($runEvolutionActual) { $loopArgs += '-RunEvolution' }
    if ($useLatestActual) { $loopArgs += '-UseLatestKnowledgeVersion' }
    if ($NoExecute) { $loopArgs += '-NoExecute' }

    Write-JsonStatus -Path $statusPath -Data ([ordered]@{
        schema = 'unattended_replay_control_status.v1'
        status = 'RUNNING_CYCLE'
        run_id = $runId
        cycle = $cycle
        max_cycles = $maxCyclesActual
        cycle_rounds = $cycleRoundsActual
        start_round = $nextStartRound
        knowledge_version_before = $beforeVersion.Version
        stdout = $cycleOut
        stderr = $cycleErr
        updated_at = (Get-Date).ToString('s')
    })
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) CYCLE_START cycle=$cycle version=$($beforeVersion.Version) start_round=$nextStartRound rounds=$cycleRoundsActual"

    $exitCode = Invoke-CycleReplayLoop -ArgumentList $loopArgs -WorkingDirectory $scriptRoot -StdoutPath $cycleOut -StderrPath $cycleErr
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) CYCLE_EXIT cycle=$cycle exit=$exitCode stdout=$cycleOut stderr=$cycleErr"
    if ($exitCode -ne 0) {
        $stopReason = "cycle_exit_code_$exitCode"
        Write-JsonStatus -Path $statusPath -Data ([ordered]@{
            schema = 'unattended_replay_control_status.v1'
            status = 'BLOCKED_CYCLE_EXIT'
            run_id = $runId
            cycle = $cycle
            exit_code = $exitCode
            stdout = $cycleOut
            stderr = $cycleErr
            updated_at = (Get-Date).ToString('s')
        })
        exit $exitCode
    }

    $controlScript = Join-Path $PSScriptRoot 'Write-ControlPlaneSummary.ps1'
    $currentReplayRoot = Resolve-CycleReplayRootForSummary -ReplayRootBase $cycleReplayRootBase -StartRound $nextStartRound -Rounds $cycleRoundsActual
    if (Test-Path -LiteralPath $controlScript) {
        $controlArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $controlScript,
            '-EvidenceRoot', $evidenceRoot,
            '-TargetCoverage', [string]$targetCoverage
        )
        if (-not [string]::IsNullOrWhiteSpace($requiredExecutorActual)) {
            $controlArgs += @('-RequireExecutor', $requiredExecutorActual)
        }
        if (-not [string]::IsNullOrWhiteSpace($currentReplayRoot)) {
            $controlArgs += @('-ReplayRoot', $currentReplayRoot)
        }
        $controlArgs += '-Quiet'
        & powershell @controlArgs
        if ($LASTEXITCODE -ne 0) {
            $stopReason = "control_summary_exit_$LASTEXITCODE"
            Write-JsonStatus -Path $statusPath -Data ([ordered]@{
                schema = 'unattended_replay_control_status.v1'
                status = 'BLOCKED_CONTROL_SUMMARY'
                run_id = $runId
                cycle = $cycle
                exit_code = $LASTEXITCODE
                updated_at = (Get-Date).ToString('s')
            })
            exit $LASTEXITCODE
        }
    }

    $controlLatest = Join-Path $evidenceRoot '_control\RUN_CONTROL_LATEST.json'
    $control = if (Test-Path -LiteralPath $controlLatest) { Get-Content -LiteralPath $controlLatest -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    $decisionKind = if ($control) { [string]$control.control_decision.decision_kind } else { 'UNKNOWN' }
    $latestCoverage = if ($control) { $control.latest.oracle_adjusted_coverage } else { $null }
    $latestCap = if ($control) { $control.latest.verification_capped_coverage } else { $null }
    $lastReplayRoot = if ($control) { [string]$control.latest.replay_root } else { '' }
    $lastDecisionKind = $decisionKind
    $afterVersion = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
    $latestCapInt = Convert-ToIntOrDefault -Value $latestCap -DefaultValue -1
    $latestCoverageInt = Convert-ToIntOrDefault -Value $latestCoverage -DefaultValue -1
    $versionAdvancedThisCycle = [string]$afterVersion.Version -ne [string]$beforeVersion.Version
    $latestRootVersionNumber = Get-VersionNumberFromText -Text $lastReplayRoot
    $afterVersionNumber = Get-VersionNumberFromText -Text $afterVersion.Version
    $evolveWithoutLatestRootAdvance = $runEvolutionActual -and
        (@('EVOLVE', 'UPGRADE') -contains $decisionKind) -and
        $latestRootVersionNumber -ge 0 -and
        $afterVersionNumber -le $latestRootVersionNumber
    $evolveWithoutVersionAdvance = $runEvolutionActual -and
        (@('EVOLVE', 'UPGRADE') -contains $decisionKind) -and
        ((-not $versionAdvancedThisCycle) -or $evolveWithoutLatestRootAdvance)
    if ($latestCapInt -eq 0) {
        $zeroCapStreak++
    } else {
        $zeroCapStreak = 0
    }
    $zeroCapStopTriggeredRaw = $zeroCapStopEnabled -and ($zeroCapStreak -ge $zeroCapStopCycles)
    $zeroCapEvolutionContinue = $zeroCapStopTriggeredRaw -and
        ($zeroCapStreak -le $zeroCapEvolutionContinueLimit) -and
        $runEvolutionActual -and
        $versionAdvancedThisCycle -and
        (@('EVOLVE', 'UPGRADE') -contains $decisionKind)
    $zeroCapStopTriggered = $zeroCapStopTriggeredRaw -and -not $zeroCapEvolutionContinue
    $hasNextCycle = $cycle -lt $maxCyclesActual
    $targetReached = $latestCoverageInt -ge $targetCoverage
    $stoplineBlocked = $decisionKind -eq 'STOPLINE' -and -not [bool]$IgnoreStopline
    $continuableDecision = ($continueKinds -contains $decisionKind) -or ($decisionKind -eq 'STOPLINE' -and [bool]$IgnoreStopline)
    $reflectionGateStatus = 'not_run'
    $reflectionGateExitCode = 0
    $reflectionGateFailed = $false
    $ruleClosureStatus = 'not_run'
    $ruleClosureExitCode = 0
    $ruleClosureFailed = $false
    $ruleClosurePath = ''
    $reflectionGateScript = Join-Path $PSScriptRoot 'Invoke-ReflectionSufficiencyGate.ps1'
    if ($reflectionGateEnabled -and (@('EVOLVE', 'UPGRADE') -contains $decisionKind) -and -not [string]::IsNullOrWhiteSpace($lastReplayRoot) -and (Test-Path -LiteralPath $reflectionGateScript)) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $reflectionGateScript -ReplayRoot $lastReplayRoot | Out-Null
        $reflectionGateExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $reflectionGatePath = Join-Path $lastReplayRoot 'REFLECTION_GATE.json'
        if (Test-Path -LiteralPath $reflectionGatePath) {
            try {
                $reflectionGateJson = Get-Content -LiteralPath $reflectionGatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $reflectionGateStatus = [string]$reflectionGateJson.status
            } catch {
                $reflectionGateStatus = "parse_error:$($_.Exception.Message)"
            }
        } else {
            $reflectionGateStatus = "missing_result_exit_$reflectionGateExitCode"
        }
        $reflectionGateFailed = $reflectionGateExitCode -ne 0 -or $reflectionGateStatus -ne 'PASS'
    } elseif ($reflectionGateEnabled -and (@('EVOLVE', 'UPGRADE') -contains $decisionKind)) {
        $reflectionGateStatus = 'skipped_missing_script_or_root'
        $reflectionGateFailed = $true
    }
    $ruleClosureScript = Join-Path $PSScriptRoot 'Validate-VerifiableRuleClosure.ps1'
    if ((@('EVOLVE', 'UPGRADE') -contains $decisionKind) -and -not [string]::IsNullOrWhiteSpace($lastReplayRoot) -and (Test-Path -LiteralPath $ruleClosureScript)) {
        $ruleClosurePath = Join-Path $lastReplayRoot 'VERIFIABLE_RULE_CLOSURE.json'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $ruleClosureScript -ReplayRoot $lastReplayRoot -ControlRoot (Join-Path $evidenceRoot '_control') | Out-Null
        $ruleClosureExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        if (Test-Path -LiteralPath $ruleClosurePath) {
            try {
                $ruleClosureJson = Get-Content -LiteralPath $ruleClosurePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $ruleClosureStatus = [string]$ruleClosureJson.status
            } catch {
                $ruleClosureStatus = "parse_error:$($_.Exception.Message)"
            }
        } else {
            $ruleClosureStatus = "missing_result_exit_$ruleClosureExitCode"
        }
        $ruleClosureFailed = $ruleClosureExitCode -ne 0 -or $ruleClosureStatus -ne 'PASS'
    } elseif (@('EVOLVE', 'UPGRADE') -contains $decisionKind) {
        $ruleClosureStatus = 'skipped_missing_script_or_root'
        $ruleClosureFailed = $true
    }
    $shouldContinue = $hasNextCycle -and $continuableDecision -and -not $targetReached -and -not $stoplineBlocked -and -not $zeroCapStopTriggered -and -not $evolveWithoutVersionAdvance -and -not $reflectionGateFailed -and -not $ruleClosureFailed

    if ($zeroCapEvolutionContinue -and $zeroCapNextAction -eq 'golden_slice' -and -not [string]::IsNullOrWhiteSpace($lastReplayRoot)) {
        $goldenRecoveryStatus = Invoke-GoldenSliceRecoverySafe -Config $config -ReplayRootBase $cycleReplayRootBase -LatestReplayRoot $lastReplayRoot -Reason 'zero_cap_evolved_continue' -LogPath $logPath
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) zero_cap_recovery=$goldenRecoveryStatus zero_cap_stop_suppressed=true version_before=$($beforeVersion.Version) version_after=$($afterVersion.Version)"
    }

    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) CYCLE_DECISION cycle=$cycle decision=$decisionKind cap=$latestCap oracle=$latestCoverage zero_cap_streak=$zeroCapStreak zero_cap_stop_raw=$zeroCapStopTriggeredRaw zero_cap_stop=$zeroCapStopTriggered zero_cap_evolution_continue=$zeroCapEvolutionContinue zero_cap_evolution_continue_limit=$zeroCapEvolutionContinueLimit evolve_without_version_advance=$evolveWithoutVersionAdvance evolve_without_latest_root_advance=$evolveWithoutLatestRootAdvance reflection_gate=$reflectionGateStatus reflection_gate_failed=$reflectionGateFailed rule_closure=$ruleClosureStatus rule_closure_failed=$ruleClosureFailed latest_root=$lastReplayRoot latest_root_version=$latestRootVersionNumber version_after=$($afterVersion.Version)"
    Write-JsonStatus -Path $statusPath -Data ([ordered]@{
        schema = 'unattended_replay_control_status.v1'
        status = 'CYCLE_DONE'
        run_id = $runId
        cycle = $cycle
        max_cycles = $maxCyclesActual
        decision_kind = $decisionKind
        latest_replay_root = $lastReplayRoot
        verification_capped_coverage = $latestCap
        oracle_adjusted_coverage = $latestCoverage
        knowledge_version_before = $beforeVersion.Version
        knowledge_version_after = $afterVersion.Version
        version_advanced_this_cycle = $versionAdvancedThisCycle
        latest_root_version_number = $latestRootVersionNumber
        after_version_number = $afterVersionNumber
        has_next_cycle = $hasNextCycle
        zero_cap_streak = $zeroCapStreak
        zero_cap_stop_triggered_raw = $zeroCapStopTriggeredRaw
        zero_cap_stop_triggered = $zeroCapStopTriggered
        zero_cap_evolution_continue = $zeroCapEvolutionContinue
        zero_cap_evolution_continue_limit = $zeroCapEvolutionContinueLimit
        zero_cap_next_action = $zeroCapNextAction
        reflection_gate_enabled = $reflectionGateEnabled
        reflection_gate_status = $reflectionGateStatus
        reflection_gate_exit_code = $reflectionGateExitCode
        reflection_gate_failed = $reflectionGateFailed
        rule_closure_status = $ruleClosureStatus
        rule_closure_exit_code = $ruleClosureExitCode
        rule_closure_failed = $ruleClosureFailed
        rule_closure_path = $ruleClosurePath
        evolve_without_version_advance = $evolveWithoutVersionAdvance
        evolve_without_latest_root_advance = $evolveWithoutLatestRootAdvance
        will_continue = $shouldContinue
        updated_at = (Get-Date).ToString('s')
    })

    if ($targetReached) {
        $stopReason = 'target_coverage_reached'
        break
    }
    if ($reflectionGateFailed) {
        $stopReason = 'reflection_sufficiency_failed'
        Write-JsonStatus -Path $statusPath -Data ([ordered]@{
            schema = 'unattended_replay_control_status.v1'
            status = 'REFLECTION_GATE_REQUIRED'
            run_id = $runId
            cycle = $cycle
            max_cycles = $maxCyclesActual
            stop_reason = $stopReason
            decision_kind = $decisionKind
            latest_replay_root = $lastReplayRoot
            verification_capped_coverage = $latestCap
            oracle_adjusted_coverage = $latestCoverage
            reflection_gate_status = $reflectionGateStatus
            reflection_gate_exit_code = $reflectionGateExitCode
            will_continue = $false
            updated_at = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP reflection_sufficiency_failed decision=$decisionKind reflection_gate=$reflectionGateStatus latest_root=$lastReplayRoot"
        break
    }
    if ($ruleClosureFailed) {
        $stopReason = 'verifiable_rule_closure_required'
        Write-JsonStatus -Path $statusPath -Data ([ordered]@{
            schema = 'unattended_replay_control_status.v1'
            status = 'RULE_CLOSURE_REQUIRED'
            run_id = $runId
            cycle = $cycle
            max_cycles = $maxCyclesActual
            stop_reason = $stopReason
            decision_kind = $decisionKind
            latest_replay_root = $lastReplayRoot
            verification_capped_coverage = $latestCap
            oracle_adjusted_coverage = $latestCoverage
            rule_closure_status = $ruleClosureStatus
            rule_closure_exit_code = $ruleClosureExitCode
            rule_closure_path = $ruleClosurePath
            will_continue = $false
            updated_at = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP verifiable_rule_closure_required decision=$decisionKind rule_closure=$ruleClosureStatus latest_root=$lastReplayRoot"
        break
    }
    if ($zeroCapStopTriggered) {
        $stopReason = 'zero_cap_stagnation_golden_slice_required'
        $goldenRecoveryStatus = if ($zeroCapNextAction -eq 'golden_slice') {
            Invoke-GoldenSliceRecoverySafe -Config $config -ReplayRootBase $cycleReplayRootBase -LatestReplayRoot $lastReplayRoot -Reason $stopReason -LogPath $logPath
        } else {
            'skipped_by_next_action'
        }
        Write-JsonStatus -Path $statusPath -Data ([ordered]@{
            schema = 'unattended_replay_control_status.v1'
            status = 'ZERO_CAP_STOPLINE'
            run_id = $runId
            cycle = $cycle
            max_cycles = $maxCyclesActual
            stop_reason = $stopReason
            decision_kind = $decisionKind
            latest_replay_root = $lastReplayRoot
            verification_capped_coverage = $latestCap
            oracle_adjusted_coverage = $latestCoverage
            zero_cap_streak = $zeroCapStreak
            golden_recovery_status = $goldenRecoveryStatus
            will_continue = $false
            updated_at = (Get-Date).ToString('s')
        })
        break
    }
    if ($evolveWithoutVersionAdvance) {
        $stopReason = 'evolve_required_without_version_advance'
        $goldenRecoveryStatus = Invoke-GoldenSliceRecoverySafe -Config $config -ReplayRootBase $cycleReplayRootBase -LatestReplayRoot $lastReplayRoot -Reason $stopReason -LogPath $logPath
        Write-JsonStatus -Path $statusPath -Data ([ordered]@{
            schema = 'unattended_replay_control_status.v1'
            status = 'EVOLVE_REQUIRED_WITHOUT_VERSION_ADVANCE'
            run_id = $runId
            cycle = $cycle
            max_cycles = $maxCyclesActual
            stop_reason = $stopReason
            decision_kind = $decisionKind
            latest_replay_root = $lastReplayRoot
            verification_capped_coverage = $latestCap
            oracle_adjusted_coverage = $latestCoverage
            knowledge_version_before = $beforeVersion.Version
            knowledge_version_after = $afterVersion.Version
            version_advanced_this_cycle = $versionAdvancedThisCycle
            latest_root_version_number = $latestRootVersionNumber
            after_version_number = $afterVersionNumber
            evolve_without_latest_root_advance = $evolveWithoutLatestRootAdvance
            golden_recovery_status = $goldenRecoveryStatus
            will_continue = $false
            updated_at = (Get-Date).ToString('s')
        })
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) STOP evolve_required_without_version_advance decision=$decisionKind version=$($afterVersion.Version) latest_root=$lastReplayRoot"
        break
    }
    if ($decisionKind -eq 'STOPLINE' -and -not [bool]$IgnoreStopline) {
        $stopReason = 'stopline'
        break
    }
    if ($continueKinds -notcontains $decisionKind -and -not ($decisionKind -eq 'UNKNOWN')) {
        $stopReason = "non_continuable_decision_$decisionKind"
        break
    }
    if (-not $hasNextCycle) {
        $stopReason = 'max_cycles_reached'
        break
    }

    $nextStartRound = Get-NextRound -ReplayRootBase (Replace-VersionToken -Value $replayRootBaseTemplate -VersionToken $afterVersion.Version)
}

if ([string]::IsNullOrWhiteSpace($stopReason)) {
    $stopReason = 'max_cycles_reached'
}

$finalVersion = Get-LatestKnowledgeVersion -KnowledgeRepo $knowledgeRepo
$backupSyncStatus = 'not_run'
try {
    $backupSyncStatus = Invoke-KnowledgeBackupSyncSafe -Config $config -ConfigPath $configPathFull -ReplayRootBase (Replace-VersionToken -Value $replayRootBaseTemplate -VersionToken $finalVersion.Version) -LogPath $logPath
} catch {
    $backupSyncStatus = "failed:$($_.Exception.Message)"
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) knowledge_backup_sync_error=$($_.Exception.Message)"
}
$finalStatus = if ([string]$backupSyncStatus -like 'failed:*') { 'DONE_WITH_BACKUP_ERROR' } else { 'DONE' }
Write-JsonStatus -Path $statusPath -Data ([ordered]@{
    schema = 'unattended_replay_control_status.v1'
    status = $finalStatus
    run_id = $runId
    stop_reason = $stopReason
    last_decision_kind = $lastDecisionKind
    last_replay_root = $lastReplayRoot
    latest_knowledge_version = $finalVersion.Version
    backup_sync_status = $backupSyncStatus
    log_path = $logPath
    updated_at = (Get-Date).ToString('s')
})
Add-Content -LiteralPath $logPath -Encoding UTF8 -Value "$(Get-Date -Format s) $finalStatus reason=$stopReason latest_version=$($finalVersion.Version) last_decision=$lastDecisionKind backup_sync_status=$backupSyncStatus"
