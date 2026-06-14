param(
    [ValidateSet('Init', 'Status', 'ClaudeDone', 'CodexDone', 'RunLoop', 'RestoreProtectedAccess', 'ValidateOnly')]
    [string]$Action = 'Status',
    [string]$BridgeRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_agent-bridge\current",
    [string]$ArchiveRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_agent-bridge\runs",
    [string]$InitialPromptPath = '',
    [string]$InitialPromptText = '',
    [ValidateSet('claude', 'codex', 'manual')]
    [string]$ClaudeExecutor = 'claude',
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$CodexExecutor = 'codex',
    [string]$ClaudeWorkDir = "$env:AI_WORKFLOW_PROJECT_ROOT",
    [string]$CodexWorkDir = "$env:AI_WORKFLOW_PROJECT_ROOT",
    [string[]]$ProtectedGitRoots = @("$env:AI_WORKFLOW_PROJECT_ROOT"),
    [int]$MaxCycles = 1,
    [int]$TimeoutMinutes = 240,
    [int]$CompletionQuietSeconds = 30,
    [switch]$Force,
    [switch]$ForceUnlock,
    [switch]$SkipProtectedGitGuard,
    [switch]$UseProtectedRootWriteDeny,
    [switch]$AllowUnsafeProtectedRootWriteDeny
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

function New-EmptyFile {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, '', [System.Text.UTF8Encoding]::new($false))
}

function Read-JsonFile {
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

function Write-JsonFile {
    param([string]$Path, [object]$Value, [int]$Depth = 10)
    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-TextFile -Path $Path -Value $json
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

function Assert-NonEmptyTextFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-NonEmptyTextFile -Path $Path)) {
        throw "$Label is missing or empty: $Path"
    }
}

function Get-EffectiveProtectedGitRoots {
    if ($SkipProtectedGitGuard) {
        return @()
    }
    $roots = @()
    foreach ($root in $ProtectedGitRoots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }
        $full = Resolve-AbsolutePath $root
        if (Test-Path -LiteralPath $full) {
            $roots += $full
        }
    }
    return @($roots | Select-Object -Unique)
}

function Test-IsGitWorktree {
    param([string]$Root)
    $output = & git -C $Root rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and (($output | Out-String).Trim()) -eq 'true')
}

function Get-GitStatusText {
    param([string]$Root)
    $output = & git -C $Root status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read git status for protected root: $Root`n$($output | Out-String)"
    }
    return ($output | Out-String).TrimEnd()
}

function Write-ProtectedGitViolationEvidence {
    param(
        [hashtable]$Paths,
        [string]$Actor,
        [int]$Cycle,
        [string]$Phase,
        [string]$Root,
        [string]$StatusText
    )
    $logDir = Join-Path $Paths.Root ('logs\cycle-{0:D4}\{1}\protected-git-guard' -f $Cycle, $Actor)
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $safeRoot = ($Root -replace '[^A-Za-z0-9._-]', '_')
    $prefix = '{0}-{1}' -f $Phase, $safeRoot
    $statusPath = Join-Path $logDir "$prefix.status.txt"
    $diffPath = Join-Path $logDir "$prefix.diff"
    $statPath = Join-Path $logDir "$prefix.diffstat.txt"
    Set-Content -LiteralPath $statusPath -Value $StatusText -Encoding UTF8
    (& git -C $Root diff --stat 2>&1 | Out-String) | Set-Content -LiteralPath $statPath -Encoding UTF8
    (& git -C $Root diff 2>&1 | Out-String) | Set-Content -LiteralPath $diffPath -Encoding UTF8
    return $statusPath
}

function Assert-ProtectedGitRootsClean {
    param(
        [hashtable]$Paths,
        [string]$Actor,
        [int]$Cycle,
        [string]$Phase
    )
    foreach ($root in (Get-EffectiveProtectedGitRoots)) {
        if (-not (Test-IsGitWorktree -Root $root)) {
            continue
        }
        $statusText = Get-GitStatusText -Root $root
        if (-not [string]::IsNullOrWhiteSpace($statusText)) {
            $evidence = Write-ProtectedGitViolationEvidence -Paths $Paths -Actor $Actor -Cycle $Cycle -Phase $Phase -Root $root -StatusText $statusText
            throw "Protected git root is dirty $Phase $Actor step (cycle $Cycle): $root. Evidence: $evidence"
        }
    }
}

function Get-ProtectedGitBoundaryText {
    $roots = Get-EffectiveProtectedGitRoots
    if ($roots.Count -eq 0) {
        return "Protected git roots: none configured."
    }
    $lines = @(
        'Protected git roots are READ-ONLY for this bridge run:',
        ($roots | ForEach-Object { "- $_" }),
        '',
        'Do not create, edit, delete, format, restore, or commit files under protected roots.',
        'If implementation proof is needed, write patch files, evidence notes, or isolated-worktree changes under the replay root / bridge root instead.',
        'The runner checks protected git roots before and after each agent step and stops if any root becomes dirty.'
    )
    return ($lines -join "`n")
}

function Get-CurrentWindowsIdentityName {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Enable-ProtectedRootWriteDeny {
    param(
        [hashtable]$Paths,
        [string]$Actor,
        [int]$Cycle
    )
    if (-not $UseProtectedRootWriteDeny) {
        return @()
    }
    if (-not $AllowUnsafeProtectedRootWriteDeny) {
        throw "UseProtectedRootWriteDeny is disabled by default because mutating ACLs on a real repository can lock the workspace. Re-run only for a disposable test root with -AllowUnsafeProtectedRootWriteDeny."
    }
    $identity = Get-CurrentWindowsIdentityName
    $enabled = @()
    foreach ($root in (Get-EffectiveProtectedGitRoots)) {
        if (-not (Test-IsGitWorktree -Root $root)) {
            continue
        }
        $rule = "${identity}:(OI)(CI)(W,D)"
        $output = & icacls $root /deny $rule 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to enable write deny for protected root: $root`n$($output | Out-String)"
        }
        $enabled += $root
        Write-BridgeEvent -Paths $Paths -Type 'protected_write_deny_enabled' -Data @{ actor = $Actor; cycle = $Cycle; root = $root; identity = $identity }
    }
    return $enabled
}

function Disable-ProtectedRootWriteDeny {
    param(
        [hashtable]$Paths,
        [string[]]$Roots,
        [string]$Actor,
        [int]$Cycle
    )
    $identity = Get-CurrentWindowsIdentityName
    foreach ($root in @($Roots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
            continue
        }
        $output = & icacls $root /remove:d $identity 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove write deny for protected root: $root`n$($output | Out-String)"
        }
        if ($null -ne $Paths) {
            Write-BridgeEvent -Paths $Paths -Type 'protected_write_deny_removed' -Data @{ actor = $Actor; cycle = $Cycle; root = $root; identity = $identity }
        }
    }
}

function Restore-ProtectedRootWriteAccess {
    param([hashtable]$Paths)
    $roots = Get-EffectiveProtectedGitRoots
    Disable-ProtectedRootWriteDeny -Paths $Paths -Roots $roots -Actor 'restore' -Cycle 0
}

function Get-BridgePaths {
    param([string]$Root)
    return [ordered]@{
        Root = $Root
        State = Join-Path $Root 'STATE.json'
        Decision = Join-Path $Root 'DECISION.json'
        Events = Join-Path $Root 'events.jsonl'
        ClaudePrompt = Join-Path $Root 'CLAUDE_PROMPT.md'
        ClaudeAgentPrompt = Join-Path $Root 'CLAUDE_AGENT_PROMPT.md'
        ClaudeResult = Join-Path $Root 'CLAUDE_RESULT.md'
        ClaudeDone = Join-Path $Root 'CLAUDE_DONE.flag'
        CodexReviewPrompt = Join-Path $Root 'CODEX_REVIEW_PROMPT.md'
        CodexReview = Join-Path $Root 'CODEX_REVIEW.md'
        NextClaudePrompt = Join-Path $Root 'NEXT_CLAUDE_PROMPT.md'
        CodexDone = Join-Path $Root 'CODEX_DONE.flag'
        LastClaudeResult = Join-Path $Root 'LAST_CLAUDE_RESULT.md'
        LastCodexReview = Join-Path $Root 'LAST_CODEX_REVIEW.md'
        LastNextClaudePrompt = Join-Path $Root 'LAST_NEXT_CLAUDE_PROMPT.md'
        LastDecision = Join-Path $Root 'LAST_DECISION.json'
        LastArchivePath = Join-Path $Root 'LAST_ARCHIVE_PATH.txt'
        Lock = Join-Path $Root 'LOCK'
    }
}

function Write-BridgeEvent {
    param(
        [hashtable]$Paths,
        [string]$Type,
        [hashtable]$Data = @{}
    )
    $event = [ordered]@{
        ts = Get-UtcIso
        type = $Type
        data = $Data
    }
    $line = $event | ConvertTo-Json -Depth 8 -Compress
    Add-Content -LiteralPath $Paths.Events -Value $line -Encoding UTF8
}

function Get-BridgeState {
    param([hashtable]$Paths)
    $state = Read-JsonFile -Path $Paths.State
    if ($null -eq $state) {
        return [pscustomobject]@{
            protocol_version = 1
            status = 'UNINITIALIZED'
            cycle = 0
            active_actor = ''
            updated_at = Get-UtcIso
            bridge_root = $Paths.Root
            archive_root = ''
            last_message = 'Bridge is not initialized.'
        }
    }
    return $state
}

function Set-BridgeState {
    param(
        [hashtable]$Paths,
        [string]$Status,
        [int]$Cycle,
        [string]$ActiveActor,
        [string]$ArchiveRootFull,
        [string]$Message
    )
    $state = [ordered]@{
        protocol_version = 1
        status = $Status
        cycle = $Cycle
        active_actor = $ActiveActor
        updated_at = Get-UtcIso
        bridge_root = $Paths.Root
        archive_root = $ArchiveRootFull
        last_message = $Message
        expected_files = [ordered]@{
            claude_prompt = $Paths.ClaudePrompt
            claude_result = $Paths.ClaudeResult
            codex_review = $Paths.CodexReview
            next_claude_prompt = $Paths.NextClaudePrompt
            decision = $Paths.Decision
        }
    }
    Write-JsonFile -Path $Paths.State -Value $state -Depth 8
    Write-BridgeEvent -Paths $Paths -Type 'state_changed' -Data @{
        status = $Status
        cycle = $Cycle
        active_actor = $ActiveActor
        message = $Message
    }
    return $state
}

function Invoke-WithBridgeLock {
    param(
        [hashtable]$Paths,
        [scriptblock]$Body
    )
    New-Item -ItemType Directory -Force -Path $Paths.Root | Out-Null
    if ($ForceUnlock -and (Test-Path -LiteralPath $Paths.Lock)) {
        Remove-Item -LiteralPath $Paths.Lock -Force
    }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Paths.Lock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $lockText = "pid=$PID`ncreated_at=$(Get-UtcIso)`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($lockText)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        & $Body
    } catch [System.IO.IOException] {
        throw "Bridge is locked: $($Paths.Lock). Use -ForceUnlock only after confirming no bridge agent is writing."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if (Test-Path -LiteralPath $Paths.Lock) {
            Remove-Item -LiteralPath $Paths.Lock -Force
        }
    }
}

function Get-InitialClaudePrompt {
    if (-not [string]::IsNullOrWhiteSpace($InitialPromptPath)) {
        $full = Resolve-AbsolutePath $InitialPromptPath
        if (-not (Test-Path -LiteralPath $full)) {
            throw "InitialPromptPath not found: $full"
        }
        return Get-Content -LiteralPath $full -Raw -Encoding UTF8
    }
    if (-not [string]::IsNullOrWhiteSpace($InitialPromptText)) {
        return $InitialPromptText
    }
    return @'
# Claude Task

Read the current replay evidence summary, continue the next safe replay/evolution step, and write the result to CLAUDE_RESULT.md.

Required outputs:
- CLAUDE_RESULT.md
- CLAUDE_DONE.flag
'@
}

function New-ClaudeAgentPrompt {
    param([hashtable]$Paths)
    $task = Get-Content -LiteralPath $Paths.ClaudePrompt -Raw -Encoding UTF8
    $protectedBoundary = Get-ProtectedGitBoundaryText
    return @"
# Agent Bridge Role: Claude Executor

You are the execution agent in a file-driven replay workflow.

Read and execute the task below. Do not ask the human to copy results between tools.

## Protected Write Boundary

$protectedBoundary

You must write:
- $($Paths['ClaudeResult']) with a concise execution report, evidence paths, metrics, blockers, and next-suggestion if any.
- $($Paths['ClaudeDone']) after the report is fully written.

Do not write CODEX_REVIEW.md or NEXT_CLAUDE_PROMPT.md.

## Task

$task

## Previous Cycle Context

For resumed cycles, the current-cycle files may be empty because the bridge resets them before the next actor starts.
If the task asks you to read the previous Codex review, Claude result, next prompt, or decision, read these stable copies first:

- $($Paths['LastClaudeResult'])
- $($Paths['LastCodexReview'])
- $($Paths['LastNextClaudePrompt'])
- $($Paths['LastDecision'])
- $($Paths['LastArchivePath'])
"@
}

function New-CodexReviewPrompt {
    param([hashtable]$Paths)
    $protectedBoundary = Get-ProtectedGitBoundaryText
    return @"
# Agent Bridge Role: Codex Reviewer

You are the review and control agent in a file-driven replay workflow.

## Protected Write Boundary

$protectedBoundary

Read:
- $($Paths['ClaudeResult'])
- Any replay/evolution artifacts referenced by that report
- $($Paths['State'])

Write:
- $($Paths['CodexReview']) with findings, decision rationale, and evidence.
- $($Paths['NextClaudePrompt']) with the exact next prompt for Claude if another Claude step is required.
- $($Paths['Decision']) as JSON using this schema:

```json
{
  "decision": "CONTINUE",
  "reason": "short reason",
  "next_actor": "claude",
  "coverage_signal": "",
  "blocker": "",
  "created_at": ""
}
```

Allowed decision values: CONTINUE, EVOLVE, DEEP_REVIEW, STOP, BLOCKED.

Rules:
- If no further Claude step is needed, set decision to STOP or BLOCKED and still write DECISION.json.
- If decision is CONTINUE, EVOLVE, or DEEP_REVIEW, NEXT_CLAUDE_PROMPT.md must be non-empty.
- After all files are written, write $($Paths['CodexDone']).
"@
}

function Initialize-Bridge {
    param([hashtable]$Paths, [string]$ArchiveRootFull)
    if ((Test-Path -LiteralPath $Paths.State) -and -not $Force) {
        throw "Bridge already initialized: $($Paths.State). Use -Force to reset current bridge files."
    }
    New-Item -ItemType Directory -Force -Path $Paths.Root, $ArchiveRootFull | Out-Null
    $logsRoot = Join-Path $Paths.Root 'logs'
    if (Test-Path -LiteralPath $logsRoot) {
        $resolvedLogsRoot = [System.IO.Path]::GetFullPath($logsRoot)
        $resolvedBridgeRoot = [System.IO.Path]::GetFullPath($Paths.Root)
        if (-not $resolvedLogsRoot.StartsWith($resolvedBridgeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refuse to clear logs outside bridge root: $resolvedLogsRoot"
        }
        Remove-Item -LiteralPath $resolvedLogsRoot -Recurse -Force
    }
    Write-TextFile -Path $Paths.ClaudePrompt -Value (Get-InitialClaudePrompt)
    Write-TextFile -Path $Paths.ClaudeAgentPrompt -Value (New-ClaudeAgentPrompt -Paths $Paths)
    New-EmptyFile -Path $Paths.ClaudeResult
    New-EmptyFile -Path $Paths.CodexReview
    New-EmptyFile -Path $Paths.NextClaudePrompt
    New-EmptyFile -Path $Paths.CodexReviewPrompt
    if (Test-Path -LiteralPath $Paths.ClaudeDone) { Remove-Item -LiteralPath $Paths.ClaudeDone -Force }
    if (Test-Path -LiteralPath $Paths.CodexDone) { Remove-Item -LiteralPath $Paths.CodexDone -Force }
    [ordered]@{
        decision = 'CONTINUE'
        reason = 'initialized'
        next_actor = 'claude'
        coverage_signal = ''
        blocker = ''
        created_at = Get-UtcIso
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Paths.Decision -Encoding UTF8
    New-EmptyFile -Path $Paths.Events
    Set-BridgeState -Paths $Paths -Status 'WAITING_CLAUDE' -Cycle 1 -ActiveActor 'claude' -ArchiveRootFull $ArchiveRootFull -Message 'Bridge initialized.' | Out-Null
}

function Complete-ClaudeStep {
    param([hashtable]$Paths, [string]$ArchiveRootFull)
    $state = Get-BridgeState -Paths $Paths
    if ($state.status -ne 'WAITING_CLAUDE' -and $state.status -ne 'CLAUDE_RUNNING' -and $state.status -ne 'CLAUDE_DONE') {
        throw "Cannot complete Claude step from state: $($state.status)"
    }
    Assert-NonEmptyTextFile -Path $Paths.ClaudeResult -Label 'CLAUDE_RESULT.md'
    if (-not (Test-Path -LiteralPath $Paths.ClaudeDone)) {
        throw "CLAUDE_DONE.flag is missing: $($Paths.ClaudeDone)"
    }
    Write-TextFile -Path $Paths.CodexReviewPrompt -Value (New-CodexReviewPrompt -Paths $Paths)
    Set-BridgeState -Paths $Paths -Status 'WAITING_CODEX_REVIEW' -Cycle ([int]$state.cycle) -ActiveActor 'codex' -ArchiveRootFull $ArchiveRootFull -Message 'Claude result is ready for Codex review.' | Out-Null
}

function Get-DecisionKind {
    param($Decision)
    if ($null -eq $Decision) { return 'BLOCKED' }
    $raw = ''
    if ($null -ne $Decision.PSObject.Properties['decision']) {
        $raw = [string]$Decision.decision
    } elseif ($null -ne $Decision.PSObject.Properties['next_action']) {
        $raw = [string]$Decision.next_action
    }
    $kind = $raw.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($kind)) { return 'BLOCKED' }
    if ($kind -match 'CONTINUE|REPLAY|RUN|NEXT') { return 'CONTINUE' }
    if ($kind -match 'EVOLVE|EVOLUTION') { return 'EVOLVE' }
    if ($kind -match 'DEEP') { return 'DEEP_REVIEW' }
    if ($kind -match 'STOP') { return 'STOP' }
    if ($kind -match 'BLOCK') { return 'BLOCKED' }
    return $kind
}

function Archive-BridgeCycle {
    param([hashtable]$Paths, [string]$ArchiveRootFull, [int]$Cycle)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archivePath = Join-Path $ArchiveRootFull ('cycle-{0:D4}-{1}' -f $Cycle, $stamp)
    New-Item -ItemType Directory -Force -Path $archivePath | Out-Null
    $names = @(
        'STATE.json', 'DECISION.json', 'events.jsonl',
        'CLAUDE_PROMPT.md', 'CLAUDE_AGENT_PROMPT.md', 'CLAUDE_RESULT.md', 'CLAUDE_DONE.flag',
        'CODEX_REVIEW_PROMPT.md', 'CODEX_REVIEW.md', 'NEXT_CLAUDE_PROMPT.md', 'CODEX_DONE.flag',
        'LAST_CLAUDE_RESULT.md', 'LAST_CODEX_REVIEW.md', 'LAST_NEXT_CLAUDE_PROMPT.md',
        'LAST_DECISION.json', 'LAST_ARCHIVE_PATH.txt'
    )
    foreach ($name in $names) {
        $source = Join-Path $Paths.Root $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $archivePath $name) -Force
        }
    }
    return $archivePath
}

function Complete-CodexStep {
    param([hashtable]$Paths, [string]$ArchiveRootFull)
    $state = Get-BridgeState -Paths $Paths
    if ($state.status -ne 'WAITING_CODEX_REVIEW' -and $state.status -ne 'CODEX_REVIEWING' -and $state.status -ne 'CODEX_DONE') {
        throw "Cannot complete Codex step from state: $($state.status)"
    }
    Assert-NonEmptyTextFile -Path $Paths.CodexReview -Label 'CODEX_REVIEW.md'
    if (-not (Test-Path -LiteralPath $Paths.CodexDone)) {
        throw "CODEX_DONE.flag is missing: $($Paths.CodexDone)"
    }
    $decision = Read-JsonFile -Path $Paths.Decision
    $kind = Get-DecisionKind -Decision $decision
    $cycle = [int]$state.cycle
    $archivePath = Archive-BridgeCycle -Paths $Paths -ArchiveRootFull $ArchiveRootFull -Cycle $cycle
    Copy-Item -LiteralPath $Paths.ClaudeResult -Destination $Paths.LastClaudeResult -Force
    Copy-Item -LiteralPath $Paths.CodexReview -Destination $Paths.LastCodexReview -Force
    Copy-Item -LiteralPath $Paths.NextClaudePrompt -Destination $Paths.LastNextClaudePrompt -Force
    Copy-Item -LiteralPath $Paths.Decision -Destination $Paths.LastDecision -Force
    Write-TextFile -Path $Paths.LastArchivePath -Value $archivePath
    Write-BridgeEvent -Paths $Paths -Type 'cycle_archived' -Data @{ cycle = $cycle; archive_path = $archivePath; decision = $kind }

    if (@('CONTINUE', 'EVOLVE', 'DEEP_REVIEW') -contains $kind) {
        Assert-NonEmptyTextFile -Path $Paths.NextClaudePrompt -Label 'NEXT_CLAUDE_PROMPT.md'
        Copy-Item -LiteralPath $Paths.NextClaudePrompt -Destination $Paths.ClaudePrompt -Force
        Write-TextFile -Path $Paths.ClaudeAgentPrompt -Value (New-ClaudeAgentPrompt -Paths $Paths)
        New-EmptyFile -Path $Paths.ClaudeResult
        New-EmptyFile -Path $Paths.CodexReview
        New-EmptyFile -Path $Paths.NextClaudePrompt
        New-EmptyFile -Path $Paths.CodexReviewPrompt
        if (Test-Path -LiteralPath $Paths.ClaudeDone) { Remove-Item -LiteralPath $Paths.ClaudeDone -Force }
        if (Test-Path -LiteralPath $Paths.CodexDone) { Remove-Item -LiteralPath $Paths.CodexDone -Force }
        Set-BridgeState -Paths $Paths -Status 'WAITING_CLAUDE' -Cycle ($cycle + 1) -ActiveActor 'claude' -ArchiveRootFull $ArchiveRootFull -Message "Codex decision $kind; next Claude prompt is ready." | Out-Null
    } else {
        Set-BridgeState -Paths $Paths -Status 'STOPPED' -Cycle $cycle -ActiveActor '' -ArchiveRootFull $ArchiveRootFull -Message "Codex decision $kind; bridge stopped." | Out-Null
    }
}

function Invoke-AgentBridgePrompt {
    param(
        [hashtable]$Paths,
        [string]$Actor,
        [string]$Executor,
        [string]$PromptPath,
        [string]$WorkDir,
        [string]$CompletionPath,
        [int]$Cycle
    )
    $invokeScript = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'
    if (-not (Test-Path -LiteralPath $invokeScript)) {
        throw "Invoke-AgentPrompt.ps1 not found: $invokeScript"
    }
    $logs = Join-Path $Paths.Root ('logs\cycle-{0:D4}\{1}' -f $Cycle, $Actor)
    Assert-ProtectedGitRootsClean -Paths $Paths -Actor $Actor -Cycle $Cycle -Phase 'before'
    $exitCode = 1
    $writeDeniedRoots = @()
    try {
        $writeDeniedRoots = Enable-ProtectedRootWriteDeny -Paths $Paths -Actor $Actor -Cycle $Cycle
        & powershell -NoProfile -ExecutionPolicy Bypass -File $invokeScript `
            -PromptPath $PromptPath `
            -WorkDir $WorkDir `
            -LogDir $logs `
            -Executor $Executor `
            -CompletionPath $CompletionPath `
            -CompletionQuietSeconds $CompletionQuietSeconds `
            -TimeoutMinutes $TimeoutMinutes `
            -Name $Actor | Out-Null
        $exitCode = $LASTEXITCODE
    } finally {
        Disable-ProtectedRootWriteDeny -Paths $Paths -Roots $writeDeniedRoots -Actor $Actor -Cycle $Cycle
        Assert-ProtectedGitRootsClean -Paths $Paths -Actor $Actor -Cycle $Cycle -Phase 'after'
        Start-Sleep -Seconds 5
        Assert-ProtectedGitRootsClean -Paths $Paths -Actor $Actor -Cycle $Cycle -Phase 'after-quiescence'
    }
    if ($exitCode -ne 0) {
        throw "$Actor executor failed with exit code $exitCode"
    }
}

function Run-BridgeLoop {
    param([hashtable]$Paths, [string]$ArchiveRootFull)
    try {
        for ($i = 0; $i -lt [Math]::Max(1, $MaxCycles); $i++) {
            $state = Get-BridgeState -Paths $Paths
            if ($state.status -eq 'STOPPED') { break }

            if (($state.status -eq 'CLAUDE_RUNNING' -or $state.status -eq 'CLAUDE_DONE') -and (Test-Path -LiteralPath $Paths.ClaudeDone)) {
                Write-BridgeEvent -Paths $Paths -Type 'resuming_completed_actor_step' -Data @{ actor = 'claude'; cycle = [int]$state.cycle; status = $state.status }
                Complete-ClaudeStep -Paths $Paths -ArchiveRootFull $ArchiveRootFull
                $state = Get-BridgeState -Paths $Paths
            }

            if (($state.status -eq 'CODEX_REVIEWING' -or $state.status -eq 'CODEX_DONE') -and (Test-Path -LiteralPath $Paths.CodexDone)) {
                Write-BridgeEvent -Paths $Paths -Type 'resuming_completed_actor_step' -Data @{ actor = 'codex'; cycle = [int]$state.cycle; status = $state.status }
                Complete-CodexStep -Paths $Paths -ArchiveRootFull $ArchiveRootFull
                $state = Get-BridgeState -Paths $Paths
            }

            if ($state.status -eq 'STOPPED') { break }

            if ($state.status -eq 'WAITING_CLAUDE') {
                $cycle = [int]$state.cycle
                Assert-ProtectedGitRootsClean -Paths $Paths -Actor 'bridge' -Cycle $cycle -Phase 'before-claude-state'
                Write-TextFile -Path $Paths.ClaudeAgentPrompt -Value (New-ClaudeAgentPrompt -Paths $Paths)
                Set-BridgeState -Paths $Paths -Status 'CLAUDE_RUNNING' -Cycle $cycle -ActiveActor 'claude' -ArchiveRootFull $ArchiveRootFull -Message 'Claude executor started.' | Out-Null
                if ($ClaudeExecutor -eq 'manual') {
                    Write-BridgeEvent -Paths $Paths -Type 'manual_wait' -Data @{ actor = 'claude'; prompt = $Paths.ClaudeAgentPrompt }
                    return
                }
                Invoke-AgentBridgePrompt -Paths $Paths -Actor 'claude' -Executor $ClaudeExecutor -PromptPath $Paths.ClaudeAgentPrompt -WorkDir $ClaudeWorkDir -CompletionPath $Paths.ClaudeDone -Cycle $cycle
                Complete-ClaudeStep -Paths $Paths -ArchiveRootFull $ArchiveRootFull
            }
            $state = Get-BridgeState -Paths $Paths
            if ($state.status -eq 'WAITING_CODEX_REVIEW') {
                $cycle = [int]$state.cycle
                Assert-ProtectedGitRootsClean -Paths $Paths -Actor 'bridge' -Cycle $cycle -Phase 'before-codex-state'
                Set-BridgeState -Paths $Paths -Status 'CODEX_REVIEWING' -Cycle $cycle -ActiveActor 'codex' -ArchiveRootFull $ArchiveRootFull -Message 'Codex reviewer started.' | Out-Null
                if ($CodexExecutor -eq 'manual') {
                    Write-BridgeEvent -Paths $Paths -Type 'manual_wait' -Data @{ actor = 'codex'; prompt = $Paths.CodexReviewPrompt }
                    return
                }
                Invoke-AgentBridgePrompt -Paths $Paths -Actor 'codex' -Executor $CodexExecutor -PromptPath $Paths.CodexReviewPrompt -WorkDir $CodexWorkDir -CompletionPath $Paths.CodexDone -Cycle $cycle
                Complete-CodexStep -Paths $Paths -ArchiveRootFull $ArchiveRootFull
            }
        }
    } catch {
        $state = Get-BridgeState -Paths $Paths
        $cycle = if ($null -ne $state -and $null -ne $state.PSObject.Properties['cycle']) { [int]$state.cycle } else { 1 }
        Set-BridgeState -Paths $Paths -Status 'STOPPED' -Cycle $cycle -ActiveActor '' -ArchiveRootFull $ArchiveRootFull -Message "Bridge stopped after error: $($_.Exception.Message)" | Out-Null
        Write-BridgeEvent -Paths $Paths -Type 'bridge_error' -Data @{ cycle = $cycle; error = $_.Exception.Message }
        throw
    }
}

$bridgeRootFull = Resolve-AbsolutePath $BridgeRoot
$archiveRootFull = Resolve-AbsolutePath $ArchiveRoot
$paths = Get-BridgePaths -Root $bridgeRootFull

if ($Action -eq 'ValidateOnly') {
    [ordered]@{
        status = 'VALID'
        bridge_root = $bridgeRootFull
        archive_root = $archiveRootFull
        actions = @('Init', 'Status', 'ClaudeDone', 'CodexDone', 'RunLoop', 'RestoreProtectedAccess')
        protected_git_roots = Get-EffectiveProtectedGitRoots
        protected_git_guard = if ($SkipProtectedGitGuard) { 'disabled' } else { 'enabled' }
        protected_root_write_deny = if ($UseProtectedRootWriteDeny -and $AllowUnsafeProtectedRootWriteDeny) { 'enabled' } elseif ($UseProtectedRootWriteDeny) { 'blocked_requires_allow' } else { 'disabled' }
        protocol_files = @($paths.Keys | ForEach-Object { $paths[$_] })
    } | ConvertTo-Json -Depth 8
    exit 0
}

Invoke-WithBridgeLock -Paths $paths -Body {
    switch ($Action) {
        'Init' {
            Initialize-Bridge -Paths $paths -ArchiveRootFull $archiveRootFull
        }
        'Status' {
            # no state mutation
        }
        'ClaudeDone' {
            Complete-ClaudeStep -Paths $paths -ArchiveRootFull $archiveRootFull
        }
        'CodexDone' {
            Complete-CodexStep -Paths $paths -ArchiveRootFull $archiveRootFull
        }
        'RunLoop' {
            Run-BridgeLoop -Paths $paths -ArchiveRootFull $archiveRootFull
        }
        'RestoreProtectedAccess' {
            Restore-ProtectedRootWriteAccess -Paths $paths
        }
    }
}

$state = Get-BridgeState -Paths $paths
[ordered]@{
    status = 'OK'
    action = $Action
    bridge_state = $state
    files = [ordered]@{
        state = $paths.State
        claude_prompt = $paths.ClaudePrompt
        claude_result = $paths.ClaudeResult
        codex_review_prompt = $paths.CodexReviewPrompt
        codex_review = $paths.CodexReview
        next_claude_prompt = $paths.NextClaudePrompt
        decision = $paths.Decision
        events = $paths.Events
    }
} | ConvertTo-Json -Depth 10
