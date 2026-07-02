$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v263-behavior-carrier-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Assert-Equals {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )
    if ("$Expected" -ne "$Actual") {
        throw "FAIL: $Message (expected=[$Expected], actual=[$Actual])"
    }
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Data-only carrier for MQ push requirement => BLOCKED
    # =========================================================================
    Write-Host 'Test 1: Data-only carrier (enum) for MQ push requirement => BLOCKED'
    $t1Root = Join-Path $tempRoot 'test1-data-only-carrier'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null

    @"
Feature: Send MQ notification on status change
When case status changes to DSZL, push message to MQ queue via ClaimNotifyEvent.
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t1Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t1Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'ClaimNofityType enum (production enum, existing)'
        selected_carrier = 'ClaimNofityType (production enum, existing)'
        production_boundary = 'ClaimNofityType'
        downstream_side_effect_or_output = 'MQ push via ClaimNotifyEvent.pushMsgToMQ()'
        proof_required = @('RED test for enum value', 'GREEN test for MQ push')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t1Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t1Root 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    Assert-Equals 'BLOCKED' ([string]$verify1.status) 'Test 1: Status should be BLOCKED for data-only carrier with behavior requirement'
    Assert-True (@($verify1.issues | Where-Object { [string]$_.issue -eq 'data_only_carrier_for_behavior_requirement' }).Count -gt 0) 'Test 1: Should have data_only_carrier_for_behavior_requirement issue'
    Write-Host "  PASS (status=$($verify1.status), issues=$($verify1.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 2: Real behavior carrier (Facade) for behavior requirement => ALLOW
    # =========================================================================
    Write-Host 'Test 2: Real behavior carrier (Facade) for behavior requirement => ALLOW'
    $t2Root = Join-Path $tempRoot 'test2-real-behavior-carrier'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null

    @"
Feature: Send MQ notification on status change
When case status changes to DSZL, push message to MQ queue via ClaimNotifyEvent.
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t2Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t2Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'ExamplePushService.updateCaseFlowStatus()'
        selected_carrier = 'ExamplePushService'
        production_boundary = 'ExamplePushService.updateCaseFlowStatus()'
        downstream_side_effect_or_output = 'MQ push via ClaimNotifyEvent.pushMsgToMQ()'
        proof_required = @('RED test for push behavior', 'GREEN test for MQ push')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t2Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t2Root 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    Assert-Equals 'ALLOW' ([string]$verify2.status) 'Test 2: Status should be ALLOW for real behavior carrier'
    Write-Host "  PASS (status=$($verify2.status))"
    $passCount++

    # =========================================================================
    # Test 3: Receive-only facade without Push search evidence => BLOCKED
    # =========================================================================
    Write-Host 'Test 3: Receive-only facade without Push search evidence => BLOCKED'
    $t3Root = Join-Path $tempRoot 'test3-receive-only-facade'
    New-Item -ItemType Directory -Force -Path $t3Root | Out-Null

    @"
Feature: Process return ticket callback
When insurance company sends return ticket notification, receive and process the callback.
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t3Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t3Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)'
        selected_carrier = 'ExampleReceiveFacade'
        production_boundary = 'ExampleReceiveFacade'
        downstream_side_effect_or_output = 'Process callback and save return ticket'
        proof_required = @('RED test for receive method')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t3Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @"
# Exploration Report

## Selected Real Entry

ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t3Root 2>&1
    $verify3 = $result3 | ConvertFrom-Json
    Assert-Equals 'BLOCKED' ([string]$verify3.status) 'Test 3: Status should be BLOCKED for Receive-only facade without Push search evidence'
    Assert-True (@($verify3.issues | Where-Object { [string]$_.issue -eq 'facade_direction_not_exhaustively_searched' }).Count -gt 0) 'Test 3: Should have facade_direction_not_exhaustively_searched issue'
    Write-Host "  PASS (status=$($verify3.status), issues=$($verify3.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 4: Receive facade WITH Push search evidence => ALLOW
    # =========================================================================
    Write-Host 'Test 4: Receive facade WITH Push search evidence => ALLOW'
    $t4Root = Join-Path $tempRoot 'test4-receive-with-push-evidence'
    New-Item -ItemType Directory -Force -Path $t4Root | Out-Null

    @"
Feature: Process return ticket callback
When insurance company sends return ticket notification, receive and process the callback.
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t4Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t4Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)'
        selected_carrier = 'ExampleReceiveFacade'
        production_boundary = 'ExampleReceiveFacade'
        downstream_side_effect_or_output = 'Process callback and save return ticket'
        proof_required = @('RED test for receive method')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t4Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @"
# Exploration Report

## Selected Real Entry

Searched both directions:
- Receive: ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)
- Push: ExamplePushFacade.returnTicket(ExampleTicketParam)

Selected: ExampleReceiveFacade (receives the return ticket callback)
Excluded Push: This is the receiving side, not the initiating side.
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t4Root 2>&1
    $verify4 = $result4 | ConvertFrom-Json
    Assert-Equals 'ALLOW' ([string]$verify4.status) 'Test 4: Status should be ALLOW when both directions searched'
    Write-Host "  PASS (status=$($verify4.status))"
    $passCount++

    # =========================================================================
    # Test 5: No behavior requirement => ALLOW even with enum carrier
    # =========================================================================
    Write-Host 'Test 5: No behavior requirement => ALLOW even with enum carrier'
    $t5Root = Join-Path $tempRoot 'test5-no-behavior-requirement'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null

    @"
Feature: Add new status code
Add a new case status type YBJDSH for processing stage.
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t5Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t5Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'CaseStatusType enum'
        selected_carrier = 'CaseStatusType (production enum)'
        production_boundary = 'CaseStatusType'
        downstream_side_effect_or_output = 'Enum value added'
        proof_required = @('Enum value exists')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t5Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    $result5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t5Root 2>&1
    $verify5 = $result5 | ConvertFrom-Json
    Assert-Equals 'ALLOW' ([string]$verify5.status) 'Test 5: Status should be ALLOW when no behavior requirement'
    Write-Host "  PASS (status=$($verify5.status))"
    $passCount++

    # =========================================================================
    # Test 6: Side effect entry_call is data-only for behavior requirement => BLOCKED
    # =========================================================================
    Write-Host 'Test 6: Side effect entry_call is data-only for behavior => BLOCKED'
    $t6Root = Join-Path $tempRoot 'test6-side-effect-data-entry'
    New-Item -ItemType Directory -Force -Path $t6Root | Out-Null

    @"
Feature: Send MQ notification on status change
When case status changes, push message to MQ queue.
"@ | Set-Content -LiteralPath (Join-Path $t6Root 'requirements.md') -Encoding UTF8

    @{
        schema_version = 1
        run_label = 'test'
        feature_name = 'test'
        requirement_source = (Join-Path $t6Root 'requirements.md')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t6Root 'AUTOPILOT_RUN.json') -Encoding UTF8

    @{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'ExamplePushService.updateCaseFlowStatus()'
        selected_carrier = 'ExamplePushService'
        production_boundary = 'ExamplePushService'
        downstream_side_effect_or_output = 'MQ push'
        proof_required = @('test')
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        issues = @()
        warnings = @()
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t6Root 'CARRIER_AUTHORIZATION_01.json') -Encoding UTF8

    @{
        status = 'CLOSED'
        slice_index = 1
        entry_call = 'ClaimNofityType (enum)'
        expected_writes_or_outputs = @('push MQ message via ClaimNotifyEvent')
        must_not_writes = @()
        test_name = 'Test'
        red_result = 'BUSINESS_ASSERTION_FAILED'
        green_result = 'PASS'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t6Root 'SIDE_EFFECT_EVIDENCE_01.json') -Encoding UTF8

    $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Validate-BehaviorCarrierFacade.ps1') -ReplayRoot $t6Root 2>&1
    $verify6 = $result6 | ConvertFrom-Json
    Assert-Equals 'BLOCKED' ([string]$verify6.status) 'Test 6: Status should be BLOCKED for data-only side effect entry'
    Assert-True (@($verify6.issues | Where-Object { [string]$_.issue -eq 'side_effect_entry_is_data_only_for_behavior' }).Count -gt 0) 'Test 6: Should have side_effect_entry_is_data_only_for_behavior issue'
    Write-Host "  PASS (status=$($verify6.status), issues=$($verify6.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 7: RED phase all pass should trigger warning in SliceVerifier
    # =========================================================================
    Write-Host 'Test 7: RED phase all pass should flag must_fail_closed'
    $t7Root = Join-Path $tempRoot 'test7-red-all-pass'
    New-Item -ItemType Directory -Force -Path $t7Root | Out-Null
    $t7Worktree = Join-Path $t7Root 'worktree'
    New-Item -ItemType Directory -Force -Path $t7Worktree | Out-Null
    & git init $t7Worktree 2>$null | Out-Null
    $dummyFile = Join-Path $t7Worktree 'example-core/src/main/java/com/example/project/SomeService.java'
    New-Item -ItemType Directory -Force -Path (Split-Path $dummyFile -Parent) | Out-Null
    Set-Content -LiteralPath $dummyFile -Value 'class SomeService {}' -Encoding UTF8
    & git -C $t7Worktree add -A 2>$null | Out-Null
    & git -C $t7Worktree commit -m 'init' --author='test <test@test.com>' 2>$null | Out-Null

    @{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'tracer_bullet'
        target_subsurface_or_carrier = 'SomeService.method()'
        production_boundary = 'SomeService'
        proof_kind = 'real_entry_behavior'
        implemented_files = @('example-core/src/main/java/com/example/project/SomeService.java')
        current_slice_changed_files = @('example-core/src/main/java/com/example/project/SomeService.java')
        gap_flags = @()
        closed_assertions = @('entry callable')
        closed_requirement_families = @('core_entry')
        touched_requirement_families = @('core_entry')
        tests = @(
            @{ command = 'mvn test -Dtest=SomeTest'; phase = 'RED'; result = 'pass'; evidence = 'RED passed' }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $t7Root 'SLICE_RESULT_01.json') -Encoding UTF8

    @{
        verification_status = 'PASS'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $true
        adjusted_coverage_delta = 10
        coverage_cap = 100
        has_behavior_evidence = $true
        gap_flags = @()
        authorization_blockers = @()
        warnings = @()
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $t7Root 'SLICE_VERIFY_01.json') -Encoding UTF8

    $result7 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'SliceVerifier.ps1') -ReplayRoot $t7Root -SliceResult (Join-Path $t7Root 'SLICE_RESULT_01.json') -SliceIndex 1 2>&1
    $verify7 = $result7 | ConvertFrom-Json
    Assert-Equals 'FAIL' ([string]$verify7.status) 'Test 7: SliceVerifier should FAIL when RED tests all pass'
    Assert-True ($verify7.must_fail_closed) 'Test 7: must_fail_closed should be true'
    Assert-True (@($verify7.must_fail_reasons | Where-Object { $_ -eq 'red_phase_did_not_fail' }).Count -gt 0) 'Test 7: Should have red_phase_did_not_fail reason'
    Write-Host "  PASS (status=$($verify7.status), mustFail=$($verify7.must_fail_closed))"
    $passCount++

    Write-Host ""
    Write-Host "All $passCount tests passed."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
