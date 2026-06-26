param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Name"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repoRoot = Split-Path -Parent $scriptRoot
$promptPath = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$runnerPath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

Assert-True 'runner_injects_replay_autopilot_scripts_template_value' (
    $runnerText.Contains('REPLAY_AUTOPILOT_SCRIPTS = $PSScriptRoot')
)

Assert-True 'prompt_uses_absolute_carrier_signature_tool_path' (
    $promptText.Contains('{{REPLAY_AUTOPILOT_SCRIPTS}}\verify_carrier_signature.py')
)

Assert-True 'prompt_uses_absolute_v348_quality_gate_path' (
    $promptText.Contains('{{REPLAY_AUTOPILOT_SCRIPTS}}\v348_slice_quality_gate.ps1')
)

Assert-True 'prompt_uses_absolute_test_charter_prevalidator_path' (
    $promptText.Contains('{{REPLAY_AUTOPILOT_SCRIPTS}}\Invoke-TestCharterPrevalidator.ps1')
)

Assert-True 'prompt_prefers_runner_owned_gate_artifacts' (
    $promptText.Contains('runner-owned artifacts') -and
    $promptText.Contains('PRE_S1_CARRIER_SIGNATURE_AUTHORIZATION.json') -and
    $promptText.Contains('CARRIER_INVOCATION_CONTRACT_01.json')
)

Assert-True 'prompt_does_not_block_on_worktree_relative_scripts_directory' (
    -not $promptText.Contains('python scripts/verify_carrier_signature.py --input') -and
    -not $promptText.Contains('.\scripts\v348_slice_quality_gate.ps1 -SliceDir') -and
    -not $promptText.Contains('scripts\Invoke-TestCharterPrevalidator.ps1 -WorkDir {{REPLAY_ROOT}} -PassThru')
)

Write-Host 'v659 Phase1 prompt tool path regression passed.'
