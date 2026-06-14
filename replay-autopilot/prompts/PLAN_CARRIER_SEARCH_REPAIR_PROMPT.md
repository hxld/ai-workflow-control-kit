# Plan Carrier Search Repair Prompt

## Purpose

This prompt enforces **oracle-first carrier search** to prevent synthetic carrier creation (Experiment 1 from NEXT_EXPERIMENT_PLAN.md).

## Oracle Carrier Verification (MANDATORY)

Before finalizing carrier selection:

### Step 1: Load Oracle File List

Read the oracle file list from one of these sources (in priority order):
1. `{{REPLAY_ROOT}}/PHASE2_CONTRACT_VERIFY.json` - Post-hoc oracle analysis
2. `{{REPLAY_ROOT}}/ORACLE_DIFF_ANALYSIS.json` - Oracle diff analysis
3. `{{REPLAY_ROOT}}/ORACLE_CONTRACTS.json` - Extracted oracle contracts

If none exist, skip oracle verification but document `oracle_verification_skipped: no_oracle_files`.

### Step 2: For Each Planned Carrier

1. **Search oracle files for matching service/interface name**
   - Use `rg` to search for class name pattern
   - Example: `rg "class AiAutoClaimFlowService" --type java`
   - Record: `carrier_source: "oracle"` if found

2. **If found: Extract EXACT signature**
   - Method name (exact)
   - Parameter types (exact, including package)
   - Return type (exact)
   - File path (for reference)

3. **If NOT found: Verify this is NEW service**
   - Search codebase for similar existing services
   - Document why existing service cannot be reused
   - Record: `carrier_source: "new"` with justification

### Step 3: DTO Selection

1. **Search oracle domain/DTO files for matching fields**
   - Use `rg` to search for field names in DTOs
   - Example: `rg "freeReviewAmount|caseId" --type java claim-domain/`

2. **If found: Use EXISTING DTO**
   - Do NOT create new DTO with similar fields
   - Record: `dto_source: "oracle"`

3. **If NOT found: Verify no field overlap**
   - Check existing DTOs for field name conflicts
   - Document why new DTO is needed
   - Record: `dto_source: "new"` with justification

### Step 4: Record in PLAN_CONTRACT_VERIFY.json

For each carrier, record:

```json
{
  "carrier_verification_required": true,
  "fail_if_synthetic_carrier": true,
  "fail_if_signature_drift": true,
  "carriers": [
    {
      "class_name": "AiAutoClaimFlowService",
      "method_name": "handle",
      "parameter_types": ["Long", "AiApplyClaimApiTask"],
      "return_type": "void",
      "carrier_source": "oracle|new",
      "oracle_match": "exact|partial|none",
      "justification": "... (if new)",
      "signature_drift_risk": false
    }
  ]
}
```

## Blocked Patterns

These patterns are **FORBIDDEN** when oracle has matching carrier:

1. ❌ Creating new DTO when oracle has similar DTO
   - Example: Oracle has `AiApplyClaimApiTask` with `caseId`, `aiResult`
   - Forbidden: Creating `AiClaimResultDto` with same fields

2. ❌ Creating new Service method when oracle has exact method
   - Example: Oracle has `handle(Long caseId, AiApplyClaimApiTask task)`
   - Forbidden: Creating `executeAutoFlow(Long caseId)` or `processAiResult(Long caseId, AiResult result)`

3. ❌ Changing parameter types without justification
   - Example: Oracle uses `AiApplyClaimApiTask`
   - Forbidden: Changing to `AiResult` or `Long` only without documented reason

## Validation

The verifier will check:

1. **Synthetic Carrier Detection**
   - New service created when oracle has exact match → FAIL
   - New DTO created when oracle has similar DTO → FAIL

2. **Signature Drift Detection**
   - Method name differs from oracle → FAIL
   - Parameter types differ from oracle → FAIL
   - Return type differs from oracle → FAIL

3. **Missing Justification**
   - New carrier without justification → FAIL
   - "TODO" or "need to check" placeholders → FAIL

## Example: CORRECT Oracle-First Search

```markdown
## Carrier Selection for AiAutoClaimFlowService

### Step 1: Search Oracle Files

```bash
rg "class.*FlowService" --type java claim-*/src/main/java/
```

**Result Found:**
- `claim-core/src/main/java/com/huize/claim/core/ai/service/AiAutoClaimFlowService.java`

### Step 2: Extract Exact Signature

```java
public void handle(Long caseId, AiApplyClaimApiTask task)
```

### Step 3: Verify DTO

```bash
rg "AiApplyClaimApiTask" --type java claim-domain/
```

**Result Found:**
- `claim-domain/src/main/java/com/huize/claim/domain/ai/AiApplyClaimApiTask.java`

### Step 4: Record Decision

- carrier_source: oracle
- oracle_match: exact
- signature_drift_risk: false
```

## Example: WRONG Synthetic Carrier

```markdown
## WRONG: Creating New Carrier Without Search

### Selected Carrier: AiClaimResultService (NEW)

**Method:** `ResultModel<AiClaimResult> processResult(Long caseId)`

**Problem:** This was created WITHOUT searching oracle first.
**Correct Action:** Search oracle, use `AiAutoClaimFlowService.handle()` instead.
```

## Integration with Plan Phase

This verification happens **BEFORE** plan approval:

1. Agent creates plan with carrier selection
2. Runner calls carrier search verification
3. If FAIL: Agent must repair plan and re-search
4. If PASS: Plan proceeds to implementation

## Enforcement

- `fail_if_synthetic_carrier: true` - Plan rejected if synthetic carrier detected
- `fail_if_signature_drift: true` - Plan rejected if signature doesn't match oracle

See: `scripts/verify_plan_carrier_search.py` for implementation.
