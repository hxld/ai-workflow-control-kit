param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        test_name = 'v458-PlanContractGoldenSliceBindingFormat'
    } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$planPromptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'
$planPrompt = Get-Content -LiteralPath $planPromptPath -Raw -Encoding UTF8

# Test 1: golden_slice_binding field format requirement
Assert-True ($planPrompt -match 'golden_slice_binding:\s*<rule fingerprint -> selected production carrier -> first RED -> minimum GREEN -> executable side effect>') `
    'Plan prompt must specify golden_slice_binding single-line format with all required components'

# Test 2: golden_slice_binding must include fingerprint keyword requirement
Assert-True ($planPrompt -match 'side_effect_ledger_gap|exact_contract_gap|schema_contract_discovery_gap|low_verification_cap|oracle_overlap|positive_first_slice') `
    'Plan prompt must require golden_slice_binding fingerprint keyword from allowed set'

# Test 3a: PLAN_RESULT.md must include golden_slice_binding field
Assert-True ($planPrompt -match '`PLAN_RESULT\.md` must include one single-line field') `
    'Plan prompt must require golden_slice_binding in PLAN_RESULT.md'

# Test 3b: FIRST_SLICE_PROOF_PLAN.md must include the same golden_slice_binding field
Assert-True ($planPrompt -match '`FIRST_SLICE_PROOF_PLAN\.md` must include the same single-line field') `
    'Plan prompt must require golden_slice_binding in FIRST_SLICE_PROOF_PLAN.md'

# Test 3c: Verify the fingerprint keywords are explicitly listed
Assert-True ($planPrompt -match 'Do not write `NONE`, `TBD`, `unknown`, `placeholder`') `
    'Plan prompt must forbid NONE/TBD/unknown/placeholder in golden_slice_binding'

# Test 4: oracle_missing_high_weight_files format requirement
Assert-True ($planPrompt -match 'oracle_missing_high_weight_files:') `
    'Plan prompt must specify oracle_missing_high_weight_files as semicolon-separated list'

# Test 5: oracle_expansion_plan format requirement
Assert-True ($planPrompt -match 'oracle_expansion_plan:') `
    'Plan prompt must specify oracle_expansion_plan format with mapping syntax'

# Test 6: oracle_out_of_scope_files format requirement
Assert-True ($planPrompt -match 'oracle_out_of_scope_files:') `
    'Plan prompt must specify oracle_out_of_scope_files as semicolon-separated list'

# Test 7: existing_production_carriers format requirement
Assert-True ($planPrompt -match 'existing_production_carriers:') `
    'Plan prompt must specify existing_production_carriers as same-line semicolon-separated values'

# Test 8: carrier_search_queries format requirement (at least 3 search commands)
Assert-True ($planPrompt -match 'carrier_search_queries:\s*<query1>;\s*<query2>;\s*<query3>') `
    'Plan prompt must require at least 3 carrier search queries separated by semicolons'

# Test 9: real_carrier_kind enum values
Assert-True ($planPrompt -match 'production_entry_or_service|production_controller_or_route|production_mapper_or_query|production_payload_builder|production_template_or_artifact_renderer|production_lifecycle_cleanup|production_service_method|production_service|production_enum|production_dto') `
    'Plan prompt must list allowed real_carrier_kind enum values'

# Test 10: proof_kind enum values
Assert-True ($planPrompt -match 'real_entry_behavior|stateful_side_effect|route_export_behavior|payload_shape_behavior|generated_artifact_behavior') `
    'Plan prompt must list allowed proof_kind enum values'

# Test 11: Verify the plan prompt forbids TBD/unknown/placeholder in critical fields
Assert-True ($planPrompt -match 'TBD|unknown|placeholder') `
    'Plan prompt must forbid TBD/unknown/placeholder in critical golden_slice_binding fields'

[ordered]@{
    status = 'PASS'
    assertions = 13
    test_name = 'v458-PlanContractGoldenSliceBindingFormat'
    cases = @(
        'golden_slice_binding_format',
        'golden_slice_binding_fingerprint_keyword',
        'golden_slice_binding_in_plan_result',
        'golden_slice_binding_in_first_slice_proof',
        'golden_slice_binding_forbidden_placeholders',
        'oracle_missing_high_weight_files_format',
        'oracle_expansion_plan_format',
        'oracle_out_of_scope_files_format',
        'existing_production_carriers_format',
        'carrier_search_queries_three_minimum',
        'real_carrier_kind_enum_values',
        'proof_kind_enum_values',
        'forbids_tbd_placeholder'
    )
} | ConvertTo-Json -Depth 5
