# V447 Trigger Point Validation

## Overview

This prompt enforces Experiment 1 from NEXT_EXPERIMENT_PLAN.md: Correct Trigger Point Selection.

The core issue: v446 selected `ExampleCalculateTaskProcessor` (Calculate Loss task) when the requirement said "AI处理结果获取成功后" which should map to `ExampleApplyTaskProcessor` (Apply Claim task).

## Trigger Point Mapping

| Requirement Pattern | Expected Processor | Task Type | Description |
|---------------------|-------------------|-----------|-------------|
| AI处理结果获取成功后 | ExampleApplyTaskProcessor | Apply Claim | Comprehensive AI interface that triggers auto-flow AFTER result is saved |
| 处理结果获取成功后 | ExampleApplyTaskProcessor | Apply Claim | Same as above (shorter form) |
| AI处理成功后 | ExampleApplyTaskProcessor | Apply Claim | Same as above (shortest form) |
| 金额计算成功后 | ExampleCalculateTaskProcessor | Calculate Loss | Only calculates amounts, does NOT trigger auto-flow |
| 计算损失成功后 | ExampleCalculateTaskProcessor | Calculate Loss | Same as above (alternative phrasing) |

## Critical Distinction

**ExampleCalculateTaskProcessor** (Calculate Loss task):
- Only calculates loss amounts
- Does NOT trigger auto-flow
- Is NOT the comprehensive AI interface
- Should NOT be selected when requirement says "AI处理结果获取成功后"

**ExampleApplyTaskProcessor** (Apply Claim task):
- Is the comprehensive AI interface
- Triggers auto-flow AFTER result is successfully saved
- Should be selected when requirement says "AI处理结果获取成功后"
- This is where the auto-flow orchestration happens

## Phase 0 Validation Steps

Before finalizing carrier selection in Phase 0:

1. **Extract trigger pattern from requirement**:
   - Search for "XX成功后" patterns in requirement text
   - Identify the specific trigger event

2. **Map to expected processor type**:
   - Use the mapping table above
   - Determine whether this is Apply Claim or Calculate Loss task

3. **Verify selected carrier matches expected processor**:
   - If mismatch, reject current carrier selection
   - Select the correct processor instead

4. **Document the decision**:
   - In EXPLORATION_REPORT.md, under "Selected Real Entry":
     - Include `trigger_point_pattern: <extracted pattern>`
     - Include `expected_processor: <mapped processor>`
     - Include `selection_rationale: <why this processor matches the trigger>`

## Example (Current Wrong Selection)

**Requirement snippet**: "AI处理结果获取成功后，自动流转..."

**Wrong selection** (v446):
- Selected: `ExampleCalculateTaskProcessor.handleTaskResponse()`
- Reason: "Found 'AI' and 'success' in processor name"
- Status: WRONG_TEST_SURFACE

**Correct selection** (v447):
- Pattern found: "AI处理结果获取成功后"
- Expected processor: `ExampleApplyTaskProcessor`
- Selected: `ExampleApplyTaskProcessor.handleTaskResponse()`
- Reason: "Trigger pattern 'AI处理结果获取成功后' maps to Apply Claim task processor"

## Integration with Phase 0 Contract Gate

When executing Phase 0, after selecting a candidate carrier:

1. Run trigger point validation:
   ```bash
   python scripts/trigger_point_validator.py validate <requirement_text> <selected_carrier>
   ```

2. If validation FAILS:
   - Reject the current carrier
   - Search for the correct processor in baseline
   - Re-run carrier selection with the correct processor as primary target

3. If validation PASSES or WARN:
   - Continue with normal Phase 0 flow
   - Document the trigger point validation result

## Expected Impact

This validation should:
- Eliminate `wrong_test_surface` gaps caused by wrong task type selection
- Ensure correct test surface at the actual trigger point
- Enable proper auto-flow testing at the Apply Claim task level
- Improve oracle_adjusted_coverage from 0% to 20-40%

## Falsifiable Metrics

| Metric | Before (v446) | After (v447) | Delta |
|--------|---------------|--------------|-------|
| wrong_test_surface flags | 25 | 0 | -25 |
| core_entry_unclosed flags | 14 | 0 | -14 |
| verification_capped_coverage | 0% | 40-60% | +40-60% |
| oracle_adjusted_coverage | 0% | 20-40% | +20-40% |
