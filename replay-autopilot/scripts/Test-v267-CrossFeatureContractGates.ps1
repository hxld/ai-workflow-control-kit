param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\.tmp\v267-cross-feature-contract-gates-test')
)

$ErrorActionPreference = 'Stop'
$passCount = 0
$failCount = 0
$testResults = New-Object System.Collections.Generic.List[object]
$utf8 = [System.Text.Encoding]::UTF8

function Write-TestResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $script:passCount += [int]$Pass
    $script:failCount += [int](-not $Pass)
    $status = if ($Pass) { 'PASS' } else { 'FAIL' }
    $line = "[$status] $Name"
    if (-not [string]::IsNullOrWhiteSpace($Detail)) { $line += " - $Detail" }
    Write-Host $line
    $script:testResults.Add([ordered]@{ name = $Name; pass = $Pass; detail = $Detail })
}

function New-TestReplayRoot {
    param([string]$Name)
    $root = Join-Path $TestRoot $Name
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Write-File {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

function Invoke-PlanVerify {
    param([string]$Root)
    $script = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $Root -Stage Plan 2>&1
    $verifyPath = Join-Path $Root 'PLAN_CONTRACT_VERIFY.json'
    if (Test-Path -LiteralPath $verifyPath) {
        return Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Invoke-SliceVerify {
    param([string]$Root, [string]$Worktree, [string]$SliceResult)
    $script = Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -ReplayRoot $Root -Worktree $Worktree -SliceResult $SliceResult -SliceIndex 1 2>&1
    $verifyPath = Join-Path $Root 'SLICE_VERIFY_01.json'
    if (Test-Path -LiteralPath $verifyPath) {
        return Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

Write-Host '=== v267 Cross-Feature Contract Gates ==='
Write-Host ''

$promptsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'prompts'

# ============================================================
# Section 1: Phase0 Prompt has Interface Contract section
# ============================================================
$phase0Prompt = [System.IO.File]::ReadAllText((Join-Path $promptsDir 'phase0-contract-gate.prompt.md'), $utf8)
Write-TestResult 'Phase0 prompt has Interface Contract Extraction section' ($phase0Prompt.Contains('Interface Contract Extraction'))
Write-TestResult 'Phase0 prompt requires interface_contract_return_type' ($phase0Prompt.Contains('interface_contract_return_type'))
Write-TestResult 'Phase0 prompt requires interface_contract_error_handling' ($phase0Prompt.Contains('interface_contract_error_handling'))
Write-TestResult 'Phase0 prompt requires interface_contract_similarity_evidence' ($phase0Prompt.Contains('interface_contract_similarity_evidence'))
Write-TestResult 'Phase0 prompt has interface_contract_gap flag' ($phase0Prompt.Contains('interface_contract_gap'))
Write-TestResult 'Phase0 prompt has CONTRACT_INFERRED_FROM_SIMILAR fallback' ($phase0Prompt.Contains('CONTRACT_INFERRED_FROM_SIMILAR'))

# ============================================================
# Section 2: Plan Prompt has Pattern Matching fields
# ============================================================
$planPrompt = [System.IO.File]::ReadAllText((Join-Path $promptsDir 'phase-plan-tournament.prompt.md'), $utf8)
Write-TestResult 'Plan prompt has pattern_to_follow field' ($planPrompt.Contains('pattern_to_follow'))
Write-TestResult 'Plan prompt has pattern_return_type field' ($planPrompt.Contains('pattern_return_type'))
Write-TestResult 'Plan prompt has pattern_error_handling field' ($planPrompt.Contains('pattern_error_handling'))
Write-TestResult 'Plan prompt has pattern_evidence_source field' ($planPrompt.Contains('pattern_evidence_source'))
Write-TestResult 'Plan prompt has Pattern Matching Enforcement section' ($planPrompt.Contains('Pattern Matching Enforcement'))

# ============================================================
# Section 3: Slice Executor has Test Contract Verification
# ============================================================
$slicePrompt = [System.IO.File]::ReadAllText((Join-Path $promptsDir 'phase1-slice-executor.prompt.md'), $utf8)
Write-TestResult 'Slice executor has Test Contract Verification section' ($slicePrompt.Contains('Test Contract Verification'))
Write-TestResult 'Slice executor mentions test_contract_mismatch flag' ($slicePrompt.Contains('test_contract_mismatch'))
Write-TestResult 'Slice executor mentions return_value_vs_exception_mismatch' ($slicePrompt.Contains('return_value_vs_exception_mismatch'))
Write-TestResult 'Slice executor has Return Type Alignment rule' ($slicePrompt.Contains('Return Type Alignment'))
Write-TestResult 'Slice executor has Error Handling Alignment rule' ($slicePrompt.Contains('Error Handling Alignment'))
Write-TestResult 'Slice executor has Assertion Surface Alignment rule' ($slicePrompt.Contains('Assertion Surface Alignment'))

# ============================================================
# Section 4: Verify-PlanContract has interface contract checks
# ============================================================
$verifyPlanContent = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'), $utf8)
Write-TestResult 'Verify-PlanContract has interface_contract_return_type_missing issue' ($verifyPlanContent.Contains('interface_contract_return_type_missing'))
Write-TestResult 'Verify-PlanContract has pattern_to_follow_missing issue' ($verifyPlanContent.Contains('pattern_to_follow_missing'))
Write-TestResult 'Verify-PlanContract has pattern_to_follow_placeholder issue' ($verifyPlanContent.Contains('pattern_to_follow_placeholder'))
Write-TestResult 'Verify-PlanContract has pattern_evidence_source_missing issue' ($verifyPlanContent.Contains('pattern_evidence_source_missing'))

# ============================================================
# Section 5: Verify-SliceClosure has test contract mismatch checks
# ============================================================
$verifySliceContent = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1'), $utf8)
Write-TestResult 'Verify-SliceClosure has return_value_vs_exception_mismatch warning' ($verifySliceContent.Contains('return_value_vs_exception_mismatch'))
Write-TestResult 'Verify-SliceClosure has test_contract_mismatch flag' ($verifySliceContent.Contains('test_contract_mismatch'))
Write-TestResult 'Verify-SliceClosure has assertion_surface_mismatch flag' ($verifySliceContent.Contains('assertion_surface_mismatch'))
Write-TestResult 'Verify-SliceClosure has error_handling_pattern_mismatch warning' ($verifySliceContent.Contains('error_handling_pattern_mismatch'))
$hasAllNonAuthFlags = $verifySliceContent.Contains("'test_contract_mismatch'") -and $verifySliceContent.Contains("'return_value_vs_exception_mismatch'") -and $verifySliceContent.Contains("'assertion_surface_mismatch'")
Write-TestResult 'Verify-SliceClosure has all 3 new flags in non-authorizing list' $hasAllNonAuthFlags

# ============================================================
# Section 6: SliceVerifier has new gap flags
# ============================================================
$sliceVerifierContent = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SliceVerifier.ps1'), $utf8)
Write-TestResult 'SliceVerifier has test_contract_mismatch in fail-closed flags' ($sliceVerifierContent.Contains("'test_contract_mismatch'"))
Write-TestResult 'SliceVerifier has return_value_vs_exception_mismatch in fail-closed flags' ($sliceVerifierContent.Contains("'return_value_vs_exception_mismatch'"))
Write-TestResult 'SliceVerifier has assertion_surface_mismatch in fail-closed flags' ($sliceVerifierContent.Contains("'assertion_surface_mismatch'"))

# ============================================================
# Section 7: Behavioral - Plan verify passes when all fields present
# ============================================================
$root1 = New-TestReplayRoot -Name 'plan-with-pattern-fields'

$planResultContent = "# Plan Result`n- plan_status: PROCEED`n- selected_strategy: core-transaction-first`n- first_slice: S1`n- first_red_test: SomeTest#testReturnTicket`n- oracle_production_file_overlap: 60%`n- required_files: Service.java"

$firstSliceProofWithPattern = "first_slice: S1`n"
$firstSliceProofWithPattern += "highest_weight_open_gate: core_entry`n"
$firstSliceProofWithPattern += "first_red_test: InsureCompanyPushServiceTest#testReturnTicket`n"
$firstSliceProofWithPattern += "selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithPattern += "public_entry_contract_coverage: verifies response fields`n"
$firstSliceProofWithPattern += "selected_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithPattern += "target_subsurface_or_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithPattern += "real_carrier_kind: production_entry_or_service`n"
$firstSliceProofWithPattern += "minimum_side_effect_or_blocker: RefundTicketService insert`n"
$firstSliceProofWithPattern += "forbidden_substitute_check: passed`n"
$firstSliceProofWithPattern += "required_sibling_surfaces: none`n"
$firstSliceProofWithPattern += "production_boundary: InsureCompanyPushFacadeImpl`n"
$firstSliceProofWithPattern += "expected_production_diff: InsureCompanyPushFacadeImpl.java modified`n"
$firstSliceProofWithPattern += "red_expectation: test fails because method not yet returning expected response`n"
$firstSliceProofWithPattern += "green_minimum_implementation: implement returnTicket with response object`n"
$firstSliceProofWithPattern += "proof_kind: real_entry_behavior`n"
$firstSliceProofWithPattern += "forbidden_substitute_proof: no Noop/Stub/Fake/Mock`n"
$firstSliceProofWithPattern += "fail-closed condition: response object not returned`n"
$firstSliceProofWithPattern += "coverage_cap_if_not_closed: 0`n"
$firstSliceProofWithPattern += "coverage_cap_if_missing: 0`n"
$firstSliceProofWithPattern += "pattern_to_follow: SimilarService.similarMethod(Param) -> ResponseType`n"
$firstSliceProofWithPattern += "pattern_return_type: ResponseType`n"
$firstSliceProofWithPattern += "pattern_error_handling: response_codes`n"
$firstSliceProofWithPattern += "pattern_evidence_source: rg -i `"similarMethod`" --include `"*.java`""

$familyContract = '{"schema_version":1,"selected_real_entry":"Facade.returnTicket(Param)","first_executable_slice":"S1","families":[{"id":"core_entry","required":true,"weight":100,"first_executable_carrier":"Facade","planned_slice":"S1","proof_required":["real_entry_behavior"],"forbidden_proof":["helper_only"],"coverage_cap_if_open":0}]}'
$oracleAnalysis = '{"schema_version":1,"files":[{"path":"Service.java","layer":"Service","weight":"HIGH","is_production":true}],"layer_summary":{"Service":1},"production_files":1}'

Write-File -Path (Join-Path $root1 'PLAN_RESULT.md') -Content $planResultContent
Write-File -Path (Join-Path $root1 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofWithPattern
Write-File -Path (Join-Path $root1 'PLAN_CANDIDATE_1.md') -Content 'Candidate 1'
Write-File -Path (Join-Path $root1 'PLAN_CANDIDATE_2.md') -Content 'Candidate 2'
Write-File -Path (Join-Path $root1 'PLAN_CANDIDATE_3.md') -Content 'Candidate 3'
Write-File -Path (Join-Path $root1 'PLAN_SELECTION.md') -Content 'Selection'
Write-File -Path (Join-Path $root1 'REPLAY_PLAN.md') -Content 'Replay plan with core_entry and stateful_side_effect'
Write-File -Path (Join-Path $root1 'IMPLEMENTATION_CONTRACT.md') -Content 'Implementation contract with selected real entry'
Write-File -Path (Join-Path $root1 'EXPECTED_DIFF_MATRIX.md') -Content 'validation and closure'
Write-File -Path (Join-Path $root1 'SIDE_EFFECT_LEDGER.md') -Content 'state task progress log transaction'
Write-File -Path (Join-Path $root1 'TEST_CHARTER.md') -Content 'RED and GREEN'
Write-File -Path (Join-Path $root1 'FAMILY_CONTRACT.json') -Content $familyContract
Write-File -Path (Join-Path $root1 'ORACLE_DIFF_ANALYSIS.json') -Content $oracleAnalysis

$verify1 = Invoke-PlanVerify -Root $root1
$verify1HasNoInterfaceContractIssue = $null -ne $verify1 -and @($verify1.issues | Where-Object { [string]$_ -match 'interface_contract_return_type' }).Count -eq 0
Write-TestResult 'Plan verify PASSES when pattern fields present for Facade entry' $verify1HasNoInterfaceContractIssue

# ============================================================
# Section 8: Behavioral - Plan verify warns on missing pattern for Facade
# ============================================================
$root2 = New-TestReplayRoot -Name 'plan-no-pattern-to-follow'

$firstSliceProofNoPattern = "first_slice: S1`n"
$firstSliceProofNoPattern += "highest_weight_open_gate: core_entry`n"
$firstSliceProofNoPattern += "first_red_test: SomeTest#testReturnTicket`n"
$firstSliceProofNoPattern += "selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNoPattern += "public_entry_contract_coverage: verifies response fields`n"
$firstSliceProofNoPattern += "selected_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNoPattern += "target_subsurface_or_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNoPattern += "real_carrier_kind: production_entry_or_service`n"
$firstSliceProofNoPattern += "minimum_side_effect_or_blocker: RefundTicketService insert`n"
$firstSliceProofNoPattern += "forbidden_substitute_check: passed`n"
$firstSliceProofNoPattern += "required_sibling_surfaces: none`n"
$firstSliceProofNoPattern += "production_boundary: InsureCompanyPushFacadeImpl`n"
$firstSliceProofNoPattern += "expected_production_diff: InsureCompanyPushFacadeImpl.java modified`n"
$firstSliceProofNoPattern += "red_expectation: test fails`n"
$firstSliceProofNoPattern += "green_minimum_implementation: implement`n"
$firstSliceProofNoPattern += "proof_kind: real_entry_behavior`n"
$firstSliceProofNoPattern += "forbidden_substitute_proof: no Noop/Stub/Fake/Mock`n"
$firstSliceProofNoPattern += "fail-closed condition: response not returned`n"
$firstSliceProofNoPattern += "coverage_cap_if_not_closed: 0`n"
$firstSliceProofNoPattern += "coverage_cap_if_missing: 0"

Write-File -Path (Join-Path $root2 'PLAN_RESULT.md') -Content $planResultContent
Write-File -Path (Join-Path $root2 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofNoPattern
Write-File -Path (Join-Path $root2 'PLAN_CANDIDATE_1.md') -Content 'Candidate 1'
Write-File -Path (Join-Path $root2 'PLAN_CANDIDATE_2.md') -Content 'Candidate 2'
Write-File -Path (Join-Path $root2 'PLAN_CANDIDATE_3.md') -Content 'Candidate 3'
Write-File -Path (Join-Path $root2 'PLAN_SELECTION.md') -Content 'Selection'
Write-File -Path (Join-Path $root2 'REPLAY_PLAN.md') -Content 'Replay plan with core_entry'
Write-File -Path (Join-Path $root2 'IMPLEMENTATION_CONTRACT.md') -Content 'Implementation contract with selected real entry'
Write-File -Path (Join-Path $root2 'EXPECTED_DIFF_MATRIX.md') -Content 'validation and closure'
Write-File -Path (Join-Path $root2 'SIDE_EFFECT_LEDGER.md') -Content 'state task progress log transaction'
Write-File -Path (Join-Path $root2 'TEST_CHARTER.md') -Content 'RED and GREEN'
Write-File -Path (Join-Path $root2 'FAMILY_CONTRACT.json') -Content $familyContract
Write-File -Path (Join-Path $root2 'ORACLE_DIFF_ANALYSIS.json') -Content $oracleAnalysis

$verify2 = Invoke-PlanVerify -Root $root2
$verify2HasPatternIssue = $null -ne $verify2 -and @($verify2.issues | Where-Object { [string]$_ -match 'pattern_to_follow_missing' }).Count -gt 0
Write-TestResult 'Plan verify FAILS when pattern_to_follow missing for Facade entry' $verify2HasPatternIssue
$verify2HasEvidenceSourceIssue = $null -ne $verify2 -and @($verify2.issues | Where-Object { [string]$_ -match 'pattern_evidence_source_missing' }).Count -gt 0
Write-TestResult 'Plan verify FAILS when pattern_evidence_source missing for Facade entry' $verify2HasEvidenceSourceIssue
$verify2HasErrorHandlingIssue = $null -ne $verify2 -and @($verify2.issues | Where-Object { [string]$_ -match 'interface_contract_error_handling_missing' }).Count -gt 0
Write-TestResult 'Plan verify FAILS when interface_contract_error_handling missing for Facade entry' $verify2HasErrorHandlingIssue
$verify2StatusFail = $null -ne $verify2 -and $verify2.verification_status -eq 'FAIL'
Write-TestResult 'Plan verify status is FAIL when mandatory pattern/contract fields missing' $verify2StatusFail

# ============================================================
# Section 9: Behavioral - Slice verify detects return-value-vs-exception mismatch
# ============================================================
$root3 = New-TestReplayRoot -Name 'slice-contract-mismatch'
$worktree3 = Join-Path $root3 'worktree'
New-Item -ItemType Directory -Force -Path $worktree3 | Out-Null

$testDir = Join-Path $worktree3 'claim-server\src\test\java\com\test'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
$exceptionTestContent = '@Test`npublic void should_throw_when_case_not_found() {`n    try {`n        service.returnTicket(param);`n        fail("expected IllegalArgumentException");`n    } catch (IllegalArgumentException e) {`n        assertEquals("case not found", e.getMessage());`n    }`n}'
Write-File -Path (Join-Path $testDir 'SomeServiceTest.java') -Content $exceptionTestContent

& git -C $worktree3 init 2>$null | Out-Null
& git -C $worktree3 config user.email "test@test.com" 2>$null | Out-Null
& git -C $worktree3 config user.name "Test" 2>$null | Out-Null
& git -C $worktree3 add -A 2>$null | Out-Null
& git -C $worktree3 commit -m "init" 2>$null | Out-Null

$sliceResultJson = '{"slice_index":1,"slice_id":"S1","slice_title":"Return Ticket","slice_type":"tracer_bullet","slice_status":"DONE","coverage_delta":0,"target_subsurface_or_carrier":"InsureCompanyPushFacadeImpl#returnTicket","required_sibling_surfaces":[],"production_boundary":"InsureCompanyPushFacadeImpl","proof_kind":"real_entry_behavior","real_carrier_kind":"production_entry_or_service","forbidden_substitute_check":"passed","red_expectation":"test fails","implemented_files":["claim-server/src/test/java/com/test/SomeServiceTest.java"],"current_slice_changed_files":["claim-server/src/test/java/com/test/SomeServiceTest.java"],"round_changed_files_snapshot":["claim-server/src/test/java/com/test/SomeServiceTest.java"],"tests":[{"command":"mvn test -Dtest=SomeServiceTest","phase":"RED","result":"fail","evidence":"test failed"}],"closed_assertions":[],"must_not_assertions":[],"remaining_gaps":[],"gap_flags":[],"touched_requirement_families":["core_entry"],"closed_requirement_families":[],"blocker":"","next_recommended_slice_type":"stateful_success_slice"}'
Write-File -Path (Join-Path $root3 'SLICE_RESULT_01.json') -Content $sliceResultJson

$firstSliceProofWithContract = "first_slice: S1`n"
$firstSliceProofWithContract += "highest_weight_open_gate: core_entry`n"
$firstSliceProofWithContract += "first_red_test: SomeServiceTest#testReturnTicket`n"
$firstSliceProofWithContract += "selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithContract += "public_entry_contract_coverage: verifies response fields`n"
$firstSliceProofWithContract += "selected_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithContract += "target_subsurface_or_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofWithContract += "real_carrier_kind: production_entry_or_service`n"
$firstSliceProofWithContract += "minimum_side_effect_or_blocker: RefundTicketService insert`n"
$firstSliceProofWithContract += "forbidden_substitute_check: passed`n"
$firstSliceProofWithContract += "required_sibling_surfaces: none`n"
$firstSliceProofWithContract += "production_boundary: InsureCompanyPushFacadeImpl`n"
$firstSliceProofWithContract += "expected_production_diff: InsureCompanyPushFacadeImpl.java`n"
$firstSliceProofWithContract += "red_expectation: test fails`n"
$firstSliceProofWithContract += "green_minimum_implementation: implement returnTicket`n"
$firstSliceProofWithContract += "proof_kind: real_entry_behavior`n"
$firstSliceProofWithContract += "forbidden_substitute_proof: no substitutes`n"
$firstSliceProofWithContract += "fail-closed condition: response not returned`n"
$firstSliceProofWithContract += "coverage_cap_if_not_closed: 0`n"
$firstSliceProofWithContract += "coverage_cap_if_missing: 0`n"
$firstSliceProofWithContract += "pattern_to_follow: InsureCompanyPushService.returnCompany(ReturnCompanyParam) -> ReturnCompanyParam`n"
$firstSliceProofWithContract += "pattern_return_type: ReturnCompanyParam`n"
$firstSliceProofWithContract += "pattern_error_handling: response_codes`n"
$firstSliceProofWithContract += "pattern_evidence_source: rg -i `"returnCompany`" --include `"*.java`""

Write-File -Path (Join-Path $root3 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofWithContract
Write-File -Path (Join-Path $root3 'IMPLEMENTATION_CONTRACT.md') -Content 'selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket'

$verify3 = Invoke-SliceVerify -Root $root3 -Worktree $worktree3 -SliceResult (Join-Path $root3 'SLICE_RESULT_01.json')

$verify3HasMismatch = $null -ne $verify3 -and @($verify3.gap_flags | Where-Object { [string]$_ -match 'test_contract_mismatch|return_value_vs_exception_mismatch' }).Count -gt 0
Write-TestResult 'Slice verify DETECTS return-value-vs-exception mismatch' $verify3HasMismatch

$verify3HasWrongTestSurface = $null -ne $verify3 -and @($verify3.gap_flags | Where-Object { [string]$_ -eq 'wrong_test_surface' }).Count -gt 0
Write-TestResult 'Slice verify sets wrong_test_surface on contract mismatch' $verify3HasWrongTestSurface

$verify3ZeroCoverage = $null -ne $verify3 -and $null -ne $verify3.adjusted_coverage_delta -and [int]$verify3.adjusted_coverage_delta -eq 0
Write-TestResult 'Slice verify zeroes coverage delta on contract mismatch' $verify3ZeroCoverage

# ============================================================
# Section 10: Behavioral - Slice verify allows matching contract
# ============================================================
$root4 = New-TestReplayRoot -Name 'slice-contract-match'
$worktree4 = Join-Path $root4 'worktree'
New-Item -ItemType Directory -Force -Path $worktree4 | Out-Null

$testDir4 = Join-Path $worktree4 'claim-server\src\test\java\com\test'
New-Item -ItemType Directory -Force -Path $testDir4 | Out-Null
$matchingTestContent = '@Test`npublic void should_return_500_when_case_not_found() {`n    ReturnCompanyParam result = service.returnTicket(returnTicketParam);`n    assertEquals("500", result.getCode());`n    assertEquals("case not found", result.getMsg());`n}'
Write-File -Path (Join-Path $testDir4 'MatchingServiceTest.java') -Content $matchingTestContent

& git -C $worktree4 init 2>$null | Out-Null
& git -C $worktree4 config user.email "test@test.com" 2>$null | Out-Null
& git -C $worktree4 config user.name "Test" 2>$null | Out-Null
& git -C $worktree4 add -A 2>$null | Out-Null
& git -C $worktree4 commit -m "init" 2>$null | Out-Null

$sliceResult4 = '{"slice_index":1,"slice_id":"S1","slice_title":"Return Ticket","slice_type":"tracer_bullet","slice_status":"DONE","coverage_delta":0,"target_subsurface_or_carrier":"InsureCompanyPushFacadeImpl#returnTicket","required_sibling_surfaces":[],"production_boundary":"InsureCompanyPushFacadeImpl","proof_kind":"real_entry_behavior","real_carrier_kind":"production_entry_or_service","forbidden_substitute_check":"passed","red_expectation":"test fails","implemented_files":["claim-server/src/test/java/com/test/MatchingServiceTest.java"],"current_slice_changed_files":["claim-server/src/test/java/com/test/MatchingServiceTest.java"],"round_changed_files_snapshot":["claim-server/src/test/java/com/test/MatchingServiceTest.java"],"tests":[{"command":"mvn test -Dtest=MatchingServiceTest","phase":"RED","result":"fail","evidence":"test failed"}],"closed_assertions":[],"must_not_assertions":[],"remaining_gaps":[],"gap_flags":[],"touched_requirement_families":["core_entry"],"closed_requirement_families":[],"blocker":"","next_recommended_slice_type":"stateful_success_slice"}'
Write-File -Path (Join-Path $root4 'SLICE_RESULT_01.json') -Content $sliceResult4
Write-File -Path (Join-Path $root4 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofWithContract
Write-File -Path (Join-Path $root4 'IMPLEMENTATION_CONTRACT.md') -Content 'selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket'

$verify4 = Invoke-SliceVerify -Root $root4 -Worktree $worktree4 -SliceResult (Join-Path $root4 'SLICE_RESULT_01.json')

$verify4NoMismatch = $null -ne $verify4 -and @($verify4.gap_flags | Where-Object { [string]$_ -match 'test_contract_mismatch|return_value_vs_exception_mismatch' }).Count -eq 0
Write-TestResult 'Slice verify ALLOWS matching response-code test contract' $verify4NoMismatch

# ============================================================
# Section 11: Behavioral - Plan verify FAILS on placeholder error handling
# ============================================================
$root5 = New-TestReplayRoot -Name 'plan-placeholder-error-handling'

$firstSliceProofPlaceholderEH = "first_slice: S1`n"
$firstSliceProofPlaceholderEH += "highest_weight_open_gate: core_entry`n"
$firstSliceProofPlaceholderEH += "first_red_test: SomeTest#testReturnTicket`n"
$firstSliceProofPlaceholderEH += "selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofPlaceholderEH += "public_entry_contract_coverage: verifies response fields`n"
$firstSliceProofPlaceholderEH += "selected_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofPlaceholderEH += "target_subsurface_or_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofPlaceholderEH += "real_carrier_kind: production_entry_or_service`n"
$firstSliceProofPlaceholderEH += "minimum_side_effect_or_blocker: RefundTicketService insert`n"
$firstSliceProofPlaceholderEH += "forbidden_substitute_check: passed`n"
$firstSliceProofPlaceholderEH += "required_sibling_surfaces: none`n"
$firstSliceProofPlaceholderEH += "production_boundary: InsureCompanyPushFacadeImpl`n"
$firstSliceProofPlaceholderEH += "expected_production_diff: InsureCompanyPushFacadeImpl.java modified`n"
$firstSliceProofPlaceholderEH += "red_expectation: test fails`n"
$firstSliceProofPlaceholderEH += "green_minimum_implementation: implement`n"
$firstSliceProofPlaceholderEH += "proof_kind: real_entry_behavior`n"
$firstSliceProofPlaceholderEH += "forbidden_substitute_proof: no Noop/Stub/Fake/Mock`n"
$firstSliceProofPlaceholderEH += "fail-closed condition: response not returned`n"
$firstSliceProofPlaceholderEH += "coverage_cap_if_not_closed: 0`n"
$firstSliceProofPlaceholderEH += "coverage_cap_if_missing: 0`n"
$firstSliceProofPlaceholderEH += "interface_contract_error_handling: TBD`n"
$firstSliceProofPlaceholderEH += "pattern_to_follow: SimilarService.similarMethod(Param) -> ResponseType`n"
$firstSliceProofPlaceholderEH += "pattern_return_type: ResponseType`n"
$firstSliceProofPlaceholderEH += "pattern_error_handling: response_codes`n"
$firstSliceProofPlaceholderEH += "pattern_evidence_source: rg -i `"similarMethod`" --include `"*.java`""

Write-File -Path (Join-Path $root5 'PLAN_RESULT.md') -Content $planResultContent
Write-File -Path (Join-Path $root5 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofPlaceholderEH
Write-File -Path (Join-Path $root5 'PLAN_CANDIDATE_1.md') -Content 'Candidate 1'
Write-File -Path (Join-Path $root5 'PLAN_CANDIDATE_2.md') -Content 'Candidate 2'
Write-File -Path (Join-Path $root5 'PLAN_CANDIDATE_3.md') -Content 'Candidate 3'
Write-File -Path (Join-Path $root5 'PLAN_SELECTION.md') -Content 'Selection'
Write-File -Path (Join-Path $root5 'REPLAY_PLAN.md') -Content 'Replay plan with core_entry'
Write-File -Path (Join-Path $root5 'IMPLEMENTATION_CONTRACT.md') -Content 'Implementation contract with selected real entry'
Write-File -Path (Join-Path $root5 'EXPECTED_DIFF_MATRIX.md') -Content 'validation and closure'
Write-File -Path (Join-Path $root5 'SIDE_EFFECT_LEDGER.md') -Content 'state task progress log transaction'
Write-File -Path (Join-Path $root5 'TEST_CHARTER.md') -Content 'RED and GREEN'
Write-File -Path (Join-Path $root5 'FAMILY_CONTRACT.json') -Content $familyContract
Write-File -Path (Join-Path $root5 'ORACLE_DIFF_ANALYSIS.json') -Content $oracleAnalysis

$verify5 = Invoke-PlanVerify -Root $root5
$verify5HasPlaceholderEH = $null -ne $verify5 -and @($verify5.issues | Where-Object { [string]$_ -match 'interface_contract_error_handling_placeholder' }).Count -gt 0
Write-TestResult 'Plan verify FAILS when interface_contract_error_handling is placeholder' $verify5HasPlaceholderEH
$verify5StatusFail = $null -ne $verify5 -and $verify5.verification_status -eq 'FAIL'
Write-TestResult 'Plan verify status is FAIL with placeholder error handling' $verify5StatusFail

# ============================================================
# Section 12: Behavioral - Plan verify FAILS on narrative-only pattern_evidence_source
# ============================================================
$root6 = New-TestReplayRoot -Name 'plan-narrative-evidence'

$firstSliceProofNarrative = "first_slice: S1`n"
$firstSliceProofNarrative += "highest_weight_open_gate: core_entry`n"
$firstSliceProofNarrative += "first_red_test: SomeTest#testReturnTicket`n"
$firstSliceProofNarrative += "selected_real_entry: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNarrative += "public_entry_contract_coverage: verifies response fields`n"
$firstSliceProofNarrative += "selected_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNarrative += "target_subsurface_or_carrier: InsureCompanyPushFacadeImpl#returnTicket(ReturnTicketParam)`n"
$firstSliceProofNarrative += "real_carrier_kind: production_entry_or_service`n"
$firstSliceProofNarrative += "minimum_side_effect_or_blocker: RefundTicketService insert`n"
$firstSliceProofNarrative += "forbidden_substitute_check: passed`n"
$firstSliceProofNarrative += "required_sibling_surfaces: none`n"
$firstSliceProofNarrative += "production_boundary: InsureCompanyPushFacadeImpl`n"
$firstSliceProofNarrative += "expected_production_diff: InsureCompanyPushFacadeImpl.java modified`n"
$firstSliceProofNarrative += "red_expectation: test fails`n"
$firstSliceProofNarrative += "green_minimum_implementation: implement`n"
$firstSliceProofNarrative += "proof_kind: real_entry_behavior`n"
$firstSliceProofNarrative += "forbidden_substitute_proof: no Noop/Stub/Fake/Mock`n"
$firstSliceProofNarrative += "fail-closed condition: response not returned`n"
$firstSliceProofNarrative += "coverage_cap_if_not_closed: 0`n"
$firstSliceProofNarrative += "coverage_cap_if_missing: 0`n"
$firstSliceProofNarrative += "interface_contract_error_handling: response_codes`n"
$firstSliceProofNarrative += "pattern_to_follow: SimilarService.similarMethod(Param) -> ResponseType`n"
$firstSliceProofNarrative += "pattern_return_type: ResponseType`n"
$firstSliceProofNarrative += "pattern_error_handling: response_codes`n"
$firstSliceProofNarrative += "pattern_evidence_source: This pattern was found by examining the existing codebase and follows the standard approach used in similar features"

Write-File -Path (Join-Path $root6 'PLAN_RESULT.md') -Content $planResultContent
Write-File -Path (Join-Path $root6 'FIRST_SLICE_PROOF_PLAN.md') -Content $firstSliceProofNarrative
Write-File -Path (Join-Path $root6 'PLAN_CANDIDATE_1.md') -Content 'Candidate 1'
Write-File -Path (Join-Path $root6 'PLAN_CANDIDATE_2.md') -Content 'Candidate 2'
Write-File -Path (Join-Path $root6 'PLAN_CANDIDATE_3.md') -Content 'Candidate 3'
Write-File -Path (Join-Path $root6 'PLAN_SELECTION.md') -Content 'Selection'
Write-File -Path (Join-Path $root6 'REPLAY_PLAN.md') -Content 'Replay plan with core_entry'
Write-File -Path (Join-Path $root6 'IMPLEMENTATION_CONTRACT.md') -Content 'Implementation contract with selected real entry'
Write-File -Path (Join-Path $root6 'EXPECTED_DIFF_MATRIX.md') -Content 'validation and closure'
Write-File -Path (Join-Path $root6 'SIDE_EFFECT_LEDGER.md') -Content 'state task progress log transaction'
Write-File -Path (Join-Path $root6 'TEST_CHARTER.md') -Content 'RED and GREEN'
Write-File -Path (Join-Path $root6 'FAMILY_CONTRACT.json') -Content $familyContract
Write-File -Path (Join-Path $root6 'ORACLE_DIFF_ANALYSIS.json') -Content $oracleAnalysis

$verify6 = Invoke-PlanVerify -Root $root6
$verify6HasNarrativeOnly = $null -ne $verify6 -and @($verify6.issues | Where-Object { [string]$_ -match 'pattern_evidence_source_narrative_only' }).Count -gt 0
Write-TestResult 'Plan verify FAILS when pattern_evidence_source is narrative-only' $verify6HasNarrativeOnly
$verify6StatusFail = $null -ne $verify6 -and $verify6.verification_status -eq 'FAIL'
Write-TestResult 'Plan verify status is FAIL with narrative-only pattern_evidence_source' $verify6StatusFail

# ============================================================
# Summary
# ============================================================
Write-Host ''
Write-Host '=== Results ==='
Write-Host "PASS: $passCount"
Write-Host "FAIL: $failCount"
Write-Host "Total: $($passCount + $failCount)"

if ($failCount -gt 0) {
    Write-Host ''
    Write-Host 'Failed tests:'
    foreach ($r in $testResults) {
        if (-not $r.pass) {
            Write-Host "  - $($r.name): $($r.detail)"
        }
    }
    exit 1
}

Write-Host 'All v267 cross-feature contract gate tests passed.'
exit 0
