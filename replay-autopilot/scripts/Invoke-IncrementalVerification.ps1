# Incremental Verification Gate Integration
#
# This script integrates incremental_verifier.py into the TDD cycle
# Call after RED, GREEN, and before synthesis

param(
    [Parameter(Mandatory = $true)]
    [string]$Phase,

    [Parameter(Mandatory = $false)]
    [string[]]$Files,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$validPhases = @('RED', 'GREEN', 'SIDE_EFFECT')
if ($Phase -notin $validPhases) {
    Write-Error "Invalid phase: $Phase. Must be one of: $($validPhases -join ', ')"
    exit 1
}

# Ensure we're in the work directory
Push-Location $WorkDir

try {
    $scriptPath = Join-Path $PSScriptRoot "incremental_verifier.py"

    if (!(Test-Path $scriptPath)) {
        Write-Warning "Incremental verifier script not found: $scriptPath"
        if ($PassThru) { return $true }
        exit 0
    }

    Write-Host "Running $Phase phase verification..." -ForegroundColor Cyan

    $pythonArgs = @($scriptPath, $Phase)
    if ($Files) {
        $pythonArgs += $Files
    }

    $result = & python3 @pythonArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "$Phase verification: PASSED" -ForegroundColor Green
        if ($PassThru) { return $true }
        exit 0
    } else {
        Write-Host "$Phase verification: FAILED" -ForegroundColor Red
        Write-Host $result
        if ($PassThru) { return $false }
        exit 1
    }
}
finally {
    Pop-Location
}
