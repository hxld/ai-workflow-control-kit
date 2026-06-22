#!/usr/bin/env pwsh

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ''
    )
    if ($Condition) {
        Write-Host "PASS: $Name"
        return
    }
    if ([string]::IsNullOrWhiteSpace($Detail)) {
        throw "FAIL: $Name"
    }
    throw "FAIL: $Name :: $Detail"
}

if ($ValidateOnly) {
    $out = [ordered]@{
        status = 'VALID'
        test = 'v594-noop-evolution-version-guard'
    }
    $out | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autopilotRoot = Resolve-Path (Join-Path $scriptRoot '..')

$promptPath = Join-Path $autopilotRoot 'prompts\skill-evolution.prompt.md'
$runLoopPath = Join-Path $autopilotRoot 'scripts\Run-ReplayLoop.ps1'
$untilPath = Join-Path $autopilotRoot 'scripts\Run-UntilKnowledgeVersion.ps1'
$proposalPath = Join-Path $autopilotRoot 'scripts\New-EvolutionProposal.ps1'
$validatorPath = Join-Path $autopilotRoot 'scripts\Validate-EvolutionResult.ps1'

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
$untilText = Get-Content -LiteralPath $untilPath -Raw -Encoding UTF8
$proposalText = Get-Content -LiteralPath $proposalPath -Raw -Encoding UTF8
$validatorText = Get-Content -LiteralPath $validatorPath -Raw -Encoding UTF8

Write-Host '========================================'
Write-Host 'Test v594: No-op Evolution Version Guard'
Write-Host '========================================'

$expectedVersionToken = [string]::Concat('{', '{', 'EXPECTED_KNOWLEDGE_VERSION', '}', '}')
$expectedActualLine = [string]::Concat('actual_knowledge_version_after_push: ', $expectedVersionToken)
$noopHistoryRequirement = [string]::Concat($expectedVersionToken, '-*-noop-evolution.md')

Assert-True -Name 'prompt_forbids_noop_knowledge_push' -Condition ($promptText.Contains('must not edit/commit/push knowledge repo'))
Assert-True -Name 'prompt_writes_no_version_reason' -Condition ($promptText.Contains('NO_VERSION_ADVANCE_REASON.md'))
Assert-True -Name 'prompt_has_blocked_no_source_status' -Condition ($promptText.Contains('BLOCKED_NO_SOURCE_CHANGE'))
Assert-True -Name 'prompt_rejects_noop_expected_actual_combo' -Condition (($promptText.Contains($expectedActualLine)) -and ($promptText.Contains('NO_SOURCE_CHANGE')))
Assert-True -Name 'prompt_mentions_noop_history_as_forbidden' -Condition (($promptText.Contains($noopHistoryRequirement)) -and ($promptText.Contains('must not edit/commit/push knowledge repo')))

$runLoopHasGuard = ($runLoopText.Contains('No-op version advance guard')) -and ($runLoopText.Contains('must not edit/commit/push knowledge repo'))
$runLoopHasBlockedLines = ($runLoopText.Contains('final_status: BLOCKED_NO_SOURCE_CHANGE')) -and ($runLoopText.Contains('tooling_changes_applied: false'))
Assert-True -Name 'run_loop_repair_forbids_noop_push' -Condition $runLoopHasGuard
Assert-True -Name 'run_loop_repair_has_blocked_lines' -Condition $runLoopHasBlockedLines

$untilHasGuard = ($untilText.Contains('No-op version advance guard')) -and ($untilText.Contains('must not edit/commit/push knowledge repo'))
$untilHasBlockedLines = ($untilText.Contains('final_status: BLOCKED_NO_SOURCE_CHANGE')) -and ($untilText.Contains('tooling_changes_applied: false'))
Assert-True -Name 'until_runner_repair_forbids_noop_push' -Condition $untilHasGuard
Assert-True -Name 'until_runner_repair_has_blocked_lines' -Condition $untilHasBlockedLines

$proposalHasGuard = ($proposalText.Contains('no_op_version_guard')) -and ($proposalText.Contains('must not advance knowledge version'))
Assert-True -Name 'proposal_forbids_noop_version_advance' -Condition $proposalHasGuard
Assert-True -Name 'validator_rejects_no_source_change' -Condition ($validatorText.Contains('no_source_change_cannot_satisfy_stop_and_evolve'))

$tmpBase = Join-Path $autopilotRoot '.tmp'
$tmpRoot = Join-Path $tmpBase ([string]::Concat('Test-v594-NoopEvolutionVersionGuard-', [System.Guid]::NewGuid().ToString('N')))
$tmpFull = [System.IO.Path]::GetFullPath($tmpRoot)
$tmpBaseFull = [System.IO.Path]::GetFullPath($tmpBase)

try {
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
    $knowledgeRoot = Join-Path $tmpRoot 'knowledge'
    New-Item -ItemType Directory -Force -Path $knowledgeRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $knowledgeRoot 'CURRENT_VERSION.md') -Encoding UTF8 -Value "**Version**: v998`n"

    Set-Content -LiteralPath (Join-Path $tmpRoot 'STOP_OR_CONTINUE_DECISION.md') -Encoding UTF8 -Value "STOP_AND_EVOLVE`nRequired Before Next Round`n"
    Set-Content -LiteralPath (Join-Path $tmpRoot 'AUTOPILOT_DECISION.md') -Encoding UTF8 -Value "- expected_knowledge_version_after_evolution: v999`n- run_evolution_in_replay_loop: True`n- decision: STOP_FOR_EVOLUTION`n"
    Set-Content -LiteralPath (Join-Path $tmpRoot 'EVOLUTION_PROMPT.md') -Encoding UTF8 -Value "knowledge repo: $knowledgeRoot`nexpected next knowledge version: v999`n"

    $fakeResult = @(
        '- final_status: VALIDATED_TOOLING_EVOLUTION'
        '- tooling_changes_applied: false'
        '- stop_and_evolve_satisfied: true'
        '- verification_results: PASS'
        '- changed_files: none'
        '- pushed_commit: abcdef123456'
        '- actual_knowledge_version_after_push: v999'
        '- note: NO_SOURCE_CHANGE noop-evolution no-source-change audit only'
    ) -join "`n"
    Set-Content -LiteralPath (Join-Path $tmpRoot 'EVOLUTION_RESULT.md') -Encoding UTF8 -Value $fakeResult

    & powershell -NoProfile -ExecutionPolicy Bypass -File $validatorPath -ReplayRoot $tmpRoot | Out-Host
    Assert-True -Name 'validator_failed_noop_fixture' -Condition ($LASTEXITCODE -ne 0) -Detail "LASTEXITCODE=$LASTEXITCODE"

    $verify = Get-Content -LiteralPath (Join-Path $tmpRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($verify.issues)
    Assert-True -Name 'validator_reports_no_source_issue' -Condition ($issues -contains 'no_source_change_cannot_satisfy_stop_and_evolve') -Detail ($issues -join ', ')
    Assert-True -Name 'validator_reports_missing_tooling_change' -Condition ($issues -contains 'tooling_changes_applied_missing_or_false') -Detail ($issues -join ', ')
    Assert-True -Name 'validator_reports_version_file_mismatch' -Condition ($issues -contains 'actual_knowledge_version_file_not_expected:v999') -Detail ($issues -join ', ')
}
finally {
    if ($tmpFull.StartsWith($tmpBaseFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tmpRoot)) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

Write-Host ''
Write-Host '========================================'
Write-Host 'All v594 tests PASSED'
Write-Host '========================================'

$result = [ordered]@{
    status = 'PASS'
    version = 'v594'
    assertions = @(
        'prompt_forbids_noop_knowledge_push',
        'repair_prompts_forbid_noop_knowledge_push',
        'proposal_forbids_noop_version_advance',
        'validator_rejects_no_source_change_fixture'
    )
}
$result | ConvertTo-Json -Depth 5

exit 0
