param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$prompt = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\phase-plan-tournament.prompt.md'

$runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
$promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8

Assert-True 'repair_prompt_handles_golden_slice_binding_weak_plan_result' ($runLoopText.Contains('golden_slice_binding_weak:plan_result'))
Assert-True 'repair_prompt_replaces_none_with_reason_binding' ($runLoopText.Contains('none_with_reason') -and $runLoopText.Contains('exact_contract_gap -> ExampleDataAssemblyHelper.RequestBuildFunction'))
Assert-True 'repair_prompt_handles_first_slice_side_effects_insufficient' ($runLoopText.Contains('first_slice_proof_v457_side_effects_insufficient') -and $runLoopText.Contains('expected_side_effects: []'))
Assert-True 'plan_prompt_forbids_none_with_reason_even_without_golden_file' ($promptText.Contains('no golden delivery slice files exist') -and $promptText.Contains('none_with_reason') -and $promptText.Contains('stateful_side_effect'))

Write-Host 'PASS: v496 plan repair golden binding and side effects prompt'
