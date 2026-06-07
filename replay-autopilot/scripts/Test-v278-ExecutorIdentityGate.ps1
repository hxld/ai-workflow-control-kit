param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config.yaml'
$runLoop = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$sliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
$deepReview = Join-Path $PSScriptRoot 'Invoke-ReplayDeepReview.ps1'
$invokeAgent = Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'
$tempRoot = Join-Path $root ('.tmp\executor-identity-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function Invoke-Capture {
    param([object[]]$CommandArgs)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell @CommandArgs 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

$cases = New-Object System.Collections.Generic.List[string]

try {
    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $cases.Add((Assert-True 'config_defaults_to_claude' ($configText -match '(?m)^executor:\s*claude\s*$'))) | Out-Null
    $cases.Add((Assert-True 'config_requires_claude' ($configText -match '(?m)^require_executor:\s*claude\s*$'))) | Out-Null
    $cases.Add((Assert-True 'config_blocks_codex_by_default' ($configText -match '(?m)^allow_codex_executor:\s*false\s*$'))) | Out-Null

    $defaultRun = Invoke-Capture -CommandArgs @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runLoop,'-ValidateOnly')
    $cases.Add((Assert-True 'default_runloop_validate_passes' ($defaultRun.ExitCode -eq 0))) | Out-Null
    $cases.Add((Assert-True 'default_runloop_uses_claude' ($defaultRun.Output -match 'Executor\s+:\s+claude'))) | Out-Null
    $cases.Add((Assert-True 'default_phase0_uses_claude_model' ($defaultRun.Output -match 'Phase0Model\s+:\s+claude-'))) | Out-Null
    $cases.Add((Assert-True 'default_runloop_does_not_use_gpt_phase0' ($defaultRun.Output -notmatch 'Phase0Model\s+:\s+gpt-'))) | Out-Null

    $codexConfig = Join-Path $tempRoot 'codex-blocked.yaml'
    $codexText = $configText `
        -replace '(?m)^executor:.*$', 'executor: codex' `
        -replace '(?m)^require_executor:.*$', 'require_executor:' `
        -replace '(?m)^allow_codex_executor:.*$', 'allow_codex_executor: false'
    Set-Content -LiteralPath $codexConfig -Value $codexText -Encoding UTF8

    $blockedRun = Invoke-Capture -CommandArgs @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runLoop,'-ConfigPath',$codexConfig,'-ValidateOnly')
    $cases.Add((Assert-True 'codex_without_allow_is_blocked' ($blockedRun.ExitCode -ne 0))) | Out-Null
    $cases.Add((Assert-True 'codex_blocker_message_clear' ($blockedRun.Output -match 'Codex executor is blocked by default'))) | Out-Null

    $allowedRun = Invoke-Capture -CommandArgs @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runLoop,'-ConfigPath',$codexConfig,'-AllowCodexExecutor','-ValidateOnly')
    $cases.Add((Assert-True 'codex_allowed_requires_explicit_flag' ($allowedRun.ExitCode -eq 0 -and $allowedRun.Output -match 'Executor\s+:\s+codex'))) | Out-Null

    $mismatchRun = Invoke-Capture -CommandArgs @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runLoop,'-ConfigPath',$codexConfig,'-AllowCodexExecutor','-RequireExecutor','claude','-ValidateOnly')
    $cases.Add((Assert-True 'require_executor_mismatch_blocks' ($mismatchRun.ExitCode -ne 0 -and $mismatchRun.Output -match 'does not match required executor'))) | Out-Null

    $runLoopSource = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $cases.Add((Assert-True 'runloop_writes_executor_audit' ($runLoopSource -match 'EXECUTOR_AUDIT\.json'))) | Out-Null
    $cases.Add((Assert-True 'runloop_audit_records_stage_models' ($runLoopSource -match "stage = 'phase0'" -and $runLoopSource -match "stage = 'phase1'"))) | Out-Null

    $sliceSource = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8
    $deepReviewSource = Get-Content -LiteralPath $deepReview -Raw -Encoding UTF8
    $invokeSource = Get-Content -LiteralPath $invokeAgent -Raw -Encoding UTF8
    $cases.Add((Assert-True 'slice_loop_default_claude' ($sliceSource -match '\[string\]\$Executor = ''claude'''))) | Out-Null
    $cases.Add((Assert-True 'deep_review_default_claude' ($deepReviewSource -match '\[string\]\$Executor = ''claude'''))) | Out-Null
    $cases.Add((Assert-True 'invoke_agent_default_claude' ($invokeSource -match '\[string\]\$Executor = ''claude'''))) | Out-Null
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
