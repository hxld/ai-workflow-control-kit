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

function New-RepairedPlanFixture {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleFacade.java') 'package com.example.ai; public interface ExampleFacade { ResultModel<Void> save(ExampleDto dto); }'
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleFacadeImpl.java') 'package com.example.ai; public class ExampleFacadeImpl implements ExampleFacade { public ResultModel<Void> save(ExampleDto dto) { return null; } }'

    Write-JsonFile (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleFacadeImpl.java'; weight = 'HIGH'; is_production = $true; additions = 8; deletions = 0 }
        )
    })

    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_1.md') 'candidate 1'
    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_2.md') 'candidate 2'
    Write-Utf8 (Join-Path $Root 'PLAN_CANDIDATE_3.md') 'candidate 3'
    Write-JsonFile (Join-Path $Root 'FAMILY_CONTRACT.json') ([ordered]@{ selected = 'core_entry' })
    Write-Utf8 (Join-Path $Root 'PLAN_SELECTION.md') 'selected candidate 3'
    Write-Utf8 (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') 'entry -> ExampleFacade.save; side effect -> DB insert; state -> config row; transaction -> service save; proof -> query row'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'requirement -> module -> file -> change type -> validation -> closure'
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
# Plan Result

- `plan_status`: BLOCKED
- selected_candidate: 3 - Exact-Contract-and-Test-First
- selected_strategy: exact-contract-and-test-first
- implementation_model_recommendation: claude-opus-4-7
- required_files: module/src/main/java/com/example/ai/ExampleFacadeImpl.java
- oracle_primary_domain: ai
- requirement_primary_domain: ai
- oracle_production_file_overlap: 100% (1/1)
- oracle_high_weight_coverage: 100% (1/1)
- oracle_missing_high_weight_files: none
- oracle_expansion_plan: none
- oracle_out_of_scope_files: none
- golden_slice_binding: exact_contract_gap -> ExampleFacade.save -> RED: field missing -> GREEN: field persisted -> DB side effect verified
- carrier_search: performed
- carrier_search_queries: rg "interface ExampleFacade" --type java worktree; rg "class ExampleFacadeImpl" --type java worktree; rg "save" --type java worktree
- existing_production_carriers: ExampleFacade (interface); ExampleFacadeImpl
- selected_carrier_from_search: ExampleFacade
- new_service_proposed: false
- first_slice: S1
- first_red_test: ExampleFacadeTest.testSaveConfigField
- core_closure_required: true
- deploy_surface_required: false
- invalid_reason: none
- `blocker`: oracle_overlap_below_threshold
- next_action: Phase 1 implementation of S1
'@
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'S1 core_entry: ExampleFacade.save exact contract.'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExampleFacade.save
first_slice: S1
first_red_test: ExampleFacadeTest.testSaveConfigField
return_type: ResultModel<Void>
trace: ExampleController.add -> ExampleFacade.save -> ExampleFacadeImpl.save -> ExampleService.save -> ExampleMapper.insert
validation_rules: invalid DTO throws IllegalArgumentException and ResultModel carries facade failure
'@
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') @'
test_surface: ExampleFacade
entry_point: ExampleFacade.save(ExampleDto)
test_class: ExampleFacadeTest
test_method: testSaveConfigField
RED: missing persisted field assertion fails
GREEN: query response passes
DB Verification: query row verifies persisted field
'@
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
golden_slice_binding: exact_contract_gap -> ExampleFacade.save -> RED: field missing -> GREEN: field persisted -> DB side effect verified
highest_weight_open_gate: core_entry
first_slice_family: core_entry
first_red_test: ExampleFacadeTest.testSaveConfigField
selected_real_entry: ExampleFacade.save
public_entry_contract_coverage: public facade entry covered
selected_carrier: ExampleFacade
target_subsurface_or_carrier: ExampleFacadeImpl.save(ExampleDto)
production_boundary: module/src/main/java/com/example/ai/ExampleFacadeImpl.java:1
proof_kind: real_entry_behavior
real_carrier_kind: production_entry_or_service
required_sibling_surfaces: none
minimum_side_effect_or_blocker: DB insert of config row
expected_production_diff: module/src/main/java/com/example/ai/ExampleFacadeImpl.java maps persisted field
red_expectation: RED fails before field mapping exists
green_minimum_implementation: save maps and persists field
forbidden_substitute_check: passed
forbidden_substitute_proof: facade implementation and DB side effect are exercised
fail_closed_condition: block if DB query cannot verify persisted field
coverage_cap_if_not_closed: 60
target_carrier_file_path: module/src/main/java/com/example/ai/ExampleFacadeImpl.java
target_carrier_line_number: 1
expected_test_class: ExampleFacadeTest
expected_test_method: testSaveConfigField
expected_assertions: ["assert save success","assert query field","assert DB row"]
expected_side_effects: ["DB insert/update of config row"]
'@
    return $worktree
}

function Invoke-PlanVerifier {
    param([string]$Root, [string]$Worktree)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1') `
        -ReplayRoot $Root `
        -Stage Plan `
        -Worktree $Worktree | Out-Null
    return Get-Content -LiteralPath (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v633-repaired-plan-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    $root = Join-Path $tmp 'fixture'
    $worktree = New-RepairedPlanFixture -Root $root
    $verify = Invoke-PlanVerifier -Root $root -Worktree $worktree
    $json = $verify | ConvertTo-Json -Depth 12
    $issues = $verify.issues -join ';'
    $warnings = $verify.warnings -join ';'

    Assert-True 'single_string_side_effect_array_counts_as_one' (-not ($issues -match 'first_slice_proof_v457_side_effects')) $json
    $assertions++
    Assert-True 'return_type_fallback_satisfies_interface_contract' (-not ($issues -match 'interface_contract_return_type_missing')) $json
    $assertions++
    Assert-True 'error_handling_fallback_satisfies_interface_contract' (-not ($issues -match 'interface_contract_error_handling_missing')) $json
    $assertions++
    Assert-True 'trace_fallback_satisfies_pattern_to_follow' (-not ($issues -match 'pattern_to_follow_missing')) $json
    $assertions++
    Assert-True 'carrier_file_line_fallback_satisfies_pattern_evidence' (-not ($issues -match 'pattern_evidence_source_missing')) $json
    $assertions++
    Assert-True 'fallback_warnings_recorded' ($warnings -match 'interface_contract_return_type_inferred' -and $warnings -match 'pattern_to_follow_inferred' -and $warnings -match 'pattern_evidence_source_inferred') $json
    $assertions++
    Assert-True 'backtick_stale_blocker_auto_repaired' (-not ($issues -match 'plan_status_not_proceed')) $json
    $assertions++
    $repairedPlan = Get-Content -LiteralPath (Join-Path $root 'PLAN_RESULT.md') -Raw -Encoding UTF8
    Assert-True 'plan_result_rewritten_to_proceed' ($repairedPlan -match '(?m)plan_status`?:\s*PROCEED|plan_status\s*[:=]\s*PROCEED') $repairedPlan
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'single_string_side_effect_array_counts',
            'interface_contract_inferred_from_return_type_and_validation',
            'pattern_inferred_from_trace_and_carrier_line',
            'backtick_stale_blocker_auto_repaired'
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
