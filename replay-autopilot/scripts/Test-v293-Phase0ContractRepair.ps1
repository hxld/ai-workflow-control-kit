param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$phase0PromptPath = Join-Path $scriptRoot '..\prompts\phase0-contract-gate.prompt.md'
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$phase0Prompt = Get-Content -LiteralPath $phase0PromptPath -Raw -Encoding UTF8

$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize($runner, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) "Run-ReplayLoop.ps1 must parse after v293 Phase0 repair changes"

Assert-True ($runner.Contains('PHASE0_CONTRACT_REPAIR_PROMPT.md')) "Run-ReplayLoop must write a Phase0 contract repair prompt"
Assert-True ($runner.Contains('PHASE0_CONTRACT_REPAIR_RESULT.md')) "Run-ReplayLoop must wait for a Phase0 repair completion artifact"
Assert-True ($runner.Contains('before_phase0_contract_repair')) "Run-ReplayLoop must preserve pre-repair Phase0 artifacts"
Assert-True ($runner.Contains('ConvertFrom-Json')) "Phase0 repair prompt must require strict JSON parser compatibility"
Assert-True ($runner.Contains('Phase 0 contract repair pass succeeded')) "Run-ReplayLoop must re-run verifier after Phase0 repair"
Assert-True ($runner.Contains('Phase 0 contract verification failed after repair')) "Run-ReplayLoop must fail closed if repair still fails"
Assert-True ($runner.Contains('external_integration') -and $runner.Contains('lifecycle_cleanup_retention')) "Repair prompt must list all productized family ids"
Assert-True ($phase0Prompt.Contains('phase0_family_contract_strict_json')) "Phase0 prompt must contain strict JSON anchor"

[ordered]@{
    status = 'PASS'
    assertions = 9
    cases = @(
        'runner_parse',
        'phase0_repair_prompt',
        'phase0_repair_completion',
        'preserve_pre_repair_artifacts',
        'strict_json_parser_requirement',
        'repair_success_path',
        'repair_fail_closed_path',
        'all_family_ids_listed',
        'phase0_prompt_strict_json_anchor'
    )
} | ConvertTo-Json -Depth 5
