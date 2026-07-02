#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v700-verifier-ignore-blocked-exact-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'src\main\java'), (Join-Path $worktree 'src\test\java') | Out-Null
    Set-Content -LiteralPath (Join-Path $worktree 'src\main\java\SampleCarrier.java') -Encoding UTF8 -Value 'class SampleCarrier { void execute() {} }'
    Set-Content -LiteralPath (Join-Path $worktree 'src\test\java\SampleCarrierTest.java') -Encoding UTF8 -Value 'class SampleCarrierTest { void shouldCoverLifecycle() {} }'
    & git -C $worktree init | Out-Null
    & git -C $worktree add . | Out-Null

    Write-JsonFile (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_05.json') ([ordered]@{
        schema_version = 1
        slice_index = 5
        forced_requirement_family = 'lifecycle_cleanup_retention'
        authorization = 'ALLOW'
        real_entry = 'SampleCarrier.execute'
        selected_carrier = 'SampleCarrier.execute'
        production_boundary = 'SampleCarrier.execute'
        downstream_side_effect_or_output = 'ai_log_row; system_operator; task_completion_rows; negative_gate_failure_log'
        requires_side_effect_evidence = $true
        requires_exact_contract_assertions = $true
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        proof_required = @('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log')
        forbidden_proof = @('mock_only', 'helper_only')
        issues = @()
        warnings = @()
    })
    Write-JsonFile (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_05.json') ([ordered]@{
        schema_version = 1
        slice_index = 5
        forced_requirement_family = 'lifecycle_cleanup_retention'
        required_for_this_slice = $true
        entry_call = 'SampleCarrier.execute'
        expected_writes_or_outputs = @('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log')
        must_not_writes = @('blank content must not call persistence')
        test_name = 'SampleCarrierTest#shouldCoverLifecycle'
        red_result = 'BUSINESS_ASSERTION_FAILED'
        green_result = 'PASS'
        status = 'CLOSED'
    })
    Write-JsonFile (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_05.json') ([ordered]@{
        schema_version = 1
        slice_index = 5
        forced_requirement_family = 'lifecycle_cleanup_retention'
        required_for_this_slice = $true
        row_scope = 'side_effect_proof_required'
        rows = @(
            [ordered]@{ literal = 'ai_log_row'; symbol_or_field = 'ai_log_row'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'assert ai log row'; status = 'OPEN'; touched = $false; required_for_this_slice = $true },
            [ordered]@{ literal = 'system_operator'; symbol_or_field = 'system_operator'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'assert system operator'; status = 'OPEN'; touched = $false; required_for_this_slice = $true },
            [ordered]@{ literal = 'task_completion_rows'; symbol_or_field = 'task_completion_rows'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'assert task completion rows'; status = 'OPEN'; touched = $false; required_for_this_slice = $true },
            [ordered]@{ literal = 'negative_gate_failure_log'; symbol_or_field = 'negative_gate_failure_log'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'assert negative gate no write'; status = 'OPEN'; touched = $false; required_for_this_slice = $true }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_05.json') ([ordered]@{
        slice_index = 5
        slice_id = 'S5'
        slice_title = 'Lifecycle AI examine log retention'
        slice_type = 'stateful_success_slice'
        slice_status = 'PARTIAL'
        coverage_delta = 6
        matched_test_count = 1
        real_entry_invoked = $true
        target_subsurface_or_carrier = 'SampleCarrier.execute'
        production_boundary = 'SampleCarrier.execute'
        proof_kind = 'lifecycle_cleanup_behavior'
        red_expectation = 'business assertion should fail before production change'
        implemented_files = @('src/main/java/SampleCarrier.java', 'src/test/java/SampleCarrierTest.java')
        current_slice_changed_files = @('src/main/java/SampleCarrier.java', 'src/test/java/SampleCarrierTest.java')
        tests = @(
            [ordered]@{ command = 'mvn --% -Dtest=SampleCarrierTest#shouldCoverLifecycle test'; phase = 'RED'; result = 'fail'; evidence = 'business assertion failed before production change' },
            [ordered]@{ command = 'mvn --% -Dtest=SampleCarrierTest#shouldCoverLifecycle test'; phase = 'GREEN'; result = 'pass'; evidence = 'Tests run: 1, Failures: 0, Errors: 0, Skipped: 0' }
        )
        exact_contract_assertions = @(
            [ordered]@{ literal = 'ai_log_row'; symbol_or_field = 'ai_log_row'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = 'service behavior assertion proves database row persistence'; test_assertion = 'assert ai log row'; status = 'CLOSED'; source_type = 'code_fact' },
            [ordered]@{ literal = 'system_operator'; symbol_or_field = 'system_operator'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = 'service behavior assertion proves database row persistence'; test_assertion = 'assert system operator'; status = 'CLOSED'; source_type = 'code_fact' },
            [ordered]@{ literal = 'task_completion_rows'; symbol_or_field = 'task_completion_rows'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = 'service behavior assertion proves database row persistence'; test_assertion = 'assert task completion rows'; status = 'CLOSED'; source_type = 'code_fact' },
            [ordered]@{ literal = 'negative_gate_failure_log'; symbol_or_field = 'negative_gate_failure_log'; db_or_wire_or_display = 'db'; boundary_type = 'db'; production_boundary = 'SampleCarrier.execute'; closure_proof = 'service behavior assertion proves database row persistence'; test_assertion = 'assert negative gate no write'; status = 'CLOSED'; source_type = 'code_fact' },
            [ordered]@{ literal = 'ExampleApplyClaimApiTaskProcessor.handleTaskResponse'; symbol_or_field = 'ExampleApplyClaimApiTaskProcessor.handleTaskResponse'; db_or_wire_or_display = 'behavior'; boundary_type = 'behavior'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'matrix row remains unclosed'; status = 'BLOCKED'; source_type = 'requirement' },
            [ordered]@{ literal = '理算明细.png'; symbol_or_field = '理算明细.png'; db_or_wire_or_display = 'behavior'; boundary_type = 'behavior'; production_boundary = 'SampleCarrier.execute'; closure_proof = ''; test_assertion = 'matrix row remains unclosed'; status = 'BLOCKED'; source_type = 'requirement' }
        )
        side_effect_evidence = [ordered]@{
            status = 'CLOSED'
            entry_call = 'SampleCarrier.execute'
            expected_writes_or_outputs = @('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log')
            must_not_writes = @('blank content must not call persistence')
            test_name = 'SampleCarrierTest#shouldCoverLifecycle'
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'PASS'
        }
        behavior_test_charter = [ordered]@{
            proof_kind = 'db_persistence'
            production_entry = 'SampleCarrier.execute'
            state_or_output = 'sample database row'
            must_not = 'blank content must not call persistence'
            RED_command = 'mvn --% -Dtest=SampleCarrierTest#shouldCoverLifecycle test'
            expected_RED_failure = 'business assertion failed'
            GREEN_command = 'mvn --% -Dtest=SampleCarrierTest#shouldCoverLifecycle test'
            evidence_file = 'src/test/java/SampleCarrierTest.java'
        }
        closed_assertions = @('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log')
        must_not_assertions = @('blank content must not call persistence')
        remaining_gaps = @('other exact-contract rows belong to later slices')
        gap_flags = @()
        touched_requirement_families = @('lifecycle_cleanup_retention')
        closed_requirement_families = @('lifecycle_cleanup_retention')
        blocker = ''
        next_recommended_slice_type = 'exact_contract_slice'
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceResult (Join-Path $replayRoot 'SLICE_RESULT_05.json') `
        -SliceIndex 5 | Out-Null
    Assert-True 'verifier_exit_zero' ($LASTEXITCODE -eq 0)

    $verify = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_VERIFY_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrix = Get-Content -LiteralPath (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrixLiterals = @($matrix.rows | ForEach-Object { [string]$_.literal })
    $warnings = @($verify.warnings | ForEach-Object { [string]$_ })
    $gapFlags = @($verify.gap_flags | ForEach-Object { [string]$_ })
    $blockers = @($verify.authorization_blockers | ForEach-Object { [string]$_ })

    Assert-True 'out_of_slice_blocked_rows_are_reported_not_counted' (($warnings -join ',') -match 'out_of_slice_blocked_exact_assertions_ignored:ExampleApplyClaimApiTaskProcessor.handleTaskResponse') ($warnings -join ',')
    Assert-True 'matrix_keeps_only_current_slice_lifecycle_rows' (
        ($matrixLiterals.Count -eq 4) -and
        (($matrixLiterals -join ',') -notmatch 'ExampleApplyClaimApiTaskProcessor|理算明细')
    ) ($matrixLiterals -join ',')
    Assert-True 'minimum_exact_contract_gap_not_added_for_out_of_slice_rows' (-not ($gapFlags -contains 'exact_contract_minimum_coverage_gap')) ($gapFlags -join ',')
    Assert-True 'v348_blocker_not_expected_from_verifier_output' (-not ($blockers -contains 'exact_contract_post_green_not_closed')) ($blockers -join ',')

    Write-Host ''
    Write-Host 'v700 Verifier Ignores Out-Of-Slice Blocked Exact Rows: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
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
