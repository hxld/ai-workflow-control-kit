$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v259-public-entry-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function New-MinimalPlanFixtures {
    param([string]$Root)
    $planFiles = @(
        'PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
        'PLAN_RESULT.md', 'PLAN_SELECTION.md', 'REPLAY_PLAN.md',
        'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md',
        'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md'
    )
    foreach ($file in $planFiles) {
        Set-Content -LiteralPath (Join-Path $Root $file) -Value '' -Encoding UTF8
    }
    @"
- plan_status: PROCEED
- selected_strategy: core_path
- first_slice: S1
- first_red_test: T1
"@ | Set-Content -LiteralPath (Join-Path $Root 'PLAN_RESULT.md') -Encoding UTF8
    @"
## Selected Real Entry

Primary Entry: SomeFacade.someMethod(SomeParam)
"@ | Set-Content -LiteralPath (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Encoding UTF8
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Controller entry + Mapper/Entity carrier => FAIL (carrier mismatch)
    #   This is the exact v258 canary failure scenario
    # =========================================================================
    Write-Host 'Test 1: Controller entry + Mapper/Entity carrier => public_entry_carrier_mismatch'
    $t1Root = Join-Path $tempRoot 'test1-controller-mapper'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null
    New-MinimalPlanFixtures -Root $t1Root

    @"
- selected_real_entry: ExampleModuleConfigController (POST /ai/claim/config/add)
- selected_carrier: TExampleModuleConfig entity + ExampleModuleConfigDto + TExampleModuleConfigMapper.xml
- first_red_test: ExampleModuleConfigServiceTest.testSaveWithFreeReviewAmount
- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: entity mapper insert
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1Root -Stage Plan 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    $hasMismatch = @($verify1.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True ($hasMismatch) 'Controller entry + Entity/Mapper carrier MUST trigger public_entry_carrier_mismatch'
    Write-Host "  PASS (issues=$($verify1.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 2: Facade entry + Facade carrier => PASS (no mismatch)
    # =========================================================================
    Write-Host 'Test 2: Facade entry + Facade carrier => no public_entry_carrier_mismatch'
    $t2Root = Join-Path $tempRoot 'test2-facade-facade'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null
    New-MinimalPlanFixtures -Root $t2Root

    @"
- selected_real_entry: ExampleModuleConfigFacadeImpl.saveConfig(SaveConfigRequest)
- selected_carrier: ExampleModuleConfigFacadeImpl via Facade interface
- first_red_test: ExampleModuleConfigFacadeImplTest.testSaveExemptReviewAmount
- public_entry_contract_coverage: assert ResultModel.success contains exemptReviewAmount; assert null param returns ResultModel.error
- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: facade call triggers service write
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2Root -Stage Plan 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    $hasMismatch = @($verify2.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True (-not $hasMismatch) 'Facade entry + Facade carrier should NOT trigger public_entry_carrier_mismatch'
    Write-Host "  PASS (status=$($verify2.verification_status), issues=$($verify2.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 3: Service/internal entry + Mapper/Entity proof => no mismatch (not public)
    #   Ensure internal entries are not falsely caught
    # =========================================================================
    Write-Host 'Test 3: Processor entry + Mapper side-effect => no public_entry_carrier_mismatch (internal entry)'
    $t3Root = Join-Path $tempRoot 'test3-internal-mapper'
    New-Item -ItemType Directory -Force -Path $t3Root | Out-Null
    New-MinimalPlanFixtures -Root $t3Root

    @"
- selected_real_entry: ExampleCalculatorApiTaskProcessor.onTaskSuccess()
- selected_carrier: CompensateService.writeCompensateData + ExamineFlowFacadeImpl.updateCaseStatus
- first_red_test: ExampleCalculatorApiTaskProcessorTest.testOnTaskSuccessAutoFlow
- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_service
- minimum_side_effect_or_blocker: status change 34->35 via ExamineFlowFacade
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t3Root -Stage Plan 2>&1
    $verify3 = $result3 | ConvertFrom-Json
    $hasMismatch = @($verify3.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True (-not $hasMismatch) 'Internal Processor entry should NOT trigger public_entry_carrier_mismatch'
    Write-Host "  PASS (status=$($verify3.verification_status), issues=$($verify3.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 4: Controller entry + Controller carrier => PASS (correct alignment)
    # =========================================================================
    Write-Host 'Test 4: Controller entry + Controller test carrier => no mismatch'
    $t4Root = Join-Path $tempRoot 'test4-controller-controller'
    New-Item -ItemType Directory -Force -Path $t4Root | Out-Null
    New-MinimalPlanFixtures -Root $t4Root

    @"
- selected_real_entry: ExamplePushController.pushExampleTicket(ExampleTicketParam)
- selected_carrier: ExamplePushController POST /push/return-ticket response assertion
- first_red_test: ExamplePushControllerTest.testPushExampleTicketSuccess
- public_entry_contract_coverage: assert HTTP 200 with ResultModel.success; assert invalid param returns ResultModel.error with message
- forbidden_substitute_check: passed
- proof_kind: route_export_behavior
- real_carrier_kind: production_controller_or_route
- minimum_side_effect_or_blocker: controller delegates to Facade which triggers return ticket flow
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t4Root -Stage Plan 2>&1
    $verify4 = $result4 | ConvertFrom-Json
    $hasMismatch = @($verify4.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True (-not $hasMismatch) 'Controller entry + Controller carrier should NOT trigger mismatch'
    Write-Host "  PASS (status=$($verify4.verification_status), issues=$($verify4.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 5: API entry + DTO-only carrier => FAIL (carrier mismatch)
    # =========================================================================
    Write-Host 'Test 5: API endpoint entry + DTO-only carrier => public_entry_carrier_mismatch'
    $t5Root = Join-Path $tempRoot 'test5-api-dto'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null
    New-MinimalPlanFixtures -Root $t5Root

    @"
- selected_real_entry: ClaimDataApi.getClaimDetail(String caseId)
- selected_carrier: ClaimDataDto field mapping
- first_red_test: ClaimDataDtoTest.testFieldMapping
- forbidden_substitute_check: passed
- proof_kind: payload_shape_behavior
- real_carrier_kind: production_dto
- minimum_side_effect_or_blocker: DTO fields populated from DB query
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t5Root -Stage Plan 2>&1
    $verify5 = $result5 | ConvertFrom-Json
    $hasMismatch = @($verify5.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True ($hasMismatch) 'API entry + DTO-only carrier MUST trigger public_entry_carrier_mismatch'
    Write-Host "  PASS (issues=$($verify5.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 6: v258 regression - SafeInt + retry still work
    # =========================================================================
    Write-Host 'Test 6: v258 regression - SafeInt still handles string coverage_cap'
    $t6Root = Join-Path $tempRoot 'test6-v258-regression'
    New-Item -ItemType Directory -Force -Path $t6Root | Out-Null
    New-MinimalPlanFixtures -Root $t6Root

    @"
- selected_real_entry: SomeService.processData()
- selected_carrier: SomeService internal method
- first_red_test: SomeServiceTest.testProcess
- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_service
- minimum_side_effect_or_blocker: service triggers DB write
"@ | Set-Content -LiteralPath (Join-Path $t6Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8
    # FAMILY_CONTRACT with string coverage_cap
    @{
        families = @(
            @{ id = 'core_entry'; required = $true; weight = 100; coverage_cap_if_open = $null },
            @{ id = 'deploy'; required = $false; weight = 30; coverage_cap_if_open = 'file_presence_only' }
        )
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t6Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t6Root -Stage Plan 2>&1
    $verify6 = $result6 | ConvertFrom-Json
    $hasMismatch = @($verify6.issues | Where-Object { $_ -like '*public_entry_carrier_mismatch*' }).Count -gt 0
    Assert-True (-not $hasMismatch) 'v258 regression: internal entry should not trigger public_entry_carrier_mismatch'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v259-PublicEntryContractCoverage: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v259-PublicEntryContractCoverage: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
