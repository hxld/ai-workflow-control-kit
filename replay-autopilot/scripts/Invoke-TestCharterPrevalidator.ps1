# Invoke-TestCharterPrevalidator.ps1
# PowerShell wrapper for test_charter_prevalidator.py
# Part of v379 evolution: Test Charter Pre-Validation Gate

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function Resolve-PythonLauncher {
    $candidates = @(
        [pscustomobject]@{ Command = 'python'; Arguments = @() },
        [pscustomobject]@{ Command = 'py'; Arguments = @('-3') },
        [pscustomobject]@{ Command = 'python3'; Arguments = @() }
    )

    foreach ($candidate in $candidates) {
        $commandInfo = Get-Command $candidate.Command -ErrorAction SilentlyContinue
        if ($null -eq $commandInfo) { continue }

        $versionOutput = & $candidate.Command @($candidate.Arguments + @('--version')) 2>&1
        $exitCode = $LASTEXITCODE
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

$gateScript = Join-Path $PSScriptRoot 'test_charter_prevalidator.py'
$testCharterPath = Join-Path $WorkDir 'TEST_CHARTER.md'

if (-not (Test-Path -LiteralPath $gateScript)) {
    if ($PassThru) {
        [ordered]@{
            can_proceed = $true
            verification_status = 'SCRIPT_MISSING'
            failures = @()
            warnings = @()
            failure_count = 0
            warning_count = 0
        } | ConvertTo-Json -Depth 6
        exit 0
    }
    Write-Host "Test charter prevalidator: script missing at $gateScript" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path -LiteralPath $testCharterPath)) {
    if ($PassThru) {
        [ordered]@{
            can_proceed = $false
            verification_status = 'NO_TEST_CHARTER'
            failures = @([ordered]@{ code = 'TEST_CHARTER_MISSING'; message = 'TEST_CHARTER.md is required before RED/test implementation.' })
            warnings = @()
            failure_count = 1
            warning_count = 0
        } | ConvertTo-Json -Depth 6
        exit 1
    }
    Write-Host "Test charter prevalidator: TEST_CHARTER.md not found" -ForegroundColor Red
    exit 1
}

if (-not $PassThru) {
    Write-Host "Running test charter prevalidation..." -ForegroundColor Cyan
}

$python = Resolve-PythonLauncher
$result = & $python.Command @($python.Arguments + @($gateScript, $testCharterPath, '--output', 'json')) 2>&1
$exitCode = $LASTEXITCODE

if ($PassThru) {
    $resultObj = $result | ConvertFrom-Json
    [ordered]@{
        can_proceed = $resultObj.valid
        verification_status = if ($resultObj.valid) { 'PASSED' } else { 'FAILED' }
        failures = $resultObj.failures
        warnings = $resultObj.warnings
        failure_count = $resultObj.failure_count
        warning_count = $resultObj.warning_count
    } | ConvertTo-Json -Depth 12
    exit $exitCode
}

if ($exitCode -eq 0) {
    Write-Host "Test charter prevalidation: PASSED" -ForegroundColor Green
} else {
    Write-Host "Test charter prevalidation: FAILED" -ForegroundColor Red
    $resultObj = $result | ConvertFrom-Json
    if ($resultObj.failures) {
        foreach ($f in $resultObj.failures) {
            Write-Host "  ❌ [$($f.code)]: $($f.message)" -ForegroundColor Red
        }
    }
    if ($resultObj.warnings) {
        foreach ($w in $resultObj.warnings) {
            Write-Host "  ⚠️  [$($w.code)]: $($w.message)" -ForegroundColor Yellow
        }
    }
}

exit $exitCode
