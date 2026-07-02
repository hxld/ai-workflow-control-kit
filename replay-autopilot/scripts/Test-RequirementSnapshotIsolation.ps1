param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Text
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\requirement-snapshot-{0}' -f $PID)
$startScript = Join-Path $PSScriptRoot 'Start-ReplayRound.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        start_replay_round = $startScript
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

$configPath = Join-Path $tempRoot 'config.yaml'
$replayBase = Join-Path $tempRoot 'claim-codex-replay-v226-snapshot'
$originalRequirement = 'D:\opt\claim\.doc\xiebao\requirements.md'

Write-Text $configPath @"
project_root: D:\opt\claim
feature_name: xiebao
requirement_source: $originalRequirement
base_commit: 4ef00669ea2909fc77324d433cb4fbac34929e01
oracle_branch: master_xiebao_wcl
oracle_commit: f7cbcb7b20b7c861d46f438773d713f2c2204d3f
replay_root_base: $replayBase
run_label: snapshot-isolation-test
system_context_dir: D:\opt\claim\.doc\example-system-context
"@

& powershell -NoProfile -ExecutionPolicy Bypass -File $startScript -ConfigPath $configPath -Round 1 -DryRun | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Start-ReplayRound dry run failed" }

$replayRoot = "$replayBase-r01"
$phase0Prompt = Join-Path $replayRoot 'PHASE0_PROMPT.md'
$phase1Prompt = Join-Path $replayRoot 'PHASE1_PROMPT.md'
$metadataPath = Join-Path $replayRoot 'AUTOPILOT_RUN.json'

foreach ($path in @($phase0Prompt, $phase1Prompt, $metadataPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing expected dry-run artifact: $path" }
}

$phase0 = Get-Content -LiteralPath $phase0Prompt -Raw -Encoding UTF8
$phase1 = Get-Content -LiteralPath $phase1Prompt -Raw -Encoding UTF8
$metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$snapshotPath = Join-Path $replayRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md'

if ($phase0 -notmatch [regex]::Escape($snapshotPath)) { throw "PHASE0 prompt does not use requirement snapshot" }
if ($phase1 -notmatch [regex]::Escape($snapshotPath)) { throw "PHASE1 prompt does not use requirement snapshot" }
if ($phase0 -match [regex]::Escape($originalRequirement)) { throw "PHASE0 prompt leaked original requirement path" }
if ($phase1 -match [regex]::Escape($originalRequirement)) { throw "PHASE1 prompt leaked original requirement path" }
if ([string]$metadata.requirement_source -ne $snapshotPath) { throw "metadata requirement_source is not snapshot: $($metadata.requirement_source)" }
if ([string]$metadata.original_requirement_source -ne $originalRequirement) { throw "metadata original_requirement_source not preserved" }

[ordered]@{
    status = 'PASS'
    cases = @('phase0_uses_requirement_snapshot', 'phase1_uses_requirement_snapshot', 'metadata_preserves_original_source')
    replay_root = $replayRoot
} | ConvertTo-Json -Depth 6

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}

