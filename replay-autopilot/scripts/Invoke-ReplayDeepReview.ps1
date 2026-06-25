param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$HistoryRoot = '',
    [ValidateSet('codex', 'claude', 'manual')]
    [string]$Executor = 'codex',
    [ValidateSet('codex', 'claude', 'manual', '')]
    [string]$RequireExecutor = '',
    [switch]$AllowCodexExecutor,
    [string]$Model = '',
    [string]$ReasoningEffort = '',
    [string]$Sandbox = 'danger-full-access',
    [string]$Approval = 'never',
    [int]$TimeoutMinutes = 240,
    [int]$Lookback = 4,
    [switch]$NoExecute,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($RequireExecutor) -and $Executor -ne $RequireExecutor) {
    throw "Executor policy violation: actual executor '$Executor' does not match required executor '$RequireExecutor'."
}
if ($Executor -eq 'codex' -and -not $AllowCodexExecutor) {
    throw "Executor policy violation: Codex executor requires explicit authorization for deep review. Pass -AllowCodexExecutor for a Codex-primary run."
}

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Expand-Template {
    param([string]$Template, [hashtable]$Values)
    $output = $Template
    foreach ($key in $Values.Keys) {
        $output = $output.Replace('{{' + $key + '}}', [string]$Values[$key])
    }
    return $output
}

function Get-RecentReplayRoots {
    param(
        [string]$Root,
        [int]$Count
    )

    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    Get-ChildItem -LiteralPath $Root -Directory -Filter 'claim-codex-replay-v*-autopilot-*' -ErrorAction SilentlyContinue | ForEach-Object {
        $summaryPath = Join-Path $_.FullName 'AUTOPILOT_SUMMARY.md'
        if (Test-Path -LiteralPath $summaryPath) {
            $items.Add([pscustomobject]@{
                Root = $_.FullName
                Modified = (Get-Item -LiteralPath $summaryPath).LastWriteTime
            })
        }
    }

    return @($items | Sort-Object Modified -Descending | Select-Object -First $Count | ForEach-Object { $_.Root })
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$historyRootFull = Resolve-AbsolutePath $HistoryRoot
$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$templatePath = Join-Path $scriptRoot 'prompts\deep-replay-review.prompt.md'
$stopLossPath = Join-Path $replayRootFull 'STOP_LOSS_DECISION.json'
$promptPath = Join-Path $replayRootFull 'DEEP_REVIEW_PROMPT.md'

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        ReplayRoot = $replayRootFull
        HistoryRoot = $historyRootFull
        Template = $templatePath
        Executor = $Executor
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        TimeoutMinutes = $TimeoutMinutes
        Lookback = $Lookback
    } | Format-List
    exit 0
}

if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "Replay root not found: $replayRootFull"
}
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Deep review template not found: $templatePath"
}

$stopLoss = Read-JsonIfExists $stopLossPath
$reviewRoots = New-Object System.Collections.Generic.List[string]
$null = $reviewRoots.Add($replayRootFull)
if ($stopLoss -and $stopLoss.recent_roots) {
    foreach ($root in @($stopLoss.recent_roots)) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root) -and -not $reviewRoots.Contains($root)) {
            $null = $reviewRoots.Add((Resolve-AbsolutePath $root))
        }
    }
}

if ($reviewRoots.Count -lt 2) {
    foreach ($root in Get-RecentReplayRoots -Root $historyRootFull -Count $Lookback) {
        if (-not $reviewRoots.Contains($root)) {
            $null = $reviewRoots.Add((Resolve-AbsolutePath $root))
        }
    }
}

$reviewRootText = (@($reviewRoots | Select-Object -First ([Math]::Max(1, $Lookback + 1)) | ForEach-Object { "- $_" }) -join "`n")
$template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$values = @{
    REPLAY_ROOT = $replayRootFull
    STOP_LOSS_DECISION = $stopLossPath
    REVIEW_ROOTS = $reviewRootText
}
$expanded = Expand-Template -Template $template -Values $values
Set-Content -LiteralPath $promptPath -Value $expanded -Encoding UTF8

if ($NoExecute -or $Executor -eq 'manual') {
    Write-Host "Deep review prompt prepared: $promptPath"
    exit 0
}

$logDir = Join-Path $replayRootFull 'logs\deep-review'
$workDir = if (-not [string]::IsNullOrWhiteSpace($env:AI_WORKFLOW_PROJECT_ROOT) -and (Test-Path -LiteralPath $env:AI_WORKFLOW_PROJECT_ROOT)) { $env:AI_WORKFLOW_PROJECT_ROOT } else { $replayRootFull }
$invokeArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1'),
    '-PromptPath', $promptPath,
    '-WorkDir', $workDir,
    '-LogDir', $logDir,
    '-Executor', $Executor,
    '-Sandbox', $Sandbox,
    '-Approval', $Approval,
    '-TimeoutMinutes', $TimeoutMinutes,
    '-Name', 'deep-review',
    '-CompletionPath', (Join-Path $replayRootFull 'STOP_OR_CONTINUE_DECISION.md'),
    '-CompletionQuietSeconds', '90'
)
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $invokeArgs += @('-Model', $Model)
}
if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) {
    $invokeArgs += @('-ReasoningEffort', $ReasoningEffort)
}

& powershell @invokeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Deep replay review failed with exit code $LASTEXITCODE. Inspect $logDir"
}

$required = @(
    'DEEP_REVIEW_REPORT.md',
    'ROOT_CAUSE_LEDGER.json',
    'NEXT_EXPERIMENT_PLAN.md',
    'STOP_OR_CONTINUE_DECISION.md'
)
foreach ($file in $required) {
    $path = Join-Path $replayRootFull $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Deep replay review did not produce required file: $path"
    }
}

Write-Host "Deep replay review completed under $replayRootFull"
