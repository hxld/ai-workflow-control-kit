# Side Effect Ledger Requirements (v355 Evolution)

## RULE

All expected side effects MUST be verified in tests BEFORE slice completion.

## Verification Pattern

For each DB operation in `stateful_side_effect` family:

```java
// 1. Setup capture
AtomicReference<CompensateDetail> capturedDetail = new AtomicReference<>();
doAnswer(invocation -> {
    capturedDetail.set(invocation.getArgument(0));
    return 1;
}).when(compensateDetailMapper).insertList(any());

// 2. Execute
aiAutoClaimFlowService.handle(caseId, task);

// 3. Verify
assertThat(capturedDetail.get()).isNotNull();
assertThat(capturedDetail.get().getCaseId()).isEqualTo(caseId);
assertThat(capturedDetail.get()).hasSize(1);
```

## Forbidden Patterns

- ❌ TODO comments as implementation
- ❌ Comments claiming "should insert" without verification
- ❌ Test passes without DB state assertions
- ❌ Mock-only tests that don't verify actual DB operations

## Required Effects for aiClaimV2

From `REQUIREMENT_FAMILY_LEDGER.json`, the following side effects MUST be verified:

1. `t_compensate_detail` insert
2. `t_compensate_info` insert (or update)
3. `t_case_progress` insert with `flow=3`
4. `task` insert with `taskType=案件跟进`
5. `t_examine_log` insert with `logType=AI处理日志`

**Each must have corresponding verification in test code.**

## Pre-Completion Validation

Before a slice can be marked complete, the `validate_side_effects.py` script verifies:

```bash
python scripts/validate_side_effects.py \
    <ledger_path> \
    <test_evidence_path> \
    <worktree_path>
```

The validator checks:
1. All expected side effects are present in test
2. Each side effect has proper verification pattern
3. Verification uses AtomicReference, DB query, or mapper verification
4. No TODO placeholders accepted as "verification"

## Closure Criteria

A slice with side effects is COMPLETE only when:

- [ ] All expected DB operations are verified in test
- [ ] Test uses `AtomicReference` to capture arguments
- [ ] Test asserts on captured values (caseId, amount, status)
- [ ] No TODO comments in side effect implementation
- [ ] `@Transactional` annotation for rollback tests
- [ ] Verification rate ≥ 80%

## Example: Proper Side Effect Verification

```java
@Test
@Transactional
public void testHandle_Success_AllSideEffectsVerified() {
    // GIVEN
    Long caseId = 12345L;
    AiApplyClaimApiTask task = setupFlashCase();

    // Capture CompensateInfo
    AtomicReference<CompensateInfo> capturedInfo = new AtomicReference<>();
    doAnswer(invocation -> {
        capturedInfo.set(invocation.getArgument(0));
        return 1;
    }).when(compensateInfoMapper).insert(any());

    // Capture CompensateDetail
    AtomicReference<List<CompensateDetail>> capturedDetails = new AtomicReference<>();
    doAnswer(invocation -> {
        capturedDetails.set(invocation.getArgument(0));
        return 1;
    }).when(compensateDetailMapper).insertList(any());

    // WHEN
    boolean result = aiAutoClaimFlowService.handle(caseId, task);

    // THEN: All side effects verified
    assertThat(result).isTrue();

    // Verify CompensateInfo
    assertThat(capturedInfo.get()).isNotNull();
    assertThat(capturedInfo.get().getCaseId()).isEqualTo(caseId);
    assertThat(capturedInfo.get().getCompensateAmount()).isGreaterThan(0);

    // Verify CompensateDetail
    assertThat(capturedDetails.get()).isNotNull();
    assertThat(capturedDetails.get()).hasSize(1);
    assertThat(capturedDetails.get().get(0).getCaseId()).isEqualTo(caseId);

    // Verify status update
    verify(caseFlowStatusService).updateFlowStatusForCompensate(caseId);
}
```

## Example: WRONG - TODO as Implementation

```java
// WRONG - TODO comments are NOT verification
@Test
public void testHandle_Success() {
    // TODO: Verify compensate info inserted
    // TODO: Verify compensate detail inserted
    assertThat(aiAutoClaimFlowService.handle(caseId, task)).isTrue();
}
```

```java
// WRONG - No actual verification
@Service
public class AiAutoClaimFlowService {
    public boolean handle(Long caseId, AiApplyClaimApiTask task) {
        // TODO: Insert compensate info
        // TODO: Insert compensate details
        // TODO: Update case status
        return false;
    }
}
```

## Integration with Other Gates

The side effect ledger works with:
- **Core-First Completion Gate**: Side effects must be verified before core_entry can be CLOSED
- **Executable Evidence Gate**: Side effect verification IS the executable evidence
- **RED/GREEN Phase**: GREEN phase requires side effect verification

## Gap Classification

If side effects are missing or not verified:
- Gap: `side_effect_ledger_gap`
- Count: Number of missing verifications
- Impact: Slice cannot complete, next slice blocked

## Expected Metric Delta (v355-r03)

| Metric | Current | Target |
|--------|---------|--------|
| side_effect_ledger_gap | 60 | <10 |
| side_effect_evidence_missing | 60 | <10 |
| verified_db_operations | 0 | >4 |
