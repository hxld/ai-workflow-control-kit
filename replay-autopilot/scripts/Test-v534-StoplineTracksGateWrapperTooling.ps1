param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
    }
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
        [datetime]$DecisionTime
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Text (Join-Path $Root 'AUTOPILOT_SUMMARY.md') @'
# Replay Autopilot Summary

- stop_stage: Phase1
- final_status: BLOCKED
- verification_capped_coverage: 0
- fingerprints: low_verification_cap
'@
    Write-Text (Join-Path $Root 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: STOP_BLOCKED
- verification_capped_coverage: 0
'@
    foreach ($name in @('AUTOPILOT_SUMMARY.md', 'AUTOPILOT_DECISION.md')) {
        (Get-Item -LiteralPath (Join-Path $Root $name)).LastWriteTime = $DecisionTime
    }
    (Get-Item -LiteralPath $Root).LastWriteTime = $RootTime
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stopline-gate-wrapper-v534-" + [guid]::NewGuid().ToString('N'))

try {
    $stoplineText = Get-Content -LiteralPath $stoplineGate -Raw -Encoding UTF8
    Assert-True 'stopline tracks shared python resolver as tooling' ($stoplineText.Contains('Resolve-PythonLauncher.ps1'))
    Assert-True 'stopline tracks contract verification wrapper as tooling' ($stoplineText.Contains('Invoke-ContractVerification.ps1'))
    Assert-True 'stopline tracks RED hard gate wrapper as tooling' ($stoplineText.Contains('Invoke-RedPhaseHardGate.ps1'))
    Assert-True 'stopline tracks family router wrapper as tooling' ($stoplineText.Contains('FamilyRouterAndCap.ps1'))
    Assert-True 'stopline tracks side-effect verifier as tooling' ($stoplineText.Contains('verify-slice.ps1'))
    Assert-True 'stopline tracks slice evidence contract preparer as tooling' ($stoplineText.Contains('Prepare-SliceEvidenceContracts.ps1'))
    Assert-True 'stopline tracks next exact contract builder as tooling' ($stoplineText.Contains('Build-NextSliceExactContract.ps1'))
    Assert-True 'stopline tracks pre-slice authorizer as tooling' ($stoplineText.Contains('Authorize-PreSliceEvidence.ps1'))

    $tempScripts = Join-Path $tempRoot 'scripts'
    New-Item -ItemType Directory -Force -Path $tempScripts | Out-Null
    $tempStopline = Join-Path $tempScripts 'Invoke-ReplayStoplineGate.ps1'
    Copy-Item -LiteralPath $stoplineGate -Destination $tempStopline -Force

    $oldToolTime = (Get-Date).AddHours(-5)
    $newToolTime = (Get-Date).AddMinutes(-1)
    foreach ($name in @(
            'Run-ReplayLoop.ps1',
            'Run-SliceLoop.ps1',
            'Verify-PlanContract.ps1',
            'Verify-SliceClosure.ps1',
            'SliceVerifier.ps1',
            'FamilyRouterAndCap.ps1',
            'phase0-precheck.ps1',
            'Invoke-EconomyCheckpoint.ps1',
            'Invoke-RedPhaseHardGate.ps1',
            'Invoke-ContractVerification.ps1',
            'Invoke-IncrementalVerification.ps1',
            'Invoke-TodoDetector.ps1',
            'Invoke-CarrierSearch.ps1',
            'Invoke-Phase0ContractReconciliation.ps1',
            'Invoke-ReflectionSufficiencyGate.ps1',
            'Build-NextSliceExactContract.ps1',
            'Authorize-PreSliceEvidence.ps1',
            'Validate-ExecutableEvidenceGate.ps1',
            'v348_slice_quality_gate.ps1',
            'verify-slice.ps1',
            'verify-horizontal-slice.ps1',
            'verify-test-charter.ps1',
            'Invoke-TodoPlaceholderCheck.ps1',
            'Write-ControlPlaneSummary.ps1',
            'Write-FailureAuditPack.ps1',
            'Invoke-PlanSchemaFailFast.ps1'
        )) {
        Write-Text (Join-Path $tempScripts $name) "# stub $name"
        (Get-Item -LiteralPath (Join-Path $tempScripts $name)).LastWriteTime = $oldToolTime
    }
    Write-Text (Join-Path $tempScripts 'Resolve-PythonLauncher.ps1') '# python launcher fix'
    (Get-Item -LiteralPath (Join-Path $tempScripts 'Resolve-PythonLauncher.ps1')).LastWriteTime = $oldToolTime
    Write-Text (Join-Path $tempScripts 'Prepare-SliceEvidenceContracts.ps1') '# pre-slice contract fix'
    (Get-Item -LiteralPath (Join-Path $tempScripts 'Prepare-SliceEvidenceContracts.ps1')).LastWriteTime = $newToolTime
    (Get-Item -LiteralPath $tempStopline).LastWriteTime = $oldToolTime

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v534-stopline'
    $decisionTime = (Get-Date).AddHours(-2)
    New-NoProgressRoot -Root "$replayBase-r01" -RootTime (Get-Date).AddMinutes(-30) -DecisionTime $decisionTime
    New-NoProgressRoot -Root "$replayBase-r02" -RootTime (Get-Date).AddMinutes(-20) -DecisionTime $decisionTime
    New-NoProgressRoot -Root "$replayBase-r03" -RootTime (Get-Date).AddMinutes(-10) -DecisionTime $decisionTime

    & powershell -NoProfile -ExecutionPolicy Bypass -File $tempStopline `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -AllowRecentToolingChange `
        -Quiet | Out-Null

    Assert-True 'stopline allows after gate-wrapper tooling change' ($LASTEXITCODE -eq 0)
    $analysis = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline newest tooling change is slice evidence contract preparer' ((Split-Path -Leaf ([string]$analysis.newest_tooling_change)) -eq 'Prepare-SliceEvidenceContracts.ps1') ($analysis | ConvertTo-Json -Depth 12)
    Assert-True 'stopline decision records allow after tooling change' ([string]$analysis.decision -eq 'ALLOW_AFTER_TOOLING_CHANGE') ($analysis | ConvertTo-Json -Depth 12)

    Write-Host 'v534 stopline gate-wrapper tooling regression passed.'
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
