param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$prevalidator = Join-Path $scriptRoot 'Invoke-TestCharterPrevalidator.ps1'
$prevalidatorText = Get-Content -LiteralPath $prevalidator -Raw -Encoding UTF8
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("test-charter-python-v502-" + [guid]::NewGuid().ToString('N'))

try {
    Assert-True 'prevalidator_has_python_launcher_resolution' ($prevalidatorText.Contains('function Resolve-PythonLauncher') -and $prevalidatorText.Contains("'python'") -and $prevalidatorText.Contains("'py'") -and $prevalidatorText.Contains("'python3'"))
    Assert-True 'prevalidator_no_longer_hardcodes_python3_only' ($prevalidatorText.Contains('$python.Command') -and $prevalidatorText.Contains('--output'))

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Write-Text (Join-Path $tempRoot 'TEST_CHARTER.md') @'
# Test Charter

Test Class: SampleFacadeTest

Entry Point: SampleFacade.execute(Long id)

DB Verification: AtomicReference capture verifies output state.

Side Effects:
- verify: assertEquals expected state after execute

Transaction Test: transaction rollback not required for this in-memory behavior proof.
'@

    $outPath = Join-Path $tempRoot 'prevalidator-output.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru > $outPath
    $exitCode = $LASTEXITCODE
    $resultText = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8
    $result = $resultText | ConvertFrom-Json

    Assert-True 'prevalidator_passthru_runs_with_available_python' ($exitCode -eq 0 -and [bool]$result.can_proceed)
    Assert-True 'prevalidator_passthru_stdout_is_json' (-not [string]::IsNullOrWhiteSpace([string]$result.verification_status))

    Write-Host 'PASS: v502 test charter python launcher fallback'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
