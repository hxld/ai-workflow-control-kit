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

Assert-True ($runner -match 'PLAN_CONTRACT_REPAIR_PROMPT\.md') `
    'Run-ReplayLoop must create PLAN_CONTRACT_REPAIR_PROMPT.md'
Assert-True ($runner -match 'plan-contract-repair') `
    'Run-ReplayLoop must run a named plan-contract-repair pass'
Assert-True ($runner -match 'carrier_search_queries_too_few') `
    'Repair prompt must specifically repair carrier_search_queries_too_few'
Assert-True ($runner -match 'plan_result_missing:oracle_production_file_overlap') `
    'Repair prompt must specifically repair missing oracle overlap disclosure'
Assert-True ($runner -match 'oracle_overlap_below_threshold') `
    'Repair prompt must specifically repair or block low oracle overlap'
Assert-True ([regex]::Matches($runner, 'Verify-PlanContract\.ps1').Count -ge 4) `
    'Run-ReplayLoop must re-run Verify-PlanContract after repair'
Assert-True (($planPrompt -match 'carrier_search_queries_too_few') -and ($planPrompt -match 'contract repair pass')) `
    'Plan prompt must disclose the contract repair pass and fail-closed behavior'

[ordered]@{
    status = 'PASS'
    assertions = 7
    cases = @(
        'repair_prompt_created',
        'repair_pass_named',
        'carrier_search_query_repair_required',
        'oracle_overlap_disclosure_repair_required',
        'oracle_overlap_threshold_repair_required',
        'verify_rerun_after_repair',
        'plan_prompt_discloses_repair'
    )
} | ConvertTo-Json -Depth 6
