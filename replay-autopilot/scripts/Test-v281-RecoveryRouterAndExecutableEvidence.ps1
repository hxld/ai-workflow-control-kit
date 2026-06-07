# Test-v281-RecoveryRouterAndExecutableEvidence.ps1
# Tests for v281 tooling evolution: recovery router, pre-flight validation, and executable evidence gate

param()

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $scriptRoot ('.tmp\v281-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

function New-TempReplayRoot {
    $path = Join-Path $tempRoot ([guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function New-TempWorktree {
    param([string]$ReplayRoot)
    $path = Join-Path $ReplayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Test-RecoveryRouter {
    # Test recovery router for various blocker types

    $cases = New-Object System.Collections.Generic.List[string]

    # Test 1: Transient rate limit blocker
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 1 -BlockerReason 'rate limit exceeded' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_1.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'rate_limit_blocker_is_transient' ($recovery.blocker_category -eq 'transient'))) | Out-Null
    $cases.Add((Assert-True 'rate_limit_should_retry' ($recovery.should_retry -eq $true))) | Out-Null
    $cases.Add((Assert-True 'rate_limit_action_correct' ($recovery.recovery_action -eq 'RETRY_AFTER_QUOTA_RESET'))) | Out-Null

    # Test 2: Authentication blocker
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 2 -BlockerReason 'authentication failed' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_2.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'auth_blocker_is_transient' ($recovery.blocker_category -eq 'transient'))) | Out-Null
    $cases.Add((Assert-True 'auth_should_retry' ($recovery.should_retry -eq $true))) | Out-Null

    # Test 3: Carrier authorization stop (fail-closed)
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 3 -BlockerReason 'carrier_authorization_stop' -ForcedFamily 'core_entry' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_3.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'carrier_auth_blocker_is_fail_closed' ($recovery.blocker_category -eq 'fail_closed'))) | Out-Null
    $cases.Add((Assert-True 'carrier_auth_should_stop' ($recovery.should_stop -eq $true))) | Out-Null
    $cases.Add((Assert-True 'carrier_auth_should_not_retry' ($recovery.should_retry -eq $false))) | Out-Null
    $cases.Add((Assert-True 'carrier_auth_has_concrete_steps' ($recovery.concrete_steps.Count -gt 0))) | Out-Null

    # Test 4: Tooling enforcement stop
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 4 -BlockerReason 'tooling_enforcement_stop' -ForcedFamily 'stateful_side_effect' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_4.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'tooling_enforcement_is_fail_closed' ($recovery.blocker_category -eq 'fail_closed'))) | Out-Null
    $cases.Add((Assert-True 'tooling_enforcement_should_stop' ($recovery.should_stop -eq $true))) | Out-Null
    $cases.Add((Assert-True 'tooling_enforcement_action_correct' ($recovery.recovery_action -eq 'EVIDENCE_AUTHORIZATION_GAP'))) | Out-Null

    # Test 5: Wrong test surface
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 5 -BlockerReason 'wrong_test_surface' -ForcedFamily 'deploy_export_page' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_5.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'wrong_test_surface_is_fail_closed' ($recovery.blocker_category -eq 'fail_closed'))) | Out-Null
    $cases.Add((Assert-True 'wrong_test_surface_should_stop' ($recovery.should_stop -eq $true))) | Out-Null
    $cases.Add((Assert-True 'wrong_test_surface_action_correct' ($recovery.recovery_action -eq 'TEST_SURFACE_REPAIR'))) | Out-Null

    # Test 6: Side effect ledger gap
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 6 -BlockerReason 'side_effect_ledger_gap' -ForcedFamily 'stateful_side_effect' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_6.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'side_effect_ledger_is_fail_closed' ($recovery.blocker_category -eq 'fail_closed'))) | Out-Null
    $cases.Add((Assert-True 'side_effect_ledger_should_stop' ($recovery.should_stop -eq $true))) | Out-Null
    $cases.Add((Assert-True 'side_effect_ledger_action_correct' ($recovery.recovery_action -eq 'SIDE_EFFECT_EVIDENCE_REPAIR'))) | Out-Null

    # Test 7: Implementation after blocked RED
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 7 -BlockerReason 'implementation_after_blocked_red' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_7.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'implementation_after_blocked_red_is_fail_closed' ($recovery.blocker_category -eq 'fail_closed'))) | Out-Null
    $cases.Add((Assert-True 'implementation_after_blocked_red_action_correct' ($recovery.recovery_action -eq 'TDD_RED_PHASE_REPAIR'))) | Out-Null

    # Test 8: Executor failure without result
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 8 -BlockerReason 'executor_failed_without_result' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_8.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'executor_failure_should_retry' ($recovery.should_retry -eq $true))) | Out-Null
    $cases.Add((Assert-True 'executor_failure_not_stop' ($recovery.should_stop -eq $false))) | Out-Null

    # Test 9: Unknown blocker defaults to stop
    $replayRoot = New-TempReplayRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot -SliceIndex 9 -BlockerReason 'unknown blocker reason' | Out-Null
    $recovery = Get-Content -LiteralPath (Join-Path $replayRoot 'RECOVERY_ACTION_9.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'unknown_blocker_should_stop' ($recovery.should_stop -eq $true))) | Out-Null
    $cases.Add((Assert-True 'unknown_blocker_action_correct' ($recovery.recovery_action -eq 'UNKNOWN_BLOCKER'))) | Out-Null

    return @($cases)
}

function Test-ExecutableEvidenceGate {
    $cases = New-Object System.Collections.Generic.List[string]

    # Test 1: Helper-only binding for closed family should fail
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        target_subsurface_or_carrier = 'MyHelperUtil'
        production_boundary = 'helper-only utility class'
        proof_kind = 'static_contract'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        implemented_files = @('src/test/java/MyHelperUtilTest.java')
        gap_flags = @()
        tests = @()
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'helper_only_closure_fails_gate' ($exitCode -ne 0))) | Out-Null

    $gate = Get-Content -LiteralPath (Join-Path $replayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'helper_only_has_wrong_test_surface_issue' ($gate.issues -contains 'wrong_test_surface:helper_only_closure_claim'))) | Out-Null

    # Test 2: Real entry binding for closed family should pass
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        target_subsurface_or_carrier = 'MyFacadeImpl#execute'
        production_boundary = 'Facade implementation'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @('core_entry')
        implemented_files = @('src/main/java/MyFacadeImpl.java', 'src/test/java/MyFacadeImplTest.java')
        gap_flags = @()
        closed_assertions = @(
            'MyFacadeImpl#execute request/response business return value is asserted through the real facade entry'
        )
        side_effect_evidence = @{
            status = 'CLOSED'
            entry_call = 'MyFacadeImpl#execute(request)'
            expected_writes_or_outputs = @('response status field returned from business path')
            red_result = 'BUSINESS_ASSERTION_FAILED'
            green_result = 'BUSINESS_ASSERTION_PASSED'
        }
        tests = @(
            @{ phase = 'RED'; result = 'fail'; evidence = 'assert response status expected business value but implementation returns null' }
            @{ phase = 'GREEN'; result = 'pass'; evidence = 'verify MyFacadeImpl#execute returns expected response status and payload value' }
        )
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'real_entry_binding_passes_gate' ($exitCode -eq 0))) | Out-Null

    # Test 3: Stateful family without executable evidence should fail
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sideEffectLedger = @"
# Side Effect Ledger

This slice tests the helper class only.
"@
    Set-Content -LiteralPath (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') -Value $sideEffectLedger -Encoding UTF8

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        target_subsurface_or_carrier = 'MyService#process'
        production_boundary = 'Service layer'
        proof_kind = 'static_contract'
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @('stateful_side_effect')
        implemented_files = @('src/main/java/MyService.java', 'src/test/java/MyServiceTest.java')
        gap_flags = @()
        tests = @(@{ phase = 'RED'; result = 'fail'; evidence = 'compilation failed' })
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'stateful_static_proof_fails_gate' ($exitCode -ne 0))) | Out-Null

    $gate = Get-Content -LiteralPath (Join-Path $replayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'stateful_static_proof_has_side_effect_issue' ($gate.issues -contains 'side_effect_ledger_gap:static_proof_for_stateful_family'))) | Out-Null

    # Test 4: Stateful family with proper evidence should pass
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sideEffectLedger = @"
# Side Effect Ledger

This slice tests the stateful side effect:
- Insert task record into database
- Verify task status change
- Transaction rollback on error
"@
    Set-Content -LiteralPath (Join-Path $replayRoot 'SIDE_EFFECT_LEDGER.md') -Value $sideEffectLedger -Encoding UTF8

    $testCharter = @"
# Test Charter

## RED Command
mvn test -Dtest=MyServiceTest#testInsertTask

## Expected RED Failure
throws Exception due to missing implementation

## GREEN Command
mvn test -Dtest=MyServiceTest#testInsertTask

## Evidence File
test-insert-task.log shows task record inserted
"@
    Set-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.md') -Value $testCharter -Encoding UTF8

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        target_subsurface_or_carrier = 'MyService#insertTask'
        production_boundary = 'Service layer with transaction'
        proof_kind = 'stateful_side_effect'
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/MyService.java', 'src/test/java/MyServiceTest.java')
        gap_flags = @()
        tests = @(
            @{ phase = 'RED'; result = 'fail'; evidence = 'Test fails: cannot insert task, assertEquals(0, taskDao.count()) before insert' }
            @{ phase = 'GREEN'; result = 'pass'; evidence = 'Task inserted successfully, assertEquals(1, taskDao.count()) after insert' }
        )
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'stateful_with_evidence_passes_gate' ($exitCode -eq 0))) | Out-Null

    # Test 5: Implementation after blocked RED should fail
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        target_subsurface_or_carrier = 'MyFacade#execute'
        production_boundary = 'Facade layer'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @('core_entry')
        closed_requirement_families = @()
        implemented_files = @('src/main/java/MyFacade.java') # Implementation happened
        gap_flags = @()
        tests = @(@{ phase = 'RED'; result = 'blocked'; evidence = 'Test infrastructure not available' })
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'implementation_after_blocked_red_fails' ($exitCode -ne 0))) | Out-Null

    $gate = Get-Content -LiteralPath (Join-Path $replayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'implementation_after_blocked_red_detected' ($gate.issues -contains 'feedback_loop_blocker:implementation_after_blocked_red'))) | Out-Null

    # Test 6: Test-only files for closed family should fail
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    $sliceResult = [ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        target_subsurface_or_carrier = 'MyFacade#execute'
        production_boundary = 'Facade layer'
        proof_kind = 'real_entry_behavior'
        touched_requirement_families = @()
        closed_requirement_families = @('core_entry')
        implemented_files = @('src/test/java/MyFacadeTest.java') # Only test file
        gap_flags = @()
        tests = @()
    }
    $sliceResultPath = Join-Path $replayRoot 'SLICE_RESULT_01.json'
    $sliceResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sliceResultPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-ExecutableEvidenceGate.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -SliceResultPath $sliceResultPath -SliceIndex 1 | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'test_only_files_fails_gate' ($exitCode -ne 0))) | Out-Null

    $gate = Get-Content -LiteralPath (Join-Path $replayRoot 'EXECUTABLE_EVIDENCE_GATE_01.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'test_only_files_has_wrong_test_surface' ($gate.issues -contains 'wrong_test_surface:test_only_production_missing'))) | Out-Null

    return @($cases)
}

function Test-PreflightGate {
    $cases = New-Object System.Collections.Generic.List[string]

    # Test 1: Preflight SKIP when no pom.xml
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-PreflightTestCompilation.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -ProjectRoot $worktree | Out-Null
    $exitCode = $LASTEXITCODE
    $cases.Add((Assert-True 'preflight_skip_without_pom' ($exitCode -eq 0))) | Out-Null

    $result = Get-Content -LiteralPath (Join-Path $replayRoot 'PREFLIGHT_TEST_COMPILATION.json') -Raw | ConvertFrom-Json
    $cases.Add((Assert-True 'preflight_skip_status' ($result.status -eq 'SKIP'))) | Out-Null
    $cases.Add((Assert-True 'preflight_skip_decision' ($result.decision -eq 'ALLOW'))) | Out-Null

    # Test 2: Preflight BLOCKER written on compilation failure simulation
    # (We can't easily simulate a real Maven failure without a real project,
    # so we test that the script structure is correct)
    $replayRoot = New-TempReplayRoot
    $worktree = New-TempWorktree -ReplayRoot $replayRoot

    # Create a mock pom.xml
    $pomContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>test</groupId>
    <artifactId>test</artifactId>
    <version>1.0</version>
</project>
"@
    Set-Content -LiteralPath (Join-Path $worktree 'pom.xml') -Value $pomContent -Encoding UTF8

    # Run with very short timeout to trigger timeout (simulating failure)
    # Use a command that will hang on Windows to simulate timeout
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-PreflightTestCompilation.ps1') `
        -ReplayRoot $replayRoot -Worktree $worktree -ProjectRoot $worktree -TimeoutSeconds 1 -MavenCommand 'ping' | Out-Null
    $exitCode = $LASTEXITCODE
    # Should fail with timeout
    $cases.Add((Assert-True 'preflight_timeout_detected' ($exitCode -ne 0))) | Out-Null

    $result = Get-Content -LiteralPath (Join-Path $replayRoot 'PREFLIGHT_TEST_COMPILATION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cases.Add((Assert-True 'preflight_timeout_status' ($result.status -eq 'TIMEOUT'))) | Out-Null
    $cases.Add((Assert-True 'preflight_timeout_blocked' ($result.decision -eq 'BLOCKED'))) | Out-Null

    # Check blocker file was written
    $blockerExists = Test-Path -LiteralPath (Join-Path $replayRoot 'PREFLIGHT_BLOCKER.md')
    $cases.Add((Assert-True 'preflight_blocker_written' ($blockerExists -eq $true))) | Out-Null

    return @($cases)
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $allCases = New-Object System.Collections.Generic.List[string]

    Write-Host "Testing v281 Recovery Router..."
    $recoveryCases = Test-RecoveryRouter
    foreach ($case in $recoveryCases) { $allCases.Add($case) | Out-Null }

    Write-Host "Testing v281 Executable Evidence Gate..."
    $evidenceCases = Test-ExecutableEvidenceGate
    foreach ($case in $evidenceCases) { $allCases.Add($case) | Out-Null }

    Write-Host "Testing v281 Preflight Gate..."
    $preflightCases = Test-PreflightGate
    foreach ($case in $preflightCases) { $allCases.Add($case) | Out-Null }

    $result = [ordered]@{
        status = 'PASS'
        test_name = 'v281_tooling_evolution'
        assertions = $allCases.Count
        cases = @($allCases)
    }
    $result | ConvertTo-Json -Depth 6

} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
