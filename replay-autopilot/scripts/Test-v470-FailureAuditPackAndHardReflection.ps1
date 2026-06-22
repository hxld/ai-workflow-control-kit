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
$writeControl = Join-Path $scriptRoot 'Write-ControlPlaneSummary.ps1'
$writeAudit = Join-Path $scriptRoot 'Write-FailureAuditPack.ps1'
$reflectionGate = Join-Path $scriptRoot 'Invoke-ReflectionSufficiencyGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("failure-audit-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $validateJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $writeAudit -EvidenceRoot $tempRoot -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw "Failure audit ValidateOnly failed: $LASTEXITCODE" }
    $validate = $validateJson | ConvertFrom-Json
    Assert-True 'failure_audit_validate_valid' ($validate.status -eq 'VALID')
    $writeAuditText = Get-Content -LiteralPath $writeAudit -Raw -Encoding UTF8
    $writeControlText = Get-Content -LiteralPath $writeControl -Raw -Encoding UTF8
    Assert-True 'failure_audit_classifies_protected_root_isolation' ($writeAuditText -match 'protected_root_isolation_violation' -and $writeAuditText -match 'runner_isolation')
    Assert-True 'control_summary_fingerprints_protected_root_isolation' ($writeControlText -match 'protected_root_isolation_violation' -and $writeControlText -match 'protected_root_pom_forbidden')
    Assert-True 'control_summary_does_not_treat_generic_command_guard_as_protected_root' (-not ($writeControlText -match "'protected_root_isolation_violation'\s*=\s*'[^']*command_guard_violation"))

    $replayRoot = Join-Path $tempRoot 'feature-under-test\claim-codex-replay-v470-test-r01'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'ROUND_RESULT.md') @'
# Round Result

- final_status: BLOCKED
- verification_capped_coverage: 0

Known gaps:
- side_effect_ledger_gap
- exact_contract_gap
'@
    Write-Utf8 (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md') @'
# Final Replay Report

oracle_adjusted_coverage: 12
The replay still has wrong_test_surface and core_entry_unclosed risks.
'@
    Write-Utf8 (Join-Path $replayRoot 'AUTOPILOT_DECISION.md') @'
# Autopilot Decision

- decision: STOP_BLOCKED
- run_evolution_in_replay_loop: True
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $writeControl `
        -EvidenceRoot $tempRoot `
        -MaxRoots 5 `
        -RepeatBlockerThreshold 1 `
        -LowCapThreshold 45 `
        -Quiet
    Assert-True 'control_summary_writes_successfully' ($LASTEXITCODE -eq 0)

    $auditPath = Join-Path $replayRoot 'FAILURE_AUDIT_PACK.json'
    $auditMd = Join-Path $replayRoot 'FAILURE_AUDIT_PACK.md'
    $goldenPath = Join-Path $replayRoot 'NEXT_GOLDEN_DELIVERY_SLICE.json'
    Assert-True 'failure_audit_json_written_to_replay_root' (Test-Path -LiteralPath $auditPath)
    Assert-True 'failure_audit_md_written_to_replay_root' (Test-Path -LiteralPath $auditMd)
    Assert-True 'failure_audit_latest_copy_written' (Test-Path -LiteralPath (Join-Path $tempRoot '_control\FAILURE_AUDIT_PACK_LATEST.json'))
    Assert-True 'golden_slice_generated_for_low_cap' (Test-Path -LiteralPath $goldenPath)

    $audit = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $mustFix = @($audit.must_fix_before_next_replay) -join ','
    Assert-True 'audit_marks_low_cap_as_must_fix' ($mustFix -match 'low_verification_cap')
    Assert-True 'audit_marks_side_effect_as_must_fix' ($mustFix -match 'side_effect_ledger_gap')
    Assert-True 'audit_marks_exact_contract_as_must_fix' ($mustFix -match 'exact_contract_gap')
    Assert-True 'audit_requires_golden_first_slice' ([bool]$audit.golden_first_slice_required)

    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $replayRoot 'EVOLUTION_RESULT_VERIFY.json') -Encoding UTF8
    Write-Utf8 (Join-Path $replayRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

final_status: VALIDATED_TOOLING_EVOLUTION
tooling_changes_applied: true

Changed files:
- scripts/SomeUnrelatedParserFix.ps1

Verification Results: PASS

Root cause: unrelated parser alias.
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $reflectionGate -ReplayRoot $replayRoot | Out-Null
    Assert-True 'reflection_rejects_unrelated_evolution_after_audit' ($LASTEXITCODE -ne 0)
    $badGate = Get-Content -LiteralPath (Join-Path $replayRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'reflection_reports_missing_repeated_blockers' ((@($badGate.issues) -join ' ') -match 'reflection_does_not_address_repeated_blockers')

    Write-Utf8 (Join-Path $replayRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

final_status: VALIDATED_TOOLING_EVOLUTION
tooling_changes_applied: true

## Root Cause
Repeated low_verification_cap comes from zero executable coverage evidence.
Repeated side_effect_ledger_gap comes from tests that do not assert DB/state/API side effect.
Repeated exact_contract_gap comes from missing field/literal/payload assertion.
Repeated wrong_test_surface comes from validating helper/static surfaces instead of a real entry.
Repeated core_entry_unclosed comes from not closing the selected production entry path.

## Tooling Changes Applied
- Add FAILURE_AUDIT_PACK generation before the next replay.
- Add golden first slice binding for low verification cap, side effect proof, and exact contract proof.
- Add reflection gate checks that fail closed when repeated blockers are not addressed.
- Add real entry / test surface closure guidance so helper-only or core-entry-open slices cannot continue.

## Verification Results
- regression test proves unrelated evolution is rejected.
- regression test proves targeted audit + golden slice evolution is accepted.
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $reflectionGate -ReplayRoot $replayRoot | Out-Null
    Assert-True 'reflection_accepts_targeted_evolution_after_audit' ($LASTEXITCODE -eq 0)
    $goodGate = Get-Content -LiteralPath (Join-Path $replayRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'reflection_pass_status_after_targeted_evolution' ($goodGate.status -eq 'PASS')

    Write-Host 'PASS: v470 failure audit pack and hard reflection'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
