param(
    [switch]$KeepTemp
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

function Write-ReplayFixture {
    param(
        [string]$Root,
        [string]$Decision,
        [int]$Cap,
        [int]$Oracle,
        [string[]]$Fingerprints,
        [string]$Executor = 'claude',
        [string]$Policy = 'passed',
        [int]$AgeMinutes = 0
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $gapLines = New-Object System.Collections.Generic.List[string]
    foreach ($fp in $Fingerprints) {
        $gapLines.Add("- ${fp}: 1") | Out-Null
    }

    @"
# Replay Autopilot Summary

- Replay root: $Root
- phase0_status: PROCEED
- blind_self_assessed_coverage: $Oracle
- verification_capped_coverage: $Cap
- oracle_adjusted_coverage: $Oracle
- final_status: PARTIAL

## Gap Flags

$($gapLines -join "`n")
"@ | Set-Content -LiteralPath (Join-Path $Root 'AUTOPILOT_SUMMARY.md') -Encoding UTF8

    @"
# Autopilot Decision

- decision: $Decision
- verification_capped_coverage: $Cap
- oracle_adjusted_coverage: $Oracle
"@ | Set-Content -LiteralPath (Join-Path $Root 'AUTOPILOT_DECISION.md') -Encoding UTF8

    [ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = $Executor
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = $Policy
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'EXECUTOR_AUDIT.json') -Encoding UTF8

    if ($Decision -match 'STOP|FAIL') {
        '# Autopilot Blocker' | Set-Content -LiteralPath (Join-Path $Root 'AUTOPILOT_BLOCKER.md') -Encoding UTF8
    }

    (Get-Item -LiteralPath $Root).LastWriteTime = (Get-Date).AddMinutes(-1 * $AgeMinutes)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-control-v360-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$featureRoot = Join-Path $evidenceRoot 'sample-feature'
$outputRoot = Join-Path $evidenceRoot '_control'

try {
    New-Item -ItemType Directory -Force -Path $featureRoot | Out-Null
    Write-ReplayFixture -Root (Join-Path $featureRoot 'claim-codex-replay-v360-autopilot-test-r01') -Decision 'CONTINUE_IMPROVED' -Cap 20 -Oracle 20 -Fingerprints @('wrong_test_surface') -AgeMinutes 30
    Write-ReplayFixture -Root (Join-Path $featureRoot 'claim-codex-replay-v360-autopilot-test-r02') -Decision 'CONTINUE_NO_IMPROVEMENT_1' -Cap 15 -Oracle 21 -Fingerprints @('wrong_test_surface', 'side_effect_ledger_gap') -AgeMinutes 20
    $latestRoot = Join-Path $featureRoot 'claim-codex-replay-v360-autopilot-test-r03'
    Write-ReplayFixture -Root $latestRoot -Decision 'CONTINUE_NO_IMPROVEMENT_2' -Cap 10 -Oracle 21 -Fingerprints @('wrong_test_surface', 'side_effect_ledger_gap') -AgeMinutes 5

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-ControlPlaneSummary.ps1') `
        -EvidenceRoot $evidenceRoot `
        -OutputRoot $outputRoot `
        -Lookback 3 `
        -TargetCoverage 90 `
        -MinOracleImprovement 8 `
        -LowCapThreshold 45 `
        -RepeatBlockerThreshold 2 `
        -RequireExecutor claude `
        -Quiet
    if ($LASTEXITCODE -ne 0) { throw "Write-ControlPlaneSummary failed: $LASTEXITCODE" }

    $latestJson = Join-Path $outputRoot 'RUN_CONTROL_LATEST.json'
    $brief = Join-Path $outputRoot 'MORNING_BRIEF.md'
    $registryJson = Join-Path $outputRoot 'BLOCKER_REGISTRY.json'
    $summaryJson = Join-Path $latestRoot 'RUN_CONTROL_SUMMARY.json'
    $summaryMd = Join-Path $latestRoot 'RUN_CONTROL_SUMMARY.md'
    $stagnationJson = Join-Path $latestRoot 'STAGNATION_DECISION.json'
    $fingerprintsJson = Join-Path $latestRoot 'BLOCKER_FINGERPRINTS.json'

    Assert-True -Name 'writes_global_latest_json' -Condition (Test-Path -LiteralPath $latestJson)
    Assert-True -Name 'writes_morning_brief' -Condition (Test-Path -LiteralPath $brief)
    Assert-True -Name 'writes_blocker_registry' -Condition (Test-Path -LiteralPath $registryJson)
    Assert-True -Name 'writes_per_round_summary_json' -Condition (Test-Path -LiteralPath $summaryJson)
    Assert-True -Name 'writes_per_round_summary_md' -Condition (Test-Path -LiteralPath $summaryMd)
    Assert-True -Name 'writes_stagnation_decision' -Condition (Test-Path -LiteralPath $stagnationJson)
    Assert-True -Name 'writes_fingerprints_json' -Condition (Test-Path -LiteralPath $fingerprintsJson)

    $latest = Get-Content -LiteralPath $latestJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'repeated_blocker_triggers_evolve' -Condition ($latest.control_decision.decision_kind -eq 'EVOLVE')
    Assert-True -Name 'wrong_test_surface_repeated' -Condition (@($latest.control_decision.repeated_blockers) -contains 'wrong_test_surface')

    $registry = Get-Content -LiteralPath $registryJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'registry_counts_wrong_test_surface' -Condition ([int]$registry.blockers.wrong_test_surface.count -ge 3)

    $briefText = Get-Content -LiteralPath $brief -Raw -Encoding UTF8
    Assert-True -Name 'brief_contains_control_decision' -Condition ($briefText -match 'control_decision:\s*EVOLVE')

    $codexRoot = Join-Path $featureRoot 'claim-codex-replay-v360-autopilot-test-r04'
    Write-ReplayFixture -Root $codexRoot -Decision 'CONTINUE_IMPROVED' -Cap 60 -Oracle 60 -Fingerprints @() -Executor 'codex' -Policy 'blocked' -AgeMinutes 0
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Write-ControlPlaneSummary.ps1') `
        -EvidenceRoot $evidenceRoot `
        -OutputRoot $outputRoot `
        -Lookback 4 `
        -RequireExecutor claude `
        -Quiet
    if ($LASTEXITCODE -ne 0) { throw "Write-ControlPlaneSummary codex audit failed: $LASTEXITCODE" }
    $latest2 = Get-Content -LiteralPath $latestJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'codex_primary_triggers_stopline' -Condition ($latest2.control_decision.decision_kind -eq 'STOPLINE')

    Write-Host 'PASS: v360 control plane summary'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
