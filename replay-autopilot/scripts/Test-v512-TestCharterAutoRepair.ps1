param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )
    if (-not $Condition) {
        throw "ASSERT FAILED: $Name"
    }
    Write-Host "PASS: $Name"
}

function Read-Text {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Assert-Parses {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "ASSERT FAILED: parse $Path -> $($errors[0].Message)"
    }
    Write-Host "PASS: parses $Path"
}

$sliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$prevalidator = Join-Path $scriptRoot 'Invoke-TestCharterPrevalidator.ps1'

$sliceText = Read-Text $sliceLoop
$runText = Read-Text $runLoop

Assert-Parses $sliceLoop
Assert-Parses $runLoop

Assert-True 'test charter repair function exists' ($sliceText.Contains('function Invoke-TestCharterRepairGate'))
Assert-True 'repair prompt requires Entry Point label' ($sliceText.Contains('Entry Point: <exact production entry method(s)>'))
Assert-True 'repair prompt runs prevalidator passthru' ($sliceText.Contains('Invoke-TestCharterPrevalidator.ps1') -and $sliceText.Contains('-PassThru'))
Assert-True 'pre-implementation gate attempts repair before blocking' ($sliceText.Contains('Test charter prevalidation failed before executor') -and $sliceText.Contains('pre-implementation test charter gate stopped before executor'))
Assert-True 'forced-family repair path attempts test charter repair' ($sliceText.Contains('Test charter prevalidation failed after forced-family repair') -and $sliceText.Contains('test_charter_repair_attempt'))

Assert-True 'phase1 gate evidence classifier exists' ($runText.Contains('function Get-Phase1GateFailureEvidence'))
Assert-True 'phase1 blocker can classify test charter failure' ($runText.Contains('test_charter_prevalidation_failed') -and $runText.Contains('TEST_CHARTER_VALIDATION_*.stdout.log'))
Assert-True 'plan contract repair prompt requires test charter prevalidation' ($runText.Contains('TEST_CHARTER.md must pass') -and $runText.Contains('Entry Point: <exact production entry method(s)>'))

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v512-charter-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    @'
Test Class: SampleFacadeTest
DB Verification: AtomicReference capture verifies output state.
Side Effects:
- verify policy number is captured
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'TEST_CHARTER.md') -Encoding UTF8

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru 2>&1
    $exit = $LASTEXITCODE
    $json = ($output | Out-String) | ConvertFrom-Json
    $codes = @($json.failures | ForEach-Object { [string]$_.code })
    Assert-True 'prevalidator still fails missing entry point' ($exit -ne 0 -and ($codes -contains 'MISSING_ENTRY_POINT'))

    @'
Entry Point: SampleFacade.execute(Long id)
Test Class: SampleFacadeTest
DB Verification: AtomicReference capture verifies output state.
Side Effects:
- verify policy number is captured
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'TEST_CHARTER.md') -Encoding UTF8

    $output2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $tempRoot -PassThru 2>&1
    $exit2 = $LASTEXITCODE
    $json2 = ($output2 | Out-String) | ConvertFrom-Json
    Assert-True 'prevalidator passes with v512 required labels' ($exit2 -eq 0 -and [bool]$json2.can_proceed)
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'v512 test charter auto-repair regression passed.'
