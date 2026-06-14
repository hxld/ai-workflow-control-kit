$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestRoot {
    param([string]$Name, [string]$KnowledgeRoot, [string]$ExpectedVersion = 'v322')
    $root = Join-Path $env:TEMP ("replay-v322-{0}-{1}" -f $Name, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    @"
# Autopilot Decision

- run_evolution_in_replay_loop: True
- decision: STOP_BLOCKED
- expected_knowledge_version_after_evolution: $ExpectedVersion
"@ | Set-Content -LiteralPath (Join-Path $root 'AUTOPILOT_DECISION.md') -Encoding UTF8
    @"
你现在要执行 replay 后的技能进化。

【输入】
- knowledge repo: $KnowledgeRoot
- expected next knowledge version: $ExpectedVersion
"@ | Set-Content -LiteralPath (Join-Path $root 'EVOLUTION_PROMPT.md') -Encoding UTF8
    return $root
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$validator = Join-Path $scriptRoot 'Validate-EvolutionResult.ps1'
$greenScript = Join-Path $scriptRoot 'verify_green_phase.py'

$runSliceText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
Assert-True ($runSliceText.Contains('Invoke-GreenPhaseNoMockGate')) 'Run-SliceLoop must call the green phase no-mock gate'
Assert-True ($runSliceText.Contains('verify_green_phase.py')) 'Run-SliceLoop must invoke verify_green_phase.py, not only mention it in prompts'
Assert-True ($runSliceText.Contains('GREEN_PHASE_VERIFY_{0:D2}.json')) 'Run-SliceLoop must persist GREEN_PHASE_VERIFY evidence'
Assert-True ($runSliceText.Contains('mock_only_implementation_gap')) 'Run-SliceLoop must convert green-gate failure into verifier gap flags'

$mockFile = Join-Path $env:TEMP ("mock-only-{0}.java" -f ([guid]::NewGuid().ToString('N')))
@"
class MockOnly {
    Object run() {
        // TODO: actual database insert
        return null; // TODO
    }
}
"@ | Set-Content -LiteralPath $mockFile -Encoding UTF8
& python $greenScript check $mockFile *> $null
Assert-True ($LASTEXITCODE -ne 0) 'verify_green_phase.py must reject TODO/mock-only implementation'
Remove-Item -LiteralPath $mockFile -Force

$validKnowledge = Join-Path $env:TEMP ("knowledge-v322-valid-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $validKnowledge | Out-Null
"**Version**: v322" | Set-Content -LiteralPath (Join-Path $validKnowledge 'CURRENT_VERSION.md') -Encoding UTF8

$mismatchKnowledge = Join-Path $env:TEMP ("knowledge-v322-mismatch-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $mismatchKnowledge | Out-Null
"**Version**: v321" | Set-Content -LiteralPath (Join-Path $mismatchKnowledge 'CURRENT_VERSION.md') -Encoding UTF8

$mismatchRoot = New-TestRoot -Name 'version-mismatch' -KnowledgeRoot $mismatchKnowledge
@"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: D:\opt\replay-autopilot\scripts\Run-SliceLoop.ps1
- pushed_commit: abcdef123456
- actual_knowledge_version_after_push: v322
"@ | Set-Content -LiteralPath (Join-Path $mismatchRoot 'EVOLUTION_RESULT.md') -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $mismatchRoot *> $null
Assert-True ($LASTEXITCODE -ne 0) 'validator must reject EVOLUTION_RESULT when CURRENT_VERSION.md was not advanced'
$mismatchVerify = Get-Content -LiteralPath (Join-Path $mismatchRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($mismatchVerify.issues -contains 'actual_knowledge_version_file_not_expected:v322') 'validator must report CURRENT_VERSION mismatch'

$probeScript = Join-Path $scriptRoot 'zz_unintegrated_v322_probe.py'
try {
    'print("probe")' | Set-Content -LiteralPath $probeScript -Encoding UTF8
    $uninvokedRoot = New-TestRoot -Name 'uninvoked-tool' -KnowledgeRoot $validKnowledge
    @"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: $probeScript
- pushed_commit: abcdef123456
- actual_knowledge_version_after_push: v322
"@ | Set-Content -LiteralPath (Join-Path $uninvokedRoot 'EVOLUTION_RESULT.md') -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $uninvokedRoot *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'validator must reject changed tooling that is not invoked by runner/verifier/prompt'
    $uninvokedVerify = Get-Content -LiteralPath (Join-Path $uninvokedRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($uninvokedVerify.issues -contains 'changed_tooling_not_runner_invoked:zz_unintegrated_v322_probe.py') 'validator must report uninvoked changed script'
} finally {
    Remove-Item -LiteralPath $probeScript -Force -ErrorAction SilentlyContinue
}

$validRoot = New-TestRoot -Name 'valid' -KnowledgeRoot $validKnowledge
@"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: D:\opt\replay-autopilot\scripts\Run-SliceLoop.ps1; D:\opt\replay-autopilot\scripts\Validate-EvolutionResult.ps1
- pushed_commit: abcdef123456
- actual_knowledge_version_after_push: v322
"@ | Set-Content -LiteralPath (Join-Path $validRoot 'EVOLUTION_RESULT.md') -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $validRoot *> $null
Assert-True ($LASTEXITCODE -eq 0) 'valid integrated tooling evolution should pass validation'

Write-Host 'v322 GreenPhaseGateIntegration tests passed'
