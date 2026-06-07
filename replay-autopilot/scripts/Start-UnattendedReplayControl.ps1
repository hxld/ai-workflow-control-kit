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

function Resolve-EvidenceRootFromReplayBase {
    param([string]$ReplayRootBase)
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

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml $configPathFull
$replayRootBase = Resolve-AbsolutePath (Require-Key $config 'replay_root_base')
$evidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBase $replayRootBase
$runRoot = Join-Path $evidenceRoot '_control-runs'
$runId = 'launcher-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$runDir = Join-Path $runRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$stdout = Join-Path $runDir 'stdout.log'
$stderr = Join-Path $runDir 'stderr.log'
$controller = Join-Path $PSScriptRoot 'Run-UnattendedReplayControl.ps1'
$args = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $controller,
    '-ConfigPath', $configPathFull
)
if ($StartRound -gt 0) { $args += @('-StartRound', [string]$StartRound) }
if ($CycleRounds -gt 0) { $args += @('-CycleRounds', [string]$CycleRounds) }
if ($MaxCycles -gt 0) { $args += @('-MaxCycles', [string]$MaxCycles) }
if (-not [string]::IsNullOrWhiteSpace($Executor)) { $args += @('-Executor', $Executor) }
if (-not [string]::IsNullOrWhiteSpace($RequireExecutor)) { $args += @('-RequireExecutor', $RequireExecutor) }
if ($AllowCodexExecutor) { $args += '-AllowCodexExecutor' }
if ($RunEvolution) { $args += '-RunEvolution' }
if ($UseLatestKnowledgeVersion) { $args += '-UseLatestKnowledgeVersion' }
if ($IgnoreStopline) { $args += '-IgnoreStopline' }
if ($ValidateOnly) { $args += '-ValidateOnly' }

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        controller = $controller
        config = $configPathFull
        evidence_root = $evidenceRoot
        stdout = $stdout
        stderr = $stderr
        argument_list = $args
    } | ConvertTo-Json -Depth 8
    exit 0
}

$process = Start-Process -FilePath powershell.exe `
    -ArgumentList $args `
    -WorkingDirectory $scriptRoot `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -WindowStyle Hidden `
    -PassThru

$statePath = Join-Path $runRoot 'LATEST_CONTROL_LAUNCHER_STATE.json'
[ordered]@{
    schema = 'unattended_replay_control_launcher_state.v1'
    run_id = $runId
    process_id = $process.Id
    started_at = (Get-Date).ToString('s')
    controller = $controller
    config = $configPathFull
    stdout = $stdout
    stderr = $stderr
    executor = $Executor
    require_executor = $RequireExecutor
    cycle_rounds = $CycleRounds
    max_cycles = $MaxCycles
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

[ordered]@{
    status = 'STARTED'
    run_id = $runId
    process_id = $process.Id
    state = $statePath
    stdout = $stdout
    stderr = $stderr
} | ConvertTo-Json -Depth 8
