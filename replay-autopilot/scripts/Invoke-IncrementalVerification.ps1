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

$pythonResolver = Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'
if (Test-Path -LiteralPath $pythonResolver) {
    . $pythonResolver
} else {
    throw "Python launcher resolver missing: $pythonResolver"
}

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

    $python = Resolve-PythonLauncher
    $result = & $python.Command @($python.Arguments + $pythonArgs) 2>&1
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
