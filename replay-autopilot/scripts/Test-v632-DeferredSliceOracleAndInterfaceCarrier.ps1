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

function New-DeferredSliceFixture {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'

    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleConfigFacade.java') @'
package com.example.ai;
public interface ExampleConfigFacade {
    void save(ExampleConfigDto dto);
}
'@
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleConfigFacadeImpl.java') @'
package com.example.ai;
public class ExampleConfigFacadeImpl implements ExampleConfigFacade {
    private final ExampleConfigService service = new ExampleConfigService();
    public void save(ExampleConfigDto dto) { service.save(dto); }
}
'@
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleConfigService.java') 'package com.example.ai; public class ExampleConfigService { public void save(ExampleConfigDto dto) {} }'
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleConfigMapper.java') 'package com.example.ai; public interface ExampleConfigMapper { void insert(ExampleConfigDto dto); }'

    $oracleFiles = @(
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleConfigFacade.java'; weight = 'HIGH'; is_production = $true; additions = 5; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleConfigFacadeImpl.java'; weight = 'HIGH'; is_production = $true; additions = 8; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleConfigService.java'; weight = 'HIGH'; is_production = $true; additions = 10; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleConfigMapper.java'; weight = 'HIGH'; is_production = $true; additions = 4; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/AutoFlowService.java'; weight = 'HIGH'; is_production = $true; additions = 120; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/OcrRetryService.java'; weight = 'HIGH'; is_production = $true; additions = 90; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/OcrTaskProcessor.java'; weight = 'HIGH'; is_production = $true; additions = 90; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ReportExportService.java'; weight = 'HIGH'; is_production = $true; additions = 75; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/RiskRuleService.java'; weight = 'HIGH'; is_production = $true; additions = 60; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/CaseFlowService.java'; weight = 'HIGH'; is_production = $true; additions = 60; deletions = 0 }
    )
    Write-JsonFile (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{ files = $oracleFiles })

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- selected_candidate: 3 - Exact-Contract-and-Test-First
- selected_strategy: exact-contract-and-test-first
- implementation_model_recommendation: claude-opus-4-7
- required_files: module/src/main/java/com/example/ai/ExampleConfigFacade.java, module/src/main/java/com/example/ai/ExampleConfigFacadeImpl.java, module/src/main/java/com/example/ai/ExampleConfigService.java, module/src/main/java/com/example/ai/ExampleConfigMapper.java
- oracle_primary_domain: ai
- requirement_primary_domain: ai
- oracle_production_file_overlap: 40% (4/10)
- oracle_high_weight_coverage: 40% (4/10)
- oracle_missing_high_weight_files: AutoFlowService (S2), OcrRetryService (S4), OcrTaskProcessor (S4), ReportExportService (deferred scope_cap), RiskRuleService (S5), CaseFlowService (deferred follow-up run)
- oracle_expansion_plan: AutoFlowService -> S2; OcrRetryService -> S4; OcrTaskProcessor => S4; ReportExportService -> deferred follow-up run (scope_cap); RiskRuleService: S5; CaseFlowService -> deferred follow-up run (scope_cap)
- oracle_out_of_scope_files: ReportExportService (deferred follow-up run), CaseFlowService (deferred follow-up run)
- golden_slice_binding: exact_contract_gap -> ExampleConfigFacade.save -> RED: save returns null in query response -> GREEN: field added to DTO/service/mapper -> DB query assertion proves persisted value
- carrier_search: performed
- carrier_search_queries: rg "interface ExampleConfigFacade" --type java worktree; rg "class ExampleConfigFacadeImpl" --type java worktree
- existing_production_carriers: ExampleConfigFacade (interface); ExampleConfigFacadeImpl; ExampleConfigService; ExampleConfigMapper
- selected_carrier_from_search: ExampleConfigFacade
- new_service_proposed: false
- new_service_justification: none
- oracle_contract_pre_binding: skipped_no_contracts
- oracle_signature_alignment: skipped_no_contracts
- first_slice: S1
- first_red_test: ExampleConfigFacadeTest.testSaveConfigField
- core_closure_required: true
- deploy_surface_required: false
- invalid_reason: none
- blocker: none
- next_action: Phase 1 implementation of S1
'@
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') @'
# Replay Plan

S1 core_entry: ExampleConfigFacade.save config field exact contract.
S2 stateful_side_effect: AutoFlowService planned S2.
S4 wire_payload_api_contract: OcrRetryService and OcrTaskProcessor planned S4.
S5 policy_threshold: RiskRuleService planned S5.
Deferred: ReportExportService and CaseFlowService follow-up run with scope_cap.
'@
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'S1 -> ExampleConfigFacade/Impl/Service/Mapper -> field mapping -> facade test.'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') @'
selected_real_entry: ExampleConfigFacade.save
first_slice: S1
first_red_test: ExampleConfigFacadeTest.testSaveConfigField
interface_contract_return_type: void
interface_contract_error_handling: throws validation exception for invalid config
pattern_to_follow: ExampleConfigFacade.save -> ExampleConfigFacadeImpl.save -> ExampleConfigService.save -> ExampleConfigMapper.insert
pattern_evidence_source: rg "interface ExampleConfigFacade" module/src/main/java
'@
    Write-Utf8 (Join-Path $Root 'TEST_CHARTER.md') @'
test_surface: ExampleConfigFacade
entry_point: ExampleConfigFacade.save(ExampleConfigDto)
test_class: ExampleConfigFacadeTest
test_method: testSaveConfigField
RED: missing persisted field assertion fails
GREEN: mapper capture and query response pass
DB Verification: mapper ArgumentCaptor verifies persisted field
Side Effects:
- verify config row contains persisted field
'@
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
golden_slice_binding: exact_contract_gap -> ExampleConfigFacade.save -> RED: save returns null in query response -> GREEN: field added to DTO/service/mapper -> DB query assertion proves persisted value
highest_weight_open_gate: core_entry
first_slice_family: core_entry
selected_real_entry: ExampleConfigFacade.save
selected_carrier: ExampleConfigFacade
target_subsurface_or_carrier: ExampleConfigFacadeImpl.save(ExampleConfigDto)
production_boundary: module/src/main/java/com/example/ai/ExampleConfigFacadeImpl.java:4
proof_kind: real_entry_behavior
real_carrier_kind: production_entry_or_service
first_red_test: ExampleConfigFacadeTest.testSaveConfigField
public_entry_contract_coverage: public facade entry covered by facade test
forbidden_substitute_check: passed
forbidden_substitute_proof: test exercises facade, implementation, service, mapper side effect
required_sibling_surfaces: none
minimum_side_effect_or_blocker: mapper capture verifies persisted field
expected_production_diff: module/src/main/java/com/example/ai/ExampleConfigService.java and ExampleConfigMapper.java update field persistence
red_expectation: RED fails before field mapping exists
green_minimum_implementation: save maps and persists field
fail_closed_condition: block if mapper capture lacks field
coverage_cap_if_not_closed: 60
target_carrier_file_path: module/src/main/java/com/example/ai/ExampleConfigFacadeImpl.java
target_carrier_line_number: 4
expected_test_class: ExampleConfigFacadeTest
expected_test_method: testSaveConfigField
expected_assertions: ["assert mapper capture field","assert query field","assert clear field"]
expected_side_effects: ["config row persists field"]
interface_contract_return_type: void
interface_contract_error_handling: throws validation exception for invalid config
pattern_to_follow: ExampleConfigFacade.save -> ExampleConfigFacadeImpl.save -> ExampleConfigService.save -> ExampleConfigMapper.insert
pattern_evidence_source: rg "interface ExampleConfigFacade" module/src/main/java
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

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v632-deferred-slice-oracle-' + [guid]::NewGuid().ToString('N'))
$assertions = 0

try {
    $root = Join-Path $tmp 'fixture'
    $worktree = New-DeferredSliceFixture -Root $root
    $verify = Invoke-PlanVerifier -Root $root -Worktree $worktree
    $json = $verify | ConvertTo-Json -Depth 12
    $issues = $verify.issues -join ';'
    $warnings = $verify.warnings -join ';'

    Assert-True 'interface_facade_carrier_found' (-not ($issues -match 'carrier_search_selected_carrier_not_found_in_codebase')) $json
    $assertions++
    Assert-True 'planned_deferred_overall_overlap_issue_exempted' (-not ($issues -match 'oracle_overlap_below_threshold')) $json
    $assertions++
    Assert-True 'planned_deferred_high_weight_issue_exempted' (-not ($issues -match 'oracle_high_weight_overlap_below_threshold')) $json
    $assertions++
    Assert-True 'planned_deferred_overlap_warning_recorded' ($warnings -match 'oracle_overlap_below_threshold_exempted') $json
    $assertions++
    Assert-True 'planned_deferred_high_weight_warning_recorded' ($warnings -match 'oracle_high_weight_overlap_below_threshold_exempted') $json
    $assertions++
    Assert-True 'plan_not_auto_repaired_to_blocked' (-not ($issues -match 'plan_status_not_proceed')) $json
    $assertions++

    [ordered]@{
        status = 'PASS'
        assertions = $assertions
        cases = @(
            'interface_facade_carrier_is_existing_carrier',
            'planned_deferred_oracle_diff_exempts_overall_overlap',
            'planned_deferred_oracle_diff_exempts_high_weight_overlap'
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
