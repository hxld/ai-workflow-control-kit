# Slice Planning Guidance

## Exact Contract Extraction (P0 - CRITICAL)

**BEFORE planning your slice, you MUST extract and use the EXACT oracle signatures.**

### Process

1. **Load Oracle Signatures**
   - Check if `ORACLE_SIGNATURES.json` exists in your replay root
   - If not, run: `python scripts/extract_oracle_contracts.py {{WORKTREE}} {{BASE_COMMIT}}`

2. **Find Your Target Carrier**
   - Search in `ORACLE_SIGNATURES.json` for your target service
   - Example: `AiAutoClaimFlowService.handle` or `AiApplyClaimApiTaskProcessor.process`

3. **Copy EXACT Signature**
   ```json
   {
     "AiAutoClaimFlowService": [
       {
         "class_name": "AiAutoClaimFlowService",
         "method_name": "handle",
         "parameter_types": ["Long", "AiApplyClaimApiTask"],
         "return_type": "boolean",
         "file_path": "claim-core/src/main/java/.../AiAutoClaimFlowService.java"
       }
     ]
   }
   ```

4. **DO NOT Deviate**
   - Use oracle return type EXACTLY
   - Use oracle method name EXACTLY
   - Use oracle parameters in EXACT order
   - Copy oracle annotations (@Transactional, etc.)

5. **If Signature Missing**
   - STOP and report the gap
   - Write BLOCKED with `gap_flag: exact_contract_gap`

### Example

❌ **WRONG** - Invented signature:
```java
public AutoFlowResult triggerAutoFlow(Long caseId) { ... }
```

✅ **CORRECT** - Oracle signature:
```java
public boolean handle(Long caseId, AiApplyClaimApiTask task) { ... }
```

### P0 Violation Consequences

If you implement with an incorrect signature:
- `gap_flags`: [`exact_contract_gap`, `carrier_signature_mismatch`]
- `slice_status`: "BLOCKED"
- `blocker`: "signature_not_from_oracle"
- `coverage_delta`: 0

---

## Core-First Completion Gate

**RULE**: The `core_entry` family (weight 100) MUST be fully CLOSED before any other family can be targeted.

### Definition of CLOSED

A family is CLOSED only when ALL of the following are true:

1. **All validation gates are implemented** (not just TODO comments)
   - Examples: `isSupportedAutoFlowScope()`, `checkFreeReviewAmount()`, `validateBeneficiary()`
   - Must have actual business logic, not `return true;` placeholders

2. **Database side effects are verified** with @Transactional rollback test
   - `CompensateInfo.insert()` or `CompensateInfo.update()` proven
   - `CompensateDetail.insert()` or `CompensateDetail.insertList()` proven
   - Test uses `AtomicReference` to capture mapper arguments
   - Assertions verify captured values

3. **Status transitions are proven** with test assertions
   - `CaseFlowStatusService.updateFlowStatusForCompensate()` called
   - Status change verified in test
   - `t_case_flow_status` table update proven

4. **RED phase failed** with business assertion
   - Test failed before implementation with meaningful error
   - NOT a compilation error (ClassNotFoundException, NoSuchMethod)
   - Example: `assertThat(result).isNull()` fails because result was null

5. **GREEN phase passed** with behavioral verification
   - Test passes after implementation
   - Side effects verified (DB state, output values)
   - No TODO comments remaining

### If core_entry is not CLOSED

Slice planning MUST continue targeting `core_entry` until closure criteria are met.

**Forbidden**: Starting slices for other families (`stateful_side_effect`, `deploy_export_page`, `config_policy_threshold`, etc.) while `core_entry` is OPEN or PARTIAL.

### Closure Verification Checklist

Before moving to the next family, verify:

- [ ] All validation methods have real implementation
- [ ] DB insert/update operations are executed
- [ ] Test captures DB operation arguments with `AtomicReference`
- [ ] Status update is called and verified
- [ ] RED phase failed with business assertion (not compilation)
- [ ] GREEN phase passes with side effect verification
- [ ] No TODO comments in implementation
- [ ] No `return null;` placeholders in business logic

### Example: CLOSED core_entry

```java
// Implementation
@Service
public class AiAutoClaimFlowService {

    public boolean handle(Long caseId, AiApplyClaimApiTask task) {
        // Validation gates implemented
        if (!isSupportedAutoFlowScope(caseId)) {
            return false;
        }
        if (!checkFreeReviewAmount(caseId)) {
            return false;
        }

        // DB side effects
        CompensateInfo info = buildCompensateInfo(caseId, task);
        compensateInfoMapper.insert(info);

        List<CompensateDetail> details = buildCompensateDetails(info);
        compensateDetailMapper.insertList(details);

        // Status update
        caseFlowStatusService.updateFlowStatusForCompensate(caseId);

        return true;
    }
}

// Test
@Test
@Transactional
public void testHandle_Success_CompensateDataInserted() {
    // GIVEN
    Long caseId = 12345L;
    AiApplyClaimApiTask task = setupFlashCaseWithBeneficiary();

    AtomicReference<CompensateInfo> capturedInfo = new AtomicReference<>();
    doAnswer(invocation -> {
        capturedInfo.set(invocation.getArgument(0));
        return 1;
    }).when(compensateInfoMapper).insert(any());

    // WHEN
    boolean result = aiAutoClaimFlowService.handle(caseId, task);

    // THEN
    assertThat(result).isTrue();
    assertThat(capturedInfo.get()).isNotNull();
    assertThat(capturedInfo.get().getCaseId()).isEqualTo(caseId);

    verify(caseFlowStatusService).updateFlowStatusForCompensate(caseId);
}
```

### Example: OPEN/PARTIAL core_entry (DO NOT MOVE ON)

```java
// WRONG - Not closed, do not move to next family
@Service
public class AiAutoClaimFlowService {

    public boolean handle(Long caseId, AiApplyClaimApiTask task) {
        // TODO: Implement validation
        // TODO: Insert compensate info
        return false;  // Placeholder
    }
}
```

```java
// WRONG - Not closed, structural test only
@Test
public void testHandle_ServiceExists() {
    assertThat(aiAutoClaimFlowService).isNotNull();  // Wrong surface!
}
```

---

## Slice Authorization Flow

Before starting any new slice:

1. Check if `core_entry` family exists in requirement ledger
2. Check current status of `core_entry` (OPEN, PARTIAL, CLOSED)
3. If `core_entry` is not CLOSED and target_family != `core_entry`:
   - **BLOCK**: Do not start this slice
   - Continue targeting `core_entry` until closed
4. If `core_entry` is CLOSED:
   - Allow any family targeting

## Enforcer Integration

The `authorize_next_slice.py` script enforces this gate:

```bash
python scripts/authorize_next_slice.py \
    <ledger_path> \
    <slice_result_path> \
    <target_family> \
    <worktree_path>
```

Returns:
- `authorized: true` if allowed to proceed
- `authorized: false` with `reason` if blocked

---

## Horizontal Coverage Validation (v357)

### Minimum Category Requirement

Every slice must touch minimum **3 categories horizontally**:
- **Frontend**: `.jsp`, `.js`, `.ftl`, `/pages/`, `/static/`, Controller.java
- **Backend**: Service.java, Facade.java, Processor.java, `/src/main/java/`
- **Database**: Mapper.java, Mapper.xml, `.sql`, INSERT, UPDATE, `/provider/`

### Automated Check

The `validate_horizontal_coverage.py` script runs automatically during slice authorization:

```bash
python scripts/validate_horizontal_coverage.py --slice_plan SLICE_PLAN_XX.json
```

### Validation Result

```json
{
  "valid": true,
  "touched_categories": ["Frontend", "Backend", "Database"],
  "touched_count": 3,
  "required_count": 3,
  "message": "Horizontal slice coverage validated (3/3 categories)"
}
```

### Block Conditions

If validation fails:
1. Slice targets only Backend (common anti-pattern)
2. Missing Frontend or Database category
3. Must expand slice to cover minimum 3 categories

### Example

**WRONG** (Backend only):
```json
{
  "planned_files": [
    "claim-core/service/AiAutoClaimFlowService.java"
  ]
}
// Result: FAIL - only 1 category (Backend)
```

**CORRECT** (Horizontal coverage):
```json
{
  "planned_files": [
    "claim-web/controller/AiClaimController.java",      // Frontend
    "claim-core/service/AiAutoClaimFlowService.java",    // Backend
    "claim-provider/mapper/AiClaimMapper.java"           // Database
  ]
}
// Result: PASS - 3 categories covered
```

---

## Surface Layer Validation (Experiment E3)

### Phase 0 Test Surface Mapping (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)

BEFORE finalizing your test carrier, you MUST check PHASE0_RESULT.md for test_surface_mapping:

1. Load PHASE0_RESULT.md
2. Find test_surface_mapping for your target implementation carrier
3. Use the test_surface_carrier from the mapping as your test target
4. If no mapping exists, use this fallback:
   - Search BASELINE_INDEX.md for existing Facades that reference similar functionality
   - If found, use that Facade
   - If not found, document why Service layer is the only option

Example:
- If PHASE0_RESULT.md shows:
  ```json
  "test_surface_mapping": {
    "AiAutoClaimFlowService": {
      "test_surface_carrier": "AiClaimFacade",
      "test_surface_layer": "Facade"
    }
  }
  ```
- Then your test MUST target AiClaimFacade, not AiAutoClaimFlowService

### Pre-Authorization Layer Check

BEFORE finalizing slice target, validate the test surface layer. The verifier checks if you're testing the correct architectural layer.

### Real Entry Layers (PREFERRED)

- **Facade Layer**: Classes ending with `Facade`, `FacadeImpl`
- **Controller Layer**: Classes ending with `Controller`, `ApiController`
- **Api Layer**: Classes ending with `Api`

### Internal Layers (USE ONLY WHEN NECESSARY)

- **Service Layer**: Classes ending with `Service`, `Task`, `Processor`
- **Data Layer**: Classes ending with `Mapper`, `Dao`, `Repository`

### Validation Rule

**For `core_entry` and `stateful_side_effect` families:**
- Tests MUST target Facade/Controller/Api layer (real entry points)
- Service layer tests are ONLY allowed with documented justification

### Examples

❌ **WRONG** - Testing Service layer when Facade exists:
```markdown
selected_carrier: AiApplyClaimApiTaskProcessor.process
# Result: BLOCKED - wrong_test_surface
```

✅ **CORRECT** - Testing Facade layer:
```markdown
selected_carrier: AiClaimFacade.handleAiClaim
# Result: ALLOW - correct real entry surface
```

✅ **ACCEPTABLE** - Service layer with justification:
```markdown
selected_carrier: AiAutoClaimFlowService.handle

## Why Service Layer Testing
The AiAutoClaimFlowService has no Facade/Controller boundary because:
1. It's triggered by internal task queue (not HTTP)
2. Testing at Service layer validates the complete flow
# Result: ALLOW - justified internal entry
```

### Correction Suggestion Recovery (Experiment 3 from NEXT_EXPERIMENT_PLAN.md)

When you receive a `wrong_test_surface` blocker with `correction_suggestion`:

1. **STOP** - do not proceed with current test carrier
2. **READ** the `correction_suggestion` field
3. **SELECT** one of the `suggested_carriers` from the suggestion
4. **RETRY** slice planning with the suggested carrier
5. **DO NOT** ignore the suggestion or pick a different carrier

Example:
- Blocker: "AiAutoClaimFlowService is in Service layer"
- Suggestion: "Use: AiClaimFacade, ClaimCalculationFacade"
- Action: Re-plan using AiClaimFacade as test target

The verifier now provides `suggested_carriers` array with specific Facade names. Use one of these suggestions.

### Verifier Integration

The `Authorize-PreSliceEvidence.ps1` script automatically validates surface layer. If validation fails:
- `gap_flags`: [`wrong_test_surface`]
- `slice_status`: "BLOCKED"
- `coverage_delta`: 0
