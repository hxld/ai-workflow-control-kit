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

function New-NoProgressRoot {
    param(
        [string]$Root,
        [datetime]$RootTime,
        [datetime]$TerminalDecisionTime,
        [datetime]$DiagnosticRetouchTime
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Text (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') '{"verification_status":"FAIL","issues":["policy_rebuild_plan_missing:ExampleDataAssemblyHelper.buildRequestCommon"]}'
    Write-Text (Join-Path $Root 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: STOP_BLOCKED
- verification_capped_coverage: 0
'@
    Write-Text (Join-Path $Root 'AUTOPILOT_SUMMARY.md') @'
# Replay Autopilot Summary

- final_status: BLOCKED
- verification_capped_coverage: 0
'@

    (Get-Item -LiteralPath (Join-Path $Root 'AUTOPILOT_DECISION.md')).LastWriteTime = $TerminalDecisionTime
    (Get-Item -LiteralPath (Join-Path $Root 'AUTOPILOT_SUMMARY.md')).LastWriteTime = $TerminalDecisionTime
    (Get-Item -LiteralPath (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')).LastWriteTime = $DiagnosticRetouchTime
    (Get-Item -LiteralPath $Root).LastWriteTime = $RootTime
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stopline-diagnostic-retouch-v527-" + [guid]::NewGuid().ToString('N'))

try {
    $tempScripts = Join-Path $tempRoot 'scripts'
    New-Item -ItemType Directory -Force -Path $tempScripts | Out-Null
    $tempStopline = Join-Path $tempScripts 'Invoke-ReplayStoplineGate.ps1'
    Copy-Item -LiteralPath $stoplineGate -Destination $tempStopline -Force

    $oldToolTime = (Get-Date).AddHours(-5)
    $toolFixTime = (Get-Date).AddHours(-1)
    foreach ($name in @(
            'Run-SliceLoop.ps1',
            'Write-ControlPlaneSummary.ps1',
            'Write-FailureAuditPack.ps1',
            'Invoke-PlanSchemaFailFast.ps1',
            'Verify-SliceClosure.ps1',
            'SliceVerifier.ps1',
            'Run-ReplayLoop.ps1'
        )) {
        Write-Text (Join-Path $tempScripts $name) "# stub $name"
        (Get-Item -LiteralPath (Join-Path $tempScripts $name)).LastWriteTime = $oldToolTime
    }
    Write-Text (Join-Path $tempScripts 'Verify-PlanContract.ps1') '# v526 verifier fix'
    (Get-Item -LiteralPath (Join-Path $tempScripts 'Verify-PlanContract.ps1')).LastWriteTime = $toolFixTime
    (Get-Item -LiteralPath $tempStopline).LastWriteTime = $oldToolTime

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v527-stopline'
    $terminalDecisionTime = (Get-Date).AddHours(-2)
    $diagnosticRetouchTime = (Get-Date).AddMinutes(-5)

    New-NoProgressRoot -Root "$replayBase-r34" -RootTime (Get-Date).AddMinutes(-40) -TerminalDecisionTime $terminalDecisionTime -DiagnosticRetouchTime $terminalDecisionTime
    New-NoProgressRoot -Root "$replayBase-r35" -RootTime (Get-Date).AddMinutes(-30) -TerminalDecisionTime $terminalDecisionTime -DiagnosticRetouchTime $terminalDecisionTime
    New-NoProgressRoot -Root "$replayBase-r36" -RootTime (Get-Date).AddMinutes(-20) -TerminalDecisionTime $terminalDecisionTime -DiagnosticRetouchTime $diagnosticRetouchTime

    & powershell -NoProfile -ExecutionPolicy Bypass -File $tempStopline `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -AllowRecentToolingChange `
        -Quiet | Out-Null

    Assert-True 'stopline_allows_after_tool_fix_even_if_verifier_was_rechecked_later' ($LASTEXITCODE -eq 0)
    $analysis = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'decision_is_allow_after_tooling_change' ($analysis.decision -eq 'ALLOW_AFTER_TOOLING_CHANGE')
    Assert-True 'latest_decision_timestamp_uses_terminal_decision_not_rechecked_verifier' (([datetime]@($analysis.records)[0].decision_updated) -lt $toolFixTime)

    Write-Host 'PASS: v527 stopline ignores diagnostic retouch'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
