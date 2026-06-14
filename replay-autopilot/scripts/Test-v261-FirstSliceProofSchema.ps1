$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v261-schema-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Test-HasIssue {
    param(
        [object]$VerifyResult,
        [string]$Pattern
    )
    return (@($VerifyResult.issues | Where-Object { $_ -like $Pattern }).Count -gt 0)
}

function New-MinimalPlanFixtures {
    param([string]$Root)
    $worktreeSource = Join-Path $Root 'worktree\claim-api\src\main\java\com\example'
    New-Item -ItemType Directory -Force -Path $worktreeSource | Out-Null
    @'
package com.example;

public class SomeFacade {
    public void someMethod(SomeParam param) {
    }
}
'@ | Set-Content -LiteralPath (Join-Path $worktreeSource 'SomeFacade.java') -Encoding UTF8
    @'
package com.example;

public class SomeParam {
}
'@ | Set-Content -LiteralPath (Join-Path $worktreeSource 'SomeParam.java') -Encoding UTF8
    @'
package com.example;

public class SomeService {
    public void processData() {
    }
}
'@ | Set-Content -LiteralPath (Join-Path $worktreeSource 'SomeService.java') -Encoding UTF8

    $planFiles = @(
        'PLAN_CANDIDATE_1.md', 'PLAN_CANDIDATE_2.md', 'PLAN_CANDIDATE_3.md',
        'PLAN_SELECTION.md', 'REPLAY_PLAN.md'
    )
    foreach ($file in $planFiles) {
        Set-Content -LiteralPath (Join-Path $Root $file) -Value '' -Encoding UTF8
    }
    @"
- plan_status: PROCEED
- selected_strategy: core_path
- first_slice: S1
- first_red_test: T1
- oracle_production_file_overlap: 100%
- oracle_high_weight_coverage: 1/1
- carrier_search: performed
- carrier_search_queries: rg "SomeFacade" claim-api; rg "SomeService" claim-core; rg "someMethod" claim-core
- existing_production_carriers: SomeFacade.someMethod(SomeParam)
- selected_carrier_from_search: SomeFacade.someMethod(SomeParam)
- new_service_proposed: false
- new_service_justification: none
"@ | Set-Content -LiteralPath (Join-Path $Root 'PLAN_RESULT.md') -Encoding UTF8
    @"
## Selected Real Entry

Primary Entry: SomeFacade.someMethod(SomeParam)
"@ | Set-Content -LiteralPath (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8
    @"
| requirement | module | file | change_type | validation | closure |
|---|---|---|---|---|---|
| R1 | core | SomeService.java | MODIFY | unit test | compile pass |
"@ | Set-Content -LiteralPath (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') -Encoding UTF8
    @"
## Side Effect Ledger

selected real entry -> orchestration -> persistence -> state/task/progress/log -> transaction -> proof
"@ | Set-Content -LiteralPath (Join-Path $Root 'SIDE_EFFECT_LEDGER.md') -Encoding UTF8
    @"
## RED/GREEN Order

1. RED: Write failing test
2. GREEN: Implement minimum code

## Real Entry Tests

- SomeFacadeTest.testMethod
"@ | Set-Content -LiteralPath (Join-Path $Root 'TEST_CHARTER.md') -Encoding UTF8
    'core_entry -> S1 -> SomeService.java -> SomeFacadeTest.testMethod' | Set-Content -LiteralPath (Join-Path $Root 'REPLAY_PLAN.md') -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Encoding UTF8
    '{"schema_version":1,"files":[{"path":"SomeService.java","layer":"Service","weight":"HIGH","is_production":true}],"layer_summary":{"Service":1},"production_files":1}' | Set-Content -LiteralPath (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') -Encoding UTF8
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Complete key:value schema => PASS
    # =========================================================================
    Write-Host 'Test 1: Complete key:value schema => PASS'
    $t1Root = Join-Path $tempRoot 'test1-complete-schema'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null
    New-MinimalPlanFixtures -Root $t1Root

    @"
first_slice: S1
highest_weight_open_gate: core_entry (weight=100)
first_red_test: SomeFacadeTest.testMethod()
selected_real_entry: SomeFacade.someMethod(SomeParam)
public_entry_contract_coverage: assert ResultModel.success contains data field
selected_carrier: SomeFacade via Facade interface
target_subsurface_or_carrier: SomeService.processData
real_carrier_kind: production_entry_or_service
minimum_side_effect_or_blocker: service triggers DB write
forbidden_substitute_check: passed
required_sibling_surfaces: none
production_boundary: claim-core module
expected_production_diff: SomeFacade.java modify return type
red_expectation: compilation error void vs ResultModel
green_minimum_implementation: add return statement
proof_kind: real_entry_behavior
forbidden_substitute_proof: no Mock/Stub/InMemory used
fail_closed_condition: compilation failure if return type wrong
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
pattern_to_follow: SimilarFacade.similarMethod(Param) -> ResultModel
pattern_return_type: ResultModel
pattern_error_handling: response_codes
pattern_evidence_source: rg -i "similarMethod" --include "*.java"
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1Root -Stage Plan 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    Assert-True ($verify1.verification_status -eq 'PASS') "Complete schema should PASS, got $($verify1.verification_status) issues=$($verify1.issues.Count): $($verify1.issues -join ';')"
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 2: Narrative prose, no key:value fields => FAIL
    # =========================================================================
    Write-Host 'Test 2: Narrative prose without key:value => FAIL'
    $t2Root = Join-Path $tempRoot 'test2-narrative'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null
    New-MinimalPlanFixtures -Root $t2Root

    @"
# First Slice Proof Plan

## First Slice

The first slice targets the core entry point. We will modify the main service
to add a new field and verify it compiles.

## Selected Real Entry

The selected real entry is SomeFacade.someMethod(). This is a production
facade API that handles the core business logic.

## Proof Kind

The proof kind is real_entry_behavior because we are testing the actual
entry point behavior.
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2Root -Stage Plan 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    $hasSchemaMissing = Test-HasIssue $verify2 '*first_slice_proof_schema_missing*'
    Assert-True ($hasSchemaMissing) 'Narrative without key:value should trigger schema_missing issues'
    Write-Host "  PASS (issues=$($verify2.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 3: Missing selected_carrier => FAIL
    # =========================================================================
    Write-Host 'Test 3: Missing selected_carrier => FAIL'
    $t3Root = Join-Path $tempRoot 'test3-no-carrier'
    New-Item -ItemType Directory -Force -Path $t3Root | Out-Null
    New-MinimalPlanFixtures -Root $t3Root

    @"
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: SomeTest.testMethod()
selected_real_entry: SomeFacade.someMethod()
public_entry_contract_coverage: assert response
target_subsurface_or_carrier: SomeService
real_carrier_kind: production_entry_or_service
minimum_side_effect_or_blocker: DB write
forbidden_substitute_check: passed
production_boundary: claim-core
proof_kind: real_entry_behavior
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t3Root -Stage Plan 2>&1
    $verify3 = $result3 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify3 '*first_slice_proof_schema_missing:selected_carrier*') 'Missing selected_carrier should FAIL'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 4: Key present but value empty => FAIL
    # =========================================================================
    Write-Host 'Test 4: selected_carrier with empty value => FAIL'
    $t4Root = Join-Path $tempRoot 'test4-empty-value'
    New-Item -ItemType Directory -Force -Path $t4Root | Out-Null
    New-MinimalPlanFixtures -Root $t4Root

    @"
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: SomeTest.testMethod()
selected_real_entry: SomeFacade.someMethod()
public_entry_contract_coverage: assert response
selected_carrier:
target_subsurface_or_carrier: SomeService
real_carrier_kind: production_entry_or_service
minimum_side_effect_or_blocker: DB write
forbidden_substitute_check: passed
production_boundary: claim-core
proof_kind: real_entry_behavior
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t4Root -Stage Plan 2>&1
    $verify4 = $result4 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify4 '*first_slice_proof_schema_empty:selected_carrier*') 'Empty selected_carrier should FAIL'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 5: selected_carrier = TBD / unknown / N/A => FAIL
    # =========================================================================
    Write-Host 'Test 5: selected_carrier placeholder values => FAIL'
    $placeholderValues = @('TBD', 'unknown', 'N/A', 'placeholder')
    foreach ($pv in $placeholderValues) {
        $t5Root = Join-Path $tempRoot ('test5-placeholder-' + $pv)
        New-Item -ItemType Directory -Force -Path $t5Root | Out-Null
        New-MinimalPlanFixtures -Root $t5Root

        @"
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: SomeTest.testMethod()
selected_real_entry: SomeFacade.someMethod()
public_entry_contract_coverage: assert response
selected_carrier: $pv
target_subsurface_or_carrier: SomeService
real_carrier_kind: production_entry_or_service
minimum_side_effect_or_blocker: DB write
forbidden_substitute_check: passed
production_boundary: claim-core
proof_kind: real_entry_behavior
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

        $result5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t5Root -Stage Plan 2>&1
        $verify5 = $result5 | ConvertFrom-Json
        Assert-True (Test-HasIssue $verify5 '*first_slice_proof_schema_placeholder:selected_carrier*') "selected_carrier=$pv should trigger placeholder"
    }
    Write-Host "  PASS ($($placeholderValues.Count) placeholder values tested)"
    $passCount++

    # =========================================================================
    # Test 6: forbidden_substitute_check: passed => PASS
    # =========================================================================
    Write-Host 'Test 6: forbidden_substitute_check: passed in schema => PASS'
    $t6Root = Join-Path $tempRoot 'test6-fsc-passed'
    New-Item -ItemType Directory -Force -Path $t6Root | Out-Null
    New-MinimalPlanFixtures -Root $t6Root

    @"
first_slice: S1
highest_weight_open_gate: core_entry
first_red_test: SomeTest.testMethod()
selected_real_entry: SomeService.processData()
public_entry_contract_coverage: assert ResultModel.success
selected_carrier: SomeService internal method
target_subsurface_or_carrier: SomeService.processData
real_carrier_kind: production_service
minimum_side_effect_or_blocker: service triggers DB write
forbidden_substitute_check: passed
required_sibling_surfaces: none
production_boundary: claim-core module
expected_production_diff: SomeService.java add field
red_expectation: assertion failure before change
green_minimum_implementation: add field and getter
proof_kind: real_entry_behavior
forbidden_substitute_proof: no helper/mock used
fail_closed_condition: compilation failure
coverage_cap_if_not_closed: 0
coverage_cap_if_missing: 0
"@ | Set-Content -LiteralPath (Join-Path $t6Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t6Root -Stage Plan 2>&1
    $verify6 = $result6 | ConvertFrom-Json
    $hasFscIssue = Test-HasIssue $verify6 '*forbidden_substitute_check_not_passed*'
    Assert-True (-not $hasFscIssue) 'forbidden_substitute_check: passed should not trigger issue'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 7: 429 transient error detection (inline function test)
    # =========================================================================
    Write-Host 'Test 7: 429 transient error detection'
    $t7Root = Join-Path $tempRoot 'test7-429'
    New-Item -ItemType Directory -Force -Path $t7Root | Out-Null

    function Test-TransientError429 {
        param([string]$LogPath)
        if (-not (Test-Path -LiteralPath $LogPath)) { return $false }
        $logText = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
        return ($logText -match '(?i)429|rate.?limit|too.?many.?requests|throttl')
    }

    $log429 = Join-Path $t7Root 'slice01.stdout.log'
    'API Error: Request rejected (429) rate limit exceeded' | Set-Content -LiteralPath $log429 -Encoding UTF8
    Assert-True (Test-TransientError429 $log429) '429 in log should be detected as transient'

    $log429b = Join-Path $t7Root 'slice01b.stdout.log'
    'Error: Too Many Requests - throttling applied' | Set-Content -LiteralPath $log429b -Encoding UTF8
    Assert-True (Test-TransientError429 $log429b) 'Throttling should be detected as transient'

    $logNormal = Join-Path $t7Root 'slice02.stdout.log'
    'BUILD SUCCESS' | Set-Content -LiteralPath $logNormal -Encoding UTF8
    Assert-True (-not (Test-TransientError429 $logNormal)) 'Normal output should not be transient'

    $logMissing = Join-Path $t7Root 'nonexistent.stdout.log'
    Assert-True (-not (Test-TransientError429 $logMissing)) 'Missing file should not be transient'
    Write-Host "  PASS (429=detected, throttle=detected, normal=not-transient, missing=not-transient)"
    $passCount++

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v261-FirstSliceProofSchema: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v261-FirstSliceProofSchema: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
