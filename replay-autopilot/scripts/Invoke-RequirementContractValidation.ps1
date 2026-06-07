<#
.SYNOPSIS
Invoke Requirement Contract Validation (Experiment E3).

.DESCRIPTION
Calls requirement_contract.py to validate exact test names and assertion contracts.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PlanResultPath,
    [Parameter(Mandatory = $true)]
    [string]$RequirementLedgerPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
$pythonScript = Join-Path $scriptDir 'verifier\requirement_contract.py'

if (-not (Test-Path -LiteralPath $pythonScript)) {
    throw "Python script not found: $pythonScript"
}

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        PythonScript = $pythonScript
    } | ConvertTo-Json -Depth 6
    exit 0
}

# Check if Python is available
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        throw "Python not found. Please install Python 3."
    }
}

# Run the validation
$resultJson = & $pythonCmd.Path $pythonScript validate $PlanResultPath $RequirementLedgerPath 2>&1
$result = $resultJson | ConvertFrom-Json

if (-not $result.valid) {
    Write-Host "Requirement Contract Validation FAILED: $($result.reason)"
    if ($result.missing_fields) {
        Write-Host "Missing Fields:"
        foreach ($field in $result.missing_fields) {
            Write-Host "  - $($field.field): $($field.description)"
        }
    }
    if ($result.expected) {
        Write-Host "Expected: $($result.expected)"
    }
    if ($result.actual) {
        Write-Host "Actual: $($result.actual)"
    }
    if ($result.message) {
        Write-Host "Message: $($result.message)"
    }
    exit 1
}

Write-Host "Requirement Contract Validation PASSED"
Write-Host "  Test Name: $($result.test_name)"
Write-Host "  Assertions Count: $($result.assertions_count)"
Write-Host "  Side Effects Count: $($result.side_effects_count)"

exit 0
