param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'scripts'
$prompts = Join-Path $root 'prompts'

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )
    if ($Text -notmatch $Pattern) {
        throw "Assertion failed: $Name"
    }
    return $Name
}

$cases = New-Object System.Collections.Generic.List[string]

$prompt = Get-Content -LiteralPath (Join-Path $prompts 'phase1-slice-executor.prompt.md') -Raw -Encoding UTF8
$verify = Get-Content -LiteralPath (Join-Path $scripts 'Verify-SliceClosure.ps1') -Raw -Encoding UTF8
$preAuth = Get-Content -LiteralPath (Join-Path $scripts 'Authorize-PreSliceEvidence.ps1') -Raw -Encoding UTF8
$parser = Get-Content -LiteralPath (Join-Path $scripts 'Parse-ReplayReport.ps1') -Raw -Encoding UTF8
$stopLoss = Get-Content -LiteralPath (Join-Path $scripts 'Test-ReplayStopLoss.ps1') -Raw -Encoding UTF8

$cases.Add((Assert-Contains 'prompt_has_v276_red_repair_gate' $prompt 'v276 RED Repair and Behavior Test Charter Gate')) | Out-Null
$cases.Add((Assert-Contains 'prompt_allows_test_only_red_repair' $prompt 'test-only RED repair')) | Out-Null
$cases.Add((Assert-Contains 'prompt_requires_behavior_test_charter' $prompt 'behavior_test_charter')) | Out-Null
$cases.Add((Assert-Contains 'prompt_forbids_non_authorizing_charter' $prompt 'mock-only, helper-only, static-only')) | Out-Null

$cases.Add((Assert-Contains 'verifier_allows_repaired_red_after_blocked_attempt' $verify '\$redBlocked -and -not \$redFailed')) | Out-Null
$cases.Add((Assert-Contains 'verifier_detects_behavior_test_charter_missing' $verify 'behavior_test_charter_missing')) | Out-Null
$cases.Add((Assert-Contains 'verifier_emits_behavior_test_charter_gap' $verify 'behavior_test_charter_gap')) | Out-Null
$cases.Add((Assert-Contains 'verifier_outputs_behavior_charter_readiness' $verify 'behavior_test_charter_ready')) | Out-Null

$cases.Add((Assert-Contains 'preauth_reports_non_rank1_forced_family_as_warning' $preAuth 'forced_family_not_rank1')) | Out-Null
$cases.Add((Assert-Contains 'parser_counts_behavior_test_charter_gap' $parser 'behavior_test_charter_gap')) | Out-Null
$cases.Add((Assert-Contains 'stoploss_counts_behavior_test_charter_gap' $stopLoss 'behavior\[-_ \]test\[-_ \]charter')) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 6
