# Executable Contract Template

## 1. Exact Field Contract

For each field in the requirement, specify:
- **Wire field**: JSON payload field name and type
- **DB field**: Table.column name and type
- **Display field**: UI display label and format
- **Enum mapping**: If enum, list all values

Example:
```json
{
  "免复核金额": {
    "wire": "freeReviewAmount",
    "wire_type": "BigDecimal",
    "db": "t_ai_claim_config.free_review_amount",
    "db_type": "DECIMAL(18,2)",
    "display": "免复核金额",
    "display_format": "0.00"
  }
}
```

## 2. State Transition Ledger

For each state change, specify:
- **Entity**: Case, Task, Progress, etc.
- **Before state**: Current state value
- **After state**: New state value
- **Trigger condition**: When this transition occurs
- **Side effects**: What else happens during this transition

Example:
```json
{
  "case_status_transition": {
    "entity": "Case",
    "field": "caseStatus",
    "before": "审核",
    "after": "保险公司待理算",
    "trigger": "AI核赔结果满足免复核条件且理算数据完整",
    "side_effects": [
      "Create task in t_task_follow",
      "Insert progress in t_case_progress",
      "Insert AI handling log in t_case_handle_log"
    ]
  }
}
```

## 3. Side Effect Ledger

For each side effect, specify:
- **Table**: Target table name
- **Operation**: INSERT/UPDATE/DELETE
- **Fields**: Which columns are affected
- **Conditions**: When this operation occurs

Example:
```json
{
  "compensate_insert": {
    "table": "t_compensate_info",
    "operation": "INSERT",
    "trigger": "Auto-flow passes all validations",
    "fields": ["case_id", "amount", "status", "create_time"],
    "required": true
  }
}
```

## 4. Test Assertion Template

For each test scenario, specify:
- **Given**: Initial state setup
- **When**: Action taken
- **Then**: Expected outcome

Example:
```gherkin
Scenario: AI auto-flow with free review amount
  Given case status is '审核'
  And AI claim result has amount below free review threshold
  When auto-flow executes
  Then case status becomes '保险公司待理算'
  And task is created in t_task_follow
  And progress is logged in t_case_progress
```
