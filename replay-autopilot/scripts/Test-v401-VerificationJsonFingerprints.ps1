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

function New-ReplayRoot {
    param(
        [string]$Root,
        [int]$AgeMinutes,
        [string[]]$Phase0Issues = @(),
        [string[]]$CarrierIssues = @()
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    @"
# Replay Autopilot Summary

- phase0_status: BLOCKED
- verification_capped_coverage: 0
- oracle_adjusted_coverage: 0
- final_status: BLOCKED
"@ | Set-Content -LiteralPath (Join-Path $Root 'AUTOPILOT_SUMMARY.md') -Encoding UTF8

    @"
# Autopilot Decision

- decision: STOP_BLOCKED
"@ | Set-Content -LiteralPath (Join-Path $Root 'AUTOPILOT_DECISION.md') -Encoding UTF8

    [ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'EXECUTOR_AUDIT.json') -Encoding UTF8

    if ($Phase0Issues.Count -gt 0) {
        Write-Json -Path (Join-Path $Root 'PHASE0_CONTRACT_VERIFY.json') -Value ([ordered]@{
            stage = 'Phase0'
            verification_status = 'FAIL'
            issues = @($Phase0Issues)
            warnings = @()
        })
    }

    if ($CarrierIssues.Count -gt 0) {
        Write-Json -Path (Join-Path $Root 'PHASE0_CARRIER_EVIDENCE_VERIFY.json') -Value ([ordered]@{
            stage = 'Phase0'
            verification_status = 'FAIL'
            issues = @($CarrierIssues)
            warnings = @('phase0 carrier evidence missing')
        })
    }

    (Get-Item -LiteralPath $Root).LastWriteTime = (Get-Date).AddMinutes(-1 * $AgeMinutes)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v401-fingerprints-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$featureRoot = Join-Path $evidenceRoot 'sample-feature'
$outputRoot = Join-Path $evidenceRoot '_control'

try {
    New-Item -ItemType Directory -Force -Path $featureRoot | Out-Null

    New-ReplayRoot `
        -Root (Join-Path $featureRoot 'claim-codex-replay-v401-test-r01') `
        -AgeMinutes 30 `
        -Phase0Issues @('phase0_manual_oracle_wait')

    New-ReplayRoot `
        -Root (Join-Path $featureRoot 'claim-codex-replay-v401-test-r02') `
        -AgeMinutes 20 `
        -CarrierIssues @('phase0_carrier_search_commands_missing')

    $latestRoot = Join-Path $featureRoot 'claim-codex-replay-v401-test-r03'
    New-ReplayRoot `
        -Root $latestRoot `
        -AgeMinutes 5 `
        -Phase0Issues @('phase0_manual_oracle_wait') `
        -CarrierIssues @('phase0_carrier_search_commands_missing')

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
    $fingerprintsJson = Join-Path $latestRoot 'BLOCKER_FINGERPRINTS.json'
    $summaryMd = Join-Path $latestRoot 'RUN_CONTROL_SUMMARY.md'

    $latest = Get-Content -LiteralPath $latestJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $fingerprints = @($latest.latest.fingerprints)
    $verificationIssues = @($latest.latest.verification_issues)
    $repeated = @($latest.control_decision.repeated_blockers)

    Assert-True -Name 'schema_issue_maps_to_schema_fingerprint' -Condition ($fingerprints -contains 'schema_contract_discovery_gap')
    Assert-True -Name 'carrier_issue_maps_to_carrier_fingerprint' -Condition ($fingerprints -contains 'phase0_carrier_evidence_gap')
    Assert-True -Name 'carrier_issue_repeats_across_roots' -Condition ($repeated -contains 'phase0_carrier_evidence_gap')
    Assert-True -Name 'verification_issue_ledger_includes_phase0_issue' -Condition ($verificationIssues -contains 'phase0_manual_oracle_wait')
    Assert-True -Name 'verification_issue_ledger_includes_carrier_issue' -Condition ($verificationIssues -contains 'phase0_carrier_search_commands_missing')

    $fingerprintObject = Get-Content -LiteralPath $fingerprintsJson -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'per_round_fingerprints_json_contains_carrier_gap' -Condition (@($fingerprintObject.fingerprints) -contains 'phase0_carrier_evidence_gap')

    $summaryText = Get-Content -LiteralPath $summaryMd -Raw -Encoding UTF8
    Assert-True -Name 'summary_md_lists_verification_issues' -Condition ($summaryText -match 'PHASE0_CARRIER_EVIDENCE_VERIFY\.json:issue:phase0_carrier_search_commands_missing')

    Write-Host 'PASS: v401 verification JSON fingerprints'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
