# V465 Pre-Execution Constraint Gate (Experiment 1)

## PRE_EXECUTION_CONSTRAINT_GATE

Before Phase1 executor starts, ALL constraints must pass:

### Constraint 1: Carrier Exists in Baseline

- **Check**: The selected carrier MUST exist in baseline code (verified by ripgrep exit code 0)
- **Evidence**: `PRE_EXECUTION_CONSTRAINT_CHECK.json` shows `carrier_exists_in_baseline = PASS`
- **Failure**: If carrier not found, do NOT proceed to RED phase

### Constraint 2: Carrier in Valid Layer

- **Check**: Selected carrier MUST be in valid architectural layer
- **Valid Layers for core_entry**: Facade, Controller
- **Valid Layers for stateful_side_effect**: Service, Facade
- **Valid Layers for deploy_export_page**: Controller, Service
- **Evidence**: `PRE_EXECUTION_CONSTRAINT_CHECK.json` shows `carrier_in_valid_layer = PASS`
- **Failure**: If layer validation fails, reject carrier and select alternative

### Constraint 3: Plan Schema Complete

- **Check**: Plan MUST have complete schema with all required fields
- **Required Fields**:
  - `target_carrier_file_path`: Exact file path from ripgrep output
  - `target_carrier_line_number`: Exact line number from ripgrep output
  - `expected_test_class`: Full test class name (e.g., MyServiceTest)
  - `expected_test_method`: Full test method name (e.g., testMyBehavior_success)
  - `side_effects`: Array of side effect descriptions (min 1 item)
- **Forbidden Values**: TBD, NEW, unknown, UNKNOWN, empty string
- **Evidence**: `PRE_EXECUTION_CONSTRAINT_CHECK.json` shows `plan_schema_complete = PASS`
- **Failure**: If any field missing or contains placeholder, do NOT proceed

### Constraint 4: Test Charter Valid

- **Check**: TEST_CHARTER.md MUST exist and contain test surface specification
- **Required Content**: test_surface, entry_point, or test_method
- **Evidence**: `PRE_EXECUTION_CONSTRAINT_CHECK.json` shows `test_charter_valid = PASS`
- **Failure**: If TEST_CHARTER.md missing or invalid, complete before RED phase

## Enforcement

**DO NOT** proceed to RED phase if any constraint fails.

If `PRE_EXECUTION_CONSTRAINT_CHECK.json` status is `FAIL`:
- Read the failure reason from `checks` array
- Repair the issue
- Re-run constraint check
- Only proceed when status is `PASS`

## Validation Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <REPLAY_AUTOPILOT_ROOT>\scripts\Invoke-PreExecutionConstraintCheck.ps1 -ReplayRoot REPLAY_ROOT -Worktree WORKTREE -PlanResultPath PLAN_RESULT.json
```

## Expected Exit Codes

- `0`: All constraints passed, proceed to Phase1
- `1`: One or more constraints failed, do not proceed

## Rollback Condition

If after 3 rounds, AUTHORIZED slice count = 0:
1. Remove Invoke-PreExecutionConstraintCheck.ps1
2. Revert Start-ReplayRound.ps1 to original
3. The hypothesis is falsified

## Expected Impact

| Metric | Before v465 | After v465 | Delta |
|--------|-------------|-------------|-------|
| Rounds with AUTHORIZED slice status | 0 | >=1 | +1 |
| Phase1 executor attempts (invalid) | 11 | 0 | -11 |
| Pre-implementation blocking rate | 100% | 20% | -80% |
