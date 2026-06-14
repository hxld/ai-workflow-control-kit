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

function Write-Json {
    param($Object, [string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-SliceResult {
    param(
        [string]$EvidenceFile = '',
        [string[]]$EvidenceFiles = @()
    )

    $charter = [ordered]@{
        proof_kind = 'real_entry_behavior'
        production_entry = 'SampleCarrier.execute(Long caseId)'
        state_or_output = 'sample output emitted'
        must_not = 'no unrelated write'
        RED_command = 'mvn -Dtest=SampleCarrierTest#red test'
        expected_RED_failure = 'business assertion failed before implementation'
        GREEN_command = 'mvn -Dtest=SampleCarrierTest test'
    }
    if (-not [string]::IsNullOrWhiteSpace($EvidenceFile)) {
        $charter.evidence_file = $EvidenceFile
    }
    if ($EvidenceFiles.Count -gt 0) {
        $charter.evidence_files = @($EvidenceFiles)
    }

    return [ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'workflow pre-gates and evidence files'
        slice_type = 'exact_contract_slice'
        slice_status = 'DONE'
        coverage_delta = 100
        target_subsurface_or_carrier = 'SampleCarrier.execute(Long caseId)'
        required_sibling_surfaces = @()
        production_boundary = 'SampleCarrier.execute(Long caseId)'
        proof_kind = 'real_entry_behavior'
        real_carrier_kind = 'production_service'
        forbidden_substitute_check = 'passed'
        red_expectation = 'RED fails on missing sample output'
        test_compilation_exit_code = 0
        test_execution_exit_code = 0
        implemented_files = @(
            'sample-core/src/main/java/com/example/SampleCarrier.java',
            'sample-core/src/test/java/com/example/SampleCarrierTest.java',
            'sample-core/src/test/java/com/example/SampleCarrierOtherTest.java'
        )
        current_slice_changed_files = @(
            'sample-core/src/main/java/com/example/SampleCarrier.java',
            'sample-core/src/test/java/com/example/SampleCarrierTest.java',
            'sample-core/src/test/java/com/example/SampleCarrierOtherTest.java'
        )
        tests = @(
            [ordered]@{
                command = 'mvn -Dtest=SampleCarrierTest#red test'
                phase = 'RED'
                result = 'fail'
                evidence = 'business assertion failed before implementation'
            },
            [ordered]@{
                command = 'mvn -Dtest=SampleCarrierTest test'
                phase = 'GREEN'
                result = 'pass'
                evidence = 'BUILD SUCCESS; Tests run: 1, Failures: 0'
            }
        )
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'SampleCarrier.execute(Long caseId)'
            expected_writes_or_outputs = @('sample output emitted')
            must_not_writes = @('no unrelated write')
            test_name = 'SampleCarrierTest'
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        behavior_test_charter = $charter
        closed_assertions = @('assertEquals("sample", result.getValue())')
        must_not_assertions = @('no unrelated write')
        remaining_gaps = @()
        gap_flags = @()
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        blocker = ''
        next_recommended_slice_type = ''
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$verifier = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$prevalidator = Join-Path $scriptRoot 'Invoke-TestCharterPrevalidator.ps1'
$prompt = Join-Path $repoRoot 'prompts\phase1-slice-executor.prompt.md'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("workflow-pregates-v500-" + [guid]::NewGuid().ToString('N'))

try {
    $runSliceLoopText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    $prevalidatorText = Get-Content -LiteralPath $prevalidator -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8

    Assert-True 'runner_splits_behavior_charter_evidence_files' ($runSliceLoopText.Contains('Get-SliceEvidenceFiles') -and $runSliceLoopText.Contains('evidence_files'))
    Assert-True 'runner_has_same_module_surface_gate' ($runSliceLoopText.Contains('Test-TestFileMatchesProductionModule') -and $runSliceLoopText.Contains('WRONG_TEST_SURFACE'))
    Assert-True 'runner_has_post_green_exact_contract_gate' ($runSliceLoopText.Contains('exact_contract_post_green_not_closed'))
    Assert-True 'runner_has_pre_implementation_charter_stop' ($runSliceLoopText.Contains('pre-implementation test charter stop') -and $runSliceLoopText.Contains('test_charter_missing_before_implementation'))
    Assert-True 'prevalidator_passthru_outputs_json_and_blocks_missing_charter' ($prevalidatorText.Contains('ConvertTo-Json') -and $prevalidatorText.Contains('NO_TEST_CHARTER') -and $prevalidatorText.Contains('TEST_CHARTER_MISSING'))
    Assert-True 'phase1_prompt_uses_evidence_files_array' ($promptText.Contains('behavior_test_charter.evidence_files') -and $promptText.Contains('Do not put comma-separated'))
    Assert-True 'phase1_prompt_mentions_same_module_and_exact_contract' ($promptText.Contains('same module') -and $promptText.Contains('Post-GREEN Exact Contract Verification'))

    $worktree = Join-Path $tempRoot 'worktree'
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $worktree, $replayRoot | Out-Null
    & git -C $worktree init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $worktree" }

    Write-Text (Join-Path $worktree 'sample-core\src\main\java\com\example\SampleCarrier.java') 'class SampleCarrier { SampleResult execute(Long caseId) { return new SampleResult(); } }'
    Write-Text (Join-Path $worktree 'sample-core\src\test\java\com\example\SampleCarrierTest.java') 'class SampleCarrierTest { void red() { org.junit.Assert.assertEquals("sample", "actual"); } }'
    Write-Text (Join-Path $worktree 'sample-core\src\test\java\com\example\SampleCarrierOtherTest.java') 'class SampleCarrierOtherTest { void red() { org.junit.Assert.assertNotNull("actual"); } }'
    & git -C $worktree add sample-core/src/main/java/com/example/SampleCarrier.java sample-core/src/test/java/com/example/SampleCarrierTest.java sample-core/src/test/java/com/example/SampleCarrierOtherTest.java | Out-Null
    & git -C $worktree -c user.name='Replay Test' -c user.email='replay-test@example.local' commit -m 'init' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $worktree" }

    Write-Json ([ordered]@{
        schema_version = 1
        slice_index = 1
        authorization = 'ALLOW'
        real_entry = 'SampleCarrier.execute'
        selected_carrier = 'SampleCarrier.execute'
        requires_side_effect_evidence = $true
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    }) (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_01.json')
    Write-Json ([ordered]@{
        schema_version = 1
        slice_index = 1
        required_for_this_slice = $true
        entry_call = 'SampleCarrier.execute'
        expected_writes_or_outputs = @('sample output emitted')
        must_not_writes = @('no unrelated write')
        test_name = 'SampleCarrierTest'
        red_result = 'BUSINESS_ASSERTION_FAILED'
        green_result = 'PASS'
        status = 'CLOSED'
    }) (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_01.json')

    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    Write-Json (New-SliceResult -EvidenceFiles @(
        'sample-core/src/test/java/com/example/SampleCarrierTest.java',
        'sample-core/src/test/java/com/example/SampleCarrierOtherTest.java'
    )) $sliceResultPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "evidence_files verifier invocation failed" }
    $arrayVerify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'evidence_files_array_is_ready' ([bool]$arrayVerify.behavior_test_charter_ready)
    Assert-True 'evidence_files_array_records_two_files' (@($arrayVerify.behavior_test_charter_evidence_files).Count -eq 2)

    Write-Json (New-SliceResult -EvidenceFile 'sample-core/src/test/java/com/example/SampleCarrierTest.java, sample-core/src/test/java/com/example/SampleCarrierOtherTest.java') $sliceResultPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "comma evidence verifier invocation failed" }
    $commaVerify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'comma_separated_evidence_is_split_for_compatibility' ([bool]$commaVerify.behavior_test_charter_ready -and @($commaVerify.behavior_test_charter_evidence_files).Count -eq 2)

    $missingCharterOut = Join-Path $tempRoot 'missing-charter.json'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $prevalidator -WorkDir $replayRoot -PassThru > $missingCharterOut
    $missingCharterExit = $LASTEXITCODE
    $missingCharter = Get-Content -LiteralPath $missingCharterOut -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'missing_test_charter_blocks_with_json' ($missingCharterExit -ne 0 -and -not [bool]$missingCharter.can_proceed -and [string]$missingCharter.verification_status -eq 'NO_TEST_CHARTER')

    Write-Host 'PASS: v500 workflow pre-gates and evidence files'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
