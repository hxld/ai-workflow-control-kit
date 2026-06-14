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

function New-NoProgressPlanContractRoot {
    param(
        [string]$Root,
        [datetime]$RootTime,
        [datetime]$DecisionTime
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Text (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') @'
{
  "verification_status": "FAIL",
  "issues": [
    "policy_rebuild_plan_invalid:test_harness_claim_core",
    "plan_contract_verification_failed"
  ]
}
'@
    Write-Text (Join-Path $Root 'AUTOPILOT_SUMMARY.md') @'
# Replay Autopilot Summary

- plan_status: BLOCKED
- stop_stage: PlanContract
- final_status: BLOCKED
- verification_capped_coverage: 0
'@
    foreach ($name in @('PLAN_CONTRACT_VERIFY.json', 'AUTOPILOT_SUMMARY.md')) {
        (Get-Item -LiteralPath (Join-Path $Root $name)).LastWriteTime = $DecisionTime
    }
    (Get-Item -LiteralPath $Root).LastWriteTime = $RootTime
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stopline-verifier-tooling-v492-" + [guid]::NewGuid().ToString('N'))

try {
    $stoplineText = Get-Content -LiteralPath $stoplineGate -Raw -Encoding UTF8
    Assert-True 'stopline_tracks_plan_contract_verifier_as_tooling_change' ($stoplineText.Contains("Verify-PlanContract.ps1"))

    $tempScripts = Join-Path $tempRoot 'scripts'
    New-Item -ItemType Directory -Force -Path $tempScripts | Out-Null
    $tempStopline = Join-Path $tempScripts 'Invoke-ReplayStoplineGate.ps1'
    Copy-Item -LiteralPath $stoplineGate -Destination $tempStopline -Force

    $oldToolTime = (Get-Date).AddHours(-4)
    $newVerifierTime = (Get-Date).AddMinutes(-1)
    foreach ($name in @(
            'Run-ReplayLoop.ps1',
            'Run-SliceLoop.ps1',
            'Write-ControlPlaneSummary.ps1',
            'Write-FailureAuditPack.ps1',
            'Invoke-PlanSchemaFailFast.ps1',
            'Verify-SliceClosure.ps1',
            'SliceVerifier.ps1'
        )) {
        Write-Text (Join-Path $tempScripts $name) "# stub $name"
        (Get-Item -LiteralPath (Join-Path $tempScripts $name)).LastWriteTime = $oldToolTime
    }
    Write-Text (Join-Path $tempScripts 'Verify-PlanContract.ps1') '# verifier fix'
    (Get-Item -LiteralPath (Join-Path $tempScripts 'Verify-PlanContract.ps1')).LastWriteTime = $newVerifierTime
    (Get-Item -LiteralPath $tempStopline).LastWriteTime = $oldToolTime

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v492-stopline'
    $decisionTime = (Get-Date).AddHours(-2)
    New-NoProgressPlanContractRoot -Root "$replayBase-r01" -RootTime (Get-Date).AddMinutes(-30) -DecisionTime $decisionTime
    New-NoProgressPlanContractRoot -Root "$replayBase-r02" -RootTime (Get-Date).AddMinutes(-20) -DecisionTime $decisionTime
    New-NoProgressPlanContractRoot -Root "$replayBase-r03" -RootTime (Get-Date).AddMinutes(-10) -DecisionTime $decisionTime

    & powershell -NoProfile -ExecutionPolicy Bypass -File $tempStopline `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -AllowRecentToolingChange `
        -Quiet | Out-Null

    Assert-True 'stopline_allows_after_newer_verifier_change' ($LASTEXITCODE -eq 0)
    $analysis = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline_decision_records_allow_after_tooling_change' ($analysis.decision -eq 'ALLOW_AFTER_TOOLING_CHANGE')
    Assert-True 'stopline_newest_tooling_change_is_verifier' ((Split-Path -Leaf ([string]$analysis.newest_tooling_change)) -eq 'Verify-PlanContract.ps1')

    Write-Host 'PASS: v492 stopline verifier tooling change'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
