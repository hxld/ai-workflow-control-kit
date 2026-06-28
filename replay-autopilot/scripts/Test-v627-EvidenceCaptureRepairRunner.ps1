#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for conservative Phase1 evidence capture repair.

.DESCRIPTION
The test extracts Invoke-EvidenceCaptureRepair from the real Run-SliceLoop.ps1
source and executes it against fixture SLICE_RESULT files. This avoids a copied
test implementation drifting away from the production runner.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Name - $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-FunctionText {
    param([string]$Path, [string]$Name)

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $start = -1
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        if ($lines[$idx] -match ('^\s*function\s+' + [regex]::Escape($Name) + '\s*\{')) {
            $start = $idx
            break
        }
    }
    if ($start -lt 0) { throw "Function not found: $Name" }

    $depth = 0
    $captured = New-Object System.Collections.Generic.List[string]
    for ($idx = $start; $idx -lt $lines.Count; $idx++) {
        $line = $lines[$idx]
        $captured.Add($line) | Out-Null
        $depth += [regex]::Matches($line, '\{').Count
        $depth -= [regex]::Matches($line, '\}').Count
        if ($idx -gt $start -and $depth -le 0) { break }
    }

    $text = $captured -join "`n"
    if ($depth -ne 0) { throw "Function extraction ended with brace depth $depth for $Name" }
    return $text
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$sliceLoopScript = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$sourceText = Get-Content -LiteralPath $sliceLoopScript -Raw -Encoding UTF8

Assert-True 'repair_function_present' ($sourceText -match 'function Invoke-EvidenceCaptureRepair')
Assert-True 'repair_has_no_stdout_success_fallback' (-not ($sourceText -match 'test_execution_exit_code''?\s*-Value\s+0[\s\S]{0,400}stdout')) 'repair must not infer success from stdout logs'
Assert-True 'repair_requires_parsed_exit_code' ($sourceText -match 'hasParsedExitCode[\s\S]{0,500}exitCodeParsed\s+-eq\s+0')
Assert-True 'repair_requires_am_for_promoted_maven_test' ($sourceText -match 'isExecutableMavenTest[\s\S]{0,500}-am')

Invoke-Expression ((Get-FunctionText -Path $sliceLoopScript -Name 'Set-ObjectProperty') + "`n" + (Get-FunctionText -Path $sliceLoopScript -Name 'Invoke-EvidenceCaptureRepair'))

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v627-evidence-capture-repair-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $mavenGreenCommand = 'mvn --% -s D:\settings.xml -f C:\worktree\pom.xml -pl sample-tests -am -Dtest=ExampleTest#testGreen -Dsurefire.failIfNoSpecifiedTests=false test'

    $root1 = Join-Path $tempRoot 'structured-pass'
    $logs1 = Join-Path $root1 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs1 | Out-Null
    $result1 = Join-Path $root1 'SLICE_RESULT_01.json'
    Write-JsonFile $result1 ([ordered]@{
        slice_status = 'DONE'
        coverage_delta = 10
        tests = @(
            [ordered]@{ phase = 'RED'; result = 'fail'; command = 'mvn --% -f pom.xml -pl sample-tests -am -Dtest=ExampleTest#testGreen test'; exit_code = 1 },
            [ordered]@{ phase = 'GREEN'; result = 'pass'; command = $mavenGreenCommand; exit_code = 0; test_module = 'sample-tests' }
        )
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result1 -SliceLogDir $logs1 -ReplayRoot $root1
    $repaired1 = Read-JsonFile $result1
    Assert-True 'promotes_structured_green_command' ([string]$repaired1.test_execution_command -eq $mavenGreenCommand)
    Assert-True 'promotes_structured_green_exit_code' ([int]$repaired1.test_execution_exit_code -eq 0)
    Assert-True 'records_structured_execution_source' ([string]$repaired1.test_execution_evidence_source -eq 'SLICE_RESULT.tests')
    Assert-True 'promotes_test_module' ([string]$repaired1.test_module -eq 'sample-tests')

    $root2 = Join-Path $tempRoot 'missing-exit-code'
    $logs2 = Join-Path $root2 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs2 | Out-Null
    $result2 = Join-Path $root2 'SLICE_RESULT_01.json'
    Write-JsonFile $result2 ([ordered]@{
        slice_status = 'DONE'
        coverage_delta = 10
        tests = @([ordered]@{ phase = 'GREEN'; result = 'pass'; command = $mavenGreenCommand })
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result2 -SliceLogDir $logs2 -ReplayRoot $root2
    $repaired2 = Read-JsonFile $result2
    Assert-True 'does_not_promote_without_exit_code' (-not ($repaired2.PSObject.Properties.Name -contains 'test_execution_command'))

    $root3 = Join-Path $tempRoot 'stdout-only'
    $logs3 = Join-Path $root3 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs3 | Out-Null
    @(
        'mvn --% -f C:\worktree\pom.xml -pl sample-tests -am -Dtest=ExampleTest#testGreen -Dsurefire.failIfNoSpecifiedTests=false test',
        'BUILD SUCCESS'
    ) | Set-Content -LiteralPath (Join-Path $logs3 'phase1-slice01.stdout.log') -Encoding UTF8
    $result3 = Join-Path $root3 'SLICE_RESULT_01.json'
    Write-JsonFile $result3 ([ordered]@{
        slice_status = 'DONE'
        coverage_delta = 10
        tests = @([ordered]@{ phase = 'GREEN'; result = 'pass'; evidence = 'BUILD SUCCESS in stdout' })
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result3 -SliceLogDir $logs3 -ReplayRoot $root3
    $repaired3 = Read-JsonFile $result3
    Assert-True 'does_not_infer_execution_from_stdout' (-not ($repaired3.PSObject.Properties.Name -contains 'test_execution_command'))
    Assert-True 'does_not_infer_exit_zero_from_stdout' (-not ($repaired3.PSObject.Properties.Name -contains 'test_execution_exit_code'))

    $root4 = Join-Path $tempRoot 'preflight'
    $logs4 = Join-Path $root4 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs4 | Out-Null
    Write-JsonFile (Join-Path $root4 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        status = 'PASS'
        exit_code = 0
        maven_command_args = '-s D:\settings.xml -f C:\worktree\pom.xml -pl sample-tests -am test-compile -q -DskipTests'
    })
    $result4 = Join-Path $root4 'SLICE_RESULT_01.json'
    Write-JsonFile $result4 ([ordered]@{
        slice_status = 'DONE'
        coverage_delta = 10
        tests = @()
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result4 -SliceLogDir $logs4 -ReplayRoot $root4
    $repaired4 = Read-JsonFile $result4
    Assert-True 'injects_preflight_compile_command' ([string]$repaired4.test_compilation_command -match 'test-compile')
    Assert-True 'injects_preflight_compile_exit_code' ([int]$repaired4.test_compilation_exit_code -eq 0)
    Assert-True 'records_preflight_compile_source' ([string]$repaired4.test_compilation_evidence_source -eq (Join-Path $root4 'PREFLIGHT_TEST_COMPILATION.json'))

    $root5 = Join-Path $tempRoot 'blocked'
    $logs5 = Join-Path $root5 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs5 | Out-Null
    Write-JsonFile (Join-Path $root5 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        exit_code = 0
        maven_command_args = '-f pom.xml -pl sample-tests -am test-compile'
    })
    $result5 = Join-Path $root5 'SLICE_RESULT_01.json'
    Write-JsonFile $result5 ([ordered]@{
        slice_status = 'BLOCKED'
        gap_flags = @('tooling_executor_failed')
        tests = @([ordered]@{ phase = 'EXECUTOR'; result = 'blocked'; command = 'Invoke-AgentPrompt.ps1' })
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result5 -SliceLogDir $logs5 -ReplayRoot $root5
    $repaired5 = Read-JsonFile $result5
    Assert-True 'blocked_slice_is_not_mutated' (-not ($repaired5.PSObject.Properties.Name -contains 'test_compilation_command'))

    $root6 = Join-Path $tempRoot 'completed'
    $logs6 = Join-Path $root6 'logs\phase1-slices\slice01'
    New-Item -ItemType Directory -Force -Path $logs6 | Out-Null
    $result6 = Join-Path $root6 'SLICE_RESULT_01.json'
    Write-JsonFile $result6 ([ordered]@{
        slice_status = 'COMPLETED'
        coverage_delta = 10
        tests = @([ordered]@{ phase = 'VERIFY'; result = 'pass'; command = $mavenGreenCommand; exit_code = 0 })
    })
    Invoke-EvidenceCaptureRepair -SliceResultPath $result6 -SliceLogDir $logs6 -ReplayRoot $root6
    $repaired6 = Read-JsonFile $result6
    Assert-True 'completed_status_is_success_synonym' ([string]$repaired6.test_execution_command -eq $mavenGreenCommand)

    Write-Host 'PASS: v627 evidence capture repair runner'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
