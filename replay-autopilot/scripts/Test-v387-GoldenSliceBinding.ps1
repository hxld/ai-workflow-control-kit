param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "FAIL: $Name"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param(
        [string]$Path,
        [string]$Value
    )
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$planPrompt = Join-Path $repoRoot 'prompts\phase-plan-tournament.prompt.md'
$runReplayLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

$planPromptText = Get-Content -LiteralPath $planPrompt -Raw -Encoding UTF8
$runReplayLoopText = Get-Content -LiteralPath $runReplayLoop -Raw -Encoding UTF8
$verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8

Assert-True -Name 'plan_prompt_has_golden_binding_section' -Condition ($planPromptText -match 'Golden Delivery Slice Binding')
Assert-True -Name 'plan_prompt_requires_plan_result_binding' -Condition ($planPromptText -match 'PLAN_RESULT.md.*golden_slice_binding|golden_slice_binding: <rule fingerprint')
Assert-True -Name 'plan_prompt_requires_first_slice_binding' -Condition ($planPromptText -match 'FIRST_SLICE_PROOF_PLAN.md.*golden_slice_binding|golden_slice_binding: <rule fingerprint')
Assert-True -Name 'repair_prompt_reads_golden_snapshots' -Condition ($runReplayLoopText -match 'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md' -and $runReplayLoopText -match 'NEXT_GOLDEN_DELIVERY_SLICE.md')
Assert-True -Name 'repair_prompt_requires_golden_binding' -Condition ($runReplayLoopText -match 'golden_slice_binding: <rule fingerprint')
Assert-True -Name 'verifier_checks_golden_snapshot' -Condition ($verifierText -match 'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md')
Assert-True -Name 'verifier_reports_missing_binding_issues' -Condition ($verifierText -match 'golden_slice_binding_missing:plan_result' -and $verifierText -match 'golden_slice_binding_missing:first_slice_proof')

$tempRoot = Join-Path $env:TEMP ("replay-v387-golden-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    Write-Utf8 -Path (Join-Path $tempRoot 'GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md') -Value @'
# Golden Delivery Slice

First Slice Contract
positive first-slice
side_effect_ledger_gap -> exact_contract_gap -> low_verification_cap
'@

    Write-Utf8 -Path (Join-Path $tempRoot 'FAMILY_CONTRACT.json') -Value @'
{
  "selected_real_entry": "DemoService.handle",
  "first_executable_slice": "S1",
  "families": [
    {
      "id": "core_entry",
      "required": true,
      "proof_required": ["real_entry_behavior"]
    }
  ]
}
'@

    foreach ($name in @('PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md', 'PLAN_SELECTION.md')) {
        Write-Utf8 -Path (Join-Path $tempRoot $name) -Value 'candidate: core_entry DemoService.handle'
    }
    Write-Utf8 -Path (Join-Path $tempRoot 'REPLAY_PLAN.md') -Value 'slice: S1 core_entry DemoService.handle stateful_side_effect'
    Write-Utf8 -Path (Join-Path $tempRoot 'IMPLEMENTATION_CONTRACT.md') -Value 'contract: DemoService.handle core_entry stateful_side_effect'
    Write-Utf8 -Path (Join-Path $tempRoot 'EXPECTED_DIFF_MATRIX.md') -Value 'DemoService.java -> DemoTest.test -> stateful_side_effect'
    Write-Utf8 -Path (Join-Path $tempRoot 'SIDE_EFFECT_LEDGER.md') -Value 'DemoService.handle -> writes status -> assert stateful side effect'
    Write-Utf8 -Path (Join-Path $tempRoot 'TEST_CHARTER.md') -Value 'RED DemoTest.test then GREEN through real entry and stateful side effect'

    $planWithoutBinding = @'
plan_status: PROCEED
selected_strategy: core-transaction-first
carrier_search: performed
carrier_search_queries: rg "DemoService"; rg "handle"; rg "stateful"
existing_production_carriers: DemoService.handle
selected_carrier_from_search: DemoService.handle
new_service_proposed: false
new_service_justification: none
oracle_production_file_overlap: 100%
oracle_high_weight_coverage: 100%
oracle_missing_high_weight_files: none
oracle_expansion_plan: none
oracle_out_of_scope_files: none
first_slice: S1
first_red_test: DemoTest.test
'@
    $proofWithoutBinding = @'
first_slice: S1
highest_weight_open_gate: core_entry
selected_real_entry: DemoService.handle
selected_carrier: DemoService.handle
target_subsurface_or_carrier: DemoService.handle
production_boundary: DemoService.java
proof_kind: stateful_side_effect
real_carrier_kind: production_service_method
first_red_test: DemoTest.test
public_entry_contract_coverage: not_public_entry_with_reason
forbidden_substitute_check: passed
required_sibling_surfaces: none_with_reason
minimum_side_effect_or_blocker: DemoService.handle writes status and test asserts it
expected_production_diff: DemoService.java
red_expectation: DemoTest fails before DemoService writes status
green_minimum_implementation: update DemoService.handle and DemoTest
forbidden_substitute_proof: uses real entry and production side effect
fail_closed_condition: block if DemoService.handle is not used
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: DemoService.handle
pattern_return_type: void
pattern_error_handling: exception_propagation
pattern_evidence_source: rg "class DemoService" example-server/src/main/java
'@

    Write-Utf8 -Path (Join-Path $tempRoot 'PLAN_RESULT.md') -Value $planWithoutBinding
    Write-Utf8 -Path (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Value $proofWithoutBinding
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $tempRoot -Stage Plan | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True -Name 'verifier_flags_missing_plan_binding' -Condition (@($verify.issues) -contains 'golden_slice_binding_missing:plan_result')
    Assert-True -Name 'verifier_flags_missing_first_slice_binding' -Condition (@($verify.issues) -contains 'golden_slice_binding_missing:first_slice_proof')

    $binding = 'golden_slice_binding: side_effect_ledger_gap -> DemoService.handle -> DemoTest.test -> update DemoService.java -> stateful_side_effect writes status'
    Write-Utf8 -Path (Join-Path $tempRoot 'PLAN_RESULT.md') -Value ($planWithoutBinding + "`n" + $binding)
    Write-Utf8 -Path (Join-Path $tempRoot 'FIRST_SLICE_PROOF_PLAN.md') -Value ($proofWithoutBinding + "`n" + $binding)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $tempRoot -Stage Plan | Out-Null
    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $goldenIssues = @($verify.issues | Where-Object { $_ -match '^golden_slice_binding_' })
    Assert-True -Name 'verifier_accepts_explicit_golden_binding' -Condition ($goldenIssues.Count -eq 0)
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: v387 golden slice binding'
