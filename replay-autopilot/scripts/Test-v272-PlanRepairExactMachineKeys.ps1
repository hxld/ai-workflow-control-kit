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
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$planPromptPath = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        runner = $runnerPath
        plan_prompt = $planPromptPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath $planPromptPath -Raw -Encoding UTF8

Assert-True ($runner -match 'PLAN_RESULT\.md must use these exact machine keys') `
    'Repair prompt must require exact machine keys in PLAN_RESULT.md'
Assert-True ($runner -match 'carrier_search: performed') `
    'Repair prompt must require carrier_search: performed/blocked'
Assert-True ($runner -match 'existing_production_carriers: <carrier1>; <carrier2>') `
    'Repair prompt must require same-line existing_production_carriers values'
Assert-True ($runner -match 'selected_carrier_from_search: <carrier from existing_production_carriers>') `
    'Repair prompt must require selected_carrier_from_search from existing carriers'
Assert-True ($runner -match 'After expansion, if the plan honestly reaches the threshold, set `plan_status: PROCEED`') `
    'Repair prompt must allow PROCEED after honest threshold repair'
Assert-True ($runner -match '\$contractRepairResultPath' -and $runner -notmatch '`\$contractRepairResultPath') `
    'Repair completion path must interpolate the actual PLAN_CONTRACT_REPAIR_RESULT.md path'
Assert-True ($planPrompt -match 'Alias names such as `carrier_search_existing_carriers` are forbidden') `
    'Plan prompt must forbid carrier-search alias fields'
Assert-True ($planPrompt -match 'Empty key followed by bullet/list is forbidden') `
    'Plan prompt must require same-line carrier list values'
Assert-True ($planPrompt -match 'selected_carrier_from_search: <carrier from existing_production_carriers>') `
    'Plan result template must use exact selected_carrier_from_search field'

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'repair_requires_exact_machine_keys',
        'repair_requires_carrier_search_status',
        'repair_requires_same_line_existing_carriers',
        'repair_requires_selected_carrier_from_search',
        'repair_can_set_proceed_after_threshold',
        'repair_result_path_interpolates',
        'plan_prompt_forbids_alias_fields',
        'plan_prompt_forbids_bullet_only_carriers',
        'plan_template_exact_selected_carrier_key'
    )
} | ConvertTo-Json -Depth 6
