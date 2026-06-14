param(
    [string]$BridgeRoot = 'D:\opt\replay-evidence\_agent-bridge\current',
    [string]$ArchiveRoot = 'D:\opt\replay-evidence\_agent-bridge\runs',
    [string]$ReportRoot = '',
    [int]$IntervalMinutes = 10,
    [int]$MaxReports = 24,
    [ValidateSet('claude', 'none')]
    [string]$Executor = 'claude',
    [int]$ClaudeTimeoutMinutes = 20,
    [switch]$AutoAdvanceStaleDone,
    [int]$AutoAdvanceStaleMinutes = 2,
    [switch]$NoAutoRestartRunLoop,
    [ValidateSet('claude', 'manual')]
    [string]$BridgeClaudeExecutor = 'claude',
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$BridgeCodexExecutor = 'codex',
    [string]$BridgeClaudeWorkDir = 'D:\opt\replay-evidence',
    [string]$BridgeCodexWorkDir = 'D:\opt\replay-evidence',
    [string[]]$ProtectedGitRoots = @('D:\opt\claim'),
    [int]$BridgeMaxCycles = 4,
    [int]$BridgeTimeoutMinutes = 360,
    [int]$BridgeCompletionQuietSeconds = 30,
    [switch]$BridgeUseProtectedRootWriteDeny,
    [switch]$BridgeAllowUnsafeProtectedRootWriteDeny,
    [switch]$Once,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-UtcIso {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Write-TextFile {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function Read-TextIfExists {
    param([string]$Path, [int]$Tail = 0)
    if (-not (Test-Path -LiteralPath $Path)) {
        return "(missing: $Path)"
    }
    if ($Tail -gt 0) {
        return (Get-Content -LiteralPath $Path -Encoding UTF8 -Tail $Tail | Out-String)
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    return $text | ConvertFrom-Json
}

function Test-NonEmptyTextFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer -or $item.Length -le 0) {
        return $false
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return -not [string]::IsNullOrWhiteSpace($text)
}

function Get-FileSummary {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Root -Force | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            length = if ($_.PSIsContainer) { $null } else { $_.Length }
            last_write_time = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            is_directory = [bool]$_.PSIsContainer
        }
    })
}

function Get-BridgeProcesses {
    $patterns = @('Start-AgentBridge', 'Invoke-AgentPrompt', 'CLAUDE_AGENT_PROMPT', 'CODEX_REVIEW_PROMPT')
    $processes = @(Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | Where-Object {
        $cmd = [string]$_.CommandLine
        $patterns | Where-Object { $cmd -match [regex]::Escape($_) }
    } | ForEach-Object {
        [pscustomobject]@{
            process_id = $_.ProcessId
            parent_process_id = $_.ParentProcessId
            creation_date = $_.CreationDate
            command_line = $_.CommandLine
        }
    })
    return $processes
}

function Get-RunLoopProcesses {
    param([string]$BridgeRootFull)
    $escapedRoot = [regex]::Escape($BridgeRootFull)
    return @(Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" | Where-Object {
        $cmd = [string]$_.CommandLine
        $cmd -match 'Start-AgentBridge\.ps1' -and
        $cmd -match '\-Action\s+RunLoop' -and
        $cmd -match $escapedRoot
    } | ForEach-Object {
        [pscustomobject]@{
            process_id = $_.ProcessId
            parent_process_id = $_.ParentProcessId
            command_line = $_.CommandLine
        }
    })
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    if ($ProcessId -eq $PID) {
        return
    }
    try {
        $children = @(Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $ProcessId })
    } catch {
        $children = @()
    }
    foreach ($child in $children) {
        if ([int]$child.ProcessId -ne $PID) {
            Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
        }
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    } catch {
        # The process may have exited after discovery; the watchdog is best-effort here.
    }
}

function Test-IsGitWorktree {
    param([string]$Root)
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Root rev-parse --is-inside-work-tree 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    return ($exitCode -eq 0 -and (($output | Out-String).Trim()) -eq 'true')
}

function Get-GitStatusText {
    param([string]$Root)
    $output = & git -C $Root status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read git status for protected root: $Root`n$($output | Out-String)"
    }
    return ($output | Out-String).TrimEnd()
}

function Write-BridgeEvent {
    param(
        [string]$BridgeRootFull,
        [string]$Type,
        [object]$Data
    )
    $path = Join-Path $BridgeRootFull 'events.jsonl'
    $event = [ordered]@{
        ts = Get-UtcIso
        type = $Type
        data = $Data
    } | ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $path -Value $event -Encoding UTF8
}

function Set-BridgeStoppedForProtectedRoot {
    param(
        [string]$BridgeRootFull,
        [string]$ArchiveRootFull,
        [string]$Message
    )
    $statePath = Join-Path $BridgeRootFull 'STATE.json'
    $oldState = Read-JsonIfExists -Path $statePath
    $cycle = 1
    if ($null -ne $oldState -and $null -ne $oldState.PSObject.Properties['cycle']) {
        $cycle = [int]$oldState.cycle
    }
    $state = [ordered]@{
        protocol_version = 1
        status = 'STOPPED'
        cycle = $cycle
        active_actor = ''
        updated_at = Get-UtcIso
        bridge_root = $BridgeRootFull
        archive_root = $ArchiveRootFull
        last_message = $Message
        expected_files = [ordered]@{
            claude_prompt = Join-Path $BridgeRootFull 'CLAUDE_PROMPT.md'
            claude_result = Join-Path $BridgeRootFull 'CLAUDE_RESULT.md'
            codex_review = Join-Path $BridgeRootFull 'CODEX_REVIEW.md'
            next_claude_prompt = Join-Path $BridgeRootFull 'NEXT_CLAUDE_PROMPT.md'
            decision = Join-Path $BridgeRootFull 'DECISION.json'
        }
    }
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-BridgeEvent -BridgeRootFull $BridgeRootFull -Type 'protected_root_violation' -Data @{ message = $Message; cycle = $cycle }
}

function Invoke-ProtectedRootWatchdog {
    param(
        [string]$BridgeRootFull,
        [string]$ArchiveRootFull,
        [string]$ReportRootFull,
        [int]$ReportIndex
    )
    foreach ($root in $ProtectedGitRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        $full = Resolve-AbsolutePath $root
        if (-not (Test-Path -LiteralPath $full) -or -not (Test-IsGitWorktree -Root $full)) {
            continue
        }
        $statusText = Get-GitStatusText -Root $full
        if ([string]::IsNullOrWhiteSpace($statusText)) {
            continue
        }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeRoot = (Split-Path -Leaf $full) -replace '[^A-Za-z0-9._-]', '_'
        $violationDir = Join-Path $ReportRootFull ("protected-root-violation-{0:D3}-{1}-{2}" -f $ReportIndex, $stamp, $safeRoot)
        New-Item -ItemType Directory -Force -Path $violationDir | Out-Null
        Set-Content -LiteralPath (Join-Path $violationDir 'status.txt') -Value $statusText -Encoding UTF8
        (& git -C $full diff --stat 2>&1 | Out-String) | Set-Content -LiteralPath (Join-Path $violationDir 'diffstat.txt') -Encoding UTF8
        (& git -C $full diff 2>&1 | Out-String) | Set-Content -LiteralPath (Join-Path $violationDir 'diff.patch') -Encoding UTF8

        $message = "Protected git root dirty; bridge stopped. Root: $full. Evidence: $violationDir"
        Set-BridgeStoppedForProtectedRoot -BridgeRootFull $BridgeRootFull -ArchiveRootFull $ArchiveRootFull -Message $message
        $runLoops = @(Get-RunLoopProcesses -BridgeRootFull $BridgeRootFull)
        $evidence = [ordered]@{
            generated_at = Get-UtcIso
            report_index = $ReportIndex
            root = $full
            status = $statusText
            evidence_dir = $violationDir
            stopped_runloop_pids = @($runLoops | ForEach-Object { $_.process_id })
        }
        $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $violationDir 'violation.json') -Encoding UTF8
        foreach ($proc in $runLoops) {
            Stop-ProcessTree -ProcessId ([int]$proc.process_id)
        }
        return $evidence
    }
    return $null
}

function Get-StateAgeMinutes {
    param($State)
    if ($null -eq $State -or $null -eq $State.PSObject.Properties['updated_at']) {
        return [double]::PositiveInfinity
    }
    try {
        $updated = [datetimeoffset]::Parse([string]$State.updated_at)
        return ([datetimeoffset]::UtcNow - $updated.ToUniversalTime()).TotalMinutes
    } catch {
        return [double]::PositiveInfinity
    }
}

function Invoke-BridgeAction {
    param(
        [string]$Action,
        [string]$BridgeRootFull,
        [string]$ArchiveRootFull,
        [string]$BridgeScript
    )
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $BridgeScript,
        '-Action', $Action,
        '-BridgeRoot', $BridgeRootFull,
        '-ArchiveRoot', $ArchiveRootFull,
        '-ClaudeExecutor', $BridgeClaudeExecutor,
        '-CodexExecutor', $BridgeCodexExecutor,
        '-ClaudeWorkDir', $BridgeClaudeWorkDir,
        '-CodexWorkDir', $BridgeCodexWorkDir,
        '-MaxCycles', ([string]$BridgeMaxCycles),
        '-TimeoutMinutes', ([string]$BridgeTimeoutMinutes),
        '-CompletionQuietSeconds', ([string]$BridgeCompletionQuietSeconds),
        '-ForceUnlock'
    )
    if ($BridgeUseProtectedRootWriteDeny) {
        $args += '-UseProtectedRootWriteDeny'
    }
    if ($BridgeAllowUnsafeProtectedRootWriteDeny) {
        $args += '-AllowUnsafeProtectedRootWriteDeny'
    }
    if ($ProtectedGitRoots.Count -gt 0) {
        $args += '-ProtectedGitRoots'
        foreach ($root in $ProtectedGitRoots) {
            $args += $root
        }
    }
    & powershell @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Start-AgentBridge.ps1 -Action $Action failed with exit code $LASTEXITCODE"
    }
}

function Start-BridgeRunLoop {
    param(
        [string]$BridgeRootFull,
        [string]$ArchiveRootFull,
        [string]$BridgeScript
    )
    $protectedArgs = ''
    if ($ProtectedGitRoots.Count -gt 0) {
        $protectedArgs = '-ProtectedGitRoots ' + (($ProtectedGitRoots | ForEach-Object { "`"$($_)`"" }) -join ' ')
    }
    $argLine = @(
        '-NoProfile',
        '-ExecutionPolicy Bypass',
        "-File `"$BridgeScript`"",
        '-Action RunLoop',
        "-BridgeRoot `"$BridgeRootFull`"",
        "-ArchiveRoot `"$ArchiveRootFull`"",
        "-ClaudeExecutor $BridgeClaudeExecutor",
        "-CodexExecutor $BridgeCodexExecutor",
        "-ClaudeWorkDir `"$BridgeClaudeWorkDir`"",
        "-CodexWorkDir `"$BridgeCodexWorkDir`"",
        $protectedArgs,
        "-MaxCycles $BridgeMaxCycles",
        "-TimeoutMinutes $BridgeTimeoutMinutes",
        "-CompletionQuietSeconds $BridgeCompletionQuietSeconds",
        '-ForceUnlock'
    ) -join ' '
    if ($BridgeUseProtectedRootWriteDeny) {
        $argLine += ' -UseProtectedRootWriteDeny'
    }
    if ($BridgeAllowUnsafeProtectedRootWriteDeny) {
        $argLine += ' -AllowUnsafeProtectedRootWriteDeny'
    }
    return Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WorkingDirectory $BridgeClaudeWorkDir -WindowStyle Hidden -PassThru
}

function Invoke-AutoAdvanceIfStaleDone {
    param(
        [string]$BridgeRootFull,
        [string]$ArchiveRootFull,
        [string]$BridgeScript,
        [string]$ReportRootFull,
        [int]$ReportIndex
    )
    if (-not $AutoAdvanceStaleDone) {
        return $null
    }

    $statePath = Join-Path $BridgeRootFull 'STATE.json'
    $state = Read-JsonIfExists -Path $statePath
    if ($null -eq $state) {
        return $null
    }

    $status = [string]$state.status
    $ageMinutes = Get-StateAgeMinutes -State $state
    if ($ageMinutes -lt $AutoAdvanceStaleMinutes) {
        return $null
    }

    $claudeDone = Join-Path $BridgeRootFull 'CLAUDE_DONE.flag'
    $claudeResult = Join-Path $BridgeRootFull 'CLAUDE_RESULT.md'
    $codexDone = Join-Path $BridgeRootFull 'CODEX_DONE.flag'
    $codexReview = Join-Path $BridgeRootFull 'CODEX_REVIEW.md'
    $decision = Join-Path $BridgeRootFull 'DECISION.json'
    $action = ''

    if (($status -eq 'CLAUDE_RUNNING' -or $status -eq 'CLAUDE_DONE') -and
        (Test-Path -LiteralPath $claudeDone) -and
        (Test-NonEmptyTextFile -Path $claudeResult)) {
        $action = 'ClaudeDone'
    } elseif (($status -eq 'CODEX_REVIEWING' -or $status -eq 'CODEX_DONE') -and
        (Test-Path -LiteralPath $codexDone) -and
        (Test-NonEmptyTextFile -Path $codexReview) -and
        (Test-NonEmptyTextFile -Path $decision)) {
        $action = 'CodexDone'
    } else {
        return $null
    }

    $runLoops = @(Get-RunLoopProcesses -BridgeRootFull $BridgeRootFull)
    foreach ($proc in $runLoops) {
        Stop-ProcessTree -ProcessId ([int]$proc.process_id)
    }

    Invoke-BridgeAction -Action $action -BridgeRootFull $BridgeRootFull -ArchiveRootFull $ArchiveRootFull -BridgeScript $BridgeScript
    $newState = Read-JsonIfExists -Path $statePath
    $restartPid = $null
    if (-not $NoAutoRestartRunLoop -and $null -ne $newState -and
        ($newState.status -eq 'WAITING_CLAUDE' -or $newState.status -eq 'WAITING_CODEX_REVIEW')) {
        $restart = Start-BridgeRunLoop -BridgeRootFull $BridgeRootFull -ArchiveRootFull $ArchiveRootFull -BridgeScript $BridgeScript
        $restartPid = $restart.Id
    }

    $evidence = [ordered]@{
        generated_at = Get-UtcIso
        report_index = $ReportIndex
        action = $action
        previous_status = $status
        previous_state_age_minutes = [math]::Round($ageMinutes, 2)
        stopped_runloop_pids = @($runLoops | ForEach-Object { $_.process_id })
        restarted_runloop_pid = $restartPid
        new_status = if ($null -ne $newState) { [string]$newState.status } else { '' }
    }
    $path = Join-Path $ReportRootFull ("watchdog-auto-advance-{0:D3}-{1}.json" -f $ReportIndex, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $evidence
}

function New-MonitorInput {
    param(
        [string]$BridgeRootFull,
        [string]$ReportRootFull,
        [int]$ReportIndex
    )
    $statePath = Join-Path $BridgeRootFull 'STATE.json'
    $eventsPath = Join-Path $BridgeRootFull 'events.jsonl'
    $claudeResultPath = Join-Path $BridgeRootFull 'CLAUDE_RESULT.md'
    $codexReviewPath = Join-Path $BridgeRootFull 'CODEX_REVIEW.md'
    $nextPromptPath = Join-Path $BridgeRootFull 'NEXT_CLAUDE_PROMPT.md'
    $runStdoutPath = Join-Path $BridgeRootFull 'runloop.stdout.log'
    $runStderrPath = Join-Path $BridgeRootFull 'runloop.stderr.log'

    $snapshot = [ordered]@{
        generated_at = Get-UtcIso
        report_index = $ReportIndex
        bridge_root = $BridgeRootFull
        report_root = $ReportRootFull
        file_summary = Get-FileSummary -Root $BridgeRootFull
        processes = Get-BridgeProcesses
    } | ConvertTo-Json -Depth 8

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Agent Bridge Monitor Evidence')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Snapshot')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~json')
    [void]$sb.AppendLine($snapshot)
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## STATE.json')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~json')
    [void]$sb.AppendLine((Read-TextIfExists -Path $statePath))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## events.jsonl tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~text')
    [void]$sb.AppendLine((Read-TextIfExists -Path $eventsPath -Tail 40))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## CLAUDE_RESULT.md tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~markdown')
    [void]$sb.AppendLine((Read-TextIfExists -Path $claudeResultPath -Tail 80))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## CODEX_REVIEW.md tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~markdown')
    [void]$sb.AppendLine((Read-TextIfExists -Path $codexReviewPath -Tail 80))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## NEXT_CLAUDE_PROMPT.md tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~markdown')
    [void]$sb.AppendLine((Read-TextIfExists -Path $nextPromptPath -Tail 80))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## runloop stdout tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~text')
    [void]$sb.AppendLine((Read-TextIfExists -Path $runStdoutPath -Tail 60))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## runloop stderr tail')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~text')
    [void]$sb.AppendLine((Read-TextIfExists -Path $runStderrPath -Tail 80))
    [void]$sb.AppendLine('~~~')
    return $sb.ToString()
}

function New-MonitorPrompt {
    param(
        [string]$InputPath,
        [string]$ReportPath,
        [string]$LatestPath,
        [string]$DonePath
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Agent Bridge Progress Monitor')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Read the evidence file:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($InputPath)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Write a concise Chinese progress report to:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($ReportPath)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Also overwrite:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($LatestPath)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('After both reports are written, create:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($DonePath)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Report format:')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- Current state')
    [void]$sb.AppendLine('- Current actor / cycle')
    [void]$sb.AppendLine('- What changed in the last monitor interval')
    [void]$sb.AppendLine('- Errors, timeout, 429, usage limit, missing done flag, or missing DECISION.json')
    [void]$sb.AppendLine('- Whether human intervention is needed')
    [void]$sb.AppendLine('- What to watch in the next monitor interval')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Do not modify replay code, bridge state, prompts, decisions, or result files.')
    return $sb.ToString()
}

function Write-FallbackReport {
    param(
        [string]$ReportPath,
        [string]$LatestPath,
        [string]$InputPath,
        [string]$Reason
    )
    $statePath = Join-Path $bridgeRootFull 'STATE.json'
    $eventsPath = Join-Path $bridgeRootFull 'events.jsonl'
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Agent Bridge Progress Report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- generated_at: $(Get-UtcIso)")
    [void]$sb.AppendLine('- mode: fallback')
    [void]$sb.AppendLine("- reason: $Reason")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Current State')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~json')
    [void]$sb.AppendLine((Read-TextIfExists -Path $statePath))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Recent Events')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('~~~text')
    [void]$sb.AppendLine((Read-TextIfExists -Path $eventsPath -Tail 20))
    [void]$sb.AppendLine('~~~')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Evidence Input')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($InputPath)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Human Intervention')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('No mandatory human intervention was detected. If STATE.json stays in a running state for too long, inspect the related logs directory.')
    $content = $sb.ToString()
    Write-TextFile -Path $ReportPath -Value $content
    Write-TextFile -Path $LatestPath -Value $content
}

$bridgeRootFull = Resolve-AbsolutePath $BridgeRoot
$archiveRootFull = Resolve-AbsolutePath $ArchiveRoot
if ([string]::IsNullOrWhiteSpace($ReportRoot)) {
    $reportRootFull = Join-Path $bridgeRootFull 'monitor'
} else {
    $reportRootFull = Resolve-AbsolutePath $ReportRoot
}
$invokeScript = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'
$bridgeScript = Join-Path $PSScriptRoot 'Start-AgentBridge.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        bridge_root = $bridgeRootFull
        archive_root = $archiveRootFull
        report_root = $reportRootFull
        executor = $Executor
        interval_minutes = $IntervalMinutes
        max_reports = $MaxReports
        auto_advance_stale_done = [bool]$AutoAdvanceStaleDone
        auto_advance_stale_minutes = $AutoAdvanceStaleMinutes
        auto_restart_runloop = -not [bool]$NoAutoRestartRunLoop
        protected_git_roots = $ProtectedGitRoots
        bridge_protected_root_write_deny = [bool]$BridgeUseProtectedRootWriteDeny
        bridge_allow_unsafe_protected_root_write_deny = [bool]$BridgeAllowUnsafeProtectedRootWriteDeny
    } | ConvertTo-Json -Depth 6
    exit 0
}

if (-not (Test-Path -LiteralPath $bridgeRootFull)) {
    throw "BridgeRoot not found: $bridgeRootFull"
}
New-Item -ItemType Directory -Force -Path $reportRootFull | Out-Null

$count = if ($Once) { 1 } else { [Math]::Max(1, $MaxReports) }
for ($i = 1; $i -le $count; $i++) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $inputPath = Join-Path $reportRootFull ("monitor-input-{0:D3}-{1}.md" -f $i, $stamp)
    $promptPath = Join-Path $reportRootFull ("monitor-prompt-{0:D3}-{1}.md" -f $i, $stamp)
    $reportPath = Join-Path $reportRootFull ("progress-{0:D3}-{1}.md" -f $i, $stamp)
    $latestPath = Join-Path $reportRootFull 'progress-latest.md'
    $donePath = Join-Path $reportRootFull ("monitor-done-{0:D3}-{1}.flag" -f $i, $stamp)
    $logDir = Join-Path $reportRootFull ("logs\monitor-{0:D3}-{1}" -f $i, $stamp)

    Invoke-ProtectedRootWatchdog -BridgeRootFull $bridgeRootFull -ArchiveRootFull $archiveRootFull -ReportRootFull $reportRootFull -ReportIndex $i | Out-Null
    Invoke-AutoAdvanceIfStaleDone -BridgeRootFull $bridgeRootFull -ArchiveRootFull $archiveRootFull -BridgeScript $bridgeScript -ReportRootFull $reportRootFull -ReportIndex $i | Out-Null

    Write-TextFile -Path $inputPath -Value (New-MonitorInput -BridgeRootFull $bridgeRootFull -ReportRootFull $reportRootFull -ReportIndex $i)
    Write-TextFile -Path $promptPath -Value (New-MonitorPrompt -InputPath $inputPath -ReportPath $reportPath -LatestPath $latestPath -DonePath $donePath)

    if ($Executor -eq 'claude') {
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
                -PromptPath $promptPath `
                -WorkDir $bridgeRootFull `
                -LogDir $logDir `
                -Executor claude `
                -CompletionPath $donePath `
                -CompletionQuietSeconds 10 `
                -TimeoutMinutes $ClaudeTimeoutMinutes `
                -Name ("bridge-monitor-{0:D3}" -f $i) | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $donePath)) {
                Write-FallbackReport -ReportPath $reportPath -LatestPath $latestPath -InputPath $inputPath -Reason "Claude monitor failed or did not write done flag. exit=$LASTEXITCODE"
            }
        } catch {
            Write-FallbackReport -ReportPath $reportPath -LatestPath $latestPath -InputPath $inputPath -Reason $_.Exception.Message
        }
    } else {
        Write-FallbackReport -ReportPath $reportPath -LatestPath $latestPath -InputPath $inputPath -Reason 'Executor=none'
    }

    if ($Once -or $i -ge $count) {
        break
    }
    Start-Sleep -Seconds ([Math]::Max(60, $IntervalMinutes * 60))
}

[ordered]@{
    status = 'DONE'
    reports_written = $count
    report_root = $reportRootFull
    latest_report = (Join-Path $reportRootFull 'progress-latest.md')
} | ConvertTo-Json -Depth 6
