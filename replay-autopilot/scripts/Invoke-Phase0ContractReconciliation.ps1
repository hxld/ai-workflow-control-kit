<#
.SYNOPSIS
    Contract Reconciliation Pipeline - Phase 0 artifact cross-validation.

.DESCRIPTION
    Validates that REQUIREMENT_FAMILY_LEDGER.json and FAMILY_CONTRACT.json
    do not contradict each other before Phase 1 begins.

    Experiment 1 from NEXT_EXPERIMENT_PLAN.md - addresses v318's contract contradiction blocker.

.PARAMETER ReplayRoot
    Path to the replay root directory containing the artifacts.

.PARAMETER FailOnContradiction
    If specified, exits with error code 1 when contradictions are found.

.OUTPUTS
    System.Collections.Hashtable
    Returns reconciliation result with status, contradictions, and metrics.

.EXAMPLE
    $result = Invoke-Phase0ContractReconciliation -ReplayRoot "<REPLAY_EVIDENCE_ROOT>"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [switch]$FailOnContradiction
)

$ErrorActionPreference = 'Stop'

$ledgerPath = Join-Path $ReplayRoot "REQUIREMENT_FAMILY_LEDGER.json"
$contractPath = Join-Path $ReplayRoot "FAMILY_CONTRACT.json"
$scriptPath = Join-Path $PSScriptRoot "reconcile_phase0_artifacts.py"
$outputPath = Join-Path $ReplayRoot "RECONCILIATION_RESULT.json"
$pythonResolver = Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'
if (Test-Path -LiteralPath $pythonResolver) {
    . $pythonResolver
} else {
    throw "Python launcher resolver missing: $pythonResolver"
}

# Check if artifacts exist
if (-not (Test-Path -LiteralPath $ledgerPath)) {
    Write-Warning "Phase0ContractReconciliation: REQUIREMENT_FAMILY_LEDGER.json not found, skipping reconciliation"
    return @{ status = "SKIP"; reason = "ledger_not_found" }
}

if (-not (Test-Path -LiteralPath $contractPath)) {
    Write-Warning "Phase0ContractReconciliation: FAMILY_CONTRACT.json not found, skipping reconciliation"
    return @{ status = "SKIP"; reason = "contract_not_found" }
}

# Check if Python script exists
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Warning "Phase0ContractReconciliation: reconcile_phase0_artifacts.py not found at $scriptPath"
    return @{ status = "SKIP"; reason = "script_not_found" }
}

# Run Python reconciliation script. The Python helper writes operational notes to
# stderr even on expected exits, so capture native stderr without letting
# $ErrorActionPreference abort before we can inspect $LASTEXITCODE.
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$python = Resolve-PythonLauncher
$output = & $python.Command @($python.Arguments + @($scriptPath, $ledgerPath, $contractPath, '--output', $outputPath)) 2>&1
$pythonExitCode = $LASTEXITCODE
$ErrorActionPreference = $oldErrorActionPreference

if ($pythonExitCode -eq 0 -or $pythonExitCode -eq 1) {
    # Parse the JSON output
    try {
        if (Test-Path -LiteralPath $outputPath) {
            $result = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            $jsonText = ($output | Where-Object { $_ -match '^\s*[\{\[]' }) -join "`n"
            $result = $jsonText | ConvertFrom-Json
        }
        Write-Host "Phase0ContractReconciliation: $($result.status) - $($result.contradiction_count) contradictions, $($result.warning_count) warnings"

        if ($result.status -eq "RESOLVE") {
            Write-Host "Phase0ContractReconciliation: Contradictions detected:"
            foreach ($c in $result.contradictions) {
                Write-Host "  - $($c.family): $($c.issue) (severity: $($c.severity))"
            }
        }

        if ($FailOnContradiction -and $result.status -eq "RESOLVE") {
            Write-Error "Phase0ContractReconciliation: Contradiction rate $($result.contradiction_rate)% exceeds threshold"
        }

        return $result
    } catch {
        Write-Warning "Phase0ContractReconciliation: Failed to parse output - $_"
        return @{ status = "ERROR"; reason = "parse_failed"; output = $output }
    }
} else {
    Write-Warning "Phase0ContractReconciliation: Script execution failed with exit code $pythonExitCode"
    return @{ status = "ERROR"; reason = "script_failed"; exit_code = $pythonExitCode }
}
