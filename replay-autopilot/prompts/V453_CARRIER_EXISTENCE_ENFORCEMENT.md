# V453 Carrier Existence Enforcement

## Experiment 1: Carrier Search Requirement

This prompt enforces **carrier search queries** as a mandatory requirement before plan approval.

## Problem Statement

Currently, `carrier_search_queries_missing` is treated as a warning. This allows plans to proceed without proving the selected carrier exists in the baseline codebase. When carrier search is missing, the agent defaults to creating ORACLE_NEW services which then fail at architectural validation.

## Mandatory Carrier Search Requirement

Before selecting any carrier for implementation, you MUST:

### Step 1: Search for Existing Carriers

Run at least 3 reproducible search commands:

```bash
# Example for Facade layer
rg "class.*Facade.*java" --type java example-core/src/main/java/

# Example for Service layer
rg "class.*Service.*java" --type java example-core/src/main/java/

# Example for Controller layer
rg "class.*Controller.*java" --type java example-core/src/main/java/
```

### Step 2: Document Search Queries

In PLAN_RESULT.md, you MUST include:

```markdown
carrier_search: performed
carrier_search_queries: rg "class.*Facade.*java" --type java; rg "ClaimCalculationFacade" --type java; rg "ExampleFacade" --type java
existing_production_carriers: ExampleFacade; ClaimCalculationFacade; RiskInfoFacade
selected_carrier_from_search: ExampleFacade
```

### Step 3: Justify New Service (Only If Required)

If NO existing carrier can carry the requirement:

```markdown
new_service_proposed: true
new_service_justification: orphan_feature_no_existing_domain
```

**Valid reasons for new service**:
- `orphan_feature_no_existing_domain` - Feature has no existing domain
- `new_external_boundary` - New external integration boundary
- `incompatible_existing_carriers` - Existing carriers architecturally incompatible
- `oracle_new_service_no_existing_orchestration` - Oracle shows new service is correct

## Blocker Behavior

Plans without `carrier_search_queries` will be **REJECTED** at Phase 0 contract verification:

```
verification_status: FAIL
issues:
  - carrier_search_queries_missing: plan_rejected
```

## Verifier Contract

See `scripts/verifier/plan_contract_verify.json`:

```json
{
  "check_name": "carrier_search_queries_mandatory",
  "priority": "P0",
  "condition": "plan_status == 'PROCEED'",
  "fail_if": "carrier_search_queries is missing, empty, or has fewer than 3 queries",
  "blocks_plan_approval": true,
  "v453_experiment": "carrier_existence_enforcement"
}
```

## Example: CORRECT Carrier Search

```markdown
## Carrier Selection for Auto Flow Feature

### Carrier Search Performed

**Search Queries:**
```bash
rg "class.*Facade.*java" --type java example-core/src/main/java/
rg "triggerAutoFlow" --type java example-core/src/main/java/
rg "ExampleFacade" --type java example-core/src/main/java/
```

**Existing Production Carriers Found:**
- ExampleFacade - Methods: submit, query, updateStatus
- ClaimCalculationFacade - Methods: calculate, getBook
- RiskInfoFacade - Methods: queryRisk, updateRisk

**Selected Carrier:** ExampleFacade (EXISTING)
**Reason:** Closest match for core_entry family, has `submit` method
```

## Example: WRONG Missing Carrier Search

```markdown
## WRONG: No Carrier Search Performed

### Selected Carrier: ExampleFlowService (NEW)

**Problems:**
1. Did NOT search for existing Facade/Service carriers
2. Did NOT document search queries
3. Directly created NEW service without proving existing carriers insufficient

**Correct Action:**
1. Search existing carriers FIRST using at least 3 rg commands
2. Document carrier_search_queries and existing_production_carriers
3. Only create NEW service if all existing carriers are inadequate
4. Justify why each existing carrier cannot carry the requirement
```

## Related Files

- Script: `scripts/Invoke-PlanCarrierSearchVerification.ps1`
- Verifier: `scripts/verifier/plan_contract_verify.json`
- Prompt: `prompts/V446_FACADE_FIRST_CARRIER_SEARCH.md`

## Expected Impact

| Metric | Before | After Target | Delta |
|--------|--------|--------------|-------|
| ORACLE_NEW carrier selection | 82% | <20% | -62% |
| Plan-to-execution success rate | 18% | >70% | +52% |
| carrier_search_queries_missing flags | 9/11 | 0-1/11 | -8 to -9 |
