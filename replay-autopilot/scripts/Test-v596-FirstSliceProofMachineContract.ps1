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
$verifyScript = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoopScript = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("v596-first-slice-proof-contract-" + [guid]::NewGuid().ToString('N'))

try {
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core\src\main\java\com\example') | Out-Null
    Write-Utf8 (Join-Path $worktree 'claim-core\src\main\java\com\example\ConfigCarrier.java') @'
package com.example;
class ConfigCarrier {
  void save(Object dto) {}
}
'@

    $binding = 'exact_contract_gap -> ConfigCarrier.save -> RED -> GREEN -> stateful_side_effect'
    Write-Utf8 (Join-Path $tempRoot 'PLAN_RESULT.md') @"
plan_status: PROCEED
selected_strategy: machine-contract-fixture
carrier_search: performed
existing_production_carriers: ConfigCarrier
selected_carrier: ConfigCarrier
oracle_production_file_overlap: 80%
oracle_high_weight_file_overlap: 80%
oracle_repair_ledger: none
oracle_missing_high_weight_map: none
oracle_out_of_scope_files: none
golden_slice_binding: $binding
first_slice: S1
first_red_test: ConfigCarrierTest.savesThreshold
core_closure_required: false
"@
    Write-Utf8 (Join-Path $tempRoot 'PLAN_CANDIDATE_1.md') 'candidate 1'
    Write-Utf8 (Join-Path $tempRoot 'PLAN_CANDIDATE_2.md') 'candidate 2'
    Write-Utf8 (Join-Path $tempRoot 'PLAN_CANDIDATE_3.md') 'candidate 3'
    Write-Utf8 (Join-Path $tempRoot 'PLAN_SELECTION.md') 'selected_strategy: machine-contract-fixture'
    Write-Utf8 (Join-Path $tempRoot 'REPLAY_PLAN.md') 'wire_payload_api_contract ConfigCarrier S1'
    Write-Utf8 (Join-Path $tempRoot 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: com.example.Entry.handle()
first_slice: S1
first_red_test: ConfigCarrierTest.savesThreshold'
    Write-Utf8 (Join-Path $tempRoot 'EXPECTED_DIFF_MATRIX.md') 'validation closure status for ConfigCarrier.java'
    Write-Utf8 (Join-Path $tempRoot 'SIDE_EFFECT_LEDGER.md') 'state task progress log transaction DB insert/update threshold'
    Write-Utf8 (Join-Path $tempRoot 'TEST_CHARTER.md') 'RED GREEN ConfigCarrierTest savesThreshold'
    Write-Utf8 (Join-Path $tempRoot 'FAMILY_CONTRACT.json') '{"selected_real_entry":"com.example.Entry.handle()","first_executable_slice":"S1","families":[{"id":"wire_payload_api_contract","required":true}]}'

    Write-Utf8 (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
# First Slice Proof Plan

- **first_slice**: S1
- **golden_slice_binding**: $binding
- **highest_weight_open_gate**: wire_payload_api_contract
- **first_slice_family**: wire_payload_api_contract
- **first_red_test**: ConfigCarrierTest.savesThreshold
- **selected_real_entry**: com.example.Entry.handle()
- **public_entry_contract_coverage**: not_public_entry_with_reason:service_threshold_slice
- **selected_carrier**: ConfigCarrier
- **target_subsurface_or_carrier**: ConfigCarrier.save
- **production_boundary**: claim-core/src/main/java/com/example/ConfigCarrier.java
- **proof_kind**: stateful_side_effect
- **real_carrier_kind**: production_service_method
- **required_sibling_surfaces**: none
- **minimum_side_effect_or_blocker**: mapper insert/update persists threshold
- **expected_production_diff**: claim-core/src/main/java/com/example/ConfigCarrier.java
- **red_expectation**: test fails before threshold persistence exists
- **green_minimum_implementation**: add minimum service/entity/mapper threshold persistence
- **forbidden_substitute_check**: passed
- **forbidden_substitute_proof**: not helper-only or static-only
- **fail_closed_condition**: fail if no executable state assertion
- **coverage_cap_if_not_closed**: none
- **target_carrier_file_path**: claim-core/src/main/java/com/example/ConfigCarrier.java
- **target_carrier_line_number**: 3
- **expected_test_class**: ConfigCarrierTest
- **expected_test_method**: savesThreshold
- **expected_assertions**: ["captured entity contains threshold","mapper insert called","mapper update called"]
- **expected_side_effects**: [{"state":"threshold","operation":"insert/update","proof":"mapper capture"}]
"@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $tempRoot -Stage Plan -Worktree $worktree | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues) -join ' '
    Assert-True 'bold_bullet_schema_fields_are_parsed' ($issues -notmatch 'first_slice_proof_schema_missing:')
    Assert-True 'bold_bullet_v457_fields_are_parsed' ($issues -notmatch 'first_slice_proof_v457_missing:')
    Assert-True 'bold_bullet_side_effects_are_parsed' ($issues -notmatch 'first_slice_proof_v457_side_effects_missing')
    Assert-True 'bold_bullet_assertions_are_parsed' ($issues -notmatch 'first_slice_proof_v457_assertions_missing')

    $runLoopText = Get-Content -LiteralPath $runLoopScript -Raw -Encoding UTF8
    Assert-True 'artifact_repair_prompt_has_machine_contract_block' ($runLoopText -match 'first_slice_family: <actual S1 family')
    Assert-True 'artifact_repair_prompt_forbids_narrative_only_schema' ($runLoopText -match 'Do not rely on headings, bullets, narrative paragraphs, or Markdown tables as the only copy')

    Write-Host 'PASS: v596 first-slice proof machine contract'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
