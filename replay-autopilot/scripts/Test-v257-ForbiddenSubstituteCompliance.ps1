$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v257-fsc-test-{0}' -f ([guid]::NewGuid().ToString('N')))

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
        'PLAN_RESULT.md', 'FAMILY_CONTRACT.json', 'PLAN_SELECTION.md',
        'REPLAY_PLAN.md', 'IMPLEMENTATION_CONTRACT.md', 'EXPECTED_DIFF_MATRIX.md',
        'SIDE_EFFECT_LEDGER.md', 'TEST_CHARTER.md'
    )
    foreach ($file in $planFiles) {
        Set-Content -LiteralPath (Join-Path $Root $file) -Value '' -Encoding UTF8
    }
    # PLAN_RESULT.md needs plan_status=PROCEED + required fields
    @"
- plan_status: PROCEED
- selected_strategy: core_path
- first_slice: S1
- first_red_test: T1
- required_files: []
"@ | Set-Content -LiteralPath (Join-Path $Root 'PLAN_RESULT.md') -Encoding UTF8
    # FAMILY_CONTRACT.json
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Encoding UTF8
    # IMPLEMENTATION_CONTRACT.md needs selected real entry
    @"
## Selected Real Entry

Primary Entry: SomeFacade.someMethod(SomeParam)

## First Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: forbidden_substitute_check: passed -> no issue
    # =========================================================================
    Write-Host 'Test 1: forbidden_substitute_check: passed -> no forbidden_substitute issue'
    $t1Root = Join-Path $tempRoot 'test1-passed'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null
    New-MinimalPlanFixtures -Root $t1Root

    @"
## First Slice Proof Plan

- forbidden_substitute_check: passed
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: facade call triggers service method
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1Root -Stage Plan 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    $hasFscIssue = @($verify1.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True (-not $hasFscIssue) 'forbidden_substitute_check: passed should NOT trigger forbidden_substitute_check_not_passed issue'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 2: forbidden_substitute_check: failed:reason -> issue reported
    # =========================================================================
    Write-Host 'Test 2: forbidden_substitute_check: failed:reason -> forbidden_substitute issue reported'
    $t2Root = Join-Path $tempRoot 'test2-failed'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null
    New-MinimalPlanFixtures -Root $t2Root

    @"
## First Slice Proof Plan

- forbidden_substitute_check: failed:found mock in test helper
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: facade call triggers service method
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2Root -Stage Plan 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    $hasFscIssue = @($verify2.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True ($hasFscIssue) 'forbidden_substitute_check: failed:reason MUST trigger forbidden_substitute_check_not_passed (only "passed" is valid)'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 3: forbidden_substitute_check: descriptive text -> issue reported
    # =========================================================================
    Write-Host 'Test 3: forbidden_substitute_check: descriptive text -> forbidden_substitute issue reported'
    $t3Root = Join-Path $tempRoot 'test3-descriptive'
    New-Item -ItemType Directory -Force -Path $t3Root | Out-Null
    New-MinimalPlanFixtures -Root $t3Root

    @"
## First Slice Proof Plan

- forbidden_substitute_check: Must verify no Mock/Stub is used in production entry tests
- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: facade call triggers service method
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t3Root -Stage Plan 2>&1
    $verify3 = $result3 | ConvertFrom-Json
    $hasFscIssue = @($verify3.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True ($hasFscIssue) 'forbidden_substitute_check: descriptive text MUST trigger forbidden_substitute_check_not_passed'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 4: forbidden_substitute_check missing entirely -> issue reported
    # =========================================================================
    Write-Host 'Test 4: forbidden_substitute_check missing -> forbidden_substitute issue reported'
    $t4Root = Join-Path $tempRoot 'test4-missing'
    New-Item -ItemType Directory -Force -Path $t4Root | Out-Null
    New-MinimalPlanFixtures -Root $t4Root

    @"
## First Slice Proof Plan

- proof_kind: real_entry_behavior
- real_carrier_kind: production_entry_or_service
- minimum_side_effect_or_blocker: facade call triggers service method
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t4Root -Stage Plan 2>&1
    $verify4 = $result4 | ConvertFrom-Json
    $hasFscIssue = @($verify4.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True ($hasFscIssue) 'missing forbidden_substitute_check MUST trigger forbidden_substitute_check_not_passed'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 5: forbidden_substitute_check in table format -> no issue
    # =========================================================================
    Write-Host 'Test 5: forbidden_substitute_check in table format -> no forbidden_substitute issue'
    $t5Root = Join-Path $tempRoot 'test5-table'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null
    New-MinimalPlanFixtures -Root $t5Root

    @"
## First Slice Proof Plan

| Field | Value |
|-------|-------|
| forbidden_substitute_check | passed |
| proof_kind | real_entry_behavior |
| real_carrier_kind | production_entry_or_service |
| minimum_side_effect_or_blocker | facade call triggers service method |
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'FIRST_SLICE_PROOF_PLAN.md') -Encoding UTF8

    $result5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t5Root -Stage Plan 2>&1
    $verify5 = $result5 | ConvertFrom-Json
    $hasFscIssue = @($verify5.issues | Where-Object { $_ -like '*forbidden_substitute_check_not_passed*' }).Count -gt 0
    Assert-True (-not $hasFscIssue) 'forbidden_substitute_check in table format should NOT trigger issue'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v257-ForbiddenSubstituteCompliance: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v257-ForbiddenSubstituteCompliance: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
