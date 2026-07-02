param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$normalizerScript = Join-Path $scriptRoot 'Sync-PlanMachineContract.ps1'
$schemaScript = Join-Path $scriptRoot 'Invoke-PlanSchemaFailFast.ps1'
$runLoopScript = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v614-plan-machine-contract-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-server\src\test\java\com\example') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'example-server\pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'example-server\src\test\java\com\example\ExampleApplyClaimApiTaskProcessorTest.java') @'
package com.example;
class ExampleApplyClaimApiTaskProcessorTest {}
'@

    $compileCommand = "mvn -s D:\maven\settings\settings.xml -f $worktree\pom.xml -pl example-server -am test-compile"
    Write-Utf8 (Join-Path $tempRoot 'TEST_INFRASTRUCTURE_DRY_RUN.json') @"
{
  "exit_code": 0,
  "command": "$($compileCommand -replace '\\', '\\')",
  "stdout": "BUILD SUCCESS"
}
"@

    Write-Utf8 (Join-Path $tempRoot 'PLAN_RESULT.json') @"
{
  "plan_status": "PROCEED",
  "target_carrier_file_path": "example-core/src/main/java/com/example/project/core/ai/task/ExampleApplyClaimApiTaskProcessor.java",
  "target_carrier_line_number": 461,
  "expected_test_class": "ExampleApplyClaimApiTaskProcessorTest",
  "expected_test_method": "testHandleTaskResponse_triggersAutoFlow",
  "expected_assertions": [
    "verify(aiAutoClaimFlowService).autoFlow(any(), any(), any())",
    "verify(caseRouteMapper).updateCaseStatus(eq(caseId), eq(35))",
    "verify(compensateDetailMapper).insert(any())"
  ],
  "expected_side_effects": [
    {"table":"t_compensate_info","operation":"insert","field":"compensate_amount_sum","value":"from claims_result"},
    {"table":"t_case_route","operation":"update","field":"case_status_id","value":"35"}
  ],
  "test_infrastructure_check": {
    "test_module_for_target": "example-server",
    "test_module_has_dependencies": true,
    "test_harness_available": true,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 0,
    "compilation_dry_run_command": "$($compileCommand -replace '\\', '\\')",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "none"
  }
}
"@

    Write-Utf8 (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
# First Slice Proof Plan

first_slice: S1
expected_assertions:
  - "verify(aiAutoClaimFlowService).autoFlow(any(), any(), any())"
  - "verify(caseRouteMapper).updateCaseStatus(eq(caseId), eq(35))"
  - "verify(compensateDetailMapper).insert(any())"
expected_side_effects:
  - table: t_compensate_info
    operation: insert
    field: compensate_amount_sum
    value: from claims_result
  - table: t_case_route
    operation: update
    field: case_status_id
    value: "35"
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $normalizerScript -ReplayRoot $tempRoot -PlanResultPath (Join-Path $tempRoot 'PLAN_RESULT.json') -FirstSliceProofPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') | Out-Null
    Assert-True 'normalizer_exit_success' ($LASTEXITCODE -eq 0)

    $normalization = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_MACHINE_CONTRACT_NORMALIZATION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'normalizer_reports_changes' ($normalization.status -eq 'NORMALIZED')

    $plan = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'side_effects_added_from_expected_side_effects' ($plan.PSObject.Properties.Name -contains 'side_effects')
    Assert-True 'side_effects_shape_has_side_effect' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].side_effect))
    Assert-True 'side_effects_shape_has_state' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].state))
    Assert-True 'side_effects_shape_has_proof' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].proof))

    $proof = Get-Content -LiteralPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Raw -Encoding UTF8
    Assert-True 'first_slice_assertions_single_line_json' ($proof -match '(?m)^expected_assertions:\s*\[')
    Assert-True 'first_slice_side_effects_single_line_json' ($proof -match '(?m)^expected_side_effects:\s*\[')
    Assert-True 'first_slice_yaml_assertion_block_removed' ($proof -notmatch '(?m)^\s+-\s+"verify\(aiAutoClaimFlowService\)')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaScript -ReplayRoot $tempRoot -PlanResultPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Worktree $worktree | Out-Null
    $schema = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_failfast_passes_after_normalization' ($schema.status -eq 'PASS')
    Assert-True 'schema_no_missing_side_effects' (-not ((@($schema.issues) -join ';') -match 'side_effects missing|Missing required fields: side_effects'))

    $runLoopText = Get-Content -LiteralPath $runLoopScript -Raw -Encoding UTF8
    Assert-True 'runner_invokes_plan_machine_normalizer' ($runLoopText.Contains('Sync-PlanMachineContract.ps1'))

    Write-Host 'PASS: v614 plan machine contract normalization'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
