param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$summaryPath = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("control-summary-current-root-v506-" + [guid]::NewGuid().ToString('N'))

try {
    Assert-True 'runner_accepts_current_replay_root_for_control_summary' ($runnerText.Contains('[string]$CurrentReplayRoot') -and $runnerText.Contains('-CurrentReplayRoot $replayRoot'))
    Assert-True 'runner_passes_replay_root_to_control_summary' ($runnerText.Contains('$controlArgs += @(''-ReplayRoot'', $CurrentReplayRoot)'))

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $outputRoot = Join-Path $tempRoot 'control'
    $prefix = 'claim' + '-codex-replay-'
    $currentRoot = Join-Path $evidenceRoot ($prefix + 'current')
    $otherRoot = Join-Path $evidenceRoot ($prefix + 'newer')
    New-Item -ItemType Directory -Force -Path $currentRoot, $otherRoot | Out-Null

    Write-Text (Join-Path $currentRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: STOP_BLOCKED
'@
    Write-Text (Join-Path $currentRoot 'PLAN_SCHEMA_FAILFAST.json') @'
{
  "stage": "PlanSchemaFailFast",
  "status": "FAIL",
  "issues": ["current-root-selected"]
}
'@
    Write-Text (Join-Path $otherRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: TARGET_REACHED
'@

    (Get-Item -LiteralPath $currentRoot).LastWriteTime = (Get-Date).AddMinutes(-10)
    (Get-Item -LiteralPath $otherRoot).LastWriteTime = (Get-Date)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryPath `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot $currentRoot `
        -OutputRoot $outputRoot `
        -MaxRoots 80 `
        -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Write-ControlPlaneSummary failed with exit code $LASTEXITCODE"
    }

    $latest = Get-Content -LiteralPath (Join-Path $outputRoot 'RUN_CONTROL_LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'control_summary_uses_explicit_current_root' ([System.IO.Path]::GetFullPath([string]$latest.latest.replay_root).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($currentRoot).TrimEnd('\'))
    Assert-True 'control_summary_does_not_pick_newer_root_when_replay_root_is_set' ([string]$latest.latest.autopilot_decision -eq 'STOP_BLOCKED')

    Write-Host 'PASS: v506 control plane summary current root'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
