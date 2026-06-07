param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-JsonFile {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonObject {
    param([string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function New-SliceResultObject {
    param(
        [string]$Status = 'DONE',
        [string]$SliceType = 'exact_contract_slice',
        [int]$CoverageDelta = 8,
        [string]$ProofKind = 'controller',
        [string[]]$TouchedFamilies = @(),
        [string[]]$ClosedFamilies = @(),
        [string[]]$GapFlags = @(),
        [object[]]$Tests = @()
    )

    return [ordered]@{
        slice_index = 1
        slice_id = 'S1'
        slice_title = 'verifier contract case'
        slice_type = $SliceType
        slice_status = $Status
        coverage_delta = $CoverageDelta
        target_subsurface_or_carrier = 'SampleCarrier.execute'
        required_sibling_surfaces = @()
        production_boundary = 'sample production boundary'
        proof_kind = $ProofKind
        red_expectation = 'RED should fail before the implementation exists'
        implemented_files = @('src/main/java/SampleCarrier.java')
        tests = $Tests
        closed_assertions = @('sample assertion closed')
        must_not_assertions = @('sample must-not assertion')
        remaining_gaps = @()
        gap_flags = $GapFlags
        touched_requirement_families = $TouchedFamilies
        closed_requirement_families = $ClosedFamilies
        blocker = ''
        next_recommended_slice_type = ''
    }
}

function Invoke-VerifierCase {
    param(
        [string]$Name,
        $SliceResultObject,
        [string]$ExpectedStatus,
        [int]$MaxCoverageCap = 100,
        [int]$MaxAdjustedDelta = 999,
        [object]$ExpectedShouldContinue = $null,
        [object]$ExpectedAuthorizedNextSlice = $null,
        [object]$ExpectedAuthorizedSynthesis = $null,
        [object]$ExpectedHasBehaviorEvidence = $null,
        [string[]]$ExpectedWarnings = @(),
        [string[]]$ForbiddenWarnings = @(),
        [string[]]$ExpectedGapFlags = @(),
        [string[]]$ForbiddenGapFlags = @(),
        [string[]]$ExpectedAuthorizationBlockers = @(),
        [string[]]$ForbiddenAuthorizationBlockers = @(),
        [string[]]$ExpectedProofMismatchFamilies = @(),
        [object]$CarrierAuthorizationObject = $null,
        [object]$ExactContractMatrixObject = $null,
        [object]$SideEffectEvidenceObject = $null,
        [string]$PlanLockText = '',
        [string]$RequirementText = '',
        [switch]$NoCarrierAuthorization,
        [switch]$NoExactContractMatrix,
        [switch]$NoSideEffectEvidence
    )

    $caseRoot = Join-Path $script:tempRoot $Name
    New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($PlanLockText)) {
        Set-Content -LiteralPath (Join-Path $caseRoot 'IMPLEMENTATION_CONTRACT.md') -Encoding UTF8 -Value $PlanLockText
    }
    if (-not [string]::IsNullOrWhiteSpace($RequirementText)) {
        $requirementPath = Join-Path $caseRoot 'REQUIREMENT_SOURCE_SNAPSHOT.md'
        Set-Content -LiteralPath $requirementPath -Encoding UTF8 -Value $RequirementText
        Write-JsonFile -Object ([ordered]@{ requirement_source = $requirementPath }) -Path (Join-Path $caseRoot 'AUTOPILOT_RUN.json')
    }
    $sliceResultPath = Join-Path $caseRoot 'SLICE_RESULT_01.json'
    Write-JsonFile -Object $SliceResultObject -Path $sliceResultPath
    $sliceObject = Read-JsonObject $sliceResultPath
    $families = @()
    if ($null -ne $sliceObject.touched_requirement_families) { $families += @(Get-StringArray $sliceObject.touched_requirement_families) }
    if ($null -ne $sliceObject.closed_requirement_families) { $families += @(Get-StringArray $sliceObject.closed_requirement_families) }
    $families = @($families | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $exactFamilies = @(
        'wire_payload_api_contract',
        'config_policy_threshold',
        'deploy_export_page',
        'generated_artifact_template_upload',
        'external_integration',
        'automation_test_interface',
        'lifecycle_cleanup_retention'
    )
    $requiresExact = @($families | Where-Object { $exactFamilies -contains [string]$_ }).Count -gt 0
    $requiresSideEffect = @($families | Where-Object { @('core_entry', 'stateful_side_effect', 'generated_artifact_template_upload', 'lifecycle_cleanup_retention') -contains [string]$_ }).Count -gt 0 -or [string]$sliceObject.slice_type -match 'stateful'

    if (-not $NoCarrierAuthorization) {
        $carrierObject = if ($null -ne $CarrierAuthorizationObject) {
            $CarrierAuthorizationObject
        } else {
            [ordered]@{
                schema_version = 1
                slice_index = 1
                forced_requirement_family = (@($families) | Select-Object -First 1)
                authorization = 'ALLOW'
                real_entry = 'SampleCarrier.execute'
                selected_carrier = 'SampleCarrier.execute'
                downstream_side_effect_or_output = 'sample downstream output'
                requires_side_effect_evidence = $requiresSideEffect
                requires_exact_contract_assertions = $requiresExact
                forbidden_synthetic_carrier = $false
                forbidden_helper_only_carrier = $false
                proof_required = @('sample behavior proof')
                forbidden_proof = @()
                issues = @()
                warnings = @()
                gate = 'production_carrier_authorization'
            }
        }
        Write-JsonFile -Object $carrierObject -Path (Join-Path $caseRoot 'CARRIER_AUTHORIZATION_01.json')
    }
    if ($requiresExact -and -not $NoExactContractMatrix) {
        $exactObject = if ($null -ne $ExactContractMatrixObject) {
            $ExactContractMatrixObject
        } else {
            [ordered]@{
                schema_version = 1
                slice_index = 1
                required_for_this_slice = $true
                rows = @([ordered]@{
                    literal = 'sample literal'
                    symbol_or_field = 'sampleField'
                    db_or_wire_or_display = 'sample display'
                    boundary_type = 'display'
                    production_boundary = 'SampleCarrier.execute -> sample display output'
                    closure_proof = 'controller or service behavior assertion proves sample display output'
                    test_assertion = 'assert exact sample literal'
                    status = 'CLOSED'
                    touched = $true
                    source = 'test'
                })
            }
        }
        Write-JsonFile -Object $exactObject -Path (Join-Path $caseRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_01.json')
    }
    if ($requiresSideEffect -and -not $NoSideEffectEvidence) {
        $sideObject = if ($null -ne $SideEffectEvidenceObject) {
            $SideEffectEvidenceObject
        } else {
            [ordered]@{
                schema_version = 1
                slice_index = 1
                required_for_this_slice = $true
                entry_call = 'SampleCarrier.execute'
                expected_writes_or_outputs = @('sample state write', 'sample log output')
                must_not_writes = @('no unrelated write')
                test_name = 'SampleCarrierTest'
                red_result = 'BUSINESS_ASSERTION_FAILED'
                green_result = 'PASS'
                status = 'CLOSED'
            }
        }
        Write-JsonFile -Object $sideObject -Path (Join-Path $caseRoot 'SIDE_EFFECT_EVIDENCE_01.json')
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $script:verifier `
        -ReplayRoot $caseRoot `
        -Worktree $script:worktree `
        -SliceResult $sliceResultPath `
        -SliceIndex 1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "SliceVerifier failed for case $Name with exit code $LASTEXITCODE"
    }

    $verify = Read-JsonObject (Join-Path $caseRoot 'SLICE_VERIFY_01.json')
    if ([string]$verify.verification_status -ne $ExpectedStatus) {
        throw "Case $Name expected status $ExpectedStatus but got $($verify.verification_status)"
    }
    if ([int]$verify.coverage_cap -gt $MaxCoverageCap) {
        throw "Case $Name expected coverage cap <= $MaxCoverageCap but got $($verify.coverage_cap)"
    }
    if ($null -ne $verify.adjusted_coverage_delta -and [int]$verify.adjusted_coverage_delta -gt [int]$verify.coverage_cap) {
        throw "Case $Name adjusted delta $($verify.adjusted_coverage_delta) exceeds coverage cap $($verify.coverage_cap)"
    }
    if ($null -ne $verify.adjusted_coverage_delta -and [int]$verify.adjusted_coverage_delta -gt $MaxAdjustedDelta) {
        throw "Case $Name expected adjusted delta <= $MaxAdjustedDelta but got $($verify.adjusted_coverage_delta)"
    }
    if ($null -ne $ExpectedShouldContinue -and [bool]$verify.should_continue -ne [bool]$ExpectedShouldContinue) {
        throw "Case $Name expected should_continue=$ExpectedShouldContinue but got $($verify.should_continue)"
    }
    if ($null -ne $ExpectedAuthorizedNextSlice -and [bool]$verify.authorized_for_next_slice -ne [bool]$ExpectedAuthorizedNextSlice) {
        throw "Case $Name expected authorized_for_next_slice=$ExpectedAuthorizedNextSlice but got $($verify.authorized_for_next_slice)"
    }
    if ($null -ne $ExpectedAuthorizedSynthesis -and [bool]$verify.authorized_for_synthesis -ne [bool]$ExpectedAuthorizedSynthesis) {
        throw "Case $Name expected authorized_for_synthesis=$ExpectedAuthorizedSynthesis but got $($verify.authorized_for_synthesis)"
    }
    if ($null -ne $ExpectedHasBehaviorEvidence -and [bool]$verify.has_behavior_evidence -ne [bool]$ExpectedHasBehaviorEvidence) {
        throw "Case $Name expected has_behavior_evidence=$ExpectedHasBehaviorEvidence but got $($verify.has_behavior_evidence)"
    }
    foreach ($warning in $ExpectedWarnings) {
        if (@($verify.warnings) -notcontains $warning) {
            throw "Case $Name missing warning: $warning"
        }
    }
    foreach ($warning in $ForbiddenWarnings) {
        if (@($verify.warnings) -contains $warning) {
            throw "Case $Name unexpectedly has warning: $warning"
        }
    }
    foreach ($gapFlag in $ExpectedGapFlags) {
        if (@($verify.gap_flags) -notcontains $gapFlag) {
            throw "Case $Name missing gap flag: $gapFlag"
        }
    }
    foreach ($gapFlag in $ForbiddenGapFlags) {
        if (@($verify.gap_flags) -contains $gapFlag) {
            throw "Case $Name unexpectedly has gap flag: $gapFlag"
        }
    }
    foreach ($blocker in $ExpectedAuthorizationBlockers) {
        if (@($verify.authorization_blockers) -notcontains $blocker) {
            throw "Case $Name missing authorization blocker: $blocker"
        }
    }
    foreach ($blocker in $ForbiddenAuthorizationBlockers) {
        if (@($verify.authorization_blockers) -contains $blocker) {
            throw "Case $Name unexpectedly has authorization blocker: $blocker"
        }
    }
    foreach ($family in $ExpectedProofMismatchFamilies) {
        if (@($verify.proof_type_mismatch_families) -notcontains $family) {
            throw "Case $Name missing proof type mismatch family: $family"
        }
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$script:verifier = Join-Path $PSScriptRoot 'SliceVerifier.ps1'
$script:tempRoot = Join-Path $scriptRoot ('.tmp\verifier-contracts-{0}' -f $PID)
$script:worktree = Join-Path $script:tempRoot 'worktree'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        verifier = $script:verifier
        temp_root = $script:tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

New-Item -ItemType Directory -Force -Path $script:worktree | Out-Null
& git -C $script:worktree init | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git init failed for $script:worktree" }
Set-Content -LiteralPath (Join-Path $script:worktree 'README.md') -Encoding UTF8 -Value 'verifier contract worktree'
New-Item -ItemType Directory -Force -Path (Join-Path $script:worktree 'src\main\java') | Out-Null
Set-Content -LiteralPath (Join-Path $script:worktree 'src\main\java\SampleCarrier.java') -Encoding UTF8 -Value 'class SampleCarrier {}'
New-Item -ItemType Directory -Force -Path (Join-Path $script:worktree 'src\test\java') | Out-Null
Set-Content -LiteralPath (Join-Path $script:worktree 'src\main\java\SampleProcessor.java') -Encoding UTF8 -Value @"
class SampleProcessor {
    protected void handleSystemAutoFlow(Object task, Object result) {
        // tracer bullet only lands the hook
    }
}
"@
Set-Content -LiteralPath (Join-Path $script:worktree 'src\test\java\SampleProcessorTest.java') -Encoding UTF8 -Value @"
class SampleProcessorTest {
    static class TestableSampleProcessor extends SampleProcessor {
        private int autoFlowInvokeCount;

        @Override
        protected void handleSystemAutoFlow(Object task, Object result) {
            autoFlowInvokeCount++;
        }

        int getAutoFlowInvokeCount() {
            return autoFlowInvokeCount;
        }
    }
}
"@
Set-Content -LiteralPath (Join-Path $script:worktree 'src\test\java\SampleCarrierTest.java') -Encoding UTF8 -Value 'class SampleCarrierTest {}'
Set-Content -LiteralPath (Join-Path $script:worktree 'src\main\java\DependencyEvent.java') -Encoding UTF8 -Value 'class DependencyEvent { void publish() {} }'
Set-Content -LiteralPath (Join-Path $script:worktree 'src\test\java\DependencySpyTest.java') -Encoding UTF8 -Value @"
class DependencySpyTest {
    static class CountingDependencyEvent extends DependencyEvent {
        private int invokeCount;

        @Override
        void publish() {
            invokeCount++;
        }

        int getInvokeCount() {
            return invokeCount;
        }
    }
}
"@
& git -C $script:worktree add README.md src/main/java/SampleCarrier.java src/main/java/SampleProcessor.java src/main/java/DependencyEvent.java src/test/java/SampleProcessorTest.java src/test/java/SampleCarrierTest.java src/test/java/DependencySpyTest.java | Out-Null
& git -C $script:worktree -c user.name='Replay Test' -c user.email='replay-test@example.local' commit -m 'init' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git commit failed for $script:worktree" }

$redFail = [ordered]@{ command = 'test-red'; phase = 'RED'; result = 'fail'; evidence = 'expected assertion failed' }
$redBlocked = [ordered]@{ command = 'test-red'; phase = 'RED'; result = 'blocked'; evidence = 'red command was blocked and did not prove failure' }
$greenPass = [ordered]@{ command = 'test-green'; phase = 'GREEN'; result = 'pass'; evidence = 'green passed' }
$verifyPass = [ordered]@{ command = 'test-verify'; phase = 'VERIFY'; result = 'pass'; evidence = 'verification passed' }

$plannedClassDotBindingCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'real_entry_behavior' `
    -CoverageDelta 8 `
    -TouchedFamilies @('core_entry') `
    -ClosedFamilies @('core_entry') `
    -Tests @(
        [ordered]@{ command = 'mvn -Dtest=SampleCarrierTest test'; phase = 'RED'; result = 'fail'; evidence = 'planned class red failed' },
        [ordered]@{ command = 'mvn -Dtest=SampleCarrierTest test'; phase = 'GREEN'; result = 'pass'; evidence = 'planned class green passed' }
    )
$plannedClassDotBindingCase.target_subsurface_or_carrier = 'SampleCarrier.execute'
$plannedClassDotBindingCase.production_boundary = 'SampleCarrier.execute'
$plannedClassDotPlan = @(
    'first_red_test: SampleCarrierTest.shouldCallCarrier',
    'selected_carrier: SampleCarrier.execute',
    'selected_real_entry: src/main/java/SampleCarrier.java#execute'
) -join "`n"
Invoke-VerifierCase `
    -Name 'planned_class_dot_method_binding_matches_maven_class_filter' `
    -SliceResultObject $plannedClassDotBindingCase `
    -PlanLockText $plannedClassDotPlan `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 8 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $true `
    -ForbiddenWarnings @('planned_red_test_mismatch') `
    -ForbiddenGapFlags @('planned_red_test_mismatch', 'wrong_test_surface') `
    -ForbiddenAuthorizationBlockers @('wrong_test_surface', 'proof_type_mismatch')

$provisionalExactGapCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'real_entry_behavior' `
    -CoverageDelta 8 `
    -TouchedFamilies @('core_entry') `
    -ClosedFamilies @('core_entry') `
    -Tests @($redFail, $greenPass)
$provisionalExactGapCase.target_subsurface_or_carrier = 'SampleCarrier.execute'
$provisionalExactGapCase.production_boundary = 'SampleCarrier.execute'
$provisionalExactGapCase.exact_contract_assertions = @([ordered]@{
    literal = 'TASK_STATUS(21) maps to wait-material scene'
    symbol_or_field = 'CaseStatusType.TASK_STATUS'
    db_or_wire_or_display = 'wire'
    production_predicate = 'currentStatus in {21,92} maps to TASK_STATUS'
    forbidden_extra_predicate = 'No extra status guard'
    test_assertion = 'SampleCarrierTest asserts TASK_STATUS'
    source_type = 'requirement'
    status = 'CLOSED'
})
Invoke-VerifierCase `
    -Name 'provisional_exact_predicate_gap_allows_next_but_not_synthesis' `
    -SliceResultObject $provisionalExactGapCase `
    -RequirementText 'Requirement requires notification when entering wait-material status, but does not freeze the internal enum name.' `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 75 `
    -MaxAdjustedDelta 8 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedHasBehaviorEvidence $true `
    -ExpectedWarnings @('unproven_extra_requirement_predicate') `
    -ExpectedGapFlags @('exact_contract_gap', 'provisional_exact_contract_gap') `
    -ForbiddenGapFlags @('exact_contract_not_closed', 'tooling_enforcement_stop', 'wrong_test_surface') `
    -ForbiddenAuthorizationBlockers @('behavior_evidence_missing', 'exact_contract_not_closed', 'wrong_test_surface')

$dependencySpyResult = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'real_entry_behavior' `
    -CoverageDelta 35 `
    -TouchedFamilies @('core_entry') `
    -ClosedFamilies @('core_entry') `
    -Tests @($redFail, $greenPass, $verifyPass)
$dependencySpyResult.implemented_files = @('src/main/java/SampleCarrier.java', 'src/test/java/DependencySpyTest.java')
$dependencySpyResult.target_subsurface_or_carrier = 'SampleCarrier.execute -> DependencyEvent.publish'
$dependencySpyResult.closed_assertions = @('real entry calls dependency event once')
Invoke-VerifierCase `
    -Name 'dependency_spy_allows_next_but_not_synthesis' `
    -SliceResultObject $dependencySpyResult `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 45 `
    -MaxAdjustedDelta 8 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('dependency_spy_counter_proof') `
    -ExpectedGapFlags @('dependency_spy_output_gap') `
    -CarrierAuthorizationObject ([ordered]@{
        schema_version = 1
        slice_index = 1
        forced_requirement_family = 'core_entry'
        authorization = 'ALLOW'
        real_entry = 'SampleCarrier.execute'
        selected_carrier = 'SampleCarrier.execute -> DependencyEvent.publish'
        downstream_side_effect_or_output = 'dependency event publish'
        requires_side_effect_evidence = $true
        requires_exact_contract_assertions = $false
        forbidden_synthetic_carrier = $false
        forbidden_helper_only_carrier = $false
        proof_required = @('real entry behavior')
        forbidden_proof = @('subclass primary carrier')
        issues = @()
        warnings = @()
        gate = 'production_carrier_authorization'
    })

Invoke-VerifierCase `
    -Name 'red_missing_done_is_partial' `
    -SliceResultObject (New-SliceResultObject -Tests @($greenPass) -TouchedFamilies @('wire_payload_api_contract') -ClosedFamilies @('wire_payload_api_contract') -CoverageDelta 12) `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 55 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('red_phase_missing')

$tddRedNotReplayedCase = New-SliceResultObject `
    -Status 'PARTIAL' `
    -SliceType 'deploy_surface_first_slice' `
    -ProofKind 'export' `
    -Tests @($greenPass, $verifyPass) `
    -TouchedFamilies @('deploy_export_page') `
    -GapFlags @('tdd_red_not_replayed') `
    -CoverageDelta 10
Invoke-VerifierCase `
    -Name 'tdd_red_not_replayed_stops_loop' `
    -SliceResultObject $tddRedNotReplayedCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 45 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('tdd_red_not_replayed') `
    -ExpectedGapFlags @('tdd_red_not_replayed') `
    -ExpectedAuthorizationBlockers @('tdd_red_not_replayed')

$redBlockedCase = New-SliceResultObject `
    -Status 'PARTIAL' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'service' `
    -Tests @($redBlocked, $greenPass, $verifyPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -CoverageDelta 10
Invoke-VerifierCase `
    -Name 'red_blocked_stops_loop' `
    -SliceResultObject $redBlockedCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('red_phase_did_not_fail') `
    -ExpectedAuthorizationBlockers @('red_phase_did_not_fail')

$executorBlockedCase = New-SliceResultObject `
    -Status 'BLOCKED' `
    -SliceType 'blocker' `
    -ProofKind 'static_contract' `
    -Tests @([ordered]@{ command = 'Invoke-AgentPrompt.ps1'; phase = 'EXECUTOR'; result = 'blocked'; evidence = 'executor failed before production boundary' }) `
    -GapFlags @('tooling_executor_failed', 'no_progress_slice') `
    -CoverageDelta 0
$executorBlockedCase['target_subsurface_or_carrier'] = 'executor:blocker'
$executorBlockedCase['production_boundary'] = 'none - executor failed before production boundary could be changed'
$executorBlockedCase['implemented_files'] = @()
Invoke-VerifierCase `
    -Name 'executor_blocked_has_no_behavior_evidence' `
    -SliceResultObject $executorBlockedCase `
    -ExpectedStatus 'BLOCKED' `
    -MaxCoverageCap 40 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedHasBehaviorEvidence $false `
    -ExpectedWarnings @('no_progress_slice') `
    -ExpectedGapFlags @('no_progress_slice') `
    -ExpectedAuthorizationBlockers @('verification_failed_or_blocked', 'behavior_evidence_missing')

$coreRedNotReplayedCase = New-SliceResultObject `
    -Status 'PARTIAL' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'unit' `
    -Tests @($greenPass, $verifyPass) `
    -TouchedFamilies @('core_entry') `
    -GapFlags @('tdd_red_not_replayed') `
    -CoverageDelta 8
$coreRedNotReplayedCase.target_subsurface_or_carrier = 'SampleProcessor.handleTaskResponse'
Invoke-VerifierCase `
    -Name 'core_red_not_replayed_caps_at_ten' `
    -SliceResultObject $coreRedNotReplayedCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('tdd_red_not_replayed') `
    -ExpectedGapFlags @('tdd_red_not_replayed') `
    -ExpectedAuthorizationBlockers @('tdd_red_not_replayed')

$missingCarrierAuthCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('core_entry') `
    -CoverageDelta 12
$missingCarrierAuthCase.target_subsurface_or_carrier = 'SampleCarrier.execute'
Invoke-VerifierCase `
    -Name 'carrier_authorization_missing_fails_closed' `
    -SliceResultObject $missingCarrierAuthCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('carrier_authorization_missing') `
    -ExpectedGapFlags @('carrier_authorization_missing', 'tooling_enforcement_stop') `
    -ExpectedAuthorizationBlockers @('carrier_authorization_missing') `
    -NoCarrierAuthorization

$carrierStopCase = New-SliceResultObject `
    -Status 'BLOCKED' `
    -SliceType 'blocker' `
    -ProofKind 'static_contract' `
    -Tests @([ordered]@{ command = 'carrier-auth'; phase = 'VERIFY'; result = 'blocked'; evidence = 'carrier authorization stopped' }) `
    -TouchedFamilies @('core_entry') `
    -GapFlags @('carrier_authorization_stop') `
    -CoverageDelta 0
$carrierStopObject = [ordered]@{
    schema_version = 1
    slice_index = 1
    authorization = 'STOP'
    real_entry = ''
    selected_carrier = ''
    downstream_side_effect_or_output = ''
    requires_side_effect_evidence = $true
    requires_exact_contract_assertions = $false
    forbidden_synthetic_carrier = $false
    forbidden_helper_only_carrier = $false
    issues = @('selected_carrier_missing')
    warnings = @()
}
Invoke-VerifierCase `
    -Name 'carrier_authorization_stop_fails_closed' `
    -SliceResultObject $carrierStopCase `
    -ExpectedStatus 'BLOCKED' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('carrier_authorization_stop', 'selected_carrier_missing', 'downstream_side_effect_or_output_missing') `
    -ExpectedGapFlags @('carrier_authorization_stop', 'tooling_enforcement_stop') `
    -ExpectedAuthorizationBlockers @('verification_failed_or_blocked', 'carrier_authorization_stop') `
    -CarrierAuthorizationObject $carrierStopObject `
    -NoSideEffectEvidence

$exactAssertionMissingCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'exact_contract_slice' `
    -ProofKind 'controller' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('wire_payload_api_contract') `
    -ClosedFamilies @('wire_payload_api_contract') `
    -CoverageDelta 10
$openExactMatrix = [ordered]@{
    schema_version = 1
    slice_index = 1
    required_for_this_slice = $true
    rows = @([ordered]@{
        literal = 'sample literal'
        symbol_or_field = ''
        db_or_wire_or_display = ''
        test_assertion = ''
        status = 'OPEN'
        touched = $true
    })
}
Invoke-VerifierCase `
    -Name 'exact_contract_assertion_missing_fails_closed' `
    -SliceResultObject $exactAssertionMissingCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('exact_contract_assertion_missing') `
    -ExpectedGapFlags @('exact_contract_assertion_missing', 'exact_contract_gap') `
    -ExpectedAuthorizationBlockers @('exact_contract_assertion_missing') `
    -ExactContractMatrixObject $openExactMatrix

$exactOpenGapCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'exact_contract_slice' `
    -ProofKind 'controller' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('wire_payload_api_contract') `
    -ClosedFamilies @('wire_payload_api_contract') `
    -GapFlags @('exact_contract_gap') `
    -CoverageDelta 8
$exactOpenGapCase['exact_contract_assertions'] = @([ordered]@{
    literal = 'sample literal'
    symbol_or_field = 'sampleField'
    db_or_wire_or_display = 'wire'
    test_assertion = 'assert sample literal'
    status = 'CLOSED'
})
Invoke-VerifierCase `
    -Name 'exact_contract_gap_fails_closed_even_with_some_assertions' `
    -SliceResultObject $exactOpenGapCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 25 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('exact_contract_open') `
    -ExpectedGapFlags @('exact_contract_not_closed') `
    -ExpectedAuthorizationBlockers @('exact_contract_not_closed')

$sideEffectMissingCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'transaction' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 15
Invoke-VerifierCase `
    -Name 'side_effect_evidence_missing_fails_closed' `
    -SliceResultObject $sideEffectMissingCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('side_effect_evidence_missing') `
    -ExpectedGapFlags @('side_effect_evidence_missing', 'side_effect_ledger_gap') `
    -ExpectedAuthorizationBlockers @('side_effect_evidence_missing') `
    -NoSideEffectEvidence

$subclassOnlyProofCase = New-SliceResultObject `
    -Status 'PARTIAL' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'unit' `
    -Tests @($greenPass) `
    -TouchedFamilies @('core_entry') `
    -GapFlags @('tracer_bullet_only') `
    -CoverageDelta 8
$subclassOnlyProofCase.target_subsurface_or_carrier = 'SampleProcessor.handleTaskResponse'
$subclassOnlyProofCase.production_boundary = 'real entry calls protected empty hook'
$subclassOnlyProofCase.implemented_files = @('src/main/java/SampleProcessor.java', 'src/test/java/SampleProcessorTest.java')
$subclassOnlyProofCase.closed_assertions = @('subclass counter incremented')
$subclassOnlyProofCase.next_recommended_slice_type = 'stateful_success_slice'
Invoke-VerifierCase `
    -Name 'subclass_empty_hook_is_tooling_stop' `
    -SliceResultObject $subclassOnlyProofCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('empty_or_noop_production_carrier', 'subclass_only_proof', 'tooling_enforcement_stop') `
    -ExpectedGapFlags @('wrong_test_surface', 'synthetic_carrier_gap', 'shallow_module', 'tooling_enforcement_stop') `
    -ExpectedAuthorizationBlockers @('behavior_evidence_missing', 'substitute_or_shallow_proof')

$absolutePathProofCase = New-SliceResultObject `
    -Status 'PARTIAL' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'unit' `
    -Tests @($greenPass) `
    -TouchedFamilies @('core_entry') `
    -GapFlags @('tracer_bullet_only') `
    -CoverageDelta 8
$absolutePathProofCase.target_subsurface_or_carrier = 'SampleProcessor.handleTaskResponse'
$absolutePathProofCase.production_boundary = 'real entry calls protected empty hook'
$absolutePathProofCase.implemented_files = @(
    (Join-Path $script:worktree 'src\main\java\SampleProcessor.java'),
    (Join-Path $script:worktree 'src\test\java\SampleProcessorTest.java')
)
$absolutePathProofCase.closed_assertions = @('subclass counter incremented')
$absolutePathProofCase.next_recommended_slice_type = 'stateful_success_slice'
Invoke-VerifierCase `
    -Name 'absolute_paths_are_read_for_tooling_stop' `
    -SliceResultObject $absolutePathProofCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 10 `
    -MaxAdjustedDelta 0 `
    -ExpectedShouldContinue $false `
    -ExpectedAuthorizedNextSlice $false `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedWarnings @('empty_or_noop_production_carrier', 'subclass_only_proof', 'tooling_enforcement_stop') `
    -ExpectedGapFlags @('wrong_test_surface', 'synthetic_carrier_gap', 'shallow_module', 'tooling_enforcement_stop') `
    -ExpectedAuthorizationBlockers @('behavior_evidence_missing', 'substitute_or_shallow_proof')

$placeholderCase = New-SliceResultObject `
    -SliceType 'deploy_surface_first_slice' `
    -ProofKind 'unit' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('generated_artifact_template_upload') `
    -ClosedFamilies @('generated_artifact_template_upload') `
    -CoverageDelta 15
$placeholderCase.closed_assertions = @('uploaded placeholder png bytes through attachment helper')
Invoke-VerifierCase `
    -Name 'placeholder_artifact_is_partial' `
    -SliceResultObject $placeholderCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 60 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('placeholder_artifact_cannot_close_family') `
    -ExpectedGapFlags @('placeholder_artifact_gap')

$deployMissingCarrierCase = New-SliceResultObject `
    -SliceType 'deploy_surface_first_slice' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('deploy_export_page') `
    -ClosedFamilies @('deploy_export_page') `
    -CoverageDelta 8
$deployMissingCarrierCase.implemented_files = @('src/main/java/SampleHelper.java')
$deployMissingCarrierCase.closed_assertions = @('helper assertion passed without a deploy-facing carrier proof')
Invoke-VerifierCase `
    -Name 'deploy_closed_without_deploy_carrier_is_partial' `
    -SliceResultObject $deployMissingCarrierCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 65 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('deploy_asset_or_endpoint_proof_missing') `
    -ExpectedGapFlags @('deploy_asset_gap') `
    -ExpectedProofMismatchFamilies @('deploy_export_page')

$deployPassCase = New-SliceResultObject `
    -SliceType 'deploy_surface_first_slice' `
    -ProofKind 'export' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('deploy_export_page') `
    -ClosedFamilies @('deploy_export_page') `
    -CoverageDelta 8
$deployPassCase.implemented_files = @('src/main/java/SampleExportController.java', 'src/main/java/SampleExportMapper.xml')
$deployPassCase.production_boundary = 'export endpoint returns report download rows through mapper query'
$deployPassCase.closed_assertions = @('controller export endpoint assertion passed for report download header')
Invoke-VerifierCase `
    -Name 'deploy_export_real_slice_can_pass' `
    -SliceResultObject $deployPassCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 8 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $true

Invoke-VerifierCase `
    -Name 'automation_contract_real_slice_can_pass' `
    -SliceResultObject (New-SliceResultObject -ProofKind 'controller' -Tests @($redFail, $greenPass) -TouchedFamilies @('automation_test_interface') -ClosedFamilies @('automation_test_interface') -CoverageDelta 7) `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 7

$wireMissingShapeCase = New-SliceResultObject `
    -ProofKind 'helper' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('wire_payload_api_contract') `
    -ClosedFamilies @('wire_payload_api_contract') `
    -CoverageDelta 9
$wireMissingShapeCase.implemented_files = @('src/main/java/SampleHelper.java')
$wireMissingShapeCase.closed_assertions = @('helper constant exists but no actual request body or payload shape was asserted')
Invoke-VerifierCase `
    -Name 'wire_payload_without_shape_is_partial' `
    -SliceResultObject $wireMissingShapeCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 60 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('wire_payload_shape_proof_missing') `
    -ExpectedGapFlags @('wire_payload_shape_gap') `
    -ExpectedProofMismatchFamilies @('wire_payload_api_contract')

$wirePassCase = New-SliceResultObject `
    -ProofKind 'controller' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('wire_payload_api_contract') `
    -ClosedFamilies @('wire_payload_api_contract') `
    -CoverageDelta 8
$wirePassCase.implemented_files = @('src/main/java/SamplePayloadRequest.java', 'src/main/java/SampleApiController.java')
$wirePassCase.production_boundary = 'API controller builds actual request payload JSON'
$wirePassCase.closed_assertions = @('asserted actual request body JSON array field and wire payload schema')
Invoke-VerifierCase `
    -Name 'wire_payload_real_slice_can_pass' `
    -SliceResultObject $wirePassCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 8

$configThresholdCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'exact_contract_slice' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('config_policy_threshold') `
    -ClosedFamilies @('config_policy_threshold') `
    -CoverageDelta 7
$configThresholdCase.implemented_files = @('src/main/java/SampleCarrier.java', 'src/test/java/SampleConfigThresholdTest.java')
$configThresholdCase.production_boundary = 'SampleConfigService#save -> SampleConfigMapper.xml free_review_amount update'
$configThresholdCase.exact_contract_assertions = @([ordered]@{
    literal = 'free_review_amount'
    symbol_or_field = 'SampleConfigMapper.xml'
    db_or_wire_or_display = 'db'
    boundary_type = 'db'
    production_boundary = 'SampleConfigService#save -> SampleConfigMapper.xml free_review_amount update'
    closure_proof = 'mapper update assertion proves database free_review_amount persistence'
    test_assertion = 'clear submit updates persisted threshold column'
    status = 'CLOSED'
})
$configThresholdCase.closed_assertions = @(
    'service validates threshold literal',
    'mapper update persists free_review_amount',
    'wire dto exposes freeReviewAmount'
)
Invoke-VerifierCase `
    -Name 'config_policy_threshold_service_persistence_can_pass' `
    -SliceResultObject $configThresholdCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 7 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $true

$openSiblingCase = New-SliceResultObject `
    -SliceType 'deploy_surface_first_slice' `
    -ProofKind 'export' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('deploy_export_page') `
    -ClosedFamilies @('deploy_export_page') `
    -CoverageDelta 9
$openSiblingCase.implemented_files = @('src/main/java/SampleExportController.java')
$openSiblingCase.required_sibling_surfaces = @('ReportTableController export endpoint still lacks executable value assertion')
Invoke-VerifierCase `
    -Name 'closed_family_with_open_sibling_is_partial' `
    -SliceResultObject $openSiblingCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 65 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('family_sibling_surface_open') `
    -ExpectedGapFlags @('family_sibling_gap')

$statefulWithDeploySiblingCase = New-SliceResultObject `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'transaction' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('stateful_side_effect', 'deploy_export_page') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 8
$statefulWithDeploySiblingCase.required_sibling_surfaces = @('deploy_export_page: /case/export workbook assertion still open')
$statefulWithDeploySiblingCase.closed_assertions = @('asserted transaction rollback, commit order, task update, state transition, and progress log')
Invoke-VerifierCase `
    -Name 'family_scoped_sibling_does_not_block_other_family' `
    -SliceResultObject $statefulWithDeploySiblingCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 8

$progressiveCoreSlice = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'tracer_bullet' `
    -ProofKind 'real_entry_behavior' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('core_entry') `
    -ClosedFamilies @('core_entry') `
    -GapFlags @('tracer_bullet_only', 'side_effect_ledger_gap', 'deploy_surface_contract_gap') `
    -CoverageDelta 8
$progressiveCoreSlice.target_subsurface_or_carrier = 'OpenClaimService.parseDangerInfo -> ReportService.createReport -> ClaimNotifyEvent.pushMsgToMQ'
$progressiveCoreSlice.production_boundary = 'XmlpOpenClaimController.reportCase -> OpenClaimService.parseDangerInfo -> ReportService.createReport'
$progressiveCoreSlice.implemented_files = @(
    'src/main/java/SampleCarrier.java',
    'src/test/java/SampleCarrierTest.java'
)
$progressiveCoreSlice.next_recommended_slice_type = 'stateful_success_slice'
$progressiveCoreSlice.exact_contract_assertions = @([ordered]@{
    literal = 'OpenReportDto.wxId'
    symbol_or_field = 'CaseInfoParam.wxId'
    db_or_wire_or_display = 'wire'
    production_predicate = 'OpenClaimService copies wxId into CaseInfoParam'
    forbidden_extra_predicate = 'none'
    test_assertion = 'request wxId reaches payload wxId'
    source_type = 'requirement'
    status = 'CLOSED'
})
$progressiveCoreSlice.side_effect_evidence = [ordered]@{
    status = 'CLOSED'
    entry_call = 'XmlpOpenClaimController.reportCase'
    expected_writes_or_outputs = @('Report wxId is written', 'MQ payload wxId is emitted')
    must_not_writes = @('no rabbit topology change')
    test_name = 'OpenClaimWxIdContractTest'
    red_result = 'BUSINESS_ASSERTION_FAILED'
    green_result = 'PASS'
}
$progressiveCoreCarrier = [ordered]@{
    schema_version = 1
    slice_index = 1
    forced_requirement_family = 'core_entry'
    authorization = 'ALLOW'
    real_entry = 'XmlpOpenClaimController.reportCase'
    selected_carrier = 'XmlpOpenClaimController.reportCase -> OpenClaimService.parseDangerInfo -> ReportService.createReport'
    downstream_side_effect_or_output = 'Report wxId and MQ payload wxId'
    requires_side_effect_evidence = $true
    requires_exact_contract_assertions = $false
    forbidden_synthetic_carrier = $false
    forbidden_helper_only_carrier = $false
    proof_required = @('real controller entry behavior')
    forbidden_proof = @()
    issues = @()
    warnings = @()
    gate = 'production_carrier_authorization'
}
Invoke-VerifierCase `
    -Name 'progressive_core_slice_allows_next_slice_with_future_surface_gaps' `
    -SliceResultObject $progressiveCoreSlice `
    -CarrierAuthorizationObject $progressiveCoreCarrier `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 40 `
    -MaxAdjustedDelta 8 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $false `
    -ExpectedHasBehaviorEvidence $true

$testOnlyClosureCase = New-SliceResultObject `
    -ProofKind 'controller' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('automation_test_interface') `
    -ClosedFamilies @('automation_test_interface') `
    -CoverageDelta 8
$testOnlyClosureCase.implemented_files = @('src/test/java/SampleInterfaceTest.java')
Invoke-VerifierCase `
    -Name 'test_only_closure_is_wrong_surface' `
    -SliceResultObject $testOnlyClosureCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 50 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('production_carrier_missing') `
    -ExpectedGapFlags @('wrong_test_surface')

$newOnlyCoreCarrierCase = New-SliceResultObject `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'transaction' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('core_entry', 'stateful_side_effect') `
    -ClosedFamilies @('core_entry') `
    -CoverageDelta 8
$newOnlyCoreCarrierCase.implemented_files = @('src/main/java/NewReplayOnlyAutoFlowService.java')
$newOnlyCoreCarrierCase.closed_assertions = @('asserted transaction rollback, commit order, task update, state transition, and progress log')
Invoke-VerifierCase `
    -Name 'new_only_core_carrier_is_shallow' `
    -SliceResultObject $newOnlyCoreCarrierCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 55 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('existing_production_carrier_missing') `
    -ExpectedGapFlags @('shallow_module')

$syntheticCarrierCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 10
$syntheticCarrierCase.implemented_files = @('claim-core/src/main/java/example/AutoFlowNoop.java', 'claim-server/src/test/java/example/AutoFlowNoopTest.java')
$syntheticCarrierCase.target_subsurface_or_carrier = 'AutoFlowNoop.orchestrate'
$syntheticCarrierCase.production_boundary = 'real entry -> AutoFlowNoop substitute carrier'
$syntheticCarrierCase.closed_assertions = @('asserted transaction rollback, commit order, task update, state transition, and progress log')
Invoke-VerifierCase `
    -Name 'synthetic_production_carrier_is_wrong_surface' `
    -SliceResultObject $syntheticCarrierCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 35 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('synthetic_production_carrier') `
    -ExpectedGapFlags @('synthetic_carrier_gap', 'wrong_test_surface', 'shallow_module')

Invoke-VerifierCase `
    -Name 'stateful_gap_is_partial' `
    -SliceResultObject (New-SliceResultObject -Status 'PARTIAL' -SliceType 'stateful_success_slice' -ProofKind 'service' -Tests @($redFail, $greenPass) -TouchedFamilies @('stateful_side_effect') -GapFlags @('side_effect_ledger_gap') -CoverageDelta 10) `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 60

$statefulMissingTransactionCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 10
$statefulMissingTransactionCase.closed_assertions = @('service method returned success with mock collaborators only')
Invoke-VerifierCase `
    -Name 'stateful_closed_without_transaction_depth_is_partial' `
    -SliceResultObject $statefulMissingTransactionCase `
    -ExpectedStatus 'PARTIAL' `
    -MaxCoverageCap 60 `
    -MaxAdjustedDelta 3 `
    -ExpectedWarnings @('transaction_depth_proof_missing') `
    -ExpectedGapFlags @('transaction_depth_gap')

$statefulPassCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'transaction' `
    -Tests @($redFail, $greenPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 9
$statefulPassCase.production_boundary = 'transactional service persists database side effects'
$statefulPassCase.closed_assertions = @('asserted transaction rollback, commit order, task update, state transition, and progress log')
Invoke-VerifierCase `
    -Name 'stateful_transaction_real_slice_can_pass' `
    -SliceResultObject $statefulPassCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 9 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $true

$newStatefulDir = Join-Path $script:worktree 'claim-core\src\main\java\com\example\ai'
New-Item -ItemType Directory -Force -Path $newStatefulDir | Out-Null
Set-Content -LiteralPath (Join-Path $newStatefulDir 'AiAutoClaimFlowService.java') -Encoding UTF8 -Value @"
class AiAutoClaimFlowService {
    private CompensateInfoMapper compensateInfoMapper;
    private CompensateDetailMapper compensateDetailMapper;
    private CaseFlowStatusService caseFlowStatusService;
    private CaseProgressService caseProgressService;
    private TaskService taskService;
    private ExamineLogService examineLogService;

    void handle() {
        compensateInfoMapper.insert(null);
        compensateDetailMapper.insert(null);
        caseFlowStatusService.updateFlowStatus(null, 35, null);
        caseProgressService.insertCaseProgress(null);
        taskService.completeTask(null);
        taskService.processTask(null);
        examineLogService.saveExamineLog(null);
        // failure isolation: exceptions must not write unrelated case progress
    }
}
"@
$statefulNewDomainCarrierCase = New-SliceResultObject `
    -Status 'DONE' `
    -SliceType 'stateful_success_slice' `
    -ProofKind 'service' `
    -Tests @($redFail, $greenPass, $verifyPass) `
    -TouchedFamilies @('stateful_side_effect') `
    -ClosedFamilies @('stateful_side_effect') `
    -CoverageDelta 12
$statefulNewDomainCarrierCase.implemented_files = @(
    'claim-core/src/main/java/com/example/ai/AiAutoClaimFlowService.java',
    'claim-server/src/test/java/com/example/ai/AiAutoClaimFlowServiceTest.java'
)
$statefulNewDomainCarrierCase.production_boundary = 'real entry -> AiAutoClaimFlowService#handle -> CompensateInfoMapper/CompensateDetailMapper + CaseFlowStatusService + CaseProgressService + TaskService + ExamineLogService'
$statefulNewDomainCarrierCase.closed_assertions = @(
    'writes compensate info/detail mapper rows',
    'updates status 35',
    'inserts progress',
    'completes and processes tasks',
    'writes log',
    'failure isolation must-not writes are asserted'
)
$statefulNewDomainCarrierCase.side_effect_evidence = [ordered]@{
    status = 'CLOSED'
    entry_call = 'AiAutoClaimFlowService#handle'
    expected_writes_or_outputs = @(
        'valid path writes t_compensate_info and t_compensate_detail',
        'valid path updates status 35 and inserts case progress',
        'old tasks complete and follow task is created',
        'failure paths write only AI log'
    )
    must_not_writes = @('no case progress on precondition failure')
    test_name = 'AiAutoClaimFlowServiceTest'
    red_result = 'BUSINESS_ASSERTION_FAILED'
    green_result = 'PASS'
}
Invoke-VerifierCase `
    -Name 'stateful_new_domain_carrier_with_side_effects_can_pass' `
    -SliceResultObject $statefulNewDomainCarrierCase `
    -ExpectedStatus 'PASS' `
    -MaxCoverageCap 100 `
    -MaxAdjustedDelta 12 `
    -ExpectedAuthorizedNextSlice $true `
    -ExpectedAuthorizedSynthesis $true

$summary = [ordered]@{
    status = 'PASS'
    cases = @(
        'planned_class_dot_method_binding_matches_maven_class_filter',
        'provisional_exact_predicate_gap_allows_next_but_not_synthesis',
        'red_missing_done_is_partial',
        'tdd_red_not_replayed_stops_loop',
        'red_blocked_stops_loop',
        'executor_blocked_has_no_behavior_evidence',
        'core_red_not_replayed_caps_at_ten',
        'carrier_authorization_missing_fails_closed',
        'carrier_authorization_stop_fails_closed',
        'exact_contract_assertion_missing_fails_closed',
        'exact_contract_gap_fails_closed_even_with_some_assertions',
        'side_effect_evidence_missing_fails_closed',
        'subclass_empty_hook_is_tooling_stop',
        'absolute_paths_are_read_for_tooling_stop',
        'placeholder_artifact_is_partial',
        'deploy_closed_without_deploy_carrier_is_partial',
        'deploy_export_real_slice_can_pass',
        'automation_contract_real_slice_can_pass',
        'wire_payload_without_shape_is_partial',
        'wire_payload_real_slice_can_pass',
        'config_policy_threshold_service_persistence_can_pass',
        'closed_family_with_open_sibling_is_partial',
        'family_scoped_sibling_does_not_block_other_family',
        'progressive_core_slice_allows_next_slice_with_future_surface_gaps',
        'test_only_closure_is_wrong_surface',
        'new_only_core_carrier_is_shallow',
        'synthetic_production_carrier_is_wrong_surface',
        'stateful_gap_is_partial',
        'stateful_closed_without_transaction_depth_is_partial',
        'stateful_transaction_real_slice_can_pass',
        'stateful_new_domain_carrier_with_side_effects_can_pass'
    )
    temp_root = $script:tempRoot
}
$summary | ConvertTo-Json -Depth 8

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $script:tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
