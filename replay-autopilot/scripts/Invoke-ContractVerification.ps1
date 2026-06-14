# Contract Verification Gate Integration
#
# This script integrates pre_flight_contract_check.py into the replay workflow
# Call before Phase 1 (RED phase) starts

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$pythonResolver = Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'
if (Test-Path -LiteralPath $pythonResolver) {
    . $pythonResolver
} else {
    throw "Python launcher resolver missing: $pythonResolver"
}

# Ensure we're in the work directory
Push-Location $WorkDir

try {
    $scriptPath = Join-Path $PSScriptRoot "pre_flight_contract_check.py"

    if (!(Test-Path $scriptPath)) {
        Write-Warning "Contract verification script not found: $scriptPath"
        if ($PassThru) { return $false }
        exit 0
    }

    # Check if TEST_CHARTER.md exists
    if (!(Test-Path "TEST_CHARTER.md")) {
        Write-Warning "TEST_CHARTER.md not found in $WorkDir"
        if ($PassThru) { return $true }  # Skip verification if no charter
        exit 0
    }

    Write-Host "Running contract verification..." -ForegroundColor Cyan

    $python = Resolve-PythonLauncher
    $result = & $python.Command @($python.Arguments + @($scriptPath)) 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "Contract verification: PASSED" -ForegroundColor Green
        if ($PassThru) { return $true }
        exit 0
    } else {
        Write-Host "Contract verification: FAILED" -ForegroundColor Red
        Write-Host $result
        if ($PassThru) { return $false }
        exit 1
    }
}
finally {
    Pop-Location
}
