param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$SliceIndex,
    [Parameter(Mandatory = $true)]
    [string]$BlockerReason,
    [string]$ForcedFamily = '',
    [string]$SliceType = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$recoveryPath = Join-Path $replayRootFull ('RECOVERY_ACTION_{0}.json' -f $SliceIndex)

$blockerLower = $BlockerReason.ToLowerInvariant()
$recoveryAction = ''
$shouldRetry = $false
$shouldStop = $false
$concreteAction = @()

# Classify blocker type and determine recovery strategy
# Order matters: more specific patterns must come before generic ones
if ($blockerLower -match 'executor_credit_required|402\s+credit|required account credit|credit required|positive balance|required for this model|insufficient credits|not enough credits') {
    $recoveryAction = 'RESTORE_EXECUTOR_CREDIT'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: primary executor requires account credit or a positive balance.',
        'Recovery: Restore Claude/executor credit, or intentionally change executor policy with audit disclosure.',
        'Action: Do NOT score this run, do NOT evolve replay skills from it, and do NOT start another unattended replay until the resource blocker is cleared.'
    )
} elseif ($blockerLower -match 'usage_limit|rate.?limit|too.?many.?requests|throttl|429') {
    $recoveryAction = 'RETRY_AFTER_QUOTA_RESET'
    $shouldRetry = $true
    $concreteAction = @(
        'Blocker: executor hit model usage limit.',
        'Recovery: Resume after quota resets or switch executor.',
        'Action: Do NOT score this run or evolve skills. This is a resource blocker, not workflow coverage evidence.'
    )
} elseif ($blockerLower -match 'carrier_authorization_stop|carrier_authorization_missing|selected_carrier_missing') {
    $recoveryAction = 'REPAIR_CARRIER_AUTHORIZATION'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Carrier authorization failed.',
        'Recovery: Review CARRIER_AUTHORIZATION_<N>.json issues.',
        "Action: If the selected carrier is synthetic/helper-only, select a real production carrier for the forced family: $ForcedFamily.",
        'If the issue is missing carrier search evidence, re-run Plan stage with concrete search commands.',
        'If the issue is a genuine gap in the production codebase, set plan_status: BLOCKED with concrete blocker.'
    )
} elseif ($blockerLower -match 'executor.*auth|executor.*login|executor.*authentication|unauthorized.*executor|401.*executor|403.*executor') {
    # Only match executor-level auth issues, not carrier authorization
    $recoveryAction = 'RETRY_AFTER_AUTH_FIX'
    $shouldRetry = $true
    $concreteAction = @(
        'Blocker: Executor failed authentication.',
        'Recovery: Resume after login is fixed or switch executor.',
        'Action: Do NOT score this run or evolve skills. This is a resource blocker, not workflow coverage evidence.'
    )
} elseif ($blockerLower -match '^authentication failed|^login failed|^auth error|^unauthorized') {
    # Plain auth errors without carrier context
    $recoveryAction = 'RETRY_AFTER_AUTH_FIX'
    $shouldRetry = $true
    $concreteAction = @(
        'Blocker: Executor failed authentication.',
        'Recovery: Resume after login is fixed or switch executor.',
        'Action: Do NOT score this run or evolve skills. This is a resource blocker, not workflow coverage evidence.'
    )
} elseif ($blockerLower -match 'pre_slice_authorization|pre_flight_blocker') {
    $recoveryAction = 'RESOLVE_PREFLIGHT_BLOCKER'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Pre-flight or pre-slice authorization failed.',
        'Recovery: Review PRE_SLICE_AUTHORIZATION_<N>.json issues.',
        'Action: If baseline tests cannot compile, fix the test infrastructure before Phase 1 implementation.',
        'If the issue is environment-related, fix the environment and retry.',
        'If the issue is a genuine blocker, document it in PLAN_RESULT.md and set plan_status: BLOCKED.'
    )
} elseif ($blockerLower -match 'tooling_enforcement_stop|non_authorizing_evidence') {
    $recoveryAction = 'EVIDENCE_AUTHORIZATION_GAP'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Slice evidence was not authorizing for the next slice.',
        'Recovery: Review SLICE_VERIFY_<N>.json authorization_blockers.',
        "Action: For forced family: $ForcedFamily, ensure:",
        '- target_subsurface_or_carrier binds to a real production carrier (not helper-only, DTO-only, or mock-only)',
        '- proof_kind is real_entry_behavior, stateful_side_effect, or production_boundary (not static_contract or helper_only)',
        '- For side-effect families, RED test must validate business state change (not just compilation or file presence)',
        '- If the slice genuinely cannot close the family, document remaining gaps in required_sibling_surfaces.'
    )
} elseif ($blockerLower -match 'executor_failed_without_result|missing_slice_result') {
    $recoveryAction = 'EXECUTOR_FAILURE_RECOVERY'
    $shouldRetry = $true
    $concreteAction = @(
        'Blocker: Executor failed without writing SLICE_RESULT.',
        'Recovery: Check logs under phase1-slices directory.',
        'Action: If the error was transient (rate limit, network), retry after delay.',
        'If the error was a prompt parsing issue, check PHASE1_SLICE_<N>_PROMPT.md for template syntax.',
        'If the executor ran out of tokens, reduce slice scope to one concrete carrier.',
        'A retry with narrowed scope has already been attempted if executor_exit_code permits.'
    )
} elseif ($blockerLower -match 'wrong_test_surface|shallow_module|synthetic_carrier_gap') {
    $recoveryAction = 'TEST_SURFACE_REPAIR'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Test surface validation failed - wrong or insufficient test coverage.',
        'Recovery: Review SLICE_VERIFY_<N>.json warnings.',
        "Action: For family: $ForcedFamily, ensure:",
        '- Tests target the real production entry (Facade/Controller/Service), not helpers/DTOs only',
        '- Test class is named after the production class (e.g., MyFacadeTest for MyFacade)',
        '- RED phase fails before GREEN phase passes',
        '- Evidence includes real execution (transaction/DB/state change), not just compilation or file presence.',
        '- If selecting a new carrier, ensure it is a real production class, not a TestStub/Noop/Mock.'
    )
} elseif ($blockerLower -match 'side_effect_ledger_gap|side_effect_evidence_missing|needs_transaction_test') {
    $recoveryAction = 'SIDE_EFFECT_EVIDENCE_REPAIR'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Side-effect evidence is missing or insufficient.',
        'Recovery: Review SIDE_EFFECT_LEDGER.md and test evidence.',
        "Action: For stateful_side_effect family, ensure:",
        '- RED test validates a real state change (insert/update/delete/transaction/rollback)',
        '- Evidence includes DB state assertion, not just method invocation',
        '- Test uses real transaction boundaries, not in-memory or test-only substitutes',
        '- Document the specific entry -> state change -> verification chain in SIDE_EFFECT_LEDGER.md.',
        '- If the slice is for a read-only or helper-only carrier, it cannot close stateful_side_effect.'
    )
} elseif ($blockerLower -match 'implementation_after_blocked_red|tdd_red_not_replayed|red_phase_did_not_fail') {
    $recoveryAction = 'TDD_RED_PHASE_REPAIR'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: TDD RED phase validation failed.',
        'Recovery: Review test phase sequence in SLICE_RESULT_<N>.json.',
        'Action: Ensure proper TDD workflow:',
        '- RED phase must FAIL before any implementation',
        '- GREEN phase must PASS after implementation',
        '- If RED was BLOCKED, do not implement production code - fix the test infrastructure first',
        '- If RED passed without implementation, the test is not a valid RED assertion',
        '- Re-run the slice with proper RED->GREEN sequence.'
    )
} elseif ($blockerLower -match 'plan_contract_verification_failed|plan_status_blocked') {
    $recoveryAction = 'PLAN_CONTRACT_REPAIR'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Plan contract verification failed.',
        'Recovery: Review PLAN_CONTRACT_VERIFY.json or PHASE0_CONTRACT_VERIFY.json.',
        'Action: Fix missing or invalid plan artifacts:',
        '- Ensure all required fields exist with non-placeholder values in FIRST_SLICE_PROOF_PLAN.md',
        '- Ensure carrier_search_queries includes at least 3 reproducible search commands',
        '- Ensure selected_carrier_from_search is derived from existing_production_carriers',
        '- If oracle_overlap_below_threshold, expand plan to cover more oracle production files.',
        '- After fixing, re-run Plan stage to regenerate valid artifacts.'
    )
} elseif ($blockerLower -match 'oracle_overlap_gate|oracle_analysis_missing') {
    $recoveryAction = 'ORACLE_OVERLAP_REPAIR'
    $shouldRetry = $false
    $shouldStop = $true
    $concreteAction = @(
        'Blocker: Oracle overlap gate failed.',
        'Recovery: Review ORACLE_OVERLAP_GATE.json.',
        'Action: Ensure Plan stage has:',
        '- ORACLE_DIFF_ANALYSIS.json with production files identified',
        '- Plan overlaps at least 50% of oracle production files by filename or path',
        '- If overlap is genuinely below 50%, the feature may not align with the oracle baseline.',
        '- Consider expanding scope or documenting why the feature diverges from oracle changes.'
    )
} else {
    $recoveryAction = 'UNKNOWN_BLOCKER'
    $shouldStop = $true
    $concreteAction = @(
        "Blocker: $BlockerReason",
        'Recovery: Inspect logs and artifacts for details.',
        'Action: Review the specific blocker context and determine if:',
        '- This is a transient issue (retry possible)',
        '- This is a skill/prompt gap (evolution required)',
        '- This is a genuine project blocker (plan_status: BLOCKED)'
    )
}

# Build machine-readable recovery output
$recovery = [ordered]@{
    slice_index = [int]$SliceIndex
    blocker_reason = $BlockerReason
    blocker_category = if ($shouldRetry) { 'transient' } elseif ($shouldStop) { 'fail_closed' } else { 'recoverable' }
    recovery_action = $recoveryAction
    should_retry = $shouldRetry
    should_stop = $shouldStop
    forced_family = $ForcedFamily
    slice_type = $SliceType
    concrete_steps = @($concreteAction)
    generated_at = (Get-Date).ToString('s')
}

$recovery | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recoveryPath -Encoding UTF8

# Also write a human-readable markdown version
$recoveryMdPath = Join-Path $replayRootFull ('RECOVERY_ACTION_{0}.md' -f $SliceIndex)
$mdContent = @"
# Recovery Action for S$SliceIndex

**Blocker**: $BlockerReason
**Category**: $($recovery.blocker_category)
**Action**: $recoveryAction

## Decision

$(
    if ($shouldRetry) {
        "- **RETRY**: This blocker is transient. Resume after fixing the resource issue."
    } elseif ($shouldStop) {
        "- **STOP**: This blocker is fail-closed. Do not proceed without fixing the underlying gap."
    } else {
        "- **CONTINUE**: This blocker has a defined repair path. Fix and retry."
    }
)

## Concrete Steps

$($concreteAction | ForEach-Object { "- $_" })

## Next Steps

- Review `$recoveryPath` for machine-readable recovery action.
- If `should_retry` is true, the runner may automatically retry after a delay.
- If `should_stop` is true, manual intervention or evolution is required before continuing.
- For forced family `$ForcedFamily`, ensure the next slice addresses the concrete steps above.

---
Generated at: $($recovery.generated_at)
"@

Set-Content -LiteralPath $recoveryMdPath -Value $mdContent -Encoding UTF8

# Output the recovery object
$recovery | ConvertTo-Json -Depth 8
