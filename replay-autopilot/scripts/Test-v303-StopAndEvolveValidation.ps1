param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Text {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$validator = Join-Path $PSScriptRoot 'Validate-EvolutionResult.ps1'
$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
$untilRunner = Join-Path $PSScriptRoot 'Run-UntilKnowledgeVersion.ps1'
$prompt = Join-Path (Split-Path -Parent $PSScriptRoot) 'prompts\skill-evolution.prompt.md'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v303-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $noStopRoot = Join-Path $tmp 'no-stop'
    New-Item -ItemType Directory -Force -Path $noStopRoot | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $noStopRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Validator should pass when STOP_AND_EVOLVE is not required'

    $blockedRoot = Join-Path $tmp 'blocked-noop'
    New-Item -ItemType Directory -Force -Path $blockedRoot | Out-Null
    Write-Text (Join-Path $blockedRoot 'STOP_OR_CONTINUE_DECISION.md') @'
# Decision

## Decision: STOP_AND_EVOLVE
Required Before Next Round:
- Implement Experiment 1
'@
    Write-Text (Join-Path $blockedRoot 'NEXT_EXPERIMENT_PLAN.md') @'
# Next Experiment Plan

## Experiment 1: Pre-Slice Cap Display
'@
    Write-Text (Join-Path $blockedRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

**EVOLUTION_TYPE**: `TOOLING_EVOLUTION_NEEDED + NO_SKILL_SOURCE_CHANGE`

- final_status: VALIDATED_KNOWLEDGE_ONLY
- verification_results: PASS
- actual_knowledge_version_after_push: v303
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $blockedRoot | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'Validator must reject no-source-change when STOP_AND_EVOLVE requires experiments'
    $verifyText = Get-Content -LiteralPath (Join-Path $blockedRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8
    Assert-True ($verifyText.Contains('tooling_changes_applied_missing_or_false')) 'Validator should report missing tooling changes'

    $validRoot = Join-Path $tmp 'valid-tooling'
    New-Item -ItemType Directory -Force -Path $validRoot | Out-Null
    Write-Text (Join-Path $validRoot 'STOP_OR_CONTINUE_DECISION.md') '## Decision: STOP_AND_EVOLVE'
    Write-Text (Join-Path $validRoot 'NEXT_EXPERIMENT_PLAN.md') '## Experiment 1: Pre-Slice Cap Display'
    Write-Text (Join-Path $validRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1; replay-autopilot/prompts/skill-evolution.prompt.md
- pushed_commit: abc1234def5678
- actual_knowledge_version_after_push: v303
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $validRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Validator should accept validated tooling evolution'

    $knowledgeRoot = Join-Path $tmp 'knowledge-repo'
    New-Item -ItemType Directory -Force -Path $knowledgeRoot | Out-Null
    Write-Text (Join-Path $knowledgeRoot 'CURRENT_VERSION.md') @'
# Current Knowledge Version

**Version**: v303
'@
    git -C $knowledgeRoot init | Out-Null
    git -C $knowledgeRoot add CURRENT_VERSION.md | Out-Null
    git -C $knowledgeRoot -c user.name='Replay Test' -c user.email='replay@example.invalid' commit -m 'seed knowledge' | Out-Null
    $localCommit = (git -C $knowledgeRoot rev-parse HEAD).Trim()

    $localOnlyRoot = Join-Path $tmp 'local-only-knowledge'
    New-Item -ItemType Directory -Force -Path $localOnlyRoot | Out-Null
    Write-Text (Join-Path $localOnlyRoot 'STOP_OR_CONTINUE_DECISION.md') '## Decision: STOP_AND_EVOLVE'
    Write-Text (Join-Path $localOnlyRoot 'NEXT_EXPERIMENT_PLAN.md') '## Experiment 1: Pre-Slice Cap Display'
    Write-Text (Join-Path $localOnlyRoot 'EVOLUTION_PROMPT.md') @"
# Evolution Prompt

- knowledge repo: $knowledgeRoot
- current knowledge version: v303
- expected next knowledge version: v303
"@
    Write-Text (Join-Path $localOnlyRoot 'EVOLUTION_RESULT.md') @"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1
- pushed_commit: local-only:$localCommit
- actual_knowledge_version_after_push: v303 (remote push failed)
"@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $localOnlyRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Validator should accept clean local knowledge commit when remote push failed'
    $localOnlyVerify = Get-Content -LiteralPath (Join-Path $localOnlyRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8
    Assert-True ($localOnlyVerify.Contains('knowledge_repo_push_failed_local_commit_accepted')) 'Validator should warn when accepting local-only knowledge commit'

    $runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
    $untilRunnerText = Get-Content -LiteralPath $untilRunner -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8
    Assert-True ($runnerText.Contains('Validate-EvolutionResult.ps1')) 'Run-ReplayLoop must call evolution result validator'
    Assert-True ($untilRunnerText.Contains('Validate-EvolutionResult.ps1')) 'Run-UntilKnowledgeVersion must call evolution result validator'
    Assert-True ($promptText.Contains('{{AUTOPILOT_ROOT}}')) 'Evolution prompt must expose replay autopilot root'
    Assert-True ($promptText.Contains('stop_and_evolve_satisfied')) 'Evolution prompt must require stop_and_evolve_satisfied marker'
    Assert-True ($promptText.Contains('gate_budget_decision')) 'Evolution prompt must require gate budget decision marker'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = 10
    cases = @(
        'no_stop_passes',
        'stop_and_evolve_noop_rejected',
        'stop_and_evolve_validated_tooling_passes',
        'local_knowledge_commit_push_failure_passes',
        'run_replayloop_calls_validator',
        'run_until_calls_validator',
        'prompt_exposes_autopilot_root',
        'prompt_requires_stop_and_evolve_marker',
        'prompt_requires_gate_budget_marker'
    )
} | ConvertTo-Json -Depth 5
