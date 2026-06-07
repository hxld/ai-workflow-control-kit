param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$planPromptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'
$slicePromptPath = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$planVerifierPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$sliceVerifierPath = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        plan_prompt = $planPromptPath
        slice_prompt = $slicePromptPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$planPrompt = Get-Content -LiteralPath $planPromptPath -Raw -Encoding UTF8
$slicePrompt = Get-Content -LiteralPath $slicePromptPath -Raw -Encoding UTF8
$planVerifier = Get-Content -LiteralPath $planVerifierPath -Raw -Encoding UTF8
$sliceVerifier = Get-Content -LiteralPath $sliceVerifierPath -Raw -Encoding UTF8

Assert-True ($planPrompt -match 'Production Carrier Search') `
    'Plan prompt must contain Production Carrier Search section'
Assert-True (($planPrompt -match 'carrier_search_queries') -and ($planPrompt -match 'existing_production_carriers') -and ($planPrompt -match 'selected_carrier_from_search')) `
    'Plan prompt must require carrier search fields'
Assert-True (($planVerifier -match 'carrier_search_missing') -and ($planVerifier -match 'carrier_search_selected_carrier_not_in_results') -and ($planVerifier -match 'carrier_search_new_service_unjustified')) `
    'Plan verifier must fail closed on missing/unproven carrier search'
Assert-True (($planVerifier -match 'plan_result_missing:oracle_production_file_overlap') -and ($planVerifier -match '\$issues\.Add')) `
    'Plan verifier must treat missing oracle overlap disclosure as an issue'
Assert-True (($slicePrompt -match 'exact-contract threshold') -and ($slicePrompt -match 'exact_contract_minimum_coverage_gap')) `
    'Slice prompt must require exact-contract minimum coverage'
Assert-True (($sliceVerifier -match 'exact_contract_minimum_coverage_gap') -and ($sliceVerifier -match '50')) `
    'Slice verifier must enforce exact-contract minimum coverage'
Assert-True (($slicePrompt -match 'stateful side-effect evidence') -and ($sliceVerifier -match 'side_effect_db_evidence_missing')) `
    'Slice prompt/verifier must enforce executable stateful side-effect evidence'

[ordered]@{
    status = 'PASS'
    assertions = 7
    cases = @(
        'production_carrier_search_prompt_required',
        'carrier_search_fields_required',
        'carrier_search_verifier_fail_closed',
        'oracle_overlap_missing_is_issue',
        'exact_contract_threshold_prompt_required',
        'exact_contract_threshold_verifier_required',
        'stateful_side_effect_db_evidence_required'
    )
} | ConvertTo-Json -Depth 6
