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

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$phase0Prompt = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase0-contract-gate.prompt.md') -Raw -Encoding UTF8
$runner = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8

$cases = New-Object System.Collections.Generic.List[string]

$cases.Add((Assert-True -Name 'phase0_prompt_defines_blind_oracle_boundary' -Condition ($phase0Prompt -match 'Blind Replay Oracle Boundary'))) | Out-Null
$cases.Add((Assert-True -Name 'oracle_method_signature_gap_not_blocker' -Condition ($phase0Prompt -match 'cannot verify exact oracle method signatures'))) | Out-Null
$cases.Add((Assert-True -Name 'phase0_forbids_wait_for_oracle' -Condition ($phase0Prompt -match 'awaiting oracle verification' -and $phase0Prompt -match 'user must waive coverage caps'))) | Out-Null
$cases.Add((Assert-True -Name 'selected_entry_not_from_oracle_diff' -Condition ($phase0Prompt -match 'inferred from Oracle diff'))) | Out-Null
$cases.Add((Assert-True -Name 'oracle_alignment_is_metadata_only' -Condition ($phase0Prompt -match 'Allowed Metadata Only' -and $phase0Prompt -match 'oracle_analysis_skipped'))) | Out-Null
$cases.Add((Assert-True -Name 'phase0_blocked_runs_evolution_when_enabled' -Condition ($runner -match 'Phase 0 returned BLOCKED\.' -and $runner -match 'Knowledge version refreshed for next round after phase0 blocked evolution' -and $runner -match '(?s)Phase 0 returned BLOCKED\..+continue'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
