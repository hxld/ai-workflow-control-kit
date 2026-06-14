param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ''
    )
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) {
            throw "FAIL: $Name"
        }
        throw "FAIL: $Name - $Details"
    }
    Write-Host "PASS: $Name"
}

function Write-Json {
    param(
        [string]$Path,
        [object]$Value
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Text {
    param(
        [string]$Path,
        [string]$Value
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

function New-ReadOnlyPlanRoot {
    param([string]$Root)

    $worktree = Join-Path $Root 'worktree'
    $testDir = Join-Path $worktree 'claim-server\src\test\java\com\huize\claim\test'
    $carrierDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task'
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    New-Item -ItemType Directory -Force -Path $carrierDir | Out-Null
    Write-Text (Join-Path $worktree 'pom.xml') '<project />'
    Write-Text (Join-Path $worktree 'claim-core\pom.xml') '<project />'
    Write-Text (Join-Path $worktree 'claim-server\pom.xml') '<project />'
    Write-Text (Join-Path $testDir 'ExistingHarnessTest.java') 'class ExistingHarnessTest {}'
    Write-Text (Join-Path $carrierDir 'AiApplyClaimApiTaskProcessor.java') 'public class AiApplyClaimApiTaskProcessor {}'

    $dryRun = [ordered]@{
        exit_code = 0
        command = "mvn -s D:\maven\settings\settings.xml -f $worktree\pom.xml -pl claim-server -am test-compile"
        stdout = 'BUILD SUCCESS'
    }
    Write-Json (Join-Path $Root 'TEST_INFRASTRUCTURE_DRY_RUN.json') $dryRun

    Write-Json (Join-Path $Root 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        schema = 'feature_classification.v1'
        classification = 'narrow_backend_read_only_fix'
        base_classification = 'narrow_backend_fix'
        read_only = $true
        backend_only = $true
        verifier_adjustments = [ordered]@{
            stateful_side_effect_required = $false
            red_phase_required = $false
            horizontal_minimum = 2
            non_applicable_families = @('stateful_side_effect')
        }
    })

    Write-Json (Join-Path $Root 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
        target_carrier_line_number = 385
        expected_test_class = 'AiApplyClaimApiTaskProcessorRebuildTest'
        expected_test_method = 'testRebuildTaskData_preservesPolicyNumAndInsureNum'
        side_effects = @(
            [ordered]@{ memory = 'request.policyNum'; operation = 'set'; value = 'from buildContext.getPolicyNum()' },
            [ordered]@{ memory = 'request.insureNum'; operation = 'set'; value = 'from buildContext.getInsureNum()' },
            [ordered]@{ memory = 'taskData.policyNum'; operation = 'set'; value = 'from request.getPolicyNum()' },
            [ordered]@{ memory = 'taskData.insureNum'; operation = 'set'; value = 'from request.getInsureNum()' }
        )
        expected_assertions = @(
            'assertEquals("P2024001", taskData.getPolicyNum())',
            'assertEquals("I2024001", taskData.getInsureNum())'
        )
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = "mvn -s D:\maven\settings\settings.xml -f $worktree\pom.xml -pl claim-server -am test-compile"
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    })

    Write-Text (Join-Path $Root 'TEST_CHARTER.md') @'
# Test Charter

- test_surface: claim-server unit harness invoking rebuildTaskData through the selected TaskProcessor carrier
- entry_point: AiApplyClaimApiTaskProcessor.rebuildTaskData
- test_class: AiApplyClaimApiTaskProcessorRebuildTest
- test_method: testRebuildTaskData_preservesPolicyNumAndInsureNum
- test_scenario: read-only memory propagation from RequestBuildContext to request/taskData
'@

    Write-Text (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
# First Slice Proof Plan

- highest_weight_open_gate: core_entry
- selected_carrier: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
- target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
- target_carrier_line_number: 385
- expected_test_class: AiApplyClaimApiTaskProcessorRebuildTest
- expected_test_method: testRebuildTaskData_preservesPolicyNumAndInsureNum
- expected_assertions: ["assert policyNum propagated","assert insureNum propagated","assert taskData not null"]
- expected_side_effects: [{"memory":"request.policyNum","operation":"set","value":"from buildContext.getPolicyNum()"}]
- minimum_side_effect_or_blocker: read_only_memory_propagation
'@

    return $worktree
}

function New-ZeroCapRound {
    param(
        [string]$Root,
        [int]$AgeMinutes
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Text (Join-Path $Root 'ROUND_RESULT.md') @"
# Round Result

- final_status: BLOCKED
- verification_capped_coverage: 0
- oracle_adjusted_coverage: 0
- gap_flags: low_verification_cap
"@
    Write-Text (Join-Path $Root 'FINAL_REPLAY_REPORT.md') @"
# Final Replay Report

| coverage dimension | value |
| --- | ---: |
| verification_capped_coverage | 0 |
| oracle_adjusted_coverage | 0 |

Decision: STOP_AND_EVOLVE
"@
    Write-Json (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') ([ordered]@{
        verification_status = 'PASS'
        oracle_overlap_percent = 100
    })
    Write-Json (Join-Path $Root 'SLICE_VERIFY_01.json') ([ordered]@{
        verification_status = 'FAIL'
        verification_capped_coverage = 0
        adjusted_coverage_delta = 0
        authorization_blockers = @('low_verification_cap')
        gap_flags = @('low_verification_cap')
    })
    Write-Text (Join-Path $Root 'AUTOPILOT_DECISION.md') @"
# Autopilot Decision

- decision: STOP_BLOCKED
- verification_capped_coverage: 0
"@
    (Get-Item -LiteralPath $Root).LastWriteTime = (Get-Date).AddMinutes(-1 * $AgeMinutes)
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$schemaGate = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$preExecutionGate = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$stoplineGate = Join-Path $scriptRoot 'Invoke-ReplayStoplineGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v521-" + [guid]::NewGuid().ToString('N'))

try {
    $planRoot = Join-Path $tempRoot 'plan'
    $worktree = New-ReadOnlyPlanRoot -Root $planRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaGate `
        -ReplayRoot $planRoot `
        -PlanResultPath (Join-Path $planRoot 'PLAN_RESULT.json') `
        -Worktree $worktree | Out-Null
    Assert-True 'read_only_plan_schema_passes' ($LASTEXITCODE -eq 0)
    $schema = Get-Content -LiteralPath (Join-Path $planRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_records_feature_classification' ([string]$schema.checks.feature_classification -eq 'narrow_backend_read_only_fix') ($schema | ConvertTo-Json -Depth 12)
    Assert-True 'schema_uses_read_only_side_effect_mode' ([string]$schema.checks.side_effect_schema_mode -eq 'read_only_memory_or_not_required') ($schema | ConvertTo-Json -Depth 12)
    Assert-True 'schema_no_side_effect_issues' (@($schema.checks.side_effect_issues).Count -eq 0) ($schema | ConvertTo-Json -Depth 12)

    & powershell -NoProfile -ExecutionPolicy Bypass -File $preExecutionGate `
        -ReplayRoot $planRoot `
        -Worktree $worktree `
        -PlanResultPath (Join-Path $planRoot 'PLAN_RESULT.json') `
        -BaselineRoot $worktree | Out-Null
    Assert-True 'read_only_preexecution_passes' ($LASTEXITCODE -eq 0)
    $preExecution = Get-Content -LiteralPath (Join-Path $planRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $planSchemaCheck = @($preExecution.checks | Where-Object { $_.name -eq 'plan_schema_complete' } | Select-Object -First 1)[0]
    Assert-True 'preexecution_records_feature_classification' ([string]$planSchemaCheck.feature_classification -eq 'narrow_backend_read_only_fix') ($preExecution | ConvertTo-Json -Depth 12)
    Assert-True 'preexecution_uses_read_only_side_effect_mode' ([string]$planSchemaCheck.side_effect_schema_mode -eq 'read_only_memory_or_not_required') ($preExecution | ConvertTo-Json -Depth 12)

    $evidenceRoot = Join-Path $tempRoot 'evidence'
    $replayBase = Join-Path $evidenceRoot 'claim-codex-replay-v521-policy'
    New-ZeroCapRound -Root "$replayBase-r01" -AgeMinutes 30
    New-ZeroCapRound -Root "$replayBase-r02" -AgeMinutes 20
    New-ZeroCapRound -Root "$replayBase-r03" -AgeMinutes 10
    New-Item -ItemType Directory -Force -Path "$replayBase-r04-aborted-local-probe" | Out-Null
    Write-Text (Join-Path "$replayBase-r04-aborted-local-probe" 'AUTOPILOT_DECISION.md') '- decision: STOP_BLOCKED'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $stoplineGate `
        -EvidenceRoot $evidenceRoot `
        -ReplayRootBase $replayBase `
        -Lookback 3 `
        -RepeatThreshold 3 `
        -MinimumVerificationProgress 5 `
        -Quiet | Out-Null
    Assert-True 'stopline_blocks_three_completed_zero_cap_rounds' ($LASTEXITCODE -eq 94)
    $stopline = Get-Content -LiteralPath (Join-Path $evidenceRoot '_control\STOPLINE_ANALYSIS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'stopline_records_minimum_progress_threshold' ([int]$stopline.minimum_verification_progress -eq 5) ($stopline | ConvertTo-Json -Depth 12)
    Assert-True 'aborted_probe_root_is_ignored' (-not ((@($stopline.records.name) -join ' ') -match 'aborted')) ($stopline | ConvertTo-Json -Depth 12)
    Assert-True 'all_recent_rounds_are_no_progress' (@($stopline.records | Where-Object { -not [bool]$_.no_progress }).Count -eq 0) ($stopline | ConvertTo-Json -Depth 12)
    Assert-True 'completed_failed_round_is_phase1_not_planready' (@($stopline.records | Where-Object { $_.stage -ne 'Phase1' }).Count -eq 0) ($stopline | ConvertTo-Json -Depth 12)
    Assert-True 'completed_rounds_are_not_substantive_progress' (@($stopline.records | Where-Object { [bool]$_.substantive_progress }).Count -eq 0) ($stopline | ConvertTo-Json -Depth 12)

    Write-Host 'PASS: v523 read-only gate propagation and substantive stopline'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

