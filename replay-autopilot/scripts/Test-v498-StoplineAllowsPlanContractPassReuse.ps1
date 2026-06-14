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

function New-PlanRoot {
    param(
        [string]$Root,
        [string]$Status,
        [datetime]$RootTime
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    if ($Status -eq 'PASS') {
        Write-Text (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') '{"verification_status":"PASS","issues":[]}'
        Write-Text (Join-Path $Root 'PLAN_RESULT.md') 'plan_status: PROCEED'
    } else {
        Write-Text (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') '{"verification_status":"FAIL","issues":["policy_rebuild_plan_invalid:test_harness_claim_core","plan_contract_verification_failed"]}'
        Write-Text (Join-Path $Root 'AUTOPILOT_SUMMARY.md') 'final_status: BLOCKED; verification_capped_coverage: 0; side effect gap'
    }

    foreach ($file in Get-ChildItem -LiteralPath $Root -File) {
        $file.LastWriteTime = $RootTime
    }
    (Get-Item -LiteralPath $Root).LastWriteTime = $RootTime
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stopline-planready-v498-" + [guid]::NewGuid().ToString('N'))

try {
    $stoplineText = Get-Content -LiteralPath $stoplineGate -Raw -Encoding UTF8
    Assert-True 'stopline_has_planready_stage' ($stoplineText.Contains("return 'PlanReady'"))
    Assert-True 'stopline_planready_is_not_no_progress' ($stoplineText.Contains('$Stage -eq ''PlanReady'''))

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v498-planready'
    New-PlanRoot -Root "$replayBase-r28" -Status 'FAIL' -RootTime (Get-Date).AddMinutes(-30)
    New-PlanRoot -Root "$replayBase-r29" -Status 'FAIL' -RootTime (Get-Date).AddMinutes(-20)
    New-PlanRoot -Root "$replayBase-r30" -Status 'PASS' -RootTime (Get-Date).AddMinutes(-10)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $stoplineGate `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -Quiet | Out-Null

    Assert-True 'stopline_allows_plan_contract_pass_root' ($LASTEXITCODE -eq 0)
    $analysis = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline_decision_pass_for_planready_latest' ($analysis.decision -eq 'PASS')
    Assert-True 'latest_planready_record_not_no_progress' (-not [bool](@($analysis.records)[0].no_progress))

    Write-Host 'PASS: v498 stopline allows PlanContract PASS reuse'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
