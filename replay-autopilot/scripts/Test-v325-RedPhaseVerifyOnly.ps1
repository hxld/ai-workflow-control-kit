<#
.SYNOPSIS
    Regression tests for v325 RED phase VerifyOnly gate.

.DESCRIPTION
    Ensures VerifyOnly mode is actually verify-only: it must not run Maven,
    must write RED_PHASE_GATE_XX.json on both pass and fail, and must fail
    closed for structural RED evidence or no GREEN implementation.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== v325 RED Phase VerifyOnly Test ===" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host "FAIL: Invoke-RedPhaseHardGate.ps1 not found" -ForegroundColor Red
    exit 1
}

function Write-SliceResult {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Gate {
    param([string]$ReplayRoot, [string]$SliceResultPath, [int]$Index)
    $stdout = Join-Path $ReplayRoot ("gate-$Index.stdout.log")
    $stderr = Join-Path $ReplayRoot ("gate-$Index.stderr.log")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -VerifyOnly -SliceResultPath $SliceResultPath -ReplayRoot $ReplayRoot -SliceIndex $Index > $stdout 2> $stderr
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Stdout = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 } else { '' }
        Stderr = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 } else { '' }
        JsonPath = Join-Path $ReplayRoot ("RED_PHASE_GATE_{0:D2}.json" -f $Index)
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("red-phase-v325-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Write-Host "`n[Test 1] Structural RED pass fails closed and writes JSON..."
    $slice1 = Join-Path $tempRoot 'slice1.json'
    Write-SliceResult -Path $slice1 -Object ([ordered]@{
        slice_index = 1
        implemented_files = @()
        current_slice_changed_files = @('claim-server/src/test/java/ExampleTest.java')
        tests = @([ordered]@{
            phase = 'RED'
            result = 'pass'
            evidence = "ClassNotFoundException as expected"
        })
    })
    $r1 = Invoke-Gate -ReplayRoot $tempRoot -SliceResultPath $slice1 -Index 1
    if ($r1.ExitCode -eq 0) { throw 'Expected structural RED pass to fail' }
    if (-not (Test-Path -LiteralPath $r1.JsonPath)) { throw 'Expected RED_PHASE_GATE_01.json' }
    if ($r1.Stdout -match 'Pre-flight dependency compilation') { throw 'VerifyOnly must not run Maven preflight' }
    $j1 = Get-Content -LiteralPath $r1.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $codes1 = @($j1.issues | ForEach-Object { $_.code })
    if ($codes1 -notcontains 'red_phase_passed_before_fix') { throw 'Expected red_phase_passed_before_fix issue' }
    if ($codes1 -notcontains 'no_green_implementation') { throw 'Expected no_green_implementation issue' }
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 2] Proper RED fail plus implementation and GREEN passes..."
    $slice2 = Join-Path $tempRoot 'slice2.json'
    Write-SliceResult -Path $slice2 -Object ([ordered]@{
        slice_index = 2
        implemented_files = @('claim-core/src/main/java/ExampleService.java')
        current_slice_changed_files = @('claim-core/src/main/java/ExampleService.java', 'claim-server/src/test/java/ExampleServiceTest.java')
        tests = @(
            [ordered]@{ phase = 'RED'; result = 'failed'; evidence = 'AssertionError: expected persisted status row' },
            [ordered]@{ phase = 'GREEN'; result = 'passed'; evidence = 'Maven test passed after implementation' }
        )
    })
    $r2 = Invoke-Gate -ReplayRoot $tempRoot -SliceResultPath $slice2 -Index 2
    if ($r2.ExitCode -ne 0) { throw "Expected valid RED/GREEN to pass, exit=$($r2.ExitCode)" }
    if (-not (Test-Path -LiteralPath $r2.JsonPath)) { throw 'Expected RED_PHASE_GATE_02.json' }
    $j2 = Get-Content -LiteralPath $r2.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$j2.can_proceed) { throw 'Expected can_proceed=true' }
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 3] RED fail without implementation fails closed..."
    $slice3 = Join-Path $tempRoot 'slice3.json'
    Write-SliceResult -Path $slice3 -Object ([ordered]@{
        slice_index = 3
        implemented_files = @()
        tests = @([ordered]@{ phase = 'RED'; result = 'failed'; evidence = 'AssertionError: expected state change' })
    })
    $r3 = Invoke-Gate -ReplayRoot $tempRoot -SliceResultPath $slice3 -Index 3
    if ($r3.ExitCode -eq 0) { throw 'Expected missing implementation to fail' }
    $j3 = Get-Content -LiteralPath $r3.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $codes3 = @($j3.issues | ForEach-Object { $_.code })
    if ($codes3 -notcontains 'no_green_implementation') { throw 'Expected no_green_implementation issue' }
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 4] VerifyOnly block appears before execute-mode Maven logic..."
    $content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    if ($content.IndexOf('if ($VerifyOnly)') -lt 0) { throw 'VerifyOnly block missing' }
    if ($content.IndexOf('if ($VerifyOnly)') -gt $content.IndexOf('Pre-flight dependency compilation')) {
        throw 'VerifyOnly must run before execute-mode Maven preflight'
    }
    Write-Host "PASS" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
