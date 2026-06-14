# RED Phase Pre-Flight Checklist

**Slice**: {{SLICE_ID}}
**Test Class**: {{TEST_CLASS_NAME}}

---

## Before Submitting to GREEN Phase

**CRITICAL**: Do NOT write implementation code until RED phase passes ALL checks.

---

## Test Compilation Check

**Step 1**: Verify test compiles without errors

```bash
mvn test-compile -pl <test-module>
```

- [ ] Test compiles successfully
- [ ] No "cannot find symbol" errors
- [ ] No missing import errors
- [ ] All test dependencies resolved

**If BLOCKED**: Fix pom.xml test dependencies, then retry. Do NOT proceed to GREEN.

---

## Test Execution Check

**Step 2**: Verify test runs without runtime exceptions

```bash
mvn test -Dtest={{TEST_CLASS_NAME}}#{{TEST_METHOD}} -Dsurefire.failIfNoSpecifiedTests=false
```

- [ ] Test executes without crashing
- [ ] No NullPointerException
- [ ] No ClassNotFoundException
- [ ] No Spring context loading errors

**If BLOCKED**: Fix runtime setup (mocks, context), then retry. Do NOT proceed to GREEN.

---

## RED Phase Failure Check

**Step 3**: Verify test FAILS with business assertion

**Expected**: Test should fail with assertion error, NOT pass.

- [ ] Test result: **FAILED** (not passed)
- [ ] Failure message shows: `expected: X but was: Y`
- [ ] Failure is from business assertion (assertThat, assertEquals)
- [ ] Failure is NOT from compilation error
- [ ] Failure is NOT from runtime crash

**If test PASSES**: This means either:
1. Code already exists (test is redundant)
2. Assertion is tautology (assertTrue(true))
3. Test doesn't actually check the behavior

**Action**: Rewrite RED test to properly fail before implementation.

---

## Behavioral Assertion Check

**Step 4**: Verify test has business assertions

**Required patterns** (at least 3):
- [ ] `assertThat(actual).isEqualTo(expected)`
- [ ] `assertThat(value).isNotNull()`
- [ ] `verify(service).method(argThat(...))`
- [ ] `assertEquals(expected, actual)`

**Forbidden patterns** (zero tolerance):
- [ ] `fail("not implemented")` → NO
- [ ] `assertTrue(true)` → NO
- [ ] `// TODO: implement test` → NO

**Minimum assertion count**: 3 business assertions per test

---

## Implementation Check

**Step 5**: Verify NO implementation code exists

- [ ] NO production code written yet
- [ ] NO TODO placeholders in production code
- [ ] NO stub implementations returning null/false
- [ ] Only test file exists, production method may not exist yet

**If implementation exists**: Delete it. RED phase must fail WITHOUT the code.

---

## Layer Validation Check

**Step 6**: Verify test targets correct layer

- [ ] Test class is `*FacadeTest` or `*ControllerTest`
- [ ] Test does NOT target Service layer directly
- [ ] Test uses Facade/Controller as entry point

**If targeting Service**: This is `wrong_test_surface` violation. Move test to Facade layer.

---

## Side Effect Declaration Check (if stateful)

**Step 7**: Verify side effects are declared

**If test has side effects** (DB writes, status updates):

- [ ] SIDE_EFFECT_LEDGER.md exists
- [ ] All expected DB changes listed
- [ ] Verification queries documented
- [ ] @Transactional annotation present

**If side effects NOT declared**: Test will be rejected as `side_effect_ledger_gap`.

---

## RED Phase Authorization

**Only proceed to GREEN phase if ALL checks above pass**:

| Check | Status | Notes |
|-------|--------|-------|
| Test compiles | [ ] PASS | |
| Test runs | [ ] PASS | |
| Test fails with assertion | [ ] PASS | |
| Has 3+ business assertions | [ ] PASS | |
| NO implementation code | [ ] PASS | |
| Correct layer (Facade) | [ ] PASS | |
| Side effects declared | [ ] PASS | (if stateful) |

**Authorization**: Only if all PASS checkboxes are checked.

---

## Recovery Actions

### If RED is BLOCKED by compilation error

1. Check test dependencies in `pom.xml`
2. Add missing imports
3. Fix syntax errors
4. Retry from Step 1

### If RED is BLOCKED by runtime error

1. Check test setup (mocks, fixtures)
2. Check Spring context configuration
3. Fix null pointer exceptions
4. Retry from Step 2

### If RED PASSES instead of failing

1. Delete implementation code
2. Make assertion fail (assertNull, assertThat(null))
3. Verify test fails without implementation
4. Retry from Step 3

### If test has NO business assertions

1. Add specific assertions about expected behavior
2. Replace `fail()` with real failing assertion
3. Remove `assertTrue(true)` tautologies
4. Retry from Step 4

### If test targets wrong layer

1. Change test from `*ServiceTest` to `*FacadeTest`
2. Use Facade as entry point
3. Verify test still validates same behavior
4. Retry from Step 6

---

## Gap Prevention

This checklist prevents:
- **implementation_after_blocked_red**: Blocks GREEN if RED fails
- **compilation_error_in_red**: Requires fix before implementation
- **wrong_test_surface**: Validates layer selection
- **side_effect_ledger_gap**: Requires side effect declaration

---

## TDD Discipline

**Remember**: RED phase is about proving the code DOESN'T exist yet.

1. Write test that fails
2. Verify failure is meaningful (business assertion)
3. Only then write implementation
4. Verify test passes after implementation

Skipping RED phase guarantees `implementation_after_blocked_red` violation.

---

*Generated from RED_PHASE_CHECKLIST.md (v431)*
