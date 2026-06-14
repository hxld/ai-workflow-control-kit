# TDD RED-GREEN-REFACTOR Cycle (MANDATORY)

## ⚠️ CRITICAL: RED Phase Must Succeed Before ANY Implementation

You are FORBIDDEN from writing ANY implementation code until ALL of these conditions are met:

### Pre-Flight Check (Before RED)

1. Ensure all dependency modules compile:
   - example-domain must compile
   - example-api must compile
   - example-common must compile

2. If compilation fails:
   - STOP IMMEDIATELY
   - Fix compilation errors first
   - DO NOT proceed to RED test until dependencies compile

### RED Phase (Before Implementation - MANDATORY)

1. Write your test FIRST
2. Run the test and verify it FAILS with meaningful business assertion
3. If RED is BLOCKED by compilation:
   - **STOP IMMEDIATELY**
   - **DO NOT write implementation**
   - Fix compilation and re-run RED
4. Only proceed to GREEN after RED gate passes

### What Makes a Good RED Test?

A RED test MUST:
1. ✅ Verify BUSINESS BEHAVIOR (what the system DOES)
2. ✅ FAIL when run without implementation
3. ✅ Have a MEANINGFUL failure message
4. ✅ Call the production method and assert on business result

A RED test MUST NOT:
1. ❌ Verify STRUCTURE (what the system HAS)
2. ❌ Pass without implementation
3. ❌ Only check method existence
4. ❌ Fail with compilation error (ClassNotFoundException, NoSuchMethodException)

### Executable Test Surface Requirements (v355 Evolution)

#### RED Phase Requirements

**WRONG** (compilation test):
```java
@Test
public void testHandle_ShouldFail() {
    // This will fail because method doesn't exist yet - WRONG!
    aiAutoClaimFlowService.handle(caseId, task);
}
```

**WRONG** (structural test):
```java
@Test
public void testHandle_ServiceExists() {
    // This test PASSES without implementation - WRONG!
    assertThat(aiAutoClaimFlowService).isNotNull();
}
```

**CORRECT** (business assertion):
```java
@Test
public void testHandle_ShouldWriteCompensateDataWhenConditionsMet() {
    // GIVEN: Flash case with beneficiary data
    Long caseId = 123L;
    ExampleApplyApiTask task = setupFlashCaseWithBeneficiary();

    // WHEN: Handle is called
    boolean result = aiAutoClaimFlowService.handle(caseId, task);

    // THEN: Should fail because we haven't implemented yet - CORRECT!
    assertThat(result).isTrue(); // This will fail because method returns false
    // OR
    assertThat(compensateInfoMapper.getByCaseId(caseId)).isNotNull(); // Will fail because no DB write
}
```

**Requirements**:
1. Test must call the production method
2. Test must assert on BUSINESS RESULT (return value, DB state, output object)
3. Failure must be due to missing business logic, not missing method/compilation

#### GREEN Phase Requirements

**Requirements**:
1. Test must pass after implementation
2. Side effects must be VERIFIED:
   - DB operations: Use `AtomicReference` to capture mapper arguments
   - Output: Verify generated files, API calls, status updates
   - Transaction: Use `@Transactional` with rollback for isolation

**Example GREEN verification**:
```java
@Test
@Transactional
public void testHandle_Success_CompensateDetailInserted() {
    // Setup capture
    AtomicReference<CompensateDetail> capturedDetail = new AtomicReference<>();
    when(compensateDetailMapper.insertList(any())).thenAnswer(invocation -> {
        capturedDetail.set(invocation.getArgument(0));
        return 1;
    });

    // Execute
    boolean result = aiAutoClaimFlowService.handle(caseId, task);

    // Verify
    assertThat(result).isTrue();
    assertThat(capturedDetail.get()).isNotNull();
    assertThat(capturedDetail.get().getCaseId()).isEqualTo(caseId);
    assertThat(capturedDetail.get()).hasSize(1);
}
```

### Examples

**GOOD RED Test (Business Behavior):**
```java
@Test
public void testAutoFlow_Success_CompensateDetailInserted() {
    // Arrange
    Long caseId = 12345L;

    // Act
    aiAutoClaimFlowService.handle(caseId, task);

    // Assert: Business Behavior
    CompensateDetail detail = compensateDetailMapper.selectByCaseId(caseId);
    assertThat(detail).isNotNull();  // FAILS without implementation
    assertThat(detail.getCaseId()).isEqualTo(caseId);  // FAILS without implementation
}
```

**BAD RED Test (Structure Only - WRONG):**
```java
@Test
public void testAutoFlow_ServiceExists() {
    // This test PASSES without implementation!
    assertThat(aiAutoClaimFlowService).isNotNull();
}
```

### RED Phase Gate

Before you write ANY implementation:
1. Write your test
2. Run `mvn test -Dtest=YourTest`
3. Verify it FAILS with a meaningful error
4. If it PASSES, rewrite as behavioral test

## GREEN Phase (After RED Confirmed)

1. Implement ONLY what the failing test requires
2. Run `mvn test -Dtest=YourTest`
3. Verify it PASSES
4. NO TODO comments allowed

## REFACTOR Phase (After GREEN)

1. Clean up code (remove duplication, improve names)
2. Verify tests still PASS
3. No behavior changes

## Forbidden Anti-Patterns

❌ **GREEN before RED**: Implementing then writing tests
❌ **Structural RED**: Testing method existence instead of behavior
❌ **Fake GREEN**: TODO comments that make tests pass
❌ **Skip RED**: Writing implementation without failing test first

---

## ⚠️ FATAL Workflow Violations

The following are FATAL violations that INVALIDATE the entire slice:

### 1. Implementation After Blocked RED (CRITICAL)

**What it is**: Writing implementation code while RED test is blocked by compilation errors.

**Why it's FATAL**:
- Violates fundamental TDD discipline
- Produces invalid code that can't be verified
- Indicates workflow enforcement failure

**Evidence from v323**: 33 occurrences detected - NEW and CRITICAL regression

**Penalty**: Entire slice is INVALID, must reset and restart

**What to do instead**:
1. Fix compilation errors first
2. Ensure dependencies compile (example-domain, example-api, example-common)
3. Re-run RED test to confirm meaningful failure
4. Only then proceed to implementation

### 2. GREEN Before RED

**What it is**: Implementing code then writing tests

**Why it's FATAL**:
- Defeats the purpose of TDD
- Tests become verification, not specification
- Often produces structural tests instead of behavioral

**Penalty**: Entire slice is INVALID, must reset and restart

### 3. Structural RED

**What it is**: Tests that verify structure (existence, not-null) instead of behavior

**Why it's FATAL**:
- Tests pass without implementation
- Don't drive business behavior
- False sense of completion

**Penalty**: Rewrite test before proceeding

**Examples**:

WRONG (Structural):
```java
@Test
public void testAutoFlow_ServiceExists() {
    assertThat(aiAutoClaimFlowService).isNotNull();  // PASSES without implementation!
}
```

CORRECT (Behavioral):
```java
@Test
public void testAutoFlow_Success_CompensateDetailInserted() {
    Long caseId = 12345L;
    aiAutoClaimFlowService.handle(caseId, task);

    CompensateDetail detail = compensateDetailMapper.selectByCaseId(caseId);
    assertThat(detail).isNotNull();  // FAILS without implementation
    assertThat(detail.getCaseId()).isEqualTo(caseId);  // FAILS without implementation
}
```

---

## Enforcement Verification

After each slice execution, the verifier checks for:
1. `implementation_after_blocked_red` violations - MUST be 0
2. `compilation_blocker_rate` - MUST be 0%
3. `RED_phase_compliance` - MUST be 100%

If any violation is detected, the slice is marked INVALID.

## RED Phase Validator Integration (v355)

The `validate_red_phase.py` script enforces RED phase requirements:

```bash
python scripts/validate_red_phase.py validate-red <test_file> <test_output_file>
```

Checks:
- RED test must NOT fail with compilation error
- RED test must have business assertions (assertThat, assertEquals, verify)
- Assertions must validate behavior, not structure

## GREEN Phase Validator Integration (v355)

The `validate_red_phase.py` script also validates GREEN phase:

```bash
python scripts/validate_red_phase.py validate-green <test_file> <expected_side_effects_json>
```

Checks:
- GREEN test must verify side effects (DB capture, output verification)
- Must use AtomicReference, mapper verification, or output assertions
- No TODO placeholders allowed in GREEN phase

## Test Charter Validation Integration (v357)

The `validate_red_phase.py validate-charter` script enforces test charter requirements:

```bash
python scripts/validate_red_phase.py validate-charter <test_file>
```

Checks:
- Test must have behavioral assertions (NOT fail() placeholders)
- Test must NOT use forbidden patterns: `fail("due to not implemented")`, `fail("TODO")`, `fail("占位")`
- Test must have @Test methods
- Assertions must validate business behavior, not structure

This validation runs BEFORE RED phase to ensure tests have proper business assertions.
