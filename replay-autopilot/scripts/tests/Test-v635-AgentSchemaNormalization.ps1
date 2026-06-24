#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for v635 agent-authored flat red_result/green_result schema normalization.

.DESCRIPTION
Validates that the SliceResultSchemaNormalizer handles agents that output
red_result/green_result as flat free-text strings (instead of structured
red_phase/green_phase objects) and that build_status is mapped to
test_compilation_exit_code for the executable evidence gate.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "FAIL: $Message" }
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 12)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-NormalizerDirect {
    param([string]$SliceResultPath, [string]$ReplayRoot = '')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\Normalize-SliceResultSchema.ps1') `
        -SliceResultPath $SliceResultPath `
        -ReplayRoot $ReplayRoot `
        -SliceIndex 1 `
        -InPlace | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Normalizer failed with exit code $LASTEXITCODE" }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v635-agent-schema-normalization-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    # ===== Scenario 1: red_result flat string + test_result flat string =====
    # Agent outputs red_result as flat free-text and test_result as flat status.
    # test_result->GREEN entry (existing normalization), red_result->RED entry (new).
    # green_result is correctly not duplicated because GREEN already exists.
    Write-Host '[Scenario 1] test_result + red_result flat strings...'
    $replay1 = Join-Path $tempRoot 'scenario-1'
    New-Item -ItemType Directory -Force -Path $replay1 | Out-Null
    $slice1 = Join-Path $replay1 'SLICE_RESULT_01.json'
    Write-JsonFile $slice1 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'DONE'
        test_result = 'PASSED'
        red_result = 'PASSED_BUSINESS_ASSERTION'
        green_result = 'PASSED'
        build_status = 'SUCCESS'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        gap_flags = @()
    })

    Invoke-NormalizerDirect -SliceResultPath $slice1 -ReplayRoot $replay1
    $norm1 = Read-JsonFile $slice1

    # Must have normalized tests[] array with both RED and GREEN
    Assert-True (@($norm1.tests).Count -eq 2) 'Scenario 1: must create 2 test entries (GREEN from test_result, RED from red_result)'
    Assert-True (@($norm1.gap_flags) -contains 'agent_result_schema_normalized') 'Scenario 1: must add normalization flag'

    # GREEN entry from test_result (existing normalization, no evidence field)
    $greenTest = @($norm1.tests | Where-Object { $_.phase -eq 'GREEN' })[0]
    Assert-True ($null -ne $greenTest) 'Scenario 1: GREEN test entry must exist'
    Assert-True ($greenTest.result -eq 'pass') 'Scenario 1: GREEN entry must have result=pass'

    # RED entry from red_result flat string (new normalization)
    $redTest = @($norm1.tests | Where-Object { $_.phase -eq 'RED' })[0]
    Assert-True ($null -ne $redTest) 'Scenario 1: RED test entry must exist'
    Assert-True ($redTest.result -eq 'fail') 'Scenario 1: RED entry must have result=fail'
    Assert-True ($redTest.evidence -eq 'PASSED_BUSINESS_ASSERTION') 'Scenario 1: RED evidence must carry the raw red_result text'

    # build_status must map to test_compilation_exit_code
    Assert-True ($norm1.test_compilation_exit_code -eq 0) 'Scenario 1: test_compilation_exit_code must be 0 from build_status=SUCCESS'
    Assert-True ($norm1.test_compilation_evidence -eq $true) 'Scenario 1: test_compilation_evidence must be true'
    Assert-True ($norm1.test_compilation_evidence_source -eq 'build_status') 'Scenario 1: evidence source must indicate build_status'

    Write-Host '  Scenario 1 PASS'

    # ===== Scenario 2: No test_result, only red_result -> injects RED only =====
    Write-Host '[Scenario 2] Only red_result flat string (no test_result)...'
    $replay2 = Join-Path $tempRoot 'scenario-2'
    New-Item -ItemType Directory -Force -Path $replay2 | Out-Null
    $slice2 = Join-Path $replay2 'SLICE_RESULT_01.json'
    Write-JsonFile $slice2 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'DONE'
        red_result = 'TESTS_RUN_1_FAILURES_1'
        build_status = 'FAILURE'
        touched_requirement_families = @()
        closed_requirement_families = @()
        gap_flags = @()
    })

    Invoke-NormalizerDirect -SliceResultPath $slice2 -ReplayRoot $replay2
    $norm2 = Read-JsonFile $slice2

    Assert-True (@($norm2.tests).Count -eq 1) 'Scenario 2: must create 1 test entry (RED from red_result)'
    Assert-True ($norm2.tests[0].phase -eq 'RED') 'Scenario 2: single entry must be RED'
    Assert-True ($norm2.tests[0].result -eq 'fail') 'Scenario 2: RED must have result=fail'
    Assert-True ($norm2.tests[0].evidence -eq 'TESTS_RUN_1_FAILURES_1') 'Scenario 2: RED evidence from red_result'
    Assert-True ($norm2.test_compilation_exit_code -eq 1) 'Scenario 2: build_status=FAILURE maps to exit code 1'
    Assert-True ($norm2.test_compilation_evidence -eq $false) 'Scenario 2: test_compilation_evidence must be false'
    Assert-True ($norm2.test_compilation_evidence_source -eq 'build_status') 'Scenario 2: evidence source must be build_status'

    Write-Host '  Scenario 2 PASS'

    # ===== Scenario 3: Already has tests[] array + red_result/green_result =====
    # Agent already outputs native tests[] array. Must not overwrite existing array
    # with synthetic entries from red_result/green_result fields.
    Write-Host '[Scenario 3] Already has tests[] array with RED must not duplicate...'
    $replay3 = Join-Path $tempRoot 'scenario-3'
    New-Item -ItemType Directory -Force -Path $replay3 | Out-Null
    $slice3 = Join-Path $replay3 'SLICE_RESULT_01.json'
    Write-JsonFile $slice3 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'DONE'
        red_result = 'PASSED_BUSINESS_ASSERTION'
        green_result = 'PASSED'
        tests = @(
            [ordered]@{ phase = 'RED'; result = 'fail'; evidence = 'AssertionError: expected but not found' }
        )
        gap_flags = @()
        touched_requirement_families = @()
        closed_requirement_families = @()
    })

    Invoke-NormalizerDirect -SliceResultPath $slice3 -ReplayRoot $replay3
    $norm3 = Read-JsonFile $slice3

    # RED already in tests[] -> no duplicate; GREEN missing -> injected from green_result
    Assert-True (@($norm3.tests).Count -eq 2) 'Scenario 3: tests[] must have 2 entries (existing RED + injected GREEN)'
    $redFromTests = @($norm3.tests | Where-Object { $_.phase -eq 'RED' })
    Assert-True ($redFromTests.Count -eq 1) 'Scenario 3: must not duplicate RED entry'
    Assert-True ($redFromTests[0].evidence -eq 'AssertionError: expected but not found') 'Scenario 3: RED must preserve original evidence'

    $greenFromTests = @($norm3.tests | Where-Object { $_.phase -eq 'GREEN' })
    Assert-True ($greenFromTests.Count -eq 1) 'Scenario 3: GREEN must be injected from green_result'
    Assert-True ($greenFromTests[0].evidence -eq 'PASSED') 'Scenario 3: GREEN must carry green_result text'

    Write-Host '  Scenario 3 PASS'

    # ===== Scenario 4: Existing test_compilation_exit_code must not be overwritten =====
    Write-Host '[Scenario 4] Pre-existing test_compilation_exit_code must survive...'
    $replay4 = Join-Path $tempRoot 'scenario-4'
    New-Item -ItemType Directory -Force -Path $replay4 | Out-Null
    $slice4 = Join-Path $replay4 'SLICE_RESULT_01.json'
    Write-JsonFile $slice4 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'DONE'
        build_status = 'SUCCESS'
        test_compilation_exit_code = 127
        red_result = 'RED_FAILED'
        touched_requirement_families = @()
        closed_requirement_families = @()
        gap_flags = @()
    })

    Invoke-NormalizerDirect -SliceResultPath $slice4 -ReplayRoot $replay4
    $norm4 = Read-JsonFile $slice4

    Assert-True ($norm4.test_compilation_exit_code -eq 127) 'Scenario 4: pre-existing exit code 127 must survive build_status mapping'

    Write-Host '  Scenario 4 PASS'

    # ===== Scenario 5: Normalizer source contains flat string normalization =====
    Write-Host '[Scenario 5] Normalizer source contains flat string normalization...'
    $normalizerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\SliceResultSchemaNormalizer.ps1') -Raw -Encoding UTF8
    Assert-True ($normalizerText -match 'red_result_flat_string') 'normalizer must reference red_result_flat_string normalized field'
    Assert-True ($normalizerText -match 'green_result_flat_string') 'normalizer must reference green_result_flat_string normalized field'
    Assert-True ($normalizerText -match 'test_compilation_exit_code:build_status') 'normalizer must reference build_status mapping field'

    Write-Host '  Scenario 5 PASS'

    Write-Host ''
    Write-Host '=== v635 AGENT SLICE RESULT SCHEMA NORMALIZATION ALL SCENARIOS PASS ===' -ForegroundColor Green

} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
