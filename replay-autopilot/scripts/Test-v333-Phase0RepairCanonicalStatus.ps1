$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8

Write-Host "=== v333 Phase0 Repair Canonical Status Test ===" -ForegroundColor Cyan

Write-Host "`n[Test 1] Phase0 repair prompt restricts phase0_status to canonical enum..."
Assert-True ($runLoopText.Contains('phase0_status is a strict machine enum')) 'repair prompt must describe phase0_status as strict machine enum'
Assert-True ($runLoopText.Contains('PROCEED, INVALID_PLAN, or BLOCKED')) 'repair prompt must list allowed phase0_status values'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 2] Phase0 repair prompt explicitly bans caveated custom statuses..."
Assert-True ($runLoopText.Contains('Never write PROCEED_WITH_CAVEATS, PROCEED_WITH_CAVIETS, PARTIAL_PROCEED, READY, or PASS as phase0_status')) 'repair prompt must ban noncanonical caveated/custom statuses'
Assert-True ($runLoopText.Contains('the verifier will reject them')) 'repair prompt must state verifier rejection for noncanonical statuses'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 3] Phase0 repair prompt routes caveats outside the status enum..."
Assert-True ($runLoopText.Contains('keep phase0_status: PROCEED when implementation can continue')) 'repair prompt must keep PROCEED for executable caveated cases'
Assert-True ($runLoopText.Contains('put caveats in required_flags, status_caveats, Uncertainty Ledger, blocker/cap fields, or prose sections')) 'repair prompt must provide non-status caveat locations'
Assert-True ($runLoopText.Contains('Do not encode caveats into the status enum')) 'repair prompt must forbid status-encoded caveats'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 4] Existing verifier still fails closed on noncanonical caveated status..."
$v298 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Test-v298-Phase0CaveatTypoNormalization.ps1') 2>&1
if ($LASTEXITCODE -ne 0) {
    $v298 | Write-Host
    throw 'FAIL: v298 caveat normalization regression failed'
}
$v298Json = ($v298 -join "`n") | ConvertFrom-Json
Assert-True ($v298Json.status -eq 'PASS') 'v298 regression must pass'
Write-Host "PASS" -ForegroundColor Green

[ordered]@{
    status = 'PASS'
    assertions = 8
    cases = @(
        'repair_prompt_declares_phase0_status_strict_enum',
        'repair_prompt_lists_allowed_statuses',
        'repair_prompt_bans_proceed_with_caveats',
        'repair_prompt_bans_typo_caviets',
        'repair_prompt_states_verifier_rejection',
        'repair_prompt_preserves_proceed_with_status_caveats',
        'repair_prompt_forbids_status_encoded_caveats',
        'v298_noncanonical_caveat_fail_closed_regression'
    )
} | ConvertTo-Json -Depth 5
