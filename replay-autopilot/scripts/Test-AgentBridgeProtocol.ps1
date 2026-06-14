param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Set-StateStatus {
    param([string]$Path, [string]$Status)
    $state = Read-JsonFile -Path $Path
    $state.status = $Status
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$bridgeScript = Join-Path $scriptRoot 'Start-AgentBridge.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-bridge-protocol-{0}' -f ([guid]::NewGuid().ToString('N')))
$bridgeRoot = Join-Path $tempRoot 'current'
$archiveRoot = Join-Path $tempRoot 'runs'
$promptPath = Join-Path $tempRoot 'initial.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        bridge_script = $bridgeScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Set-Content -LiteralPath $promptPath -Value 'Run one replay canary and write CLAUDE_RESULT.md.' -Encoding UTF8

    # Test 1: Init creates protocol files and WAITING_CLAUDE state.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $promptPath | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Init exit code should be 0"

    $statePath = Join-Path $bridgeRoot 'STATE.json'
    $state1 = Read-JsonFile -Path $statePath
    Assert-True ($state1.status -eq 'WAITING_CLAUDE') "Init should set WAITING_CLAUDE"
    Assert-True ((Test-Path -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_PROMPT.md'))) "CLAUDE_PROMPT.md should exist"
    Assert-True ((Test-Path -LiteralPath (Join-Path $bridgeRoot 'events.jsonl'))) "events.jsonl should exist"
    $initialAgentPrompt = Get-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_AGENT_PROMPT.md') -Raw -Encoding UTF8
    Assert-True ($initialAgentPrompt -match 'Protected Write Boundary') "CLAUDE_AGENT_PROMPT.md should include protected write boundary"
    Assert-True ($initialAgentPrompt -match 'Protected git roots are READ-ONLY') "CLAUDE_AGENT_PROMPT.md should list protected git roots"

    # Test 2: Force init clears stale logs so a reused bridge root cannot mislead monitors.
    $staleLogDir = Join-Path $bridgeRoot 'logs\cycle-0001\claude'
    New-Item -ItemType Directory -Force -Path $staleLogDir | Out-Null
    Set-Content -LiteralPath (Join-Path $staleLogDir 'stale.log') -Value 'old run' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $promptPath `
        -Force | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Force Init exit code should be 0"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'logs'))) "Force Init should clear stale logs"

    # Test 3: ClaudeDone rejects empty/missing result.
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ClaudeDone `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot *> $null
    $expectedFailureExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference
    $failedAsExpected = ($expectedFailureExitCode -ne 0)
    Assert-True $failedAsExpected "ClaudeDone should reject empty CLAUDE_RESULT.md"

    # Test 4: ClaudeDone advances to WAITING_CODEX_REVIEW and creates review prompt.
    # It also accepts externally marked CLAUDE_DONE so agents cannot strand the bridge.
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_RESULT.md') -Value @'
# Claude Result

Replay root: <REPLAY_EVIDENCE_ROOT>\sample
Phase0: PASS
Plan: PASS
Phase1: DONE
'@ -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_DONE.flag') -Value 'done' -Encoding UTF8
    Set-StateStatus -Path $statePath -Status 'CLAUDE_DONE'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ClaudeDone `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "ClaudeDone exit code should be 0"
    $state2 = Read-JsonFile -Path $statePath
    Assert-True ($state2.status -eq 'WAITING_CODEX_REVIEW') "ClaudeDone should set WAITING_CODEX_REVIEW"
    $codexPrompt = Get-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_REVIEW_PROMPT.md') -Raw -Encoding UTF8
    Assert-True ($codexPrompt -match 'DECISION.json') "Codex review prompt should require DECISION.json"
    Assert-True ($codexPrompt -match 'Protected Write Boundary') "Codex review prompt should include protected write boundary"

    # Test 5: CodexDone with CONTINUE archives cycle and prepares next Claude prompt.
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_REVIEW.md') -Value 'Continue with v262 implementation-quality review.' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'NEXT_CLAUDE_PROMPT.md') -Value 'Run the next focused replay/evolution step.' -Encoding UTF8
    [ordered]@{
        decision = 'CONTINUE'
        reason = 'need next step'
        next_actor = 'claude'
        coverage_signal = 'low'
        blocker = ''
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $bridgeRoot 'DECISION.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_DONE.flag') -Value 'done' -Encoding UTF8
    Set-StateStatus -Path $statePath -Status 'CODEX_DONE'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action CodexDone `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "CodexDone exit code should be 0"
    $state3 = Read-JsonFile -Path $statePath
    Assert-True ($state3.status -eq 'WAITING_CLAUDE') "CONTINUE should set WAITING_CLAUDE"
    Assert-True ([int]$state3.cycle -eq 2) "CONTINUE should increment cycle"
    $nextClaude = Get-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_PROMPT.md') -Raw -Encoding UTF8
    Assert-True ($nextClaude -match 'next focused replay') "CLAUDE_PROMPT.md should be replaced by NEXT_CLAUDE_PROMPT.md"
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'LAST_CLAUDE_RESULT.md') -Raw -Encoding UTF8) -match 'Replay root') "LAST_CLAUDE_RESULT.md should preserve previous result"
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'LAST_CODEX_REVIEW.md') -Raw -Encoding UTF8) -match 'Continue with v262') "LAST_CODEX_REVIEW.md should preserve previous review"
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'LAST_NEXT_CLAUDE_PROMPT.md') -Raw -Encoding UTF8) -match 'next focused replay') "LAST_NEXT_CLAUDE_PROMPT.md should preserve previous next prompt"
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'LAST_DECISION.json') -Raw -Encoding UTF8) -match 'CONTINUE') "LAST_DECISION.json should preserve previous decision"
    Assert-True ((Get-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_AGENT_PROMPT.md') -Raw -Encoding UTF8) -match 'Previous Cycle Context') "CLAUDE_AGENT_PROMPT.md should advertise stable previous-cycle context"
    $archives = @(Get-ChildItem -LiteralPath $archiveRoot -Directory)
    Assert-True ($archives.Count -eq 1) "One cycle archive should be written"

    # Test 6: CodexDone with STOP moves to STOPPED without requiring next prompt.
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_RESULT.md') -Value 'second result' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CLAUDE_DONE.flag') -Value 'done' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action ClaudeDone `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_REVIEW.md') -Value 'Stop after enough evidence.' -Encoding UTF8
    [ordered]@{
        decision = 'STOP'
        reason = 'done'
        next_actor = ''
        coverage_signal = ''
        blocker = ''
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $bridgeRoot 'DECISION.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridgeRoot 'CODEX_DONE.flag') -Value 'done' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action CodexDone `
        -BridgeRoot $bridgeRoot `
        -ArchiveRoot $archiveRoot | Out-Null
    $state4 = Read-JsonFile -Path $statePath
    Assert-True ($state4.status -eq 'STOPPED') "STOP should set STOPPED"

    # Test 7: RunLoop resumes an interrupted Claude step when CLAUDE_DONE.flag already exists.
    $resumeClaudeRoot = Join-Path $tempRoot 'resume-claude-current'
    $resumeClaudePrompt = Join-Path $tempRoot 'resume-claude-initial.md'
    Set-Content -LiteralPath $resumeClaudePrompt -Value 'Resume completed Claude step.' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $resumeClaudeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $resumeClaudePrompt | Out-Null
    Set-Content -LiteralPath (Join-Path $resumeClaudeRoot 'CLAUDE_RESULT.md') -Value 'completed claude result' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $resumeClaudeRoot 'CLAUDE_DONE.flag') -Value 'done' -Encoding UTF8
    Set-StateStatus -Path (Join-Path $resumeClaudeRoot 'STATE.json') -Status 'CLAUDE_RUNNING'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action RunLoop `
        -BridgeRoot $resumeClaudeRoot `
        -ArchiveRoot $archiveRoot `
        -ClaudeExecutor manual `
        -CodexExecutor manual | Out-Null
    $resumeClaudeState = Read-JsonFile -Path (Join-Path $resumeClaudeRoot 'STATE.json')
    Assert-True ($resumeClaudeState.status -eq 'CODEX_REVIEWING') "RunLoop should resume completed Claude step and wait for Codex review"
    Assert-True ((Get-Content -LiteralPath (Join-Path $resumeClaudeRoot 'CODEX_REVIEW_PROMPT.md') -Raw -Encoding UTF8) -match 'Agent Bridge Role: Codex Reviewer') "RunLoop resume should create Codex review prompt"

    # Test 8: RunLoop resumes an interrupted Codex step when CODEX_DONE.flag already exists.
    $resumeCodexRoot = Join-Path $tempRoot 'resume-codex-current'
    $resumeCodexPrompt = Join-Path $tempRoot 'resume-codex-initial.md'
    Set-Content -LiteralPath $resumeCodexPrompt -Value 'Resume completed Codex step.' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $resumeCodexRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $resumeCodexPrompt | Out-Null
    Set-Content -LiteralPath (Join-Path $resumeCodexRoot 'CLAUDE_RESULT.md') -Value 'previous claude result' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $resumeCodexRoot 'CODEX_REVIEW.md') -Value 'continue after interrupted Codex step' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $resumeCodexRoot 'NEXT_CLAUDE_PROMPT.md') -Value 'Next prompt after resume.' -Encoding UTF8
    [ordered]@{
        decision = 'CONTINUE'
        reason = 'resume test'
        next_actor = 'claude'
        coverage_signal = ''
        blocker = ''
        created_at = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $resumeCodexRoot 'DECISION.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $resumeCodexRoot 'CODEX_DONE.flag') -Value 'done' -Encoding UTF8
    Set-StateStatus -Path (Join-Path $resumeCodexRoot 'STATE.json') -Status 'CODEX_REVIEWING'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action RunLoop `
        -BridgeRoot $resumeCodexRoot `
        -ArchiveRoot $archiveRoot `
        -ClaudeExecutor manual `
        -CodexExecutor manual | Out-Null
    $resumeCodexState = Read-JsonFile -Path (Join-Path $resumeCodexRoot 'STATE.json')
    Assert-True ($resumeCodexState.status -eq 'CLAUDE_RUNNING') "RunLoop should resume completed Codex step and start next Claude step"
    Assert-True ([int]$resumeCodexState.cycle -eq 2) "RunLoop resume from Codex should increment cycle"
    Assert-True ((Get-Content -LiteralPath (Join-Path $resumeCodexRoot 'LAST_CODEX_REVIEW.md') -Raw -Encoding UTF8) -match 'interrupted Codex') "RunLoop resume should preserve last Codex review"

    # Test 9: RunLoop must fail closed before starting an actor when a protected root is already dirty.
    $dirtyBridgeRoot = Join-Path $tempRoot 'dirty-current'
    $dirtyPromptPath = Join-Path $tempRoot 'dirty-initial.md'
    $protectedRoot = Join-Path $tempRoot 'protected-root'
    New-Item -ItemType Directory -Force -Path $protectedRoot | Out-Null
    & git -C $protectedRoot init | Out-Null
    Set-Content -LiteralPath (Join-Path $protectedRoot 'dirty.txt') -Value 'dirty' -Encoding UTF8
    Set-Content -LiteralPath $dirtyPromptPath -Value 'This should not start while protected root is dirty.' -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action Init `
        -BridgeRoot $dirtyBridgeRoot `
        -ArchiveRoot $archiveRoot `
        -InitialPromptPath $dirtyPromptPath | Out-Null
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $bridgeScript `
        -Action RunLoop `
        -BridgeRoot $dirtyBridgeRoot `
        -ArchiveRoot $archiveRoot `
        -ClaudeExecutor manual `
        -ProtectedGitRoots $protectedRoot `
        -ForceUnlock *> $null
    $dirtyRunExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference
    Assert-True ($dirtyRunExitCode -ne 0) "RunLoop should fail when protected root is dirty before actor start"
    $dirtyState = Read-JsonFile -Path (Join-Path $dirtyBridgeRoot 'STATE.json')
    Assert-True ($dirtyState.status -eq 'STOPPED') "Dirty protected root should leave bridge STOPPED"
    Assert-True ($dirtyState.last_message -match 'Bridge stopped after error') "STOPPED message should explain bridge error"

    [ordered]@{
        status = 'PASS'
        assertions = 32
        cases = @(
            'init_creates_bridge_contract',
            'agent_prompts_include_protected_write_boundary',
            'force_init_clears_stale_logs',
            'claude_done_requires_result',
            'claude_done_prepares_codex_review',
            'codex_continue_archives_and_prepares_next_prompt',
            'codex_continue_preserves_last_cycle_context',
            'codex_stop_stops_bridge',
            'runloop_resumes_completed_claude_step',
            'runloop_resumes_completed_codex_step',
            'dirty_protected_root_fails_closed_before_actor_start'
        )
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 8
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolved = Resolve-AbsolutePath $tempRoot
        $tempBase = Resolve-AbsolutePath ([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refuse to delete temp outside temp root: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
