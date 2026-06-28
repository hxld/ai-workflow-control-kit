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

function New-TempGitWorktree {
    param([string]$Root)
    $worktree = Join-Path $Root 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src/main/java') | Out-Null
    & git -C $worktree init 2>$null | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'src/main/java/ExampleController.java') -Value 'class ExampleController {}' -Encoding UTF8
    & git -C $worktree add -A 2>$null | Out-Null
    & git -C $worktree commit -m init --allow-empty 2>$null | Out-Null
    return $worktree
}

function Invoke-Normalizer {
    param([string]$ReplayRoot, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\Normalize-SliceResultSchema.ps1') `
        -SliceResultPath $SliceResultPath `
        -ReplayRoot $ReplayRoot `
        -SliceIndex 1 `
        -InPlace | Out-Null
    return $LASTEXITCODE
}

function Invoke-SliceVerifier {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\SliceVerifier.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResult $SliceResultPath `
        -SliceIndex 1 | Out-Null
    return $LASTEXITCODE
}

function Invoke-EvidenceGate {
    param([string]$ReplayRoot, [string]$Worktree, [string]$SliceResultPath)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $ReplayRoot `
        -Worktree $Worktree `
        -SliceResultPath $SliceResultPath `
        -SliceIndex 1 | Out-Null
    return $LASTEXITCODE
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v630-red-phase-green-phase-normalization-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    # ===== Scenario 1: red_phase + green_phase with command =====
    Write-Host '[Scenario 1] red_phase + green_phase with test_execution_command...'
    $replay1 = Join-Path $tempRoot 'scenario-1'
    $worktree1 = New-TempGitWorktree -Root $replay1
    $slice1 = Join-Path $replay1 'SLICE_RESULT_01.json'
    Write-JsonFile $slice1 ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_type = 'field_contract_slice'
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        closed_assertions = @('assertEquals(saveResult, expected) — verifies save result')
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'ExampleController#save'
            expected_writes_or_outputs = @('result')
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        test_execution_command = 'mvn -pl app -am -Dtest=ExampleControllerTest#save test'
        red_phase = [ordered]@{
            status = 'PASS'
            test = 'ExampleControllerTest.testAutoFlow_HappyPath'
            result = 'Tests run: 1, Failures: 1, Errors: 0'
            assertion = 'java.lang.AssertionError: Result should not be empty'
        }
        green_phase = [ordered]@{
            status = 'PASS'
            test = 'ExampleControllerTest.testAutoFlow_HappyPath'
            result = 'Tests run: 1, Failures: 0, Errors: 0'
        }
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $replay1 -SliceResultPath $slice1) -eq 0) 'normalizer must exit 0'
    $norm1 = Read-JsonFile $slice1

    # Must normalize red_phase/green_phase into tests[] array
    Assert-True (@($norm1.tests).Count -ge 2) 'red_phase+green_phase must create 2 test entries'
    Assert-True (@($norm1.gap_flags) -contains 'agent_result_schema_normalized') 'must add normalization flag'

    # RED phase: must be first entry with fail result
    $redTest = @($norm1.tests | Where-Object { $_.phase -eq 'RED' })[0]
    Assert-True ($null -ne $redTest) 'RED test entry must exist'
    Assert-True ($redTest.result -eq 'fail') 'RED phase must normalize to fail result'
    Assert-True ($redTest.evidence -eq 'java.lang.AssertionError: Result should not be empty') 'RED evidence must carry assertion text'
    Assert-True ($redTest.command -match '-Dtest=ExampleControllerTest#save') 'RED test must preserve command'
    Assert-True ($redTest.test -eq 'ExampleControllerTest.testAutoFlow_HappyPath') 'RED test must preserve test name'

    # GREEN phase: must be second entry with pass result
    $greenTest = @($norm1.tests | Where-Object { $_.phase -eq 'GREEN' })[0]
    Assert-True ($null -ne $greenTest) 'GREEN test entry must exist'
    Assert-True ($greenTest.result -eq 'pass') 'GREEN phase must normalize to pass result'
    Assert-True ($greenTest.command -match '-Dtest=ExampleControllerTest#save') 'GREEN test must preserve command'
    Assert-True ($greenTest.test -eq 'ExampleControllerTest.testAutoFlow_HappyPath') 'GREEN test must preserve test name'

    # Evidence gate: with command in tests[] (from normalization) and closed_assertions/side_effect_evidence
    # the v630 fallback should resolve test_execution_exit_code from the GREEN test's mvn command,
    # and side-effect assertions satisfy the shallow_module/side_effect_ledger checks.
    Assert-True ((Invoke-EvidenceGate -ReplayRoot $replay1 -Worktree $worktree1 -SliceResultPath $slice1) -eq 0) 'evidence gate must pass with normalized tests command'

    # ===== Scenario 2: Only red_phase (partial slice, no GREEN) =====
    Write-Host '[Scenario 2] Only red_phase (no green_phase)...'
    $replay2 = Join-Path $tempRoot 'scenario-2'
    $worktree2 = New-TempGitWorktree -Root $replay2
    $slice2 = Join-Path $replay2 'SLICE_RESULT_01.json'
    Write-JsonFile $slice2 ([ordered]@{
        slice_index = 1
        slice_type = 'field_contract_slice'
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        red_phase = [ordered]@{
            status = 'PASS'
            test = 'ExampleControllerTest.testValidInput'
            result = 'Tests run: 1, Failures: 1, Errors: 0'
        }
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $replay2 -SliceResultPath $slice2) -eq 0) 'normalizer must handle red_phase-only'
    $norm2 = Read-JsonFile $slice2
    Assert-True (@($norm2.tests).Count -eq 1) 'red_phase-only must create 1 test entry'
    Assert-True ($norm2.tests[0].phase -eq 'RED') 'single entry must be RED phase'
    Assert-True (@($norm2.gap_flags) -contains 'agent_result_schema_normalized') 'must add normalization flag'

    # ===== Scenario 3: Only green_phase (GREEN-only, common in older agents) =====
    Write-Host '[Scenario 3] Only green_phase...'
    $replay3 = Join-Path $tempRoot 'scenario-3'
    $worktree3 = New-TempGitWorktree -Root $replay3
    $slice3 = Join-Path $replay3 'SLICE_RESULT_01.json'
    Write-JsonFile $slice3 ([ordered]@{
        slice_index = 1
        slice_type = 'field_contract_slice'
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        green_phase = [ordered]@{
            status = 'PASS'
            test = 'ExampleControllerTest.testValidInput'
            result = 'Tests run: 1, Failures: 0, Errors: 0'
        }
        test_execution_command = 'mvn -pl app -am -Dtest=ExampleControllerTest#validInput test'
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $replay3 -SliceResultPath $slice3) -eq 0) 'normalizer must handle green_phase-only'
    $norm3 = Read-JsonFile $slice3
    Assert-True (@($norm3.tests).Count -eq 1) 'green_phase-only must create 1 test entry'
    Assert-True ($norm3.tests[0].phase -eq 'GREEN') 'single entry must be GREEN phase'
    Assert-True ($norm3.tests[0].result -eq 'pass') 'GREEN phase must normalize to pass'
    Assert-True ($norm3.tests[0].command -match '-Dtest=ExampleControllerTest#validInput') 'must preserve top-level command'

    # ===== Scenario 4: Already has tests[] array + red_phase/green_phase (native format takes priority) =====
    Write-Host '[Scenario 4] Already has tests[] array (native format must not be overwritten)...'
    $replay4 = Join-Path $tempRoot 'scenario-4'
    $worktree4 = New-TempGitWorktree -Root $replay4
    $slice4 = Join-Path $replay4 'SLICE_RESULT_01.json'
    Write-JsonFile $slice4 ([ordered]@{
        slice_index = 1
        slice_type = 'field_contract_slice'
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        tests = @(
            [ordered]@{ phase = 'RED'; result = 'fail'; command = 'mvn test -Dtest=RedTest' }
            [ordered]@{ phase = 'GREEN'; result = 'pass'; command = 'mvn test -Dtest=GreenTest' }
        )
        red_phase = [ordered]@{ status = 'PASS'; test = 'RedTest'; result = 'error' }
        green_phase = [ordered]@{ status = 'PASS'; test = 'GreenTest'; result = 'Tests run: 1, Failures: 0' }
    })

    Assert-True ((Invoke-Normalizer -ReplayRoot $replay4 -SliceResultPath $slice4) -eq 0) 'normalizer must not overwrite existing tests[]'
    $norm4 = Read-JsonFile $slice4
    Assert-True (@($norm4.tests).Count -eq 2) 'existing tests[] must be preserved'
    Assert-True ($norm4.tests[0].command -match 'RedTest') 'native RED test command must survive'
    Assert-True ($norm4.tests[1].command -match 'GreenTest') 'native GREEN test command must survive'
    Assert-False (@($norm4.gap_flags) -contains 'agent_result_schema_normalized') 'existing tests[] must not trigger normalization flag'

    # ===== Scenario 5: red_phase/green_phase with Failures > 0 => result=fail =====
    Write-Host '[Scenario 5] GREEN phase with Failures>0 must normalize to fail...'
    $replay5 = Join-Path $tempRoot 'scenario-5'
    $worktree5 = New-TempGitWorktree -Root $replay5
    $slice5 = Join-Path $replay5 'SLICE_RESULT_01.json'
    Write-JsonFile $slice5 ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        target_subsurface_or_carrier = 'ExampleController'
        production_boundary = 'ExampleController#save'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/ExampleController.java', 'src/test/java/ExampleControllerTest.java')
        gap_flags = @()
        green_phase = [ordered]@{
            status = 'PASS'
            test = 'ExampleControllerTest.testMaybeFails'
            result = 'Tests run: 5, Failures: 2, Errors: 0'
        }
        test_execution_command = 'mvn -Dtest=ExampleControllerTest test'
    })
    Assert-True ((Invoke-Normalizer -ReplayRoot $replay5 -SliceResultPath $slice5) -eq 0) 'normalizer must detect green failures'
    $norm5 = Read-JsonFile $slice5
    Assert-True ($norm5.tests[0].result -eq 'fail') 'GREEN phase with 2 failures must normalize to fail'

    # ===== Scenario 6: Normalizer source contains the v630 red_phase/green_phase normalization =====
    Write-Host '[Scenario 6] Source code contains v630 normalization...'
    $normalizerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\SliceResultSchemaNormalizer.ps1') -Raw -Encoding UTF8
    Assert-True ($normalizerText -match 'v630') 'normalizer must mention v630 for red_phase/green_phase normalization'
    Assert-True ($normalizerText -match 'red_phase') 'normalizer must reference red_phase object'

    Write-Host ''
    Write-Host '=== v630 RED PHASE / GREEN PHASE NORMALIZATION ALL SCENARIOS PASS ==='

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
