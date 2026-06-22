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
$runReplayScript = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runSliceScript = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v615-plan-phase1-normalization-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java\com\example') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'claim-server\pom.xml') '<project></project>'
    Write-Utf8 (Join-Path $worktree 'claim-server\src\test\java\com\example\AiAutoClaimFlowServiceTest.java') @'
package com.example;
class AiAutoClaimFlowServiceTest {}
'@

    $compileCommand = "mvn -s D:\maven\settings\settings.xml -f $worktree\pom.xml -pl claim-server -am test-compile"
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
  "target_carrier_file_path": "claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java",
  "target_carrier_line_number": 1,
  "expected_test_class": "AiAutoClaimFlowServiceTest",
  "expected_test_method": "testAutoFlowPersistsClaimSideEffects",
  "expected_assertions": [
    "verify(compensateInfoMapper).insert(any())",
    "verify(compensateDetailMapper).insert(any())",
    "verify(caseFlowStatusMapper).updateStatus(eq(35))"
  ],
  "side_effects": [
    {"table":"t_compensate_info","operation":"INSERT","fields":["compensate_amount_sum","claim_advice"]},
    {"table":"t_compensate_detail","operation":"INSERT","fields":["protection_item","claim_amount"]},
    {"table":"t_case_flow_status","operation":"UPDATE","field":"statusId","value":"35"}
  ],
  "test_infrastructure_check": {
    "test_module_for_target": "claim-server",
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
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaScript -ReplayRoot $tempRoot -PlanResultPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Worktree $worktree | Out-Null
    $schemaBefore = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'fixture_fails_before_phase1_normalization' ($schemaBefore.status -eq 'FAIL' -and (@($schemaBefore.issues) -join ';') -match 'Side effects schema failed')

    & powershell -NoProfile -ExecutionPolicy Bypass -File $normalizerScript -ReplayRoot $tempRoot -PlanResultPath (Join-Path $tempRoot 'PLAN_RESULT.json') -FirstSliceProofPath (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') | Out-Null
    Assert-True 'normalizer_exit_success' ($LASTEXITCODE -eq 0)

    $normalization = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_MACHINE_CONTRACT_NORMALIZATION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $changes = @($normalization.changes)
    Assert-True 'normalizer_copies_invalid_side_effects_to_expected' ($changes -contains 'PLAN_RESULT.json.expected_side_effects_from_side_effects')
    Assert-True 'normalizer_rewrites_invalid_side_effects' ($changes -contains 'PLAN_RESULT.json.side_effects_from_expected_side_effects')

    $plan = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'normalized_side_effect_has_side_effect' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].side_effect))
    Assert-True 'normalized_side_effect_has_state' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].state))
    Assert-True 'normalized_side_effect_has_proof' (-not [string]::IsNullOrWhiteSpace([string]$plan.side_effects[0].proof))

    & powershell -NoProfile -ExecutionPolicy Bypass -File $schemaScript -ReplayRoot $tempRoot -PlanResultPath (Join-Path $tempRoot 'PLAN_RESULT.json') -Worktree $worktree | Out-Null
    $schemaAfter = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_SCHEMA_FAILFAST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'schema_passes_after_phase1_normalization' ($schemaAfter.status -eq 'PASS')

    $runReplayText = Get-Content -LiteralPath $runReplayScript -Raw -Encoding UTF8
    $repairIndex = $runReplayText.IndexOf('Plan contract repair pass exit code:')
    $postRepairNormalizerIndex = $runReplayText.IndexOf('postRepairPlanMachineNormalizer')
    Assert-True 'run_replay_normalizes_after_contract_repair' ($repairIndex -ge 0 -and $postRepairNormalizerIndex -gt $repairIndex)

    $runSliceText = Get-Content -LiteralPath $runSliceScript -Raw -Encoding UTF8
    $sliceNormalizerIndex = $runSliceText.IndexOf('Sync-PlanMachineContract.ps1')
    $sliceSchemaIndex = $runSliceText.IndexOf('Invoke-PlanSchemaFailFast.ps1')
    Assert-True 'run_slice_normalizes_before_phase1_schema_failfast' ($sliceNormalizerIndex -ge 0 -and $sliceSchemaIndex -gt $sliceNormalizerIndex)

    Write-Host 'PASS: v615 plan machine contract phase1 normalization'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
