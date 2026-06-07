# Slice Zero-Delta Evaluation
# Implements Experiment 2: Zero Executable Delta Enforcement After Blocked RED
#
# This script enforces zero-delta rule when RED is blocked

param(
    [Parameter(Mandatory = $true)]
    [string]$SliceResultPath,

    [Parameter(Mandatory = $true)]
    [string]$Phase0ContractPath
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$sliceResultPathFull = Resolve-AbsolutePath $SliceResultPath
$phase0ContractPathFull = Resolve-AbsolutePath $Phase0ContractPath

# Read inputs
$sliceResult = Get-Content -LiteralPath $sliceResultPathFull -Raw -Encoding UTF8 | ConvertFrom-Json
$phase0Contract = Get-Content -LiteralPath $phase0ContractPathFull -Raw -Encoding UTF8 | ConvertFrom-Json
$redTest = @($sliceResult.tests | Where-Object { ([string]$_.phase).ToUpperInvariant() -eq 'RED' } | Select-Object -First 1)
$greenTest = @($sliceResult.tests | Where-Object { ([string]$_.phase).ToUpperInvariant() -eq 'GREEN' } | Select-Object -First 1)
$implemented = @($sliceResult.implemented_files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

# Build input for Python script
$inputData = @{
    slice_id = $sliceResult.slice_id
    red_result = @{
        status = if ($redTest.Count -gt 0) { [string]$redTest[0].result } else { 'missing' }
        command = if ($redTest.Count -gt 0) { [string]$redTest[0].command } else { '' }
        output = if ($redTest.Count -gt 0) { [string]$redTest[0].evidence } else { '' }
    }
    green_result = if ($greenTest.Count -gt 0) { $greenTest[0] } else { @{} }
    implementation_files = $implemented
    phase0_contract = $phase0Contract
} | ConvertTo-Json -Depth 10

# Locate the Python script
$scriptDir = Split-Path -Parent $PSCommandPath
$pythonScript = Join-Path $scriptDir 'evaluate_slice_result.py'

if (-not (Test-Path -LiteralPath $pythonScript)) {
    throw "Python script not found: $pythonScript"
}

# Run the Python evaluation
$env:PYTHONIOENCODING = 'utf-8'
$tempInput = [System.IO.Path]::GetTempFileName()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempInput, $inputData, $utf8NoBom)
$resultJson = & python $pythonScript --input $tempInput 2>&1
$exitCode = $LASTEXITCODE
Remove-Item -LiteralPath $tempInput -Force -ErrorAction SilentlyContinue

# Parse result
try {
    $result = ($resultJson -join "`n") | ConvertFrom-Json
} catch {
    throw "Unable to parse zero-delta JSON: $($_.Exception.Message). Raw output: $($resultJson -join ' ')"
}

# Update slice result with zero-delta enforcement
if ($result.zero_delta_enforced) {
    $sliceResult | Add-Member -NotePropertyName 'implementation_allowed' -NotePropertyValue $result.slice_result.implementation_allowed -Force
    $sliceResult | Add-Member -NotePropertyName 'executable_delta' -NotePropertyValue $result.slice_result.executable_delta -Force
    $sliceResult | Add-Member -NotePropertyName 'stop_reason' -NotePropertyValue $result.slice_result.stop_reason -Force
    $sliceResult | Add-Member -NotePropertyName 'slice_status' -NotePropertyValue 'BLOCKED' -Force
    $sliceResult | Add-Member -NotePropertyName 'coverage_delta' -NotePropertyValue 0 -Force

    if ($result.blockers) {
        $existingGapFlags = @($sliceResult.gap_flags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $sliceResult | Add-Member -NotePropertyName 'gap_flags' -NotePropertyValue (@($existingGapFlags + @($result.blockers) + @('tooling_enforcement_stop')) | Select-Object -Unique) -Force
    }

    # Add zero-delta enforcement flag
    $sliceResult | Add-Member -NotePropertyName 'zero_delta_enforced' -NotePropertyValue $true -Force
}

# Write updated slice result
$sliceResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sliceResultPathFull -Encoding UTF8

# Log output
if ($result.zero_delta_enforced) {
    Write-Host "Zero-Delta: BLOCKED - RED was blocked, implementation disallowed"
    Write-Host "  Blockers: $($result.blockers -join ', ')"

    if ($result.red_blocked_by_environment) {
        Write-Host "  Environment blockers: $($result.environment_blockers -join ', ')"
    }

    exit 1  # Exit with error to signal block
}

Write-Host "Zero-Delta: ALLOW - RED passed, implementation allowed"
exit 0
