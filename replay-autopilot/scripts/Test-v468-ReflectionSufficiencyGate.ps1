param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$gateScript = Join-Path $scriptRoot 'Invoke-ReflectionSufficiencyGate.ps1'
$runnerScript = Join-Path $scriptRoot 'Run-UnattendedReplayControl.ps1'
$configPath = Join-Path (Split-Path -Parent $scriptRoot) 'config.yaml'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reflection-gate-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $tempRoot -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw "Reflection gate ValidateOnly failed: $LASTEXITCODE" }
    $validate = $validateJson | ConvertFrom-Json
    Assert-True 'reflection_gate_validate_valid' ($validate.status -eq 'VALID')

    $badRoot = Join-Path $tempRoot 'bad'
    New-Item -ItemType Directory -Force -Path $badRoot | Out-Null
    [ordered]@{
        schema = 'replay_stagnation_decision.v1'
        triggered = $true
        reasons = @('low_verification_cap:0', 'repeated_blockers:side_effect_ledger_gap,exact_contract_gap,plan_format_drift,evolution_validation_fail,low_verification_cap')
        repeated_blockers = @('side_effect_ledger_gap', 'exact_contract_gap', 'plan_format_drift', 'evolution_validation_fail', 'low_verification_cap')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $badRoot 'STAGNATION_DECISION.json') -Encoding UTF8
    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $badRoot 'EVOLUTION_RESULT_VERIFY.json') -Encoding UTF8
    Write-Utf8 (Join-Path $badRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

final_status: VALIDATED_TOOLING_EVOLUTION
tooling_changes_applied: true

Changed files:
- Verify-PlanContract.ps1

Verification Results: PASS

Root cause: stale oracle overlap blocker detection.
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $badRoot | Out-Null
    Assert-True 'reflection_gate_rejects_unrelated_evolution' ($LASTEXITCODE -ne 0)
    $badGate = Get-Content -LiteralPath (Join-Path $badRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'bad_gate_status_fail' ($badGate.status -eq 'FAIL')
    Assert-True 'bad_gate_writes_deep_reflection_required' (Test-Path -LiteralPath (Join-Path $badRoot 'DEEP_REFLECTION_REQUIRED.md'))
    Assert-True 'bad_gate_names_repeated_blocker_gap' ((@($badGate.issues) -join ' ') -match 'reflection_does_not_address_repeated_blockers')

    $goodRoot = Join-Path $tempRoot 'good'
    New-Item -ItemType Directory -Force -Path $goodRoot | Out-Null
    [ordered]@{
        schema = 'replay_stagnation_decision.v1'
        triggered = $true
        reasons = @('low_verification_cap:0', 'repeated_blockers:plan_format_drift,low_verification_cap')
        repeated_blockers = @('plan_format_drift', 'low_verification_cap')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $goodRoot 'STAGNATION_DECISION.json') -Encoding UTF8
    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $goodRoot 'EVOLUTION_RESULT_VERIFY.json') -Encoding UTF8
    [ordered]@{
        schema = 'failure_audit_pack.v1'
        golden_first_slice_required = $true
        must_fix_before_next_replay = @('plan_format_drift', 'low_verification_cap')
        repeated_blockers = @('plan_format_drift', 'low_verification_cap')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $goodRoot 'FAILURE_AUDIT_PACK.json') -Encoding UTF8
    [ordered]@{
        schema = 'golden_delivery_slice.v1'
        repeated_blockers = @('plan_format_drift', 'low_verification_cap')
        rules = @(
            [ordered]@{ fingerprint = 'plan_format_drift'; focus = 'machine plan contract' },
            [ordered]@{ fingerprint = 'low_verification_cap'; focus = 'first executable golden slice' }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $goodRoot 'NEXT_GOLDEN_DELIVERY_SLICE.json') -Encoding UTF8
    Write-Utf8 (Join-Path $goodRoot 'NEXT_GOLDEN_DELIVERY_SLICE.md') @'
# Golden Delivery Slice

plan_format_drift -> machine-readable schema.
low_verification_cap -> first executable side-effect proof.
'@
    Write-Utf8 (Join-Path $goodRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

final_status: VALIDATED_TOOLING_EVOLUTION
tooling_changes_applied: true

## Root Cause
Repeated plan_format_drift comes from Markdown/regex parsing of PLAN_RESULT and FIRST_SLICE_PROOF.
Repeated low_verification_cap comes from allowing zero-cap plans to continue without a golden first slice.

## Tooling Changes Applied
- Add JSON schema machine-readable plan contract validation.
- Add fail-closed reflection gate for zero cap / coverage cap stagnation.

## Verification Results
- regression test: old Markdown-only plan is rejected.
- regression test: JSON schema plan with first slice and side effect passes.
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $goodRoot | Out-Null
    Assert-True 'reflection_gate_accepts_targeted_evolution' ($LASTEXITCODE -eq 0)
    $goodGate = Get-Content -LiteralPath (Join-Path $goodRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'good_gate_status_pass' ($goodGate.status -eq 'PASS')

    $runnerText = Get-Content -LiteralPath $runnerScript -Raw -Encoding UTF8
    Assert-True 'runner_invokes_reflection_gate' ($runnerText -match 'Invoke-ReflectionSufficiencyGate\.ps1')
    Assert-True 'runner_blocks_on_reflection_failure' ($runnerText -match 'REFLECTION_GATE_REQUIRED')
    Assert-True 'runner_prevents_continue_on_reflection_failure' ($runnerText -match 'not \$reflectionGateFailed')

    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    Assert-True 'config_enables_reflection_gate' ($configText -match 'control_reflection_gate_enabled:\s*true')

    Write-Host 'PASS: v468 reflection sufficiency gate'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
