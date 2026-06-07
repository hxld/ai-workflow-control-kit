param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runLoop = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1')
$untilRunner = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-UntilKnowledgeVersion.ps1')
$evolutionPrompt = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'prompts\skill-evolution.prompt.md')

$cases = New-Object System.Collections.Generic.List[string]
$cases.Add((Assert-True -Name 'run_loop_writes_evolution_repair_prompt' -Condition ($runLoop -match 'EVOLUTION_REPAIR_PROMPT\.md'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_preserves_previous_evolution_result' -Condition ($runLoop -match 'EVOLUTION_RESULT_PRE_REPAIR\.md'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_invokes_evolution_repair' -Condition ($runLoop -match 'evolution-repair'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_validates_after_repair' -Condition ($runLoop -match 'PASS_AFTER_REPAIR')) ) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_repair_prefers_existing_powershell' -Condition ($runLoop -match 'existing PowerShell runner/verifier/prompt files'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_writes_evolution_repair_prompt' -Condition ($untilRunner -match 'EVOLUTION_REPAIR_PROMPT\.md'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_invokes_evolution_repair' -Condition ($untilRunner -match 'evolution-repair'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_validates_after_repair' -Condition ($untilRunner -match 'VALIDATION_FAILED_AFTER_REPAIR'))) | Out-Null
$cases.Add((Assert-True -Name 'prompt_rejects_unattached_script_names' -Condition ($evolutionPrompt.Contains('JS/Python') -and $evolutionPrompt.Contains('PowerShell runner/verifier/prompt/test')))) | Out-Null
$cases.Add((Assert-True -Name 'prompt_requires_actual_autopilot_changes' -Condition ($evolutionPrompt -match 'tooling_changes_applied:\s*true[\s\S]+\{\{AUTOPILOT_ROOT\}\}'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
