# Test Charter Guidance

## Document Format Requirement (v426)

**CRITICAL**: TEST_CHARTER.md must include explicit `## RED Phase` and `## GREEN Phase` section headings.

The plan contract verifier (Verify-PlanContract.ps1) searches for "RED" and "GREEN" tokens in TEST_CHARTER.md. If these tokens are missing, it triggers:
- `test_charter_missing:RED` 
- `test_charter_missing:GREEN`

This causes plan verification to FAIL even if the test content is otherwise valid.

**Required Format**:
```markdown
# Test Charter

## RED Phase
[RED test scenarios here]

## GREEN Phase
[GREEN implementation scenarios here]
```

## Behavioral Test Charter (v358)

RED tests must verify **business behavior**, not structural properties.

**EXPERIMENT 2 ENFORCEMENT (v358)**: 验证器现在自动检查测试是否包含业务断言。如果没有，slice 将被拒绝。

### Required Pattern

RED test MUST fail with **business assertion**:
- A specific domain value assertion (e.g., field is null, validation fails)
- A side effect verification (e.g., DB insert called, status updated)
- A contract boundary check (e.g., DTO field matches expected)

### GOOD Examples

✅ **Field missing assertion** (domain value):
```java
@Test
public void testFreeReviewAmountFieldMissing() {
    // Given: config without freeReviewAmount field
    TAiClaimModuleConfig config = new TAiClaimModuleConfig();
    config.setModuleName("test");

    // When: reading config
    AiClaimModuleConfigDto dto = service.getConfig("test");

    // Then: field should be null (RED fails before implementation)
    assertThat(dto.getFreeReviewAmount()).isNull();
}
```

✅ **Validation failure assertion** (business logic):
```java
@Test
public void testValidateFreeReviewAmount_WhenNegative_ShouldFail() {
    // Given: negative amount
    BigDecimal negativeAmount = new BigDecimal("-100");

    // When: validating
    ValidationResult result = service.validateFreeReviewAmount(negativeAmount);

    // Then: validation should fail
    assertThat(result.isValid()).isFalse();
    assertThat(result.getError()).contains("Amount must be non-negative");
}
```

✅ **Side effect verification** (DB interaction):
```java
@Test
public void testSaveConfig_WhenValid_ShouldWriteToDatabase() {
    // Given: valid config
    AiClaimModuleConfigDto config = new AiClaimModuleConfigDto();
    config.setFreeReviewAmount(new BigDecimal("1000"));

    // When: saving
    service.saveConfig(config);

    // Then: should write to database
    verify(mapper).insert(argThat(entity ->
        entity.getFreeReviewAmount().compareTo(new BigDecimal("1000")) == 0
    ));
}
```

### BAD Examples

❌ **fail() placeholder** (no business assertion):
```java
@Test
public void testConfig() {
    // WRONG: No business assertion
    fail("not implemented");
}
```

❌ **assertTrue(true)** (tautology):
```java
@Test
public void testConfig() {
    // WRONG: Tautology, always passes
    AiClaimModuleConfigDto dto = service.getConfig("test");
    assertTrue(true);
}
```

❌ **TODO comment** (no implementation):
```java
@Test
public void testConfig() {
    // WRONG: TODO is not a test
    // TODO: implement validation test
}
```

### For Side Effects

✅ **GOOD**: Verify DB operations
```java
verify(mapper).insertList(argThat(details -> details.size() > 0));
verify(statusService).updateFlowStatus(eq(caseId), any());
```

❌ **BAD**: No verification of DB operations
```java
service.saveConfig(config);
// Missing: verify(mapper).insert(...)
```

### For Contract Boundaries

✅ **GOOD**: Verify DTO field values
```java
assertThat(dto.getFreeReviewAmount()).isEqualTo(expected);
assertThat(result.getFreeReviewAmount()).isGreaterThan(BigDecimal.ZERO);
```

❌ **BAD**: Class existence check only
```java
assertThat(dto).isNotNull();
assertThat(config.getClass().getSimpleName()).isEqualTo("TAiClaimModuleConfig");
```

## Verification

Before GREEN phase (v357 automated enforcement):

1. **Automated**: The `validate_red_phase.py validate-charter` script runs automatically:
   ```bash
   python scripts/validate_red_phase.py validate-charter <test_file>
   ```

2. **Manual**: You can also verify manually:
   ```powershell
   verify-test-charter.ps1 -TestFile <path-to-test-file>
   ```

2. The script checks for:
   - ❌ Blocked patterns: `fail()`, `assertTrue(true)`, TODO comments
   - ✅ Required patterns: `assertThat()`, `assertEquals()`, `verify()`

3. Output:
   ```json
   {
     "verification_status": "PASS|FAIL",
     "blocked_patterns_found": ["fail() with no message"],
     "behavioral_patterns_found": ["AssertJ assertThat"],
     "behavioral_assertion_count": 3
   }
   ```

## Test Quality Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| Business assertions per test | >= 3 | Non-tautological assertions |
| Side effect verification | >= 1 | DB/status/external call verification |
| Blocked patterns | 0 | No fail()/TODO/assertTrue(true) |
| Behavioral assertion ratio | >= 80% | Behavioral vs structural assertions |

## Block Conditions

If `verify-test-charter.ps1` returns FAIL:
1. Test contains non-behavioral assertion (`fail()`, `assertTrue(true)`, TODO)
2. Test lacks behavioral assertion (no `assertThat()`, `verify()`, etc.)
3. Cannot proceed to GREEN phase until RED test has business assertion

## Common Patterns by Family

| Family | RED Test Pattern | Assertion Example |
|--------|-----------------|-------------------|
| core_entry | Service method fails | assertThat(result).isNull() |
| stateful_side_effect | DB write not called | verify(mapper).insert(...).times(0) |
| wire_payload_api_contract | DTO field missing | assertThat(dto.getField()).isNull() |
| config_policy_threshold | Validation fails | assertThat(result.isValid()).isFalse() |

## Integration with TDD Cycle

```
1. Write RED test with business assertion (FAIL)
   - verify-test-charter.ps1: PASS (has behavioral assertion)
   - Test fails: assertion error

2. Write minimum GREEN implementation
   - Test passes: business assertion satisfied

3. Verify side effects
   - Add verify(mapper) calls for DB operations
   - Test passes: side effects verified
```

See `tdd-cycle.md` for full TDD workflow.
