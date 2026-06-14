param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '.tmp\v315-evolution-result-strictness'),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function New-TestRoot {
    param([string]$Name)
    $root = Join-Path $TestRoot $Name
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    @"
# Autopilot Decision

- run_evolution_in_replay_loop: True
- decision: STOP_BLOCKED
- expected_knowledge_version_after_evolution: v315
"@ | Set-Content -LiteralPath (Join-Path $root 'AUTOPILOT_DECISION.md') -Encoding UTF8
    return $root
}

$testDir = $PSScriptRoot
$scriptsDir = Join-Path $testDir '..\..'
$promptsDir = Join-Path $testDir '..\..\..\prompts'
$validator = Join-Path $scriptsDir 'Validate-EvolutionResult.ps1'

if ($ValidateOnly) {
    $v = New-TestRoot 'validate-only'
    @"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: replay-autopilot/scripts\Validate-EvolutionResult.ps1
- pushed_commit: abcdef1234567890
- actual_knowledge_version_after_push: v315
"@ | Set-Content -LiteralPath (Join-Path $v 'EVOLUTION_RESULT.md') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $v *> $null
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$invalid = New-TestRoot 'invalid'
@"
# Evolution Result

## Machine-Readable Status
```
final_status: VALIDATED_TOOLING_EVOLUTION
tooling_changes_applied: true
changed_files: replay-autopilot/scripts\plan_contract_verify.py
stop_and_evolve_satisfied: true
verification_results: PASS (manual review)
actual_knowledge_version_after_push: v314 (commit blocked by environment)
```

- knowledge_repo_commit: BLOCKED by environment hook/protection
- Push status: Not attempted
- Files modified: changelog.md (uncommitted)
- Next steps: runner should integrate these scripts before the gate is effective.
"@ | Set-Content -LiteralPath (Join-Path $invalid 'EVOLUTION_RESULT.md') -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $invalid *> $null
Assert-True ($LASTEXITCODE -ne 0) 'STOP_BLOCKED evolution with blocked commit must fail validation'
$invalidVerify = Get-Content -LiteralPath (Join-Path $invalid 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($invalidVerify.issues -contains 'pushed_commit_missing_or_blocked') 'missing pushed_commit must be reported'
Assert-True ($invalidVerify.issues -contains 'knowledge_repo_commit_or_push_blocked') 'commit/push blocker must be reported'
Assert-True ($invalidVerify.issues -contains 'actual_knowledge_version_after_push_not_expected:v315') 'actual knowledge version mismatch must be reported'
Assert-True ($invalidVerify.issues -contains 'changed_tooling_not_runner_invoked:plan_contract_verify.py') 'uninvoked plan_contract_verify.py changes must be reported'
Assert-True ($invalidVerify.issues -contains 'tooling_not_integrated_into_runner') 'deferred runner integration must be reported'

$valid = New-TestRoot 'valid'
@"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: replay-autopilot/scripts\Validate-EvolutionResult.ps1; replay-autopilot\prompts\skill-evolution.prompt.md
- pushed_commit: abcdef1234567890
- actual_knowledge_version_after_push: v315
"@ | Set-Content -LiteralPath (Join-Path $valid 'EVOLUTION_RESULT.md') -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $valid *> $null
Assert-True ($LASTEXITCODE -eq 0) 'valid pushed evolution result should pass'

$runLoopText = Get-Content -LiteralPath (Join-Path $scriptsDir 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
Assert-True ($runLoopText.Contains('- pushed_commit: <knowledge repo commit hash>')) 'repair prompt must require pushed_commit'
Assert-True ($runLoopText.Contains('commit/push is blocked')) 'repair prompt must reject blocked commit as VALIDATED'

$promptText = Get-Content -LiteralPath (Join-Path $promptsDir 'skill-evolution.prompt.md') -Raw -Encoding UTF8
Assert-True ($promptText.Contains('actual_knowledge_version_after_push')) 'evolution prompt must require actual knowledge version after push'
Assert-True ($promptText.Contains('runner/verifier')) 'evolution prompt must require runner-invoked tooling changes'
Assert-True ($promptText.Contains('manual review')) 'evolution prompt must reject manual-only verification'

[ordered]@{
    status = 'PASS'
    assertions = 8
    cases = @(
        'invalid_stop_blocked_fails',
        'missing_pushed_commit_reported',
        'commit_push_blocker_reported',
        'knowledge_version_mismatch_reported',
        'tooling_not_runner_invoked_reported',
        'deferred_integration_reported',
        'valid_pushed_evolution_passes',
        'repair_prompt_requires_pushed_commit',
        'repair_prompt_rejects_blocked_commit',
        'evolution_prompt_requires_actual_version',
        'evolution_prompt_requires_runner_invoked',
        'evolution_prompt_rejects_manual_only'
    )
} | ConvertTo-Json -Depth 5
