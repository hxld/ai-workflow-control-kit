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
    param([string]$EvidenceFile)

    return [ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'behavior charter evidence validation'
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
            'src/main/java/SampleCarrier.java',
            'sample-server/src/test/java/com/example/SampleCarrierTest.java'
        )
        current_slice_changed_files = @(
            'src/main/java/SampleCarrier.java',
            'sample-server/src/test/java/com/example/SampleCarrierTest.java'
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
        behavior_test_charter = [ordered]@{
            proof_kind = 'real_entry_behavior'
            production_entry = 'SampleCarrier.execute(Long caseId)'
            state_or_output = 'sample output emitted'
            must_not = 'no unrelated write'
            RED_command = 'mvn -Dtest=SampleCarrierTest#red test'
            expected_RED_failure = 'business assertion failed before implementation'
            GREEN_command = 'mvn -Dtest=SampleCarrierTest test'
            evidence_file = $EvidenceFile
        }
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
$verifier = Join-Path $scriptRoot 'Verify-SliceClosure.ps1'
$runSliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$prompt = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\phase1-slice-executor.prompt.md'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("behavior-charter-evidence-v499-" + [guid]::NewGuid().ToString('N'))

try {
    $runSliceLoopText = Get-Content -LiteralPath $runSliceLoop -Raw -Encoding UTF8
    $promptText = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8
    Assert-True 'v348_reports_invalid_behavior_charter_evidence_file' ($runSliceLoopText.Contains('behavior_test_charter_evidence_file_invalid') -and $runSliceLoopText.Contains('INVALID_EVIDENCE_FILE'))
    Assert-True 'phase1_prompt_forbids_self_referential_evidence_file' ($promptText.Contains('behavior_test_charter.evidence_file') -and $promptText.Contains('SLICE_RESULT_*.json'))

    $worktree = Join-Path $tempRoot 'worktree'
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $worktree, $replayRoot | Out-Null
    & git -C $worktree init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $worktree" }

    Write-Text (Join-Path $worktree 'src\main\java\SampleCarrier.java') 'class SampleCarrier { SampleResult execute(Long caseId) { return new SampleResult(); } }'
    Write-Text (Join-Path $worktree 'sample-server\src\test\java\com\example\SampleCarrierTest.java') 'class SampleCarrierTest { void red() { org.junit.Assert.assertEquals("sample", "actual"); } }'
    & git -C $worktree add src/main/java/SampleCarrier.java sample-server/src/test/java/com/example/SampleCarrierTest.java | Out-Null
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
    Write-Json (New-SliceResult -EvidenceFile 'SLICE_RESULT_01.json') $sliceResultPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "invalid evidence verifier invocation failed" }

    $invalidVerify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'self_referential_evidence_file_is_not_ready' (-not [bool]$invalidVerify.behavior_test_charter_ready)
    Assert-True 'self_referential_evidence_file_clears_behavior_evidence' (-not [bool]$invalidVerify.has_behavior_evidence)
    Assert-True 'self_referential_evidence_file_warns_invalid' (@($invalidVerify.warnings) -contains 'behavior_test_charter_evidence_file_invalid')
    Assert-True 'self_referential_evidence_file_warns_generated_artifact' (@($invalidVerify.warnings) -contains 'behavior_test_charter_evidence_file_generated_artifact')
    Assert-True 'self_referential_evidence_file_sets_charter_gap' (@($invalidVerify.gap_flags) -contains 'behavior_test_charter_gap')
    Assert-True 'self_referential_evidence_file_blocks_authorization' (@($invalidVerify.authorization_blockers) -contains 'behavior_test_charter_gap')

    Write-Json (New-SliceResult -EvidenceFile 'sample-server/src/test/java/com/example/SampleCarrierTest.java') $sliceResultPath
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $replayRoot -Worktree $worktree -SliceResult $sliceResultPath -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "valid evidence verifier invocation failed" }

    $validVerify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'valid_test_source_evidence_file_is_ready' ([bool]$validVerify.behavior_test_charter_ready)
    Assert-True 'valid_test_source_evidence_file_has_no_invalid_warning' (-not (@($validVerify.warnings) -contains 'behavior_test_charter_evidence_file_invalid'))
    Assert-True 'valid_test_source_evidence_file_resolves_under_worktree' ([string]$validVerify.behavior_test_charter_evidence_resolved_path -match 'sample-server\\src\\test\\java\\com\\example\\SampleCarrierTest\.java$')

    Write-Host 'PASS: v499 behavior charter evidence file validation'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}
