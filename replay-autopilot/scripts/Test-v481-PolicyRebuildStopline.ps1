param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Json {
    param([string]$Path, [object]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function New-PolicyRebuildRoot {
    param(
        [string]$Root,
        [int]$AgeMinutes = 0
    )

    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Encoding UTF8
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-core\pom.xml') -Encoding UTF8

    Write-Json (Join-Path $Root 'EXECUTOR_AUDIT.json') ([ordered]@{
        schema = 'replay_executor_audit.v1'
        executor = 'claude'
        require_executor = 'claude'
        allow_codex_executor = $false
        policy = 'passed'
    })

    Write-Json (Join-Path $Root 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 384
        expected_test_class = 'AiApplyClaimApiTaskProcessorTest'
        expected_test_method = 'testRebuildTaskData_MissingPolicyNumAndInsureNum'
        side_effects = @(
            [ordered]@{
                table = 't_ai_claim_api_task'
                operation = 'UPDATE'
                field = 'task_data_json'
                value = 'non-null policyNum/insureNum'
            }
        )
        expected_assertions = @('assert policyNum', 'assert insureNum')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-core'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-core -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    Write-Json (Join-Path $Root 'PLAN_SCHEMA_FAILFAST.json') ([ordered]@{
        stage = 'PlanSchemaFailFast'
        status = 'FAIL'
        required = $true
        can_proceed = $false
        checks = [ordered]@{
            plan_status = 'PROCEED'
            test_infrastructure_issues = @(
                'test_module_missing_src_test:claim-core',
                'policy_rebuild_test_module_must_be_claim_server',
                'policy_rebuild_expected_test_class_must_use_claim_server_harness',
                'policy_rebuild_compile_dry_run_must_use_claim_server_am_test_compile'
            )
            side_effect_issues = @()
        }
        issues = @('Test infrastructure check failed')
    })

    Write-Json (Join-Path $Root 'PLAN_VERDICT.json') ([ordered]@{
        stage = 'Plan'
        plan_status = 'BLOCKED'
        decision = 'STOP_BLOCKED'
        reason = 'PLAN_RESULT.json machine contract validation failed.'
    })

    Write-Utf8 (Join-Path $Root 'AUTOPILOT_SUMMARY.md') @"
# Replay Autopilot Summary

- phase0_status: PROCEED
- plan_status: BLOCKED
- stop_stage: Plan
- verification_capped_coverage: 0
- final_status: BLOCKED
"@
    Write-Utf8 (Join-Path $Root 'AUTOPILOT_DECISION.md') @"
# Autopilot Decision

- decision: STOP_BLOCKED
- verification_capped_coverage: 0
"@

    (Get-Item -LiteralPath $Root).LastWriteTime = (Get-Date).AddMinutes(-1 * $AgeMinutes)
    return $worktree
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$controlSummary = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("policy-rebuild-stopline-v481-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v481-policy'

try {
    New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

    $runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
    $stoplineText = Get-Content -LiteralPath $stoplineGate -Raw -Encoding UTF8
    $functionBlock = [regex]::Match(
        $runLoopText,
        '(?s)function Resolve-ReplayEvidencePath.+?(?=function Repair-Phase0ManualOracleWaitText)'
    ).Value
    Assert-True 'runner_plan_evidence_functions_extractable' (-not [string]::IsNullOrWhiteSpace($functionBlock))
    Assert-True 'stopline_policy_fingerprint_avoids_backtracking_lookahead' (-not $stoplineText.Contains('(?=.*'))
    Invoke-Expression $functionBlock

    $badRoot = "$replayBase-r01"
    $badWorktree = New-PolicyRebuildRoot -Root $badRoot -AgeMinutes 30
    $badEvidence = Join-Path $badRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json'
    Ensure-PlanTestCompileEvidence -ReplayRoot $badRoot -Worktree $badWorktree -PlanResultJsonPath (Join-Path $badRoot 'PLAN_RESULT.json')
    Assert-True 'runner_skips_maven_for_policy_rebuild_claim_core_harness' (-not (Test-Path -LiteralPath $badEvidence))
    $policyGatePath = Join-Path $badRoot 'PLAN_TEST_COMPILE_EVIDENCE_POLICY_GATE.json'
    Assert-True 'runner_writes_policy_gate_artifact_before_schema' (Test-Path -LiteralPath $policyGatePath)
    $policyGate = Get-Content -LiteralPath $policyGatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'policy_gate_uses_precise_fingerprint' ($policyGate.fingerprint -eq 'policy_rebuild_claim_core_harness')
    Assert-True 'policy_gate_skips_maven' ($policyGate.decision -eq 'SKIP_MAVEN')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate -ReplayRoot $badRoot -PlanResultPath (Join-Path $badRoot 'PLAN_RESULT.json') -Worktree $badWorktree | Out-Null
    Assert-True 'schema_rejects_r17_shaped_policy_rebuild_plan' ($LASTEXITCODE -ne 0)
    $schema = Get-Content -LiteralPath (Join-Path $badRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_reports_claim_server_harness_required' ((@($schema.checks.test_infrastructure_issues) -join ' ') -match 'policy_rebuild_test_module_must_be_claim_server')

    New-PolicyRebuildRoot -Root "$replayBase-r02" -AgeMinutes 20 | Out-Null
    New-PolicyRebuildRoot -Root "$replayBase-r03" -AgeMinutes 5 | Out-Null

    & powershell -NoProfile -ExecutionPolicy Bypass -File $controlSummary `
        -EvidenceRoot $evidenceRoot `
        -ReplayRoot "$replayBase-r03" `
        -Lookback 3 `
        -RepeatBlockerThreshold 1 `
        -RequireExecutor claude `
        -Quiet
    Assert-True 'control_summary_succeeds_for_policy_rebuild_fixture' ($LASTEXITCODE -eq 0)
    $fingerprints = Get-Content -LiteralPath (Join-Path "$replayBase-r03" 'BLOCKER_FINGERPRINTS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'control_summary_emits_policy_rebuild_fingerprint' (@($fingerprints.fingerprints) -contains 'policy_rebuild_claim_core_harness')
    $audit = Get-Content -LiteralPath (Join-Path "$replayBase-r03" 'FAILURE_AUDIT_PACK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'failure_audit_marks_policy_rebuild_as_must_fix' (@($audit.must_fix_before_next_replay) -contains 'policy_rebuild_claim_core_harness')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $stoplineGate `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -Quiet | Out-Null
    Assert-True 'stopline_gate_returns_94_after_three_no_progress_rounds' ($LASTEXITCODE -eq 94)
    $stopline = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline_decision_is_repeated_no_progress' ($stopline.decision -eq 'STOPLINE_REPEATED_NO_PROGRESS')
    Assert-True 'stopline_repeated_blocker_is_policy_rebuild' (@($stopline.repeated_blockers) -contains 'policy_rebuild_claim_core_harness')

    foreach ($root in @("$replayBase-r01", "$replayBase-r02", "$replayBase-r03")) {
        foreach ($artifact in @(
                'ROUND_RESULT.md',
                'PLAN_VERDICT.json',
                'PLAN_SCHEMA_FAILFAST.json',
                'PLAN_CONTRACT_VERIFY.json',
                'AUTOPILOT_SUMMARY.md',
                'AUTOPILOT_DECISION.md',
                'AUTOPILOT_BLOCKER.md',
                'BLOCKER_FINGERPRINTS.json',
                'FAILURE_AUDIT_PACK.json'
            )) {
            $path = Join-Path $root $artifact
            if (Test-Path -LiteralPath $path) {
                (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddHours(-2)
            }
        }
        (Get-Item -LiteralPath $root).LastWriteTime = (Get-Date).AddMinutes(10)
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $stoplineGate `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -AllowRecentToolingChange `
        -Quiet | Out-Null
    Assert-True 'stopline_allow_recent_tooling_uses_decision_timestamp_not_root_timestamp' ($LASTEXITCODE -eq 0)
    $stoplineAllow = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline_allow_recent_tooling_decision' ($stoplineAllow.decision -eq 'ALLOW_AFTER_TOOLING_CHANGE')
    Assert-True 'stopline_records_decision_updated_timestamp' ($null -ne @($stoplineAllow.records)[0].decision_updated_text)

    Write-Host 'PASS: v481 policy rebuild stopline'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
