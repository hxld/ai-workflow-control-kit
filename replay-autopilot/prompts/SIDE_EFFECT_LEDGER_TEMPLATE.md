# Side Effect Ledger Template

**Feature**: {{FEATURE_NAME}}
**Slice**: {{SLICE_ID}}
**Family**: {{FAMILY_ID}}

---

## Purpose

This ledger documents ALL expected side effects for stateful operations. Each side effect MUST have corresponding verification in the test code.

---

## Stateful Families

### Family: `stateful_side_effect`

**Rule**: DB side effects MUST be verified before slice completion. No TODO placeholders accepted.

---

## Expected Side Effects

### Effect 1: {{TABLE_NAME_1}}

**Operation**: {{INSERT/UPDATE/DELETE}}
**Table**: `{{TABLE_NAME_1}}`
**Trigger**: {{WHEN_THIS_HAPPENS}}

**Verification Query**:
```sql
SELECT * FROM {{TABLE_NAME_1}}
WHERE {{KEY_COLUMN}} = ?
  AND {{CONDITION}} = ?
```

**Test Assertion Pattern**:
```java
// Capture the operation
AtomicReference<{{ENTITY_NAME}}> captured{{ENTITY_NAME}} = new AtomicReference<>();
doAnswer(invocation -> {
    Object[] args = invocation.getArguments();
    captured{{ENTITY_NAME}}.set(({{ENTITY_NAME}}) args[0]);
    return 1;
}).when({{MAPPER_NAME}}).{{METHOD_NAME}}(any());

// Execute
facade.{{TEST_METHOD}}({{PARAMETERS}});

// Verify
assertThat(captured{{ENTITY_NAME}}.get()).isNotNull();
assertThat(captured{{ENTITY_NAME}}.get().{{KEY_PROPERTY}}()).isEqualTo({{EXPECTED_VALUE}});
```

---

### Effect 2: {{TABLE_NAME_2}}

**Operation**: {{INSERT/UPDATE/DELETE}}
**Table**: `{{TABLE_NAME_2}}`
**Trigger**: {{WHEN_THIS_HAPPENS}}

**Verification Query**:
```sql
SELECT * FROM {{TABLE_NAME_2}}
WHERE {{KEY_COLUMN}} = ?
ORDER BY {{TIME_COLUMN}} DESC
LIMIT 1
```

**Test Assertion Pattern**:
```java
verify({{MAPPER_NAME}}).{{METHOD_NAME}}(argThat(entity -> {
    return entity.get{{KEY_PROPERTY}}() != null
        && entity.get{{CONDITION_PROPERTY}}() == {{EXPECTED_CONDITION}};
}));
```

---

## DB Connection Note

**Use @Transactional with rollback for test isolation**:

```java
@Test
@Transactional
@Rollback
public void test{{SCENARIO_NAME}}_WithSideEffects() {
    // Test code
    // All DB changes automatically rolled back
}
```

---

## Forbidden Patterns

**DO NOT use these as "verification"**:

- [x] `// TODO: Verify insert happened`
- [x] `// TODO: Check DB state`
- [x] Comments claiming "should write" without actual verification
- [x] `assertTrue(true)` as placeholder

**These patterns cause `side_effect_ledger_gap` flag and slice rejection**.

---

## Closure Criteria

A slice with side effects is COMPLETE only when:

- [ ] All expected DB operations are captured in test
- [ ] Test uses `AtomicReference` or `verify()` for verification
- [ ] Test asserts on captured values (key fields, status, amounts)
- [ ] No TODO comments in side effect code
- [ ] `@Transactional` annotation present for rollback
- [ ] Verification rate = 100% (all effects verified)

---

## Example: Complete Side Effect Verification

```java
@Test
@Transactional
public void testHandleAutoClaim_AllSideEffectsVerified() {
    // GIVEN
    Long fixtureCaseId = Long.valueOf(Math.abs("CarrierUnderTest".hashCode()));
    AiApplyClaimApiTask task = setupFlashCase();

    // Capture CompensateInfo
    AtomicReference<CompensateInfo> capturedInfo = new AtomicReference<>();
    doAnswer(invocation -> {
        Object[] args = invocation.getArguments();
        capturedInfo.set((CompensateInfo) args[0]);
        return 1;
    }).when(compensateInfoMapper).insert(any());

    // Capture CompensateDetail list
    AtomicReference<List<CompensateDetail>> capturedDetails = new AtomicReference<>();
    doAnswer(invocation -> {
        Object[] args = invocation.getArguments();
        @SuppressWarnings("unchecked")
        List<CompensateDetail> details = (List<CompensateDetail>) args[0];
        capturedDetails.set(details);
        return 1;
    }).when(compensateDetailMapper).insertList(any());

    // WHEN
    boolean result = aiClaimFacade.handleAutoClaim(caseId, task);

    // THEN: Side effects verified
    assertThat(result).isTrue();

    // Verify CompensateInfo
    assertThat(capturedInfo.get()).isNotNull();
    assertThat(capturedInfo.get().getCaseId()).isEqualTo(caseId);
    assertThat(capturedInfo.get().getCompensateAmount()).isGreaterThan(BigDecimal.ZERO);

    // Verify CompensateDetail list
    assertThat(capturedDetails.get()).isNotNull();
    assertThat(capturedDetails.get()).hasSizeGreaterThanOrEqualTo(1);
    assertThat(capturedDetails.get().get(0).getCaseId()).isEqualTo(caseId);

    // Verify status update
    verify(caseFlowStatusService).updateFlowStatus(eq(caseId), eq(3));
}
```

---

## Gap Prevention

This template prevents:
- **side_effect_ledger_gap**: All effects must be documented
- **missing_side_effect_verification**: Verification pattern required
- **stub_implementation**: TODO placeholders explicitly rejected

---

*Generated from SIDE_EFFECT_LEDGER_TEMPLATE.md (v431)*
