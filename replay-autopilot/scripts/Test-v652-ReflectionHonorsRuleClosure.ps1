param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $Value
}

function Write-CommonReplayArtifacts {
    param(
        [string]$ReplayRoot,
        [bool]$PreservedRules,
        [bool]$ClosurePass,
        [string[]]$StagnationRepeated = @()
    )

    New-Item -ItemType Directory -Force -Path $ReplayRoot | Out-Null

    [ordered]@{
        schema = 'replay_stagnation_decision.v1'
        triggered = $true
        reasons = @('low_verification_cap:0')
        repeated_blockers = @($StagnationRepeated)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'STAGNATION_DECISION.json') -Encoding UTF8

    [ordered]@{ status = 'PASS' } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'EVOLUTION_RESULT_VERIFY.json') -Encoding UTF8

    Write-Utf8 (Join-Path $ReplayRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- verification_results: PASS
- changed_files: replay-autopilot/scripts/New-EvolutionProposal.ps1; replay-autopilot/scripts/Validate-VerifiableRuleClosure.ps1
- closed_machine_gates: plan_oracle_overlap_enforced; plan_high_weight_oracle_overlap_enforced; source_chain_context_contract_enforced; sibling_surface_coverage_enforced; blocked_plan_status_stops_replay

## Root Cause

Plan contracts stopped without closeable machine rules for oracle overlap, high-weight coverage, source-chain context, sibling coverage, and blocked plan status.

## Verification Results

- regression test proves missing verifiable rules fail closed.
- regression test proves closed machine gates satisfy the rule-closure validator.
'@

    [ordered]@{
        schema = 'failure_audit_pack.v1'
        golden_first_slice_required = $true
        must_fix_before_next_replay = @('side_effect_ledger_gap', 'plan_format_drift', 'evolution_validation_fail', 'low_verification_cap')
        repeated_blockers = @()
        preserved_existing_verifiable_rules = $PreservedRules
        verifiable_rule_count = 5
        verifiable_rules_path = (Join-Path $ReplayRoot 'VERIFIABLE_RULES.json')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'FAILURE_AUDIT_PACK.json') -Encoding UTF8

    if ($ClosurePass) {
        [ordered]@{
            schema = 'verifiable_rule_closure.v1'
            status = 'PASS'
            required = $true
            reason = 'all_must_fix_rules_closed'
            closed_rules = @(
                [ordered]@{ machine_gate = 'plan_oracle_overlap_enforced'; closure_status = 'CLOSED' },
                [ordered]@{ machine_gate = 'plan_high_weight_oracle_overlap_enforced'; closure_status = 'CLOSED' },
                [ordered]@{ machine_gate = 'source_chain_context_contract_enforced'; closure_status = 'CLOSED' },
                [ordered]@{ machine_gate = 'sibling_surface_coverage_enforced'; closure_status = 'CLOSED' },
                [ordered]@{ machine_gate = 'blocked_plan_status_stops_replay'; closure_status = 'CLOSED' }
            )
            open_rules = @()
            issues = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ReplayRoot 'VERIFIABLE_RULE_CLOSURE.json') -Encoding UTF8
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$gateScript = Join-Path $scriptRoot 'Invoke-ReflectionSufficiencyGate.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("reflection-rule-closure-" + [guid]::NewGuid().ToString('N'))

try {
    $passRoot = Join-Path $tempRoot 'preserved-closure-pass'
    Write-CommonReplayArtifacts -ReplayRoot $passRoot -PreservedRules $true -ClosurePass $true
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $passRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Reflection gate should pass when preserved rule pack has authoritative PASS closure.'
    $passGate = Get-Content -LiteralPath (Join-Path $passRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($passGate.status -eq 'PASS') 'Pass scenario should write REFLECTION_GATE status PASS.'
    Assert-True ([bool]$passGate.authoritative_rule_closure_applied) 'Pass scenario should record authoritative rule closure.'
    Assert-True ([bool]$passGate.failure_audit_must_fix_suppressed) 'Pass scenario should suppress generic failure-audit must-fix blockers.'
    Assert-True (@($passGate.repeated_blockers).Count -eq 0) 'Generic audit blockers should not be promoted when closure is authoritative.'
    Assert-True (-not [bool]$passGate.golden_first_slice_required) 'Generic golden-slice requirement should not survive authoritative closure.'

    $missingClosureRoot = Join-Path $tempRoot 'preserved-closure-missing'
    Write-CommonReplayArtifacts -ReplayRoot $missingClosureRoot -PreservedRules $true -ClosurePass $false
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $missingClosureRoot | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'Reflection gate should fail closed when preserved audit lacks PASS rule closure.'
    $missingGate = Get-Content -LiteralPath (Join-Path $missingClosureRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($missingGate.status -eq 'FAIL') 'Missing-closure scenario should write REFLECTION_GATE status FAIL.'
    Assert-True ((@($missingGate.repeated_blockers) -contains 'side_effect_ledger_gap')) 'Failure-audit blockers should be promoted without PASS closure.'

    $stagnationRepeatedRoot = Join-Path $tempRoot 'stagnation-repeated'
    Write-CommonReplayArtifacts -ReplayRoot $stagnationRepeatedRoot -PreservedRules $true -ClosurePass $true -StagnationRepeated @('side_effect_ledger_gap')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gateScript -ReplayRoot $stagnationRepeatedRoot | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'Reflection gate should still enforce repeated blockers from stagnation evidence.'
    $stagnationGate = Get-Content -LiteralPath (Join-Path $stagnationRepeatedRoot 'REFLECTION_GATE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ((@($stagnationGate.repeated_blockers) -contains 'side_effect_ledger_gap')) 'Stagnation repeated blocker should remain in the gate input.'
    Assert-True ((@($stagnationGate.missing_reflection_for) -contains 'side_effect_ledger_gap')) 'Stagnation repeated blocker should still require reflection evidence.'

    Write-Host 'Test-v652-ReflectionHonorsRuleClosure PASS'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
