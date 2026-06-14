# Carrier Search Requirement Integration
#
# This script integrates carrier_search.py into the workflow
# Call before creating new service classes

param(
    [Parameter(Mandatory = $true)]
    [string]$FeatureName,

    [Parameter(Mandatory = $false)]
    [string[]]$RequiredMethods,

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
    $scriptPath = Join-Path $PSScriptRoot "carrier_search.py"

    if (!(Test-Path $scriptPath)) {
        Write-Warning "Carrier search script not found: $scriptPath"
        if ($PassThru) { return $true }
        exit 0
    }

    Write-Host "Running carrier search for: $FeatureName" -ForegroundColor Cyan

    $pythonArgs = @($scriptPath, $FeatureName)
    if ($RequiredMethods) {
        $pythonArgs += $RequiredMethods
    }

    $python = Resolve-PythonLauncher
    $result = & $python.Command @($python.Arguments + $pythonArgs) 2>&1
    $exitCode = $LASTEXITCODE

    # Exit code 0 = OK to create new carrier (NO_EXISTING_CARRIER or CARRIER_INADEQUATE)
    # Exit code 1 = Existing carrier adequate, should NOT create new one

    if ($exitCode -eq 0) {
        Write-Host "Carrier search: OK to proceed" -ForegroundColor Green
        Write-Host $result
        if ($PassThru) { return $true }
        exit 0
    } else {
        Write-Host "Carrier search: USE EXISTING CARRIER" -ForegroundColor Yellow
        Write-Host $result
        Write-Host ""
        Write-Host "Action: Use existing service instead of creating new one"
        if ($PassThru) { return $false }
        exit 1  # Non-zero exit means "do not create new carrier"
    }
}
finally {
    Pop-Location
}
