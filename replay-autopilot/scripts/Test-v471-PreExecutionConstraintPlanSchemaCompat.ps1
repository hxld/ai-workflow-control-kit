# v471: Pre-execution check accepts the machine plan contract produced by PlanSchemaFailFast
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$constraintCheckPath = Join-Path $scriptRoot 'Invoke-PreExecutionConstraintCheck.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v471-' + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $testRoot 'replay'
$worktree = Join-Path $testRoot 'worktree'
$carrierRelPath = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
$carrierAbsPath = Join-Path $worktree $carrierRelPath

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $carrierAbsPath) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java\sample') | Out-Null
    '<project />' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\pom.xml') -Encoding UTF8
    'class AiApplyClaimApiTaskProcessorTest {}' | Set-Content -LiteralPath (Join-Path $worktree 'claim-server\src\test\java\sample\AiApplyClaimApiTaskProcessorTest.java') -Encoding UTF8
    @'
package com.huize.claim.core.ai.task;

public class AiApplyClaimApiTaskProcessor {
    public void rebuildTaskData() {
    }
}
'@ | Set-Content -LiteralPath $carrierAbsPath -Encoding UTF8

    [ordered]@{
        command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
        exit_code = 0
        stdout_tail = 'BUILD SUCCESS; Compiling 1 source files to claim-server\target\test-classes'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') -Encoding UTF8

    [ordered]@{
        plan_status = 'PROCEED'
        target_carrier_file_path = $carrierRelPath
        expected_test_class = 'AiApplyClaimApiTaskProcessorTest'
        expected_test_method = 'testRebuildTaskData_SetsPolicyNum_WhenSourceExists'
        side_effects = @('MEMORY_SET: taskData.policyNum')
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'claim-server'
            test_module_has_dependencies = $true
            test_harness_available = $true
            can_import_production_classes = $true
            compilation_dry_run_exit_code = 0
            compilation_dry_run_command = 'mvn -s D:\maven\settings\settings.xml -f <worktree>\pom.xml -pl claim-server -am test-compile'
            compilation_dry_run_evidence_file = 'TEST_INFRASTRUCTURE_DRY_RUN.json'
            blocker_reason = 'none'
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $replayRoot 'PLAN_RESULT.json') -Encoding UTF8

    @'
# Test Charter

## Scenario

**Entry Point**: `AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)`
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8

    @'
# First Slice Proof Plan

highest_weight_open_gate: core_entry
selected_carrier: AiApplyClaimApiTaskProcessor.rebuildTaskData()
target_carrier_file_path: claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java
target_carrier_line_number: 10
expected_test_class: AiApplyClaimApiTaskProcessorTest
expected_test_method: testRebuildTaskData_SetsPolicyNum_WhenSourceExists
expected_assertions: ["assertNotNull(taskData)", "assertEquals(\"P\", taskData.getPolicyNum())", "assertEquals(\"I\", taskData.getInsureNum())"]
expected_side_effects: [{"operation":"MEMORY_SET","field":"taskData.policyNum","value":"from request"}]
minimum_side_effect_or_blocker: taskData.policyNum is assigned from request.policyNum
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $constraintCheckPath -ReplayRoot $replayRoot -Worktree $worktree -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') -BaselineRoot $worktree | Out-Null
    $result = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw | ConvertFrom-Json

    $cases = @()
    $cases += (Assert-True -Name 'constraint_check_passes_with_target_carrier_file_path' -Condition ($result.status -eq 'PASS'))
    $cases += (Assert-True -Name 'target_carrier_file_path_used_as_selected_carrier' -Condition ([string]$result.selected_carrier -eq $carrierRelPath))
    $cases += (Assert-True -Name 'entry_point_with_space_is_valid_test_surface' -Condition ([bool]($result.checks | Where-Object { $_.name -eq 'test_charter_valid' }).has_test_surface))
    $cases += (Assert-True -Name 'task_processor_is_allowed_as_existing_executable_carrier' -Condition ([string]($result.checks | Where-Object { $_.name -eq 'carrier_in_valid_layer' }).layer -eq 'TaskProcessor'))
    $cases += (Assert-True -Name 'test_infrastructure_check_passes' -Condition ([string]($result.checks | Where-Object { $_.name -eq 'test_infrastructure_check' }).status -eq 'PASS'))

    @'
# Test Charter

## RED Phase

### Test Class: AiApplyClaimApiTaskProcessorTest

Scenario: backend TaskProcessor rebuild path preserves policy number.
'@ | Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $constraintCheckPath -ReplayRoot $replayRoot -Worktree $worktree -PlanResultPath (Join-Path $replayRoot 'PLAN_RESULT.json') -BaselineRoot $worktree | Out-Null
    $result2 = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_EXECUTION_CONSTRAINT_CHECK.json') -Raw | ConvertFrom-Json
    $cases += (Assert-True -Name 'test_class_heading_is_valid_test_surface' -Condition ([bool]($result2.checks | Where-Object { $_.name -eq 'test_charter_valid' }).has_test_surface))

    [ordered]@{
        status = 'PASS'
        assertions = $cases.Count
        cases = $cases
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $testRoot -Recurse -Force
        }
    }
}
