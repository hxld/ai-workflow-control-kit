# V446 Facade-First Carrier Selection Prompt

## Experiment 1: Facade-First Carrier Selection

This prompt enforces **Facade-First carrier selection** to reduce `wrong_test_surface` gaps by 80%.

## Carrier Selection Priority Order

When selecting carriers for implementation, you MUST follow this priority order:

### 1. EXISTING FACADE CARRIERS (Highest Priority)

**Search Pattern:**
```bash
rg "class.*Facade.*java" --type java
```

**For `core_entry` family:**
- MUST select from Facade layer FIRST
- If Facade exists and matches requirement: **USE IT**
- Do NOT create NEW service if Facade carrier is available

**Example Correct Flow:**
```markdown
## Step 1: Search for Facade Carriers

```bash
rg "class.*Facade.*java" --type java example-core/src/main/java/
```

**Found Facades:**
- `ExampleFacade` - Methods: submit, query, update
- `ClaimCalculationFacade` - Methods: calculate, getBook

**Decision:** Use `ExampleFacade` as entry point for core_entry family
**Reason:** Facade layer is required for core_entry family per architecture
```

### 2. EXISTING CONTROLLER CARRIERS

**Search Pattern:**
```bash
rg "class.*Controller.*java" --type java
```

**Alternative to Facade for web-facing features:**
- Use Controller for `deploy_export_page` family
- Use Controller for HTTP endpoint features

### 3. NEW SERVICE (Last Resort, Requires Justification)

**ONLY if NO Facade/Controller matches:**

You MUST provide:

```markdown
### New Service Justification

**all_facades_checked:**
- ExampleFacade - Checked: Methods do not include auto flow trigger
- ClaimCalculationFacade - Checked: Only calculation methods
- RiskInfoFacade - Checked: Only risk query methods
- ... (list ALL Facades checked)

**facade_insufficiency_reason:**
- `ExampleFacade`: Has `submit` method but not `triggerAutoFlow`
- `ClaimCalculationFacade`: Read-only calculation, no state change
- `RiskInfoFacade`: Risk query only, no flow orchestration

**orphan_feature:** true
**orphan_feature_no_existing_domain:** false (only true if truly no domain exists)
```

## Layer Requirements by Family

| Family | Required Layers | Notes |
|--------|----------------|-------|
| `core_entry` | Facade, Controller | MUST enter through Facade/Controller |
| `stateful_side_effect` | Service, Facade | Can use Service if Facade unavailable |
| `config_policy_threshold` | Service, Facade | Configuration updates |
| `deploy_export_page` | Controller, Facade | Export pages and HTTP endpoints |

## Validation Checks

The verifier will check:

### Check: `facade_exists_check`

**Condition:** `selected_carrier_type == 'NEW' and target_family == 'core_entry'`

**Required Evidence:**
1. `all_facades_checked`: List of ALL `*Facade.java` files matching feature keywords
2. `facade_insufficiency_reason`: Explanation for each Facade why it cannot carry the requirement

**Fail If:**
- `all_facades_checked` is empty
- `facade_insufficiency_reason` is missing
- Less than 3 Facades checked for feature (unless fewer exist in codebase)

## Example: CORRECT Facade-First Selection

```markdown
## Carrier Selection for Auto Flow Feature

### Target Family: core_entry

### Step 1: Search Facade Layer

```bash
rg "class.*Facade.*java" --type java example-core/src/main/java/
```

**Found 5 Facades:**
1. `ExampleFacade` - Methods: submit, query, updateStatus
2. `ClaimCalculationFacade` - Methods: calculate, getBook
3. `RiskInfoFacade` - Methods: queryRisk, updateRisk
4. `CompensateFacade` - Methods: create, query, update
5. `ReviewFacade` - Methods: submit, query

### Step 2: Check Each Facade for Auto Flow Support

**ExampleFacade:** No `triggerAutoFlow` method found
**ClaimCalculationFacade:** Calculation only, no flow methods
**RiskInfoFacade:** Read-only query methods
**CompensateFacade:** Compensation-specific methods
**ReviewFacade:** Review-specific methods

### Step 3: Decision

**Selected Carrier:** `ExampleFacade` (EXISTING)
**Reason:** Closest match for core_entry family, has `submit` method that can be extended
**Layer:** Facade (correct for core_entry)
**Implementation:** Add new method `triggerAutoFlow` to existing Facade
```

## Example: WRONG Service-First Selection

```markdown
## WRONG: Skipping Facade Search

### Selected Carrier: ExampleFlowService (NEW)

**Problem:**
1. Did NOT search `rg "class.*Facade.*java"` first
2. Did NOT check `ExampleFacade` which could handle this
3. Created NEW service when existing Facade exists

**Correct Action:**
1. Search Facade layer FIRST
2. Check each Facade for matching methods
3. Only create NEW service if all Facades are inadequate
4. Document all Facades checked and why insufficient
```

## Blocked Patterns

These patterns are **FORBIDDEN:**

1. ❌ Creating NEW service without checking Facade layer first
   - For `core_entry` family, MUST check Facade first

2. ❌ Checking only 1-2 Facades and concluding "no Facade exists"
   - Must check ALL Facades matching feature keywords

3. ❌ Empty `all_facades_checked` list when creating NEW service
   - Must list at least 3-5 Facades checked

4. ❌ Using Service layer carrier when Facade available for `core_entry`
   - Facade/Controller preferred for entry point families

## Integration with Implementation Contract

When writing `IMPLEMENTATION_CONTRACT.md`, each carrier must include:

```json
{
  "classpath": "com.example.project.api.facade.ExampleFacade",
  "target_family": "core_entry",
  "target_layer": "Facade",
  "layer_justification": "Facade layer is required for core_entry family per architectural rules",
  "carrier_type": "EXISTING",
  "methods_to_use": ["submit", "query"]
}
```

For NEW services:

```json
{
  "classpath": "com.example.project.service.ExampleFlowService",
  "target_family": "core_entry",
  "target_layer": "Service",
  "layer_justification": "No existing Facade has auto flow trigger capability; all_facades_checked lists 5 Facades, all inadequate for flow orchestration",
  "carrier_type": "NEW",
  "all_facades_checked": [
    "ExampleFacade",
    "ClaimCalculationFacade",
    "RiskInfoFacade",
    "CompensateFacade",
    "ReviewFacade"
  ],
  "facade_insufficiency_reason": "None of the 5 existing Facades have triggerAutoFlow method or flow orchestration capability"
}
```

## Validation Command

After plan creation, the verifier runs:

```bash
python facade_first_carrier_search.py validate \
  <selected_carriers_json> \
  <families_json> \
  <worktree>
```

**Exit Code 0:** PASS - Facade-First followed correctly
**Exit Code 1:** FAIL - Violation detected (e.g., NEW service without Facade check)

## Expected Impact

| Metric | Current | Expected After Exp1 | Delta |
|--------|---------|---------------------|-------|
| wrong_test_surface gap count | 17 | ≤ 3 | -14 |
| Rounds reaching RED phase | 0 | ≥ 1 | +1 |
| Rounds completing 1+ slices | 0 | ≥ 1 | +1 |
| oracle_adjusted_coverage | 0% | 10-20% | +10-20% |

## Related Files

- Script: `scripts/facade_first_carrier_search.py`
- Verifier: `scripts/verifier/plan_contract_verify.json`
- Integration: `scripts/Invoke-V446ExperimentValidation.ps1`
