# V457 Plan Contract Hard Requirements (Experiment 3)

## PLAN_HARD_REQUIREMENTS

For the **HIGHEST-WEIGHT open family**, you MUST provide `first_slice_proof` with ALL fields:

### Required first_slice_proof Fields

1. **target_carrier_file_path**: Exact file path
   - Example: `"<production-module>/src/main/java/com/example/project/core/task/ExampleTaskProcessor.java"`

2. **target_carrier_line_number**: Exact line number where method is defined
   - Example: `42`

3. **expected_test_class**: Full test class name
   - Example: `"ExampleApplyTaskProcessorTest"`

4. **expected_test_method**: Test method name
   - Example: `"testExecuteTask_AutoFlowTriggered"`

5. **expected_assertions**: Array of at least 3 test assertions
   - Example:
     ```json
     [
       "assertEquals(35, caseStatus)",
       "verify(compensateDetailMapper).insert()",
       "assertNotNull(result)"
     ]
     ```

6. **expected_side_effects**: Array of side effects with structure
   - Example:
     ```json
     [
       {"table": "t_compensate_detail", "operation": "insert"},
       {"table": "t_case_route", "operation": "update", "field": "status", "value": "35"}
     ]
     ```

### Validation Rules

- **IF** any field is MISSING or `"unknown"` → **PLAN IS INVALID**
- **IF** expected_assertions < 3 items → **PLAN IS INVALID**
- **IF** expected_side_effects = 0 items → **PLAN IS INVALID**
- **IF** target_carrier_file_path not in BASELINE_CARRIER_INDEX → **PLAN IS INVALID**

**DO NOT** proceed to implementation until first_slice_proof is COMPLETE.

---

## first_slice_proof Schema

```json
{
  "highest_weight_family": "core_entry",
  "family_weight": 100,
  "first_slice_proof": {
    "target_carrier_file_path": "<production-module>/src/main/java/com/example/project/core/task/ExampleTaskProcessor.java",
    "target_carrier_line_number": 42,
    "expected_test_class": "ExampleApplyTaskProcessorTest",
    "expected_test_method": "testExecuteTask_AutoFlowTriggered",
    "expected_assertions": [
      "assertEquals(35, caseStatus)",
      "verify(compensateDetailMapper).insert()",
      "assertNotNull(result)"
    ],
    "expected_side_effects": [
      {"table": "t_compensate_detail", "operation": "insert"},
      {"table": "t_case_route", "operation": "update", "field": "status", "value": "35"}
    ]
  }
}
```

---

## Verification Failures

### first_slice_proof_missing

Triggered when:
- Highest-weight open family does not have first_slice_proof field
- first_slice_proof is null or empty

**Gap Flag**: `first_slice_proof_missing:highest_weight_open_gate:{family_id}`

### first_slice_proof_schema_missing

Triggered when:
- Required field is missing from first_slice_proof
- Field value is "unknown" or placeholder

**Gap Flag**: `first_slice_proof_schema_missing:{missing_fields_comma_separated}`

### expected_assertions_insufficient

Triggered when:
- expected_assertions array has fewer than 3 items
- expected_assertions is missing

**Gap Flag**: `expected_assertions_insufficient:{count}/3`

### expected_side_effects_missing

Triggered when:
- expected_side_effects array is empty
- expected_side_effects is missing

**Gap Flag**: `expected_side_effects_missing`

---

## Rollback Condition

If plan-stage block rate > 40% after 3 rounds:
1. Revert to soft plan verification
2. Make first_slice_proof optional (warning, not blocker)
3. Remove PLAN_HARD_REQUIREMENTS from prompt

---

## Expected Impact

| Metric | Current | Target | Delta |
|--------|---------|--------|-------|
| Plan-stage block rate | 60% | 20% | -40% |
| Plans with first_slice_proof | 20% | 90% | +70% |
| Plans with complete assertions | 5% | 80% | +75% |
