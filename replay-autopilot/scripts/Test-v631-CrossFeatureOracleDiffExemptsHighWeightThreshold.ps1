param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-CrossFeatureFixture {
    param(
        [string]$Root,
        [switch]$CrossFeature
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'
    $carrierPath = Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleConfigService.java'
    Write-Utf8 $carrierPath 'package com.example.ai; public class ExampleConfigService { public void save() {} }'

    $oracleFiles = @()
    $oracleFiles += [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleConfigService.java'; weight = 'HIGH'; is_production = $true; additions = 3; deletions = 0 }
    foreach ($idx in 1..9) {
        $oracleFiles += [pscustomobject]@{ path = ('module/src/main/java/com/example/ai/OtherFeature{0}Service.java' -f $idx); weight = 'HIGH'; is_production = $true; additions = 50; deletions = 0 }
    }
    Write-JsonFile (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{ files = $oracleFiles })

    $expansion = if ($CrossFeature) {
        'The remaining HIGH-weight oracle files belong to other requirements and other features in this multi-feature oracle diff; they are not in scope for this slice and will be addressed in their own separate feature slices.'
    } else {
        'The remaining HIGH-weight oracle files are missing from the current plan with no cross-feature explanation.'
    }

    $plan = @"
# Plan Result

- plan_status: PROCEED
- selected_candidate: 1 - Exact Contract First
- selected_strategy: exact-contract-first
- implementation_model_recommendation: claude-opus-4-7
- oracle_primary_domain: ai
- requirement_primary_domain: ai
- oracle_production_file_overlap: 10%
- oracle_high_weight_coverage: 10% (1/10)
- oracle_missing_high_weight_files: documented by expansion plan
- oracle_expansion_plan: $expansion
- golden_slice_binding: oracle_overlap -> ExampleConfigService -> RED: ExampleConfigServiceTest.testSaveConfig fails -> GREEN: ExampleConfigService.save persists value -> executable side effect verified by mapper capture
- carrier_search: performed
- carrier_search_queries: rg "class ExampleConfigService" --type java; rg "void save" --type java; rg "ExampleConfigMapper" --type java
- existing_production_carriers: ExampleConfigService; ExampleConfigMapper; ExampleConfigController
- selected_carrier_from_search: ExampleConfigService
- new_service_proposed: false
- new_service_justification: none
- first_slice: S1 - config field exact contract
- first_red_test: ExampleConfigServiceTest.testSaveConfig
- core_closure_required: true
- deploy_surface_required: false
- invalid_reason: none
- blocker: none
- next_action: write RED test and implement field mapping
"@
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') $plan
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'S1: ExampleConfigService.save config field exact contract.'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'ExampleConfigService.java -> LOGIC_ADD -> copy field; ExampleConfigMapper.xml -> SQL_ADD -> persist field.'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExampleConfigFacade.save()
first_slice: S1
first_red_test: ExampleConfigServiceTest.testSaveConfig
interface_contract_return_type: void
interface_contract_error_handling: throws validation exception for invalid config
pattern_to_follow: ExampleConfigFacade.save() -> ExampleConfigService.save()
pattern_evidence_source: rg "class ExampleConfigFacade" module/src/main/java; ExampleConfigFacade.save()
'@
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') @'
Entry Point: ExampleConfigService.save()
Test Class: ExampleConfigServiceTest
RED: missing persisted field assertion fails
GREEN: mapper capture and query response pass
DB Verification: mapper ArgumentCaptor verifies persisted field
Side Effects:
- verify config row contains persisted field
'@
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
golden_slice_binding: oracle_overlap -> ExampleConfigService -> RED: ExampleConfigServiceTest.testSaveConfig fails -> GREEN: save copies and persists field -> executable side effect mapper capture
highest_weight_open_gate: core_entry
first_slice_family: core_entry
selected_real_entry: ExampleConfigFacade.save()
selected_carrier: ExampleConfigFacade.save()
target_subsurface_or_carrier: ExampleConfigService.save()
production_boundary: ExampleConfigFacade.save() delegates to ExampleConfigService.save() and mapper persistence
proof_kind: real_entry_behavior
real_carrier_kind: production_entry_or_service
first_red_test: ExampleConfigServiceTest.testSaveConfig
public_entry_contract_coverage: public facade entry covered
forbidden_substitute_check: passed
required_sibling_surfaces: none
minimum_side_effect_or_blocker: mapper capture verifies persisted field
expected_production_diff: module/src/main/java/com/example/ai/ExampleConfigService.java updates save mapping
red_expectation: RED fails before field mapping exists
green_minimum_implementation: save maps and persists field
fail_closed_condition: block if mapper capture lacks field
coverage_cap_if_not_closed: 60
target_carrier_file_path: module/src/main/java/com/example/ai/ExampleConfigService.java
target_carrier_line_number: 1
expected_test_class: ExampleConfigServiceTest
expected_test_method: testSaveConfig
expected_assertions: ["assert mapper capture field","assert query field","assert clear field"]
expected_side_effects: ["config row persists field"]
interface_contract_return_type: void
interface_contract_error_handling: throws validation exception for invalid config
pattern_to_follow: ExampleConfigFacade.save() -> ExampleConfigService.save()
pattern_evidence_source: rg "class ExampleConfigFacade" module/src/main/java; ExampleConfigFacade.save()
'@

    return $worktree
}

function Invoke-PlanVerifier {
    param([string]$Root, [string]$Worktree)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') `
        -ReplayRoot $Root `
        -Stage Plan `
        -Worktree $Worktree | Out-Null
    $verifyPath = Join-Path $Root 'PLAN_CONTRACT_VERIFY.json'
    if (-not (Test-Path -LiteralPath $verifyPath)) {
        throw "Verify-PlanContract did not write PLAN_CONTRACT_VERIFY.json for $Root"
    }
    return Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v631-cross-feature-oracle-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    $crossRoot = Join-Path $tmp 'cross-feature'
    $crossWorktree = New-CrossFeatureFixture -Root $crossRoot -CrossFeature
    $crossVerify = Invoke-PlanVerifier -Root $crossRoot -Worktree $crossWorktree
    $crossJson = $crossVerify | ConvertTo-Json -Depth 12
    Assert-True 'cross_feature_overall_overlap_issue_exempted' (-not (($crossVerify.issues -join ';') -match 'oracle_overlap_below_threshold')) $crossJson
    $assertions++
    Assert-True 'cross_feature_high_weight_issue_exempted' (-not (($crossVerify.issues -join ';') -match 'oracle_high_weight_overlap_below_threshold')) $crossJson
    $assertions++
    Assert-True 'cross_feature_overlap_warning_recorded' (($crossVerify.warnings -join ';') -match 'oracle_overlap_below_threshold_exempted') $crossJson
    $assertions++
    Assert-True 'cross_feature_high_weight_warning_recorded' (($crossVerify.warnings -join ';') -match 'oracle_high_weight_overlap_below_threshold_exempted') $crossJson
    $assertions++

    $plainRoot = Join-Path $tmp 'plain-low-overlap'
    $plainWorktree = New-CrossFeatureFixture -Root $plainRoot
    $plainVerify = Invoke-PlanVerifier -Root $plainRoot -Worktree $plainWorktree
    $plainJson = $plainVerify | ConvertTo-Json -Depth 12
    Assert-True 'plain_low_overlap_still_fails_overall_overlap' (($plainVerify.issues -join ';') -match 'oracle_overlap_below_threshold') $plainJson
    $assertions++
    Assert-True 'plain_low_overlap_still_fails_high_weight' (($plainVerify.issues -join ';') -match 'oracle_high_weight_overlap_below_threshold') $plainJson
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'cross_feature_oracle_diff_exempts_overall_overlap',
            'cross_feature_oracle_diff_exempts_high_weight_overlap',
            'non_cross_feature_low_overlap_still_fails_closed'
        )
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $tmp) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tmp)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tmp -Recurse -Force
        }
    }
}
