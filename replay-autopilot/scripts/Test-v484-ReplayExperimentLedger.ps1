param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function New-ReplayRootFixture {
    param(
        [string]$Root,
        [datetime]$UpdatedAt
    )
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    (Get-Item -LiteralPath $Root).LastWriteTime = $UpdatedAt
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$ledgerScript = Join-Path $scriptRoot 'Write-ReplayExperimentLedger.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-experiment-ledger-v484-" + [guid]::NewGuid().ToString('N'))

try {
    $evidenceRoot = Join-Path $tempRoot 'feature'
    $base = Join-Path $evidenceRoot 'claim-codex-replay-ledger-demo'
    $control = Join-Path $evidenceRoot '_control'
    New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

    $r01 = "$base-r01"
    New-ReplayRootFixture -Root $r01 -UpdatedAt ([datetime]'2026-01-01T00:01:00')
    @'
# ROUND_RESULT

- final_status: PARTIAL_PROGRESS
- verification_capped_coverage: 10
- oracle_adjusted_coverage: 20
'@ | Set-Content -LiteralPath (Join-Path $r01 'ROUND_RESULT.md') -Encoding UTF8
    [ordered]@{
        replay_root = $r01
        events = @(
            [ordered]@{
                stage = 'initial_after_start_replay_round'
                head = 'abcdef1234567890abcdef'
                captured_at = '2026-01-01T00:01:00'
            }
        )
        initial_after_start_replay_round = 'abcdef1234567890abcdef'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $r01 'WORKTREE_HEAD_AUDIT.json') -Encoding UTF8

    $r02 = "$base-r02"
    New-ReplayRootFixture -Root $r02 -UpdatedAt ([datetime]'2026-01-01T00:02:00')
    [ordered]@{
        stage = 'Plan'
        verification_status = 'FAIL'
        issues = @(
            'policy_rebuild_plan_missing:ExampleDataAssemblyHelper.RequestBuildFunction',
            'policy_rebuild_plan_invalid:fixed_db_caseid'
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $r02 'PLAN_CONTRACT_VERIFY.json') -Encoding UTF8

    $r03 = "$base-r03"
    New-ReplayRootFixture -Root $r03 -UpdatedAt ([datetime]'2026-01-01T00:03:00')
    @'
# ROUND_RESULT

- final_status: REGRESSION
- verification_capped_coverage: 5
- oracle_adjusted_coverage: 15
'@ | Set-Content -LiteralPath (Join-Path $r03 'ROUND_RESULT.md') -Encoding UTF8

    $r04 = "$base-r04"
    New-ReplayRootFixture -Root $r04 -UpdatedAt ([datetime]'2026-01-01T00:04:00')
    @'
# ROUND_RESULT

- final_status: PARTIAL_PROGRESS
- verification_capped_coverage: 15
- oracle_adjusted_coverage: 25
'@ | Set-Content -LiteralPath (Join-Path $r04 'ROUND_RESULT.md') -Encoding UTF8
    @'
{
  "history": [
    "PLAN_SCHEMA_FAILFAST.json:test_infrastructure_issue:policy_rebuild_test_module_must_be_claim_server",
    "PLAN_CONTRACT_VERIFY.json:issue:policy_rebuild_plan_invalid:test_harness_claim_core"
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $r04 'RUN_CONTROL_SUMMARY.json') -Encoding UTF8

    $r05 = "$base-r05"
    New-ReplayRootFixture -Root $r05 -UpdatedAt ([datetime]'2026-01-01T00:05:00')
    @'
# AUTOPILOT_BLOCKER

Executor timed out after 120 minutes.
'@ | Set-Content -LiteralPath (Join-Path $r05 'AUTOPILOT_BLOCKER.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $ledgerScript -ReplayRootBase $base -OutputRoot $control -Quiet
    Assert-True 'ledger_script_exit_success' ($LASTEXITCODE -eq 0)

    $jsonPath = Join-Path $control 'REPLAY_EXPERIMENT_LEDGER.json'
    $tsvPath = Join-Path $control 'REPLAY_EXPERIMENT_LEDGER.tsv'
    $mdPath = Join-Path $control 'REPLAY_EXPERIMENT_LEDGER.md'
    Assert-True 'ledger_json_written' (Test-Path -LiteralPath $jsonPath)
    Assert-True 'ledger_tsv_written' (Test-Path -LiteralPath $tsvPath)
    Assert-True 'ledger_markdown_written' (Test-Path -LiteralPath $mdPath)

    $ledger = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'ledger_schema' ([string]$ledger.schema -eq 'replay_experiment_ledger.v1')
    Assert-True 'ledger_has_five_records' (@($ledger.records).Count -eq 5)

    $records = @($ledger.records)
    Assert-True 'r01_baseline_keep' ($records[0].round -eq 1 -and $records[0].status -eq 'keep' -and $records[0].status_reason -eq 'verification_cap_improved')
    Assert-True 'r01_head_from_audit' ($records[0].worktree_head -eq 'abcdef123456')
    Assert-True 'r02_plan_contract_discard' ($records[1].round -eq 2 -and $records[1].status -eq 'discard' -and $records[1].stage -eq 'PlanContract')
    Assert-True 'r02_policy_fingerprint_present' (@($records[1].fingerprints) -contains 'plan_format_drift')
    Assert-True 'r03_metric_regression_discard' ($records[2].round -eq 3 -and $records[2].status -eq 'discard' -and $records[2].status_reason -eq 'verification_cap_not_improved')
    Assert-True 'r04_metric_improvement_keep' ($records[3].round -eq 4 -and $records[3].status -eq 'keep' -and $records[3].verification_capped_coverage -eq 15)
    Assert-True 'r04_ignores_stale_run_control_history' (-not (@($records[3].fingerprints) -contains 'policy_rebuild_claim_core_harness'))
    Assert-True 'r05_timeout_crash' ($records[4].round -eq 5 -and $records[4].status -eq 'crash' -and (@($records[4].fingerprints) -contains 'executor_timeout'))

    $tsv = Get-Content -LiteralPath $tsvPath -Encoding UTF8
    Assert-True 'ledger_tsv_header' ($tsv[0] -eq 'round	updated_at	status	status_reason	stage	verification_capped_coverage	oracle_adjusted_coverage	fingerprints	worktree_head	description	replay_root')
    Assert-True 'ledger_tsv_has_rows' ($tsv.Count -eq 6)

    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $ledgerScriptText = Get-Content -LiteralPath $ledgerScript -Raw -Encoding UTF8
    Assert-True 'ledger_does_not_shell_git_for_historical_worktrees' (-not $ledgerScriptText.Contains('git -C'))
    Assert-True 'runner_invokes_experiment_ledger_safe' ($runLoopText.Contains('Invoke-ReplayExperimentLedgerSafe -ReplayRootBase $replayRootBase'))
    Assert-True 'runner_uses_experiment_ledger_script' ($runLoopText.Contains('Write-ReplayExperimentLedger.ps1'))

    Write-Host 'PASS: v484 replay experiment ledger'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
