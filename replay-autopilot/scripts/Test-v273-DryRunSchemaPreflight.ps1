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
$verifyPlanPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$dryRunPath = Join-Path $scriptRoot 'Invoke-ReplayDryRun.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        runner = $runnerPath
        plan_prompt = $planPromptPath
        verify_plan = $verifyPlanPath
        dry_run = $dryRunPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$planPrompt = Get-Content -LiteralPath $planPromptPath -Raw -Encoding UTF8
$verifyPlan = Get-Content -LiteralPath $verifyPlanPath -Raw -Encoding UTF8
$dryRun = Get-Content -LiteralPath $dryRunPath -Raw -Encoding UTF8

Assert-True ($runner -match 'FIRST_SLICE_PROOF_PLAN\.md must use these exact single-line') `
    'Repair prompt must explicitly repair FIRST_SLICE_PROOF_PLAN machine fields'
Assert-True ($runner -match 'required_sibling_surfaces: <value or none_with_reason>') `
    'Repair prompt must require required_sibling_surfaces'
Assert-True ($runner -match 'fail_closed_condition: <condition that blocks Phase1 if unmet>') `
    'Repair prompt must require fail_closed_condition'
Assert-True ($runner -match 'Do not write `fail-closed condition:`; use `fail_closed_condition:`') `
    'Repair prompt must forbid the old fail-closed condition field alias'
Assert-True ($planPrompt -match 'fail_closed_condition: <condition that stops Phase1>') `
    'Plan prompt schema must use fail_closed_condition'
Assert-True ($planPrompt -notmatch 'fail-closed condition: <condition that stops Phase1>') `
    'Plan prompt schema must not advertise the old fail-closed condition field'
Assert-True ($verifyPlan -match "'required_sibling_surfaces'") `
    'Verify-PlanContract must preflight required_sibling_surfaces before dry-run'
Assert-True ($verifyPlan -match "'fail_closed_condition'") `
    'Verify-PlanContract must preflight fail_closed_condition before dry-run'
Assert-True ($dryRun -match 'required_sibling_surfaces' -and $dryRun -match 'fail_closed_condition') `
    'Dry-run still validates required_sibling_surfaces and fail_closed_condition'

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'repair_prompt_first_slice_schema',
        'repair_prompt_required_siblings',
        'repair_prompt_fail_closed_condition',
        'repair_prompt_forbids_old_alias',
        'plan_prompt_fail_closed_condition_schema',
        'plan_prompt_old_alias_removed',
        'plan_verifier_preflights_required_siblings',
        'plan_verifier_preflights_fail_closed_condition',
        'dry_run_contract_still_has_fields'
    )
} | ConvertTo-Json -Depth 6
