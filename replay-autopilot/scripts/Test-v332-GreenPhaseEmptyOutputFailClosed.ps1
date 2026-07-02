$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runSlicePath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$runSliceText = Get-Content -LiteralPath $runSlicePath -Raw -Encoding UTF8

Write-Host "=== v332 Green Phase Empty Output Fail-Closed Test ===" -ForegroundColor Cyan

Write-Host "`n[Test 1] Run-SliceLoop contains explicit empty/null output guards..."
Assert-True ($runSliceText.Contains('green_phase_gate_empty_output')) 'Run-SliceLoop must report green_phase_gate_empty_output'
Assert-True ($runSliceText.Contains('green_phase_gate_null_output')) 'Run-SliceLoop must report green_phase_gate_null_output'
Assert-True ($runSliceText.Contains('[string]::IsNullOrWhiteSpace($stdoutText)')) 'Run-SliceLoop must check blank stdout before ConvertFrom-Json'
Write-Host "PASS" -ForegroundColor Green

$tempRoot = Join-Path $env:TEMP ("replay-v332-green-empty-{0}" -f ([guid]::NewGuid().ToString('N')))
$originalPath = $env:PATH

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    $fakeBin = Join-Path $tempRoot 'fake-bin'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree, $fakeBin | Out-Null

    $sourceFile = Join-Path $worktree 'src\main\java\Example.java'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourceFile) | Out-Null
    @"
class Example {
    void save() {
        mapper.insert(new Object());
    }
}
"@ | Set-Content -LiteralPath $sourceFile -Encoding UTF8

    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    [ordered]@{
        slice_status = 'PARTIAL'
        implemented_files = @(
            'src/main/java/Example.java',
            'example-server/src/test/java/ExampleTest.java'
        )
        touched_requirement_families = @('core_entry')
        tests = @(
            [ordered]@{
                phase = 'GREEN'
                command = 'mvn test -pl example-server -Dtest=ExampleTest'
                evidence_file = 'example-server/src/test/java/ExampleTest.java'
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    $sliceVerifyPath = Join-Path $replayRoot 'SLICE_VERIFY_01.json'
    [ordered]@{
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 0
        coverage_delta = 0
        should_continue = $false
        authorized_for_next_slice = $false
        authorization_blockers = @()
        gap_flags = @()
        warnings = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceVerifyPath -Encoding UTF8

    $runnerContractPath = Join-Path $replayRoot 'RUNNER_ENFORCEMENT_CONTRACT.md'
    '# Runner Contract' | Set-Content -LiteralPath $runnerContractPath -Encoding UTF8

    @"
@echo off
if "%1"=="--version" (
  echo Python 3.14.0
  exit /b 0
)
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeBin 'python.cmd') -Encoding ASCII
    @"
@echo off
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeBin 'mvn.cmd') -Encoding ASCII
    $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $env:PATH

    $functionStart = $runSliceText.IndexOf('function Read-JsonObject')
    $functionEnd = $runSliceText.IndexOf('function Invoke-RedPhaseHardGate')
    Assert-True ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'Could not extract green gate function block'
    $functionBlock = $runSliceText.Substring($functionStart, $functionEnd - $functionStart)
    $functionBlock = $functionBlock.Replace('$PSScriptRoot', ('"{0}"' -f $scriptRoot.Replace('"', '""')))
    Invoke-Expression $functionBlock

    Write-Host "`n[Test 2] Empty stdout from verify_green_phase.py is persisted as fail-closed JSON..."
    $result = Invoke-GreenPhaseNoMockGate `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceResultPath $sliceResultPath `
        -SliceVerifyPath $sliceVerifyPath `
        -SliceIndex 1 `
        -RunnerContractPath $runnerContractPath

    Assert-True (-not [bool]$result.CanProceed) 'empty stdout must not authorize GREEN'
    $gatePath = Join-Path $replayRoot 'GREEN_PHASE_VERIFY_01.json'
    Assert-True (Test-Path -LiteralPath $gatePath) 'GREEN_PHASE_VERIFY_01.json must be written'
    $gate = Get-Content -LiteralPath $gatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $issueCodes = @($gate.issues | ForEach-Object { $_.code })
    Assert-True ($issueCodes -contains 'green_phase_gate_empty_output') 'gate JSON must contain green_phase_gate_empty_output'
    Assert-True ([int]$gate.exit_code -eq 0) 'gate JSON must retain python exit code'
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n[Test 3] Slice verifier is updated instead of letting Phase1 crash..."
    $sliceVerify = Get-Content -LiteralPath $sliceVerifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($sliceVerify.verification_status -eq 'FAIL') 'slice verify must be marked FAIL'
    Assert-True (@($sliceVerify.authorization_blockers) -contains 'green_phase_gate_empty_output') 'slice verify must record empty-output blocker'
    Assert-True (@($sliceVerify.gap_flags) -contains 'tooling_enforcement_stop') 'slice verify must record tooling enforcement stop'
    Assert-True ($null -ne $sliceVerify.green_phase_gate) 'slice verify must embed green phase gate evidence'
    Write-Host "PASS" -ForegroundColor Green

    Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
} finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
