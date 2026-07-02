# TODO Placeholder Detector Integration
#
# This script integrates todo_detector.py into the workflow
# Call after GREEN phase to verify no TODO placeholders

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $false)]
    [string[]]$Paths,

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
    $scriptPath = Join-Path $PSScriptRoot "todo_detector.py"

    if (!(Test-Path $scriptPath)) {
        Write-Warning "TODO detector script not found: $scriptPath"
        if ($PassThru) { return $true }
        exit 0
    }

    Write-Host "Running TODO placeholder detection..." -ForegroundColor Cyan

    $pythonArgs = @($scriptPath)

    # If paths specified, check those; otherwise check common implementation dirs
    if ($Paths) {
        $pythonArgs += $Paths
    } else {
        # Default: check example-core implementation directory
        $implDirs = @(
            "example-core\src\main\java",
            "example-domain\src\main\java",
            "example-provider\src\main\java"
        )

        foreach ($dir in $implDirs) {
            if (Test-Path $dir) {
                $pythonArgs += $dir
            }
        }

        # If no directories found, skip
        if ($pythonArgs.Count -eq 1) {
            Write-Warning "No implementation directories found for TODO check"
            if ($PassThru) { return $true }
            exit 0
        }
    }

    $python = Resolve-PythonLauncher
    $result = & $python.Command @($python.Arguments + $pythonArgs) 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "TODO detection: NO PLACEHOLDERS" -ForegroundColor Green
        if ($PassThru) { return $true }
        exit 0
    } else {
        Write-Host "TODO detection: PLACEHOLDERS FOUND" -ForegroundColor Red
        Write-Host $result
        if ($PassThru) { return $false }
        exit 1
    }
}
finally {
    Pop-Location
}
