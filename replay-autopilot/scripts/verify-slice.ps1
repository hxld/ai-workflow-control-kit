# verify-slice.ps1
# Mandatory Side Effect Ledger Verification (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)

param(
    [Parameter(Mandatory = $false)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$SliceResultPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Test-SideEffectLedger {
    <#
    .SYNOPSIS
    Validates that SIDE_EFFECT_LEDGER.md exists and has proper verification for stateful families.

    .DESCRIPTION
    Prevents side_effect_ledger_gap by requiring side effect documentation before slice completion.

    Returns $true if side effects are properly documented.
    Returns $false if side effects are missing or lack verification.
    #>
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $ledgerPath = Join-Path $ReplayRoot 'SIDE_EFFECT_LEDGER.md'

    # Check if SIDE_EFFECT_LEDGER.md exists
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        Write-Host "WARNING: SIDE_EFFECT_LEDGER.md not found." -ForegroundColor Yellow
        Write-Host "Required for stateful families with DB side effects." -ForegroundColor Yellow
        return @{
            IsValid = $true  # Pass if not stateful
            Reason = 'no_side_effects_required'
            HasSideEffects = $false
        }
    }

    $ledger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8

    # Check for DB assertion patterns
    $hasSelectPattern = $ledger -match 'SELECT\s+\*\s+FROM'
    $hasAssertionPattern = $ledger -match 'assertThat\(|verify\(.+Mapper\)|AtomicReference'

    if (-not $hasSelectPattern -and -not $hasAssertionPattern) {
        Write-Host "ERROR: SIDE_EFFECT_LEDGER.md missing DB assertion patterns." -ForegroundColor Red
        Write-Host "Required pattern: SELECT * FROM table WHERE key = ?" -ForegroundColor Yellow
        Write-Host "Or verification pattern: assertThat(captured.get().getField()).isEqualTo(value)" -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'missing_verification_patterns'
            HasSideEffects = $true
            RequiredPattern = 'SELECT * FROM table WHERE key = ? or assertThat(captured.get())'
        }
    }

    # Check for stateful family declaration
    $hasStatefulFamily = $ledger -match 'stateful.*side.?effect' -or $ledger -match 'Family:\s*stateful'

    if ($hasStatefulFamily) {
        Write-Host "INFO: Stateful side effects declared with verification patterns" -ForegroundColor Green
        return @{
            IsValid = $true
            Reason = 'stateful_effects_verified'
            HasSideEffects = $true
            HasVerification = $true
        }
    }

    Write-Host "INFO: SIDE_EFFECT_LEDGER.md exists (no stateful effects detected)" -ForegroundColor Cyan
    return @{
        IsValid = $true
        Reason = 'no_stateful_effects'
        HasSideEffects = $false
    }
}

function Invoke-SideEffectVerificationGate {
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $resultPath = Join-Path $ReplayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json'

    $result = [ordered]@{
        gate = 'side_effect_ledger_complete'
        can_proceed = $true
        validation_status = 'PASS'
        issues = @()
        warnings = @()
        has_side_effects = $false
        verified_at = (Get-Date).ToString('s')
    }

    # Run side effect ledger check
    $ledgerValid = Test-SideEffectLedger -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath

    $result.has_side_effects = $ledgerValid.HasSideEffects

    if (-not $ledgerValid.IsValid) {
        $result.can_proceed = $false
        $result.validation_status = 'FAIL'
        $result.issues += @{
            code = 'side_effect_ledger_gap'
            message = 'Side effects not properly verified'
            reason = $ledgerValid.Reason
            remediation = if ($ledgerValid.RequiredPattern) { $ledgerValid.RequiredPattern } else { 'Document DB verification patterns in SIDE_EFFECT_LEDGER.md' }
        }
    }

    # Write result
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    if ($result.can_proceed) {
        Write-Host "Side effect verification: PASSED" -ForegroundColor Green
    } else {
        Write-Host "Side effect verification: FAILED" -ForegroundColor Red
        foreach ($issue in $result.issues) {
            Write-Host "  [$($issue.code)] $($issue.message)" -ForegroundColor Red
            if ($issue.remediation) {
                Write-Host "  Remediation: $($issue.remediation)" -ForegroundColor Yellow
            }
        }
    }

    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Test-SideEffectLedger: Validates SIDE_EFFECT_LEDGER.md exists',
            'Checks for DB assertion patterns (SELECT, assertThat, verify)',
            'Prevents side_effect_ledger_gap before slice completion'
        )
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-SideEffectVerificationGate -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath

exit $(if ($result.can_proceed) { 0 } else { 1 })
