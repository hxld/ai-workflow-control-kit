#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for v632 proofs normalization and evidence capture in SliceVerifier.

.DESCRIPTION
Validates that:
1. SliceResultSchemaNormalizer converts free-text proofs object -> tests[] array
2. SliceVerifier backfills PREFLIGHT_TEST_COMPILATION.json evidence after normalization
3. Verify-SliceClosure reads the injected compilation evidence
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'
$testScriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $testScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 16)
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

function New-TempGitWorktree {
    param([string]$Root)
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    & git -C $worktree init 2>$null | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src/main/java') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'src/main/java/ExampleController.java') -Value 'class ExampleController {}' -Encoding UTF8
    & git -C $worktree add -A 2>$null | Out-Null
    & git -C $worktree commit -m init --allow-empty 2>$null | Out-Null
    return $worktree
}

function Invoke-Normalizer {
    param([string]$ReplayRoot, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'Normalize-SliceResultSchema.ps1') `
        -SliceResultPath $SliceResultPath `
        -ReplayRoot $ReplayRoot `
        -SliceIndex 1 `
        -InPlace | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Normalizer failed with exit $LASTEXITCODE" }
}

function Invoke-SliceVerifier {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'SliceVerifier.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResult $SliceResultPath `
        -SliceIndex 1 2>&1 | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v632-proofs-normalization-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $assertionCount = 0
    $passedCount = 0

    # ===== Scenario 1: proofs -> tests[] normalization =====
    Write-Host '[Scenario 1] proofs -> tests[] normalization...'
    $replay1 = Join-Path $tempRoot 'scenario-1'
    $worktree1 = New-TempGitWorktree -Root $replay1
    $slice1 = Join-Path $replay1 'SLICE_RESULT_01.json'

    # Create a PREFLIGHT_TEST_COMPILATION.json so evidence is backfilled
    Write-JsonFile (Join-Path $replay1 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        status = 'PASS'
        exit_code = 0
        maven_command_args = '-f .\worktree\pom.xml -s .\settings.xml test-compile -q -DskipTests'
    })

    # Slice result with proofs format (tracer-bullet style)
    Write-JsonFile $slice1 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_name = 'S1_AutoFlowOrchestration'
        entry_point = 'ExampleController.handleTaskResponse'
        production_carrier = 'ExampleService.executeAutoFlow'
        status = 'PASS'
        proof_kind = 'real_entry_behavior'
        proofs = [ordered]@{
            red_expectation_step1 = 'PASS - compilation failure when ExampleService class did not exist'
            red_expectation_step2 = "PASS - verify(mockService).execute(eq(100L)) failed with 'Wanted but not invoked'"
            green_wiring = 'PASS - @Autowired ExampleService + conditional hook after line 494'
            green_test = 'PASS - test passes with BUILD SUCCESS, Tests run: 1, Failures: 0, Errors: 0'
            non_regression = 'PASS - manual task does NOT trigger executeAutoFlow (verifyZeroInteractions)'
        }
        exact_contract_assertions = @(
            [ordered]@{ literal = 'handleTaskResponse'; status = 'CLOSED'; evidence = 'Behavioral test' }
        )
        production_diff = [ordered]@{
            modified_files = @('src/main/java/ExampleController.java')
            created_files = @('src/main/java/ExampleService.java', 'src/test/java/ExampleServiceTest.java')
            changes = [ordered]@{}
        }
    })

    Invoke-Normalizer -ReplayRoot $replay1 -SliceResultPath $slice1
    $norm1 = Read-JsonFile $slice1
    $assertionCount++

    # Must have tests[] from proofs normalization
    $testsCount1 = @($norm1.tests).Count
    Assert-True ($testsCount1 -ge 2) "proofs must create >= 2 test entries (got $testsCount1)"
    $assertionCount++

    # Must have RED test entries
    $redTests1 = @($norm1.tests | Where-Object { $_.phase -eq 'RED' })
    Assert-True ($redTests1.Count -ge 1) 'RED test entries must be created from red_* proofs'
    Assert-True ($redTests1[0].result -eq 'fail') 'RED proof must normalize to fail result'
    $assertionCount += 2

    # Must have GREEN test entries
    $greenTests1 = @($norm1.tests | Where-Object { $_.phase -eq 'GREEN' })
    Assert-True ($greenTests1.Count -ge 1) 'GREEN test entries must be created from green_* proofs'
    Assert-True ($greenTests1[0].result -eq 'pass') 'GREEN proof must normalize to pass result'
    $assertionCount += 2

    # Must have normalization flag
    Assert-True (@($norm1.gap_flags) -contains 'agent_result_schema_normalized') 'must add schema normalization flag'
    $assertionCount++

    # ===== Scenario 2: SliceVerifier backfills preflight evidence =====
    Write-Host '[Scenario 2] SliceVerifier backfills preflight evidence...'
    $replay2 = Join-Path $tempRoot 'scenario-2'
    $worktree2 = New-TempGitWorktree -Root $replay2
    $slice2 = Join-Path $replay2 'SLICE_RESULT_01.json'
    $sliceVerify2 = Join-Path $replay2 'SLICE_VERIFY_01.json'

    # Create PREFLIGHT_TEST_COMPILATION.json
    Write-JsonFile (Join-Path $replay2 'PREFLIGHT_TEST_COMPILATION.json') ([ordered]@{
        status = 'PASS'
        exit_code = 0
        maven_command_args = '-f .\worktree\pom.xml --% -s .\settings.xml test-compile -q -DskipTests'
    })

    # Slice with proofs (no test_compilation fields yet)
    Write-JsonFile $slice2 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        proofs = [ordered]@{
            red_step = 'PASS - compilation error expected but not produced'
            green_result = 'PASS - test passes with BUILD SUCCESS'
        }
    })

    Invoke-SliceVerifier -ReplayRoot $replay2 -Worktree $worktree2 -SliceResultPath $slice2
    $verify2 = Read-JsonFile $sliceVerify2
    $assertionCount++

    # Verify-SliceClosure should detect compilation evidence from preflight
    Assert-True ([bool]$verify2.test_compilation_evidence) 'SLICE_VERIFY must report test_compilation_evidence=true from preflight backfill'
    Assert-True ($null -ne $verify2.test_compilation_exit_code) 'SLICE_VERIFY must have test_compilation_exit_code'
    $assertionCount += 2

    # SLICE_VERIFY should not have test_compilation_evidence_missing flag
    $hasMissingCompileFlag = @($verify2.gap_flags) -contains 'test_compilation_evidence_missing'
    Assert-False $hasMissingCompileFlag 'SLICE_VERIFY must not have test_compilation_evidence_missing when preflight exists'
    $assertionCount++

    # ===== Scenario 3: No PREFLIGHT file -> no evidence injection =====
    Write-Host '[Scenario 3] No PREFLIGHT file -> no evidence injection...'
    $replay3 = Join-Path $tempRoot 'scenario-3'
    $worktree3 = New-TempGitWorktree -Root $replay3
    $slice3 = Join-Path $replay3 'SLICE_RESULT_01.json'

    Write-JsonFile $slice3 ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        proof_kind = 'real_entry_behavior'
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java')
        gap_flags = @()
        proofs = [ordered]@{ red_test = 'FAIL - compilation error'; green_result = 'PASS - BUILD SUCCESS' }
    })

    Invoke-Normalizer -ReplayRoot $replay3 -SliceResultPath $slice3
    $norm3 = Read-JsonFile $slice3

    # Without PREFLIGHT, test_compilation_exit_code must remain null
    Assert-True ($null -eq $norm3.test_compilation_exit_code) 'without PREFLIGHT, test_compilation_exit_code must be null'
    $assertionCount++

    # proofs normalization must still work
    $tests3 = @($norm3.tests)
    Assert-True ($tests3.Count -ge 2) 'proofs normalization must work without PREFLIGHT file'
    $assertionCount++

    # ===== Scenario 4: proofs with embedded maven command =====
    Write-Host '[Scenario 4] proofs with embedded maven command...'
    $replay4 = Join-Path $tempRoot 'scenario-4'
    $worktree4 = New-TempGitWorktree -Root $replay4
    $slice4 = Join-Path $replay4 'SLICE_RESULT_01.json'

    Write-JsonFile $slice4 ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        proof_kind = 'real_entry_behavior'
        implemented_files = @('src/main/java/ExampleController.java')
        gap_flags = @()
        proofs = [ordered]@{
            green_test = 'PASS - mvn --% -Dtest=ExampleTest -Dsurefire.failIfNoSpecifiedTests=false test reports BUILD SUCCESS'
        }
    })

    Invoke-Normalizer -ReplayRoot $replay4 -SliceResultPath $slice4
    $norm4 = Read-JsonFile $slice4

    $green4 = @($norm4.tests | Where-Object { $_.phase -eq 'GREEN' })[0]
    Assert-True ($null -ne $green4.command) 'embedded mvn command in proof must be extracted'
    Assert-True ($green4.command -match '-Dtest=ExampleTest') 'extracted command must contain -Dtest flag'
    $assertionCount += 2

    # ===== Scenario 5: Normalizer source contains v632 proofs normalization =====
    Write-Host '[Scenario 5] Source code contains v632 proofs normalization...'
    $normalizerText = Get-Content -LiteralPath (Join-Path $repoRoot 'SliceResultSchemaNormalizer.ps1') -Raw -Encoding UTF8
    Assert-True ($normalizerText -match 'v632') 'normalizer must mention v632 for proofs normalization'
    Assert-True ($normalizerText -match 'proofs') 'normalizer must reference proofs object'
    $assertionCount += 2

    Write-Host ''
    Write-Host "=== v632 PROOFS NORMALIZATION AND EVIDENCE CAPTURE: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
    exit 0

} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
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
