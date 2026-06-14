param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$parsePath = Join-Path $scriptRoot 'Parse-ReplayReport.ps1'
$runnerPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$stopLossPath = Join-Path $scriptRoot 'Test-ReplayStopLoss.ps1'
$verifySlicePath = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$phase1PromptPath = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        parser = $parsePath
        runner = $runnerPath
        stop_loss = $stopLossPath
        verifier = $verifySlicePath
        phase1_prompt = $phase1PromptPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$tmpRoot = Join-Path $repoRoot '.tmp\v275-parser-red-gate'
if (Test-Path -LiteralPath $tmpRoot) {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

try {
    @'
# ROUND_RESULT

- phase0_status: `PROCEED`
- oracle_used: `false`
- blind_self_assessed_coverage: `10`
- verification_capped_coverage: `0`  (`min(10, 0)`)
- final_status: `BLOCKED`
'@ | Set-Content -LiteralPath (Join-Path $tmpRoot 'ROUND_RESULT.md') -Encoding UTF8

    @'
# FINAL_REPLAY_REPORT

| Metric | Value |
|---|---|
| **Final Status** | BLOCKED |
| **Production Match** | 100% |

- Oracle Test Coverage: NONE
- oracle_adjusted_coverage: `100`
'@ | Set-Content -LiteralPath (Join-Path $tmpRoot 'FINAL_REPLAY_REPORT.md') -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $parsePath -ReplayRoot $tmpRoot | Out-Null
    $summary = Get-Content -LiteralPath (Join-Path $tmpRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8

    Assert-True ($summary -match '(?m)^-\s*verification_capped_coverage:\s*0\s*$') `
        'Parser must read verification_capped_coverage even when the metric line has trailing explanatory text'
    Assert-True ($summary -match '(?m)^-\s*oracle_adjusted_coverage:\s*0\s*$') `
        'Parser must evidence-cap oracle coverage to 0 when verification cap is 0'
    Assert-True ($summary -match '(?m)^-\s*reported_oracle_adjusted_coverage:\s*100\s*$') `
        'Parser must preserve the originally reported oracle score'
    Assert-True ($summary -match '(?m)^-\s*final_status:\s*BLOCKED\s*$') `
        'Parser must read Final Status from Markdown table rows before falling back to weaker status sources'
    Assert-True ($summary -match '(?m)^-\s*production_match:\s*100\s*$') `
        'Parser must capture production match from Markdown table rows'
    Assert-True ($summary -match '(?m)^-\s*replay_classification:\s*production_match_only\s*$') `
        'Parser must classify oracle-zero-test plus 100% production match as production_match_only'
    Assert-True ($summary -match '(?m)^-\s*requires_evolution:\s*True\s*$') `
        'production_match_only replay must require workflow evolution'
} finally {
    if (Test-Path -LiteralPath $tmpRoot) {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force
    }
}

$parser = Get-Content -LiteralPath $parsePath -Raw -Encoding UTF8
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$stopLoss = Get-Content -LiteralPath $stopLossPath -Raw -Encoding UTF8
$verifySlice = Get-Content -LiteralPath $verifySlicePath -Raw -Encoding UTF8
$phase1Prompt = Get-Content -LiteralPath $phase1PromptPath -Raw -Encoding UTF8

Assert-True ($parser -match '\(\?:\\s\+\[\^\\r\\n\]\*\)') `
    'Parse-ReplayReport metric regex must allow trailing inline explanations'
Assert-True ($runner -match '\(\?:\\s\+\[\^\\r\\n\]\*\)') `
    'Run-ReplayLoop metric regex must allow trailing inline explanations'
Assert-True ($stopLoss -match 'implementation_after_blocked_red') `
    'Stop-loss gap counting must include implementation_after_blocked_red'
Assert-True ($verifySlice -match 'implementation_after_blocked_red') `
    'Slice verifier must emit implementation_after_blocked_red'
Assert-True ($verifySlice -match 'implementation_allowed') `
    'Slice verifier must expose implementation_allowed'
Assert-True ($verifySlice -match 'redBlocked') `
    'Slice verifier must detect blocked RED results'
Assert-True ($phase1Prompt -match 'v275 RED Business Assertion Gate') `
    'Phase1 prompt must include the v275 RED business assertion gate'
Assert-True ($phase1Prompt -match 'do not edit production files') `
    'Phase1 prompt must forbid edits after non-authorizing RED'

[ordered]@{
    status = 'PASS'
    assertions = 15
    cases = @(
        'parse_trailing_verification_metric',
        'parser_oracle_cap_after_trailing_metric',
        'parser_preserves_reported_oracle',
        'parser_final_status_table_row',
        'parser_production_match_table_row',
        'parser_production_match_only_classification',
        'parser_production_match_only_requires_evolution',
        'parser_metric_regex_trailing_text',
        'runner_metric_regex_trailing_text',
        'stop_loss_counts_blocked_red_edit',
        'verifier_flags_blocked_red_edit',
        'verifier_exposes_implementation_allowed',
        'verifier_detects_red_blocked',
        'phase1_prompt_red_business_gate',
        'phase1_prompt_forbids_edits_after_bad_red'
    )
} | ConvertTo-Json -Depth 6
