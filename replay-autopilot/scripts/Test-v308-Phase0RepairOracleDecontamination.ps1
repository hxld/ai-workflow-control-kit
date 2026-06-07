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

$cases = New-Object System.Collections.Generic.List[string]
$runLoop = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1')
$phase0Prompt = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'prompts\phase0-contract-gate.prompt.md')

$cases.Add((Assert-True -Name 'repair_handles_oracle_inferred_issue' -Condition ($runLoop -match 'phase0_oracle_inferred_selected_entry'))) | Out-Null
$cases.Add((Assert-True -Name 'repair_forbids_oracle_entry_authority' -Condition ($runLoop -match 'Do not cite oracle additions, oracle line counts, oracle new service, oracle metadata, oracle evidence, or oracle high-weight files as selected-entry authority'))) | Out-Null
$cases.Add((Assert-True -Name 'repair_handles_manual_oracle_wait_issue' -Condition ($runLoop -match 'phase0_manual_oracle_wait'))) | Out-Null
$cases.Add((Assert-True -Name 'repair_forbids_alternate_completion_file' -Condition ($runLoop -match 'do not create an alternate completion file'))) | Out-Null
$cases.Add((Assert-True -Name 'phase0_prompt_forbids_oracle_entry_authority' -Condition ($phase0Prompt -match 'Selected Real Entry.*oracle additions.*oracle line count.*oracle new service.*oracle metadata.*oracle evidence'))) | Out-Null
$cases.Add((Assert-True -Name 'phase0_prompt_forbids_manual_oracle_wait' -Condition ($phase0Prompt -match 'oracle verification pending.*oracle commit pending.*pending fetch.*waiting for oracle'))) | Out-Null
$cases.Add((Assert-True -Name 'phase0_prompt_limits_oracle_alignment' -Condition ($phase0Prompt -match 'Oracle Alignment.*family cap.*selected_real_entry'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
