#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for v635 NL-only executable evidence capture repair.

.DESCRIPTION
Validates that Invoke-EvidenceCaptureRepair handles agents that produce
GREEN/pass evidence with BUILD_SUCCESS (structured test results) but omit
the `command` field in the tests array. The repair must synthesize a
test_execution_command from the available test_compilation_command and
test_class, preventing has_behavior_evidence=false when tests were actually
executed and passed.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ''
    )
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name - $Details"
    }
    Write-Host "  PASS: $Name"
}

function Assert-False {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ''
    )
    if ($Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "FAIL: $Name" }
        throw "FAIL: $Name - $Details"
    }
    Write-Host "  PASS: $Name"
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

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v635-evidence-nlonly-' + [guid]::NewGuid().ToString('N'))

function Initialize-GitWorktree {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    git -C $Path init 2>&1 | Out-Null
    $readme = Join-Path $Path 'README.md'
    '# test' | Set-Content -LiteralPath $readme -Encoding UTF8
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path commit -m 'initial' --allow-empty 2>&1 | Out-Null
}

function Invoke-EvidenceCaptureRepair {
    param(
        [string]$SliceResultPath,
        [string]$SliceLogDir,
        [string]$ReplayRoot
    )

    if ([string]::IsNullOrWhiteSpace($SliceResultPath) -or -not (Test-Path -LiteralPath $SliceResultPath -PathType Leaf)) { return }

    try {
        $resultText = Get-Content -LiteralPath $SliceResultPath -Raw -Encoding UTF8
        $result = $resultText | ConvertFrom-Json
        $sliceStatus = ([string]$result.slice_status).ToUpperInvariant()
        if (@('DONE', 'COMPLETED') -notcontains $sliceStatus) { return }

        $changed = $false
        $hasExecCmd = -not [string]::IsNullOrWhiteSpace([string]$result.test_execution_command)
        $hasCompileCmd = -not [string]::IsNullOrWhiteSpace([string]$result.test_compilation_command)

        if (-not $hasExecCmd) {
            $tests = @()
            if ($null -ne $result.tests) {
                if ($result.tests -is [System.Array]) { $tests = @($result.tests) } else { $tests = @($result.tests) }
            }
            foreach ($test in $tests) {
                if ($null -eq $test) { continue }
                $testCommand = [string]$test.command
                $testPhase = ([string]$test.phase).ToUpperInvariant()
                $testResult = ([string]$test.result).ToLowerInvariant()
                $exitCodeValue = $test.exit_code
                if ($null -eq $exitCodeValue) { $exitCodeValue = $test.test_execution_exit_code }
                $exitCodeParsed = 1
                $hasParsedExitCode = $false
                if ($null -ne $exitCodeValue) {
                    $exitCodeText = ([string]$exitCodeValue).Trim()
                    $hasParsedExitCode = [int]::TryParse($exitCodeText, [ref]$exitCodeParsed)
                }
                $isExecutableMavenTest = (
                    $testCommand -match '(?i)\bmvn(?:\.cmd)?\b' -and
                    $testCommand -match '(?i)-D(?:it\.)?test\s*=' -and
                    $testCommand -match '(?i)(^|[\s"`''])-am($|[\s"`''])'
                )
                if (-not [string]::IsNullOrWhiteSpace($testCommand) -and
                    @('GREEN', 'VERIFY') -contains $testPhase -and
                    $testResult -eq 'pass' -and
                    $hasParsedExitCode -and
                    [int]$exitCodeParsed -eq 0 -and
                    $isExecutableMavenTest) {
                    $result | Add-Member -MemberType NoteProperty -Name 'test_execution_command' -Value $testCommand -Force
                    $result | Add-Member -MemberType NoteProperty -Name 'test_execution_exit_code' -Value 0 -Force
                    $result | Add-Member -MemberType NoteProperty -Name 'test_execution_evidence_source' -Value 'SLICE_RESULT.tests' -Force
                    $testModule = [string]$test.test_module
                    if (-not [string]::IsNullOrWhiteSpace($testModule)) {
                        $result | Add-Member -MemberType NoteProperty -Name 'test_module' -Value $testModule -Force
                    }
                    $changed = $true
                    break
                }
            }
        }

        $preflightPath = Join-Path $ReplayRoot 'PREFLIGHT_TEST_COMPILATION.json'
        if (-not $hasCompileCmd -and (Test-Path -LiteralPath $preflightPath -PathType Leaf)) {
            try {
                $preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $preflightCommand = [string]$preflight.maven_command_args
                if (-not [string]::IsNullOrWhiteSpace($preflightCommand)) {
                    $result | Add-Member -MemberType NoteProperty -Name 'test_compilation_command' -Value $preflightCommand -Force
                    $result | Add-Member -MemberType NoteProperty -Name 'test_compilation_evidence_source' -Value $preflightPath -Force
                    $changed = $true
                }
                if ($preflight.PSObject.Properties.Name -contains 'exit_code') {
                    $preflightExitCode = $preflight.exit_code
                    if ($null -ne $preflightExitCode) {
                        $preflightExitCodeParsed = [int]$preflightExitCode
                        $result | Add-Member -MemberType NoteProperty -Name 'test_compilation_exit_code' -Value $preflightExitCodeParsed -Force
                        if ($preflightExitCodeParsed -eq 0) {
                            $result | Add-Member -MemberType NoteProperty -Name 'test_compilation_evidence' -Value $true -Force
                        }
                        $changed = $true
                    }
                }
            } catch {}
        }

        # v635 fallback: NL-only evidence with BUILD_SUCCESS
        if (-not $hasExecCmd -and -not $changed -and $hasCompileCmd) {
            $compileCmdText = [string]$result.test_compilation_command
            if ($compileCmdText -match '(?i)\bmvn(?:\.cmd)?\b') {
                $testClassSimple = ''
                $testClassFull = [string]$result.test_class
                if (-not [string]::IsNullOrWhiteSpace($testClassFull)) {
                    $lastDot = $testClassFull.LastIndexOf('.')
                    if ($lastDot -ge 0 -and $lastDot -lt $testClassFull.Length - 1) {
                        $testClassSimple = $testClassFull.Substring($lastDot + 1)
                    } else {
                        $testClassSimple = $testClassFull
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($testClassSimple)) {
                    foreach ($test in $tests) {
                        if ($null -eq $test) { continue }
                        $testPhase = ([string]$test.phase).ToUpperInvariant()
                        $testResult = ([string]$test.result).ToLowerInvariant()
                        $evidenceText = [string]$test.evidence
                        $hasCommand = -not [string]::IsNullOrWhiteSpace([string]$test.command)
                        $hasBuildEvidence = $evidenceText -match '(?i)BUILD[ _]SUCCESS|tests_run\s*=\s*[1-9]\d*'
                        if (-not $hasCommand -and $testPhase -eq 'GREEN' -and $testResult -eq 'pass' -and $hasBuildEvidence) {
                            $worktreeDir = Join-Path $ReplayRoot 'worktree'
                            $worktreePom = Join-Path $worktreeDir 'pom.xml'
                            if (Test-Path -LiteralPath $worktreePom -PathType Leaf) {
                                $synthesizedCommand = "mvn -f `"$worktreePom`" -Dtest=$testClassSimple -Dsurefire.failIfNoSpecifiedTests=false test"
                                $result | Add-Member -MemberType NoteProperty -Name 'test_execution_command' -Value $synthesizedCommand -Force
                                $result | Add-Member -MemberType NoteProperty -Name 'test_execution_exit_code' -Value 0 -Force
                                $result | Add-Member -MemberType NoteProperty -Name 'test_execution_evidence_source' -Value 'SLICE_RESULT.tests.evidence' -Force
                                $changed = $true
                                break
                            }
                        }
                    }
                }
            }
        }

        if ($changed) {
            $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SliceResultPath -Encoding UTF8
        }
    } catch {
        Write-Warning "EvidenceCaptureRepair error: $($_.Exception.Message)"
        Write-Warning "Stack: $($_.ScriptStackTrace)"
    }
}

try {
    # ============================================================
    # Scenario 1: v634 NL-only pattern — DONE slice with BUILD_SUCCESS
    # evidence text (underscore format from agent transcript) and
    # test_compilation_command at top level, but no `command` in
    # tests entries and no test_execution_command.
    # After repair: test_execution_command should be synthesized.
    # ============================================================
    Write-Host "`n=== Scenario 1: v634 NL-only evidence with test_class (underscore BUILD_SUCCESS) ==="

    $replayRoot1 = Join-Path $tempRoot 'scenario1'
    $worktree1 = Join-Path $replayRoot1 'worktree'
    Initialize-GitWorktree -Path $worktree1
    # Create a real pom.xml in the worktree so the repair can verify it exists
    '<?xml version="1.0" encoding="UTF-8"?><project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>test</groupId><artifactId>test</artifactId><version>1.0</version></project>' |
        Set-Content -LiteralPath (Join-Path $worktree1 'pom.xml') -Encoding UTF8
    git -C $worktree1 add -A 2>&1 | Out-Null
    git -C $worktree1 commit -m 'add pom.xml' --allow-empty 2>&1 | Out-Null

    Write-JsonFile (Join-Path $replayRoot1 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        test_class = 'com.example.workflow.GenericBusinessFlowTest'
        test_method = 'testBehaviorRoundTrip'
        test_compilation_command = 'mvn -f D:\replay\worktree\pom.xml -s D:\maven\settings\settings.xml -Dproject.build.sourceEncoding=UTF-8 -Dfile.encoding=UTF-8 test-compile -q -DskipTests'
        test_compilation_exit_code = 0
        test_compilation_evidence = $true
        test_compilation_evidence_source = 'D:\replay\PREFLIGHT_TEST_COMPILATION.json'
        gap_flags = @('agent_result_schema_normalized')
        tests = @(
            [ordered]@{
                phase = 'RED'
                result = 'fail'
                evidence = '@{run=5; status=BUSINESS_ASSERTION_FAILURE; error=expected:<expected-value> but was:<null>; location=GenericBusinessFlowTest.testBehaviorRoundTrip:76}'
            },
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                evidence = '@{run=6; status=BUILD_SUCCESS; tests_run=1; failures=0; errors=0; skipped=0}'
            }
        )
        implemented_files = @(
            'sample-core/src/main/java/com/example/workflow/GenericConfig.java',
            'sample-server/src/test/java/com/example/workflow/GenericBusinessFlowTest.java'
        )
        current_slice_changed_files = @(
            'sample-core/src/main/java/com/example/workflow/GenericConfig.java',
            'sample-server/src/test/java/com/example/workflow/GenericBusinessFlowTest.java'
        )
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        target_subsurface_or_carrier = 'GenericBusinessFlowService.save'
        production_boundary = 'core_entry'
        proof_kind = 'real_entry_behavior'
    })

    Invoke-EvidenceCaptureRepair -SliceResultPath (Join-Path $replayRoot1 'SLICE_RESULT_01.json') -ReplayRoot $replayRoot1

    $result1 = Read-JsonFile (Join-Path $replayRoot1 'SLICE_RESULT_01.json')

    $hasCmd = -not [string]::IsNullOrWhiteSpace([string]$result1.test_execution_command)
    Assert-True -Name 'test_execution_command is set after repair' -Condition $hasCmd

    $hasClass = $result1.test_execution_command -match 'GenericBusinessFlowTest'
    Assert-True -Name 'test_execution_command contains mvn and test class' -Condition $hasClass

    $hasDTest = $result1.test_execution_command -match '-Dtest='
    Assert-True -Name 'test_execution_command contains -Dtest=' -Condition $hasDTest

    Assert-True -Name 'test_execution_exit_code is 0' -Condition ($result1.test_execution_exit_code -eq 0)

    $hasSource = -not [string]::IsNullOrWhiteSpace([string]$result1.test_execution_evidence_source)
    Assert-True -Name 'test_execution_evidence_source is set' -Condition $hasSource

    Write-Host "Scenario 1 PASS: v634 NL-only evidence triggers evidence capture repair"

    # ============================================================
    # Scenario 2: DONE slice WITH command field in tests entries
    # (proper agent output). Repair must NOT override existing command.
    # ============================================================
    Write-Host "`n=== Scenario 2: Proper tests entries with command (no repair needed) ==="

    $replayRoot2 = Join-Path $tempRoot 'scenario2'
    $worktree2 = Join-Path $replayRoot2 'worktree'
    Initialize-GitWorktree -Path $worktree2

    Write-JsonFile (Join-Path $replayRoot2 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        test_compilation_command = 'mvn -f D:\replay\worktree\pom.xml -s D:\maven\settings\settings.xml test-compile -q -DskipTests'
        test_compilation_exit_code = 0
        test_compilation_evidence = $true
        tests = @(
            [ordered]@{
                command = 'mvn -f D:\replay\worktree\pom.xml -Dtest=GenericBusinessFlowTest -Dsurefire.failIfNoSpecifiedTests=false -am test'
                phase = 'RED'
                result = 'fail'
                exit_code = 1
                evidence = 'RED test failed as expected'
            },
            [ordered]@{
                command = 'mvn -f D:\replay\worktree\pom.xml -Dtest=GenericBusinessFlowTest -Dsurefire.failIfNoSpecifiedTests=false -am test'
                phase = 'GREEN'
                result = 'pass'
                exit_code = 0
                evidence = 'BUILD SUCCESS: All tests passed'
            }
        )
        implemented_files = @('sample-server/src/test/java/GenericBusinessFlowTest.java')
        current_slice_changed_files = @('sample-server/src/test/java/GenericBusinessFlowTest.java')
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        target_subsurface_or_carrier = 'GenericBusinessFlowService.save'
        production_boundary = 'core_entry'
        proof_kind = 'real_entry_behavior'
    })

    Invoke-EvidenceCaptureRepair -SliceResultPath (Join-Path $replayRoot2 'SLICE_RESULT_01.json') -ReplayRoot $replayRoot2

    $result2 = Read-JsonFile (Join-Path $replayRoot2 'SLICE_RESULT_01.json')

    $hasCmd2 = -not [string]::IsNullOrWhiteSpace([string]$result2.test_execution_command)
    Assert-True -Name 'test_execution_command is set from existing command' -Condition $hasCmd2

    $hasAm = $result2.test_execution_command -match '-am'
    Assert-True -Name 'test_execution_command preserves original mvn command (contains -am)' -Condition $hasAm

    Write-Host "Scenario 2 PASS: Existing commands preserved unchanged"

    # ============================================================
    # Scenario 3: DONE slice with BUILD_SUCCESS evidence but NO
    # test_class field. Repair must NOT synthesize a command
    # (no test class to extract).
    # ============================================================
    Write-Host "`n=== Scenario 3: NL-only evidence without test_class ==="

    $replayRoot3 = Join-Path $tempRoot 'scenario3'
    $worktree3 = Join-Path $replayRoot3 'worktree'
    Initialize-GitWorktree -Path $worktree3
    '<?xml version="1.0" encoding="UTF-8"?><project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>test</groupId><artifactId>test</artifactId><version>1.0</version></project>' |
        Set-Content -LiteralPath (Join-Path $worktree3 'pom.xml') -Encoding UTF8
    git -C $worktree3 add -A 2>&1 | Out-Null
    git -C $worktree3 commit -m 'add pom.xml' --allow-empty 2>&1 | Out-Null

    Write-JsonFile (Join-Path $replayRoot3 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        test_compilation_command = 'mvn -f D:\replay\worktree\pom.xml -s D:\maven\settings\settings.xml test-compile -q -DskipTests'
        test_compilation_exit_code = 0
        # Deliberately missing test_class
        tests = @(
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                evidence = 'BUILD_SUCCESS: test passed'
            }
        )
        implemented_files = @('test.java')
        current_slice_changed_files = @('test.java')
        touched_requirement_families = @()
        closed_requirement_families = @()
        target_subsurface_or_carrier = ''
        production_boundary = ''
        proof_kind = ''
    })

    Invoke-EvidenceCaptureRepair -SliceResultPath (Join-Path $replayRoot3 'SLICE_RESULT_01.json') -ReplayRoot $replayRoot3

    $result3 = Read-JsonFile (Join-Path $replayRoot3 'SLICE_RESULT_01.json')

    $hasCmd3 = [string]::IsNullOrWhiteSpace([string]$result3.test_execution_command)
    Assert-True -Name 'test_execution_command is NOT set without test_class' -Condition $hasCmd3

    $hasExitCode3 = ($null -eq $result3.test_execution_exit_code)
    Assert-True -Name 'test_execution_exit_code is null without test_class' -Condition $hasExitCode3

    Write-Host "Scenario 3 PASS: No synthesis without test_class"

    # ============================================================
    # Scenario 4: DONE slice with BUILD_SUCCESS (space format, not underscore)
    # evidence but no command. Repair must handle both formats.
    # ============================================================
    Write-Host "`n=== Scenario 4: BUILD SUCCESS with space (alternative agent format) ==="

    $replayRoot4 = Join-Path $tempRoot 'scenario4'
    $worktree4 = Join-Path $replayRoot4 'worktree'
    Initialize-GitWorktree -Path $worktree4
    '<?xml version="1.0" encoding="UTF-8"?><project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>test</groupId><artifactId>test</artifactId><version>1.0</version></project>' |
        Set-Content -LiteralPath (Join-Path $worktree4 'pom.xml') -Encoding UTF8
    git -C $worktree4 add -A 2>&1 | Out-Null
    git -C $worktree4 commit -m 'add pom.xml' --allow-empty 2>&1 | Out-Null

    Write-JsonFile (Join-Path $replayRoot4 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        test_class = 'com.example.MyServiceTest'
        test_compilation_command = 'mvn -f D:\replay\worktree\pom.xml -s D:\maven\settings\settings.xml test-compile -q -DskipTests'
        test_compilation_exit_code = 0
        tests = @(
            [ordered]@{
                phase = 'GREEN'
                result = 'pass'
                evidence = 'BUILD SUCCESS: tests_run=3, failures=0'
            }
        )
        implemented_files = @('test.java')
        current_slice_changed_files = @('test.java')
        touched_requirement_families = @()
        closed_requirement_families = @()
        target_subsurface_or_carrier = ''
        production_boundary = ''
        proof_kind = ''
    })

    Invoke-EvidenceCaptureRepair -SliceResultPath (Join-Path $replayRoot4 'SLICE_RESULT_01.json') -ReplayRoot $replayRoot4

    $result4 = Read-JsonFile (Join-Path $replayRoot4 'SLICE_RESULT_01.json')

    $hasCmd4 = -not [string]::IsNullOrWhiteSpace([string]$result4.test_execution_command)
    Assert-True -Name 'test_execution_command set for BUILD SUCCESS (space) evidence' -Condition $hasCmd4

    $hasClass4 = $result4.test_execution_command -match 'MyServiceTest'
    Assert-True -Name 'test_execution_command contains MyServiceTest class' -Condition $hasClass4

    Write-Host "Scenario 4 PASS: BUILD SUCCESS space format triggers repair"

    # ============================================================
    # Summary
    # ============================================================
    Write-Host "`n=== All Scenarios Passed ==="
    [ordered]@{
        status = 'PASS'
        script = $PSCommandPath
        version = 'v635'
        evolution_type = 'nl_only_executable_evidence_capture_repair'
        scenarios = @(
            'scenario1_v634_nl_only_with_test_class',
            'scenario2_existing_command_preserved',
            'scenario3_no_test_class_skipped',
            'scenario4_build_success_space_format'
        )
    } | ConvertTo-Json -Depth 6
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
