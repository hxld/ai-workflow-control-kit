param([switch]$KeepTemp)

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

function Write-Json {
    param(
        [string]$Path,
        [object]$Value
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$summaryScript = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v430-phase0-evolution-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$featureRoot = Join-Path $evidenceRoot 'sample-feature'
$outputRoot = Join-Path $evidenceRoot '_control'
$replayRoot = Join-Path $featureRoot 'claim-codex-replay-v430-test-r01'

try {
    $runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
    $parseErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($runner, [ref]$parseErrors)
    Assert-True -Name 'runner_parse_ok' -Condition ($parseErrors.Count -eq 0)
    Assert-True -Name 'phase0_repair_failure_writes_evolution_artifacts' -Condition (
        $runner.Contains('Phase 0 contract verification failed after repair') -and
        $runner.Contains("Write-PlanEarlyStopEvolutionArtifacts") -and
        $runner.Contains("-StopStage 'Phase0'")
    )
    Assert-True -Name 'phase0_repair_failure_refreshes_knowledge_version' -Condition (
        $runner.Contains('Knowledge version refreshed for next round after phase0 repair-failure evolution')
    )

    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    @"
# Replay Autopilot Summary

- phase0_status: PROCEED
- verification_capped_coverage: 0
- oracle_adjusted_coverage:
- final_status: BLOCKED
"@ | Set-Content -LiteralPath (Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md') -Encoding UTF8

    @"
# Autopilot Decision

- decision: STOP_BLOCKED
"@ | Set-Content -LiteralPath (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') -Encoding UTF8

    @"
# Autopilot Blocker

Phase 0 contract verification failed after repair.
"@ | Set-Content -LiteralPath (Join-Path $replayRoot 'AUTOPILOT_BLOCKER.md') -Encoding UTF8

    [ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $replayRoot 'EXECUTOR_AUDIT.json') -Encoding UTF8

    Write-Json -Path (Join-Path $replayRoot 'PHASE0_CONTRACT_VERIFY.json') -Value ([ordered]@{
        stage = 'Phase0'
        verification_status = 'FAIL'
        issues = @('phase0_oracle_inferred_selected_entry')
        warnings = @()
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File $summaryScript `
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

    $latest = Get-Content -LiteralPath (Join-Path $outputRoot 'RUN_CONTROL_LATEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $fingerprints = @($latest.latest.fingerprints)
    $verificationIssues = @($latest.latest.verification_issues)

    Assert-True -Name 'phase0_oracle_issue_maps_to_oracle_contamination' -Condition ($fingerprints -contains 'phase0_oracle_contamination')
    Assert-True -Name 'phase0_oracle_issue_not_executor_crash' -Condition (-not ($fingerprints -contains 'executor_resource_or_crash'))
    Assert-True -Name 'phase0_oracle_issue_drives_evolve_not_upgrade' -Condition ($latest.control_decision.decision_kind -eq 'EVOLVE')
    Assert-True -Name 'verification_ledger_includes_phase0_oracle_issue' -Condition ($verificationIssues -contains 'phase0_oracle_inferred_selected_entry')

    Write-Host 'PASS: v430 Phase0 repair-failure evolution'
    [ordered]@{ status = 'PASS'; assertions = 7 } | ConvertTo-Json -Depth 4
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
