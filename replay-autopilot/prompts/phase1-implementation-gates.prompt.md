# Phase 1 Implementation Gates

These prompt additions enforce the mandatory workflow gates defined in NEXT_EXPERIMENT_PLAN.md

## Pre-Implementation Contract Verification Gate

**BEFORE writing any test or implementation code, you MUST verify exact service method signatures.**

For each service method you plan to reference:
1. Read the actual service file using the Read tool with full path
2. Verify the method exists with exact signature
3. Note the exact parameter types and return type

### Example wrong pattern (DO NOT DO THIS):
```java
// You assume this exists
compensateService.batchInsertCompensateDetail(list);
```

### Example correct pattern:
```java
// Step 1: Read claim-core/.../CompensateService.java
// Step 2: Find: public void rewriteCompensateData(Long caseId, List<DetailBundle> bundles)
// Step 3: Use verified signature
compensateService.rewriteCompensateData(caseId, bundles);
```

### Rule:
If you cannot find the exact method signature, **declare BLOCKED** and do not proceed with assumption.

---

## TODO Placeholder Ban (CRITICAL)

**TODO placeholders are FORBIDDEN in implementation code.**

### If you don't know how to implement a feature:

1. Declare the slice **BLOCKED**
2. Explain EXACTLY what information you need
3. **Do NOT write TODO comments**

### Examples of FORBIDDEN patterns:
```java
// ❌ FORBIDDEN
// TODO: 实现完整的自动流程逻辑

// ❌ FORBIDDEN
// TODO: 验证受益人数据

// ❌ FORBIDDEN
// TODO: 写入理算明细

// ❌ FORBIDDEN
public void process() {
    // TODO: implement this
}
```

### Correct pattern when implementation unknown:
```
BLOCKED: Cannot implement compensate write without verifying CompensateService.rewriteCompensateData() method signature.
Required: Read CompensateService.java to confirm signature.
```

### Verification:
The `todo_detector.py` script will automatically reject any code containing TODO placeholders.

---

## Carrier Search Requirement

**Before creating new service classes:**

1. Search for existing carriers with: `rg "class.*{Feature}Service"`
2. Read the found file to verify it cannot serve the use case
3. Only create new carrier if existing carriers are genuinely insufficient

### Rule:
- First preference: Use existing service
- Second preference: Extend existing service
- Last resort: Create new service (with justification)

### Penalty:
-50% coverage for unverified new carriers (no carrier search performed)

---

## Test Surface Verification

**When writing RED phase tests:**

1. Test methods must match the planned entry from TEST_CHARTER.md
2. Use descriptive test method names (min 8 characters, excluding "test" prefix)
3. Generic names like `test()`, `testMethod()` are **FORBIDDEN**

### Example:
```
# If planned entry is "rewriteCompensateData"
✅ GOOD: testRewriteCompensateData_success()
✅ GOOD: testRewriteCompensateData_withEmptyList()
❌ BAD: test()
❌ BAD: testMethod()
```

---

## Side Effect Verification

**Before completing GREEN phase:**

Ensure all side effects have executable proof:

1. **Database operations** (insert/update/delete) → Test verifies row count/field values
2. **External service calls** → Test uses mock and verifies call parameters
3. **State changes** → Test asserts before/after state
4. **Exception handling** → Test covers exception branch

### Rule:
If a side effect cannot be verified with executable test, mark slice as BLOCKED.

---

## Summary Checklist

Before completing any slice:

- [ ] All service method signatures verified by reading actual files
- [ ] No TODO placeholders in implementation
- [ ] Existing carriers searched before creating new service
- [ ] Test methods have descriptive names matching planned entry
- [ ] All side effects have executable test assertions
- [ ] Implementation is complete (no placeholder methods)

**Violations will result in automatic rejection by verification scripts.**
