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

function Resolve-PythonLauncher {
    $candidates = @(
        [pscustomobject]@{ Command = 'python'; Arguments = @() },
        [pscustomobject]@{ Command = 'py'; Arguments = @('-3') },
        [pscustomobject]@{ Command = 'python3'; Arguments = @() }
    )

    foreach ($candidate in $candidates) {
        $commandInfo = Get-Command $candidate.Command -ErrorAction SilentlyContinue
        if ($null -eq $commandInfo) { continue }

        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $versionOutput = & $candidate.Command @($candidate.Arguments + @('--version')) 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference

        $versionText = ($versionOutput | Out-String).Trim()
        if ($exitCode -eq 0 -and $versionText -match '^Python\s+3\.') {
            return [pscustomobject]@{
                Command = $candidate.Command
                Arguments = @($candidate.Arguments)
                Version = $versionText
            }
        }
    }

    throw 'No usable Python 3 launcher found. Tried python, py -3, python3.'
}

function Test-JsonInputFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-JsonInputFile -Path $PlanResultPath)) {
    Write-Host "Requirement Contract Validation SKIPPED: PLAN_RESULT_NOT_JSON"
    Write-Host "  PlanResultPath: $PlanResultPath"
    Write-Host "  Reason: requirement_contract.py requires machine-readable PLAN_RESULT.json; Markdown PLAN_RESULT.md is handled by later plan-artifact repair/schema gates."
    exit 0
}

if (-not (Test-JsonInputFile -Path $RequirementLedgerPath)) {
    Write-Host "Requirement Contract Validation FAILED: REQUIREMENT_LEDGER_NOT_JSON"
    Write-Host "  RequirementLedgerPath: $RequirementLedgerPath"
    exit 1
}

# Check if Python is available
$python = Resolve-PythonLauncher

# Run the validation
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$resultJson = & $python.Command @($python.Arguments + @($pythonScript, 'validate', $PlanResultPath, $RequirementLedgerPath)) 2>&1
$pythonExitCode = $LASTEXITCODE
$ErrorActionPreference = $oldPreference

try {
    $result = $resultJson | ConvertFrom-Json
} catch {
    Write-Host "Requirement Contract Validation FAILED: PYTHON_OUTPUT_NOT_JSON"
    Write-Host "  Python: $($python.Command) $($python.Arguments -join ' ')"
    Write-Host "  ExitCode: $pythonExitCode"
    Write-Host "  Output:"
    $resultJson | ForEach-Object { Write-Host "  $_" }
    exit 1
}

if ($pythonExitCode -ne 0 -or -not $result.valid) {
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
