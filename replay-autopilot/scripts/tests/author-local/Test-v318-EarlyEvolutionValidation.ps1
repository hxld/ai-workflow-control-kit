param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '.tmp\v318-early-evolution-validation'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$testDir = $PSScriptRoot
$scriptsDir = Join-Path $testDir '..\..'
$promptsDir = Join-Path $testDir '..\..\..\prompts'
$runLoopPath = Join-Path $scriptsDir 'Run-ReplayLoop.ps1'
$validatorPath = Join-Path $scriptsDir 'Validate-EvolutionResult.ps1'
$promptPath = Join-Path $promptsDir 'skill-evolution.prompt.md'

$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
$validationCalls = [regex]::Matches($runLoopText, 'Invoke-EvolutionResultValidationOrRepair').Count
Assert-True ($validationCalls -ge 5) 'Run-ReplayLoop must validate normal helper plus early-stop evolution branches'
Assert-True ($runLoopText.Contains('Knowledge version refreshed for next round after plan early-stop evolution')) 'plan early-stop refresh path must still exist'
Assert-True ($runLoopText.Contains('if (-not $evolutionValidationOk) { break }')) 'early-stop branches must stop when evolution validation fails'
Assert-True ($runLoopText.Contains('runner should integrate scripts later')) 'repair prompt must reject deferred runner integration'

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
Assert-True ($promptText.Contains('runner should integrate')) 'skill evolution prompt must reject deferred integration success reports'

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

@"
# Autopilot Decision

- run_evolution_in_replay_loop: True
- decision: STOP_BLOCKED
- expected_knowledge_version_after_evolution: v318
"@ | Set-Content -LiteralPath (Join-Path $TestRoot 'AUTOPILOT_DECISION.md') -Encoding UTF8
@"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: replay-autopilot/scripts\enforce_red_phase_gate.py
- pushed_commit: abcdef1
- actual_knowledge_version_after_push: v318

Next steps: runner should integrate these scripts before they affect replay execution.
"@ | Set-Content -LiteralPath (Join-Path $TestRoot 'EVOLUTION_RESULT.md') -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File $validatorPath -ReplayRoot $TestRoot *> $null
Assert-True ($LASTEXITCODE -ne 0) 'deferred runner integration must fail evolution validation'
$verify = Get-Content -LiteralPath (Join-Path $TestRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($verify.issues -contains 'tooling_not_integrated_into_runner') 'deferred integration issue must be reported'

$verifyText = Get-Content -LiteralPath (Join-Path $scriptsDir 'Verify-PlanContract.ps1') -Raw -Encoding UTF8
Assert-True (-not $verifyText.Contains('blind_mode_oracle_overlap')) 'invalid v318 blind-mode oracle exemption must not remain in verifier'

[ordered]@{
    status = 'PASS'
    assertions = 7
    cases = @(
        'run_loop_validation_call_count',
        'plan_early_stop_refresh_path',
        'early_stop_break_on_failure',
        'repair_rejects_deferred_integration',
        'prompt_rejects_deferred_integration',
        'deferred_integration_evolution_fails',
        'no_blind_mode_oracle_exemption'
    )
} | ConvertTo-Json -Depth 5
