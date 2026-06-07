# Experiment E2: Implementation Density Requirement

## Overview

TODO placeholders, stub implementations, and fake methods are NOT valid implementation.
The V348 quality gate will FAIL your slice if TODO/placeholder ratio > 0%.

## What Counts as Executable Code

**YES** (executable):
- Real business logic (condition checks, DB operations, service calls)
- Actual field mappings and data transformations
- Transaction boundaries with real rollback handling
- Exception handling with business-meaningful error messages
- State changes (INSERT, UPDATE, DELETE)
- Real assertions with SELECT queries

**NO** (non-executable):
- TODO comments (even with detailed plans)
- Stub methods that return null or fake values
- Placeholder classes without real behavior
- Comments describing what "should" be implemented
- Methods that only log without doing anything

## Quality Gate Thresholds

- **TODO ratio**: MUST be 0%
- **Implementation density**: MUST be >= 70%
- **Code lines**: Total non-empty, non-comment lines
- **Executable lines**: Lines with actual logic/operations

## Density Calculation

```
density = executable_lines / code_lines
todo_ratio = todo_lines / code_lines
```

Where:
- `code_lines = total_lines - empty_lines - comment_lines`
- `executable_lines` = lines with if/for/while/return/DB operations/method calls
- `todo_lines` = lines containing TODO/FIXME/XXX/NotImplementedError

## INVALID Example

```java
// TODO: Implement auto-flow logic
public void executeAutoFlow(Long caseId) {
    // Placeholder - will implement later
    log.info("Auto flow not yet implemented");
}
```

**Why invalid**:
- 2 TODO lines
- 0 executable lines (log only)
- density = 0%, todo_ratio = 100%
**Result**: BLOCKED

## VALID Example

```java
public void executeAutoFlow(Long caseId) {
    // Real condition check
    if (!shanpeiService.isShanpei(caseId)) {
        throw new BusinessException("不符合闪赔条件");
    }
    // Real DB operation
    compensateService.insertDetail(caseId, ...);
}
```

**Why valid**:
- 0 TODO lines
- 4 executable lines (if check, throw, insert)
- density = 100%, todo_ratio = 0%
**Result**: PASS

## If You Cannot Implement Full Behavior

1. Implement the smallest executable subset possible
2. Do NOT add TODO placeholders for "rest of feature"
3. Document what's DEFERRED to next slice in TEST_CHARTER.md
4. Example: "Deferred: retry logic, error handling, edge cases"

## Gate Enforcement

The `verify_implementation_density.py` script runs during slice verification and will BLOCK if:
- TODO ratio > 0%
- Implementation density < 70%

## Common Anti-Patterns

1. **"I'll add the real code in the next slice"** → NO. Add executable code now or defer the slice.
2. **"This TODO is just a reminder"** → NO. Use your plan document, not code comments.
3. **"I need to stub this to make it compile"** → NO. Redesign to avoid the dependency or implement minimal working version.
