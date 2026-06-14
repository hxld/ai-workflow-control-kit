$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($args -contains '-ValidateOnly') {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$planPrompt = Get-Content -LiteralPath (Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md') -Raw -Encoding UTF8
$phase1Prompt = Get-Content -LiteralPath (Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
$cases = @()

$cases += (Assert-True -Name 'plan_forbids_oracle_changes_already_present' -Condition ($planPrompt.Contains('oracle changes already present') -and $planPrompt.Contains('target shape')))
$cases += (Assert-True -Name 'plan_distinguishes_downstream_setter_from_source_chain' -Condition ($planPrompt.Contains('taskData.setPolicyNum(request.getPolicyNum())') -and $planPrompt.Contains('upstream source assignment')))
$cases += (Assert-True -Name 'plan_requires_source_chain_green_diff' -Condition ($planPrompt.Contains('PLAN_BLOCKED_SOURCE_CHAIN_UNPROVEN') -and $planPrompt.Contains('expected_production_diff')))
$cases += (Assert-True -Name 'phase1_rejects_oracle_present_claim' -Condition ($phase1Prompt.Contains('oracle changes already present') -and $phase1Prompt.Contains('do not') -or $phase1Prompt.Contains('不要把这些话当成授权')))
$cases += (Assert-True -Name 'phase1_requires_upstream_assignment' -Condition ($phase1Prompt.Contains('source/buildContext -> request') -and $phase1Prompt.Contains('taskData.setPolicyNum(request.getPolicyNum())')))

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = $cases
    repo_root = $repoRoot
} | ConvertTo-Json -Depth 8
