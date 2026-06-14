# V453 Layer Validation Shift-Left

## Experiment 2: Phase 0 Layer Validation

This prompt enforces **layer validation at Phase 0** to prevent S1 blockers due to layer mismatch.

## Problem Statement

Currently, layer validation (Facade/Controller vs Service) happens at pre-slice authorization (PRE_S1_CARRIER_VERIFY.json). This is too late - the plan has already been approved, slice budget allocated, and execution started. When layer validation fails, the entire round is wasted.

## Layer Validation at Phase 0

Before approving any plan, you MUST validate:

### Required Fields

Each selected carrier MUST include:

```json
{
  "classpath": "com.huize.claim.api.facade.AiClaimFacade",
  "target_family": "core_entry",
  "target_layer": "Facade",
  "layer_justification": "Facade layer is required for core_entry family per architectural rules",
  "carrier_type": "EXISTING"
}
```

### Family Layer Requirements

| Family | Required Layers | Invalid Layers |
|--------|----------------|----------------|
| `core_entry` | Facade, Controller | Service, Mapper, Dao |
| `stateful_side_effect` | Service, Facade | Mapper, Dao |
| `config_policy_threshold` | Service, Facade | Mapper, Dao |
| `deploy_export_page` | Controller, Facade | Mapper, Dao |
| `wire_payload_api_contract` | Service, Facade | Mapper, Dao |

### Blocker Behavior

Plans with `target_layer` that violates family requirements will be **REJECTED** at Phase 0:

```
verification_status: FAIL
issues:
  - layer_validation_failed: core_entry_requires_facade_controller
```

## Example: CORRECT Layer Selection

```markdown
## Carrier Selection for Auto Flow Feature

### Target Family: core_entry

### Selected Carrier: AiClaimFacade

**Layer Validation:**
- target_family: core_entry
- target_layer: Facade
- layer_justification: Facade layer is required for core_entry family per architectural rules
- Validation: PASSED - Facade is in allowed layers for core_entry
```

## Example: WRONG Layer Selection

```markdown
## WRONG: Service Layer for core_entry Family

### Selected Carrier: AiAutoClaimFlowService

**Problems:**
1. target_family: core_entry
2. target_layer: Service
3. **Layer Validation: FAILED** - Service is NOT in allowed layers for core_entry
4. Allowed layers for core_entry: Facade, Controller
5. **Correct Action:** Select a Facade or Controller carrier instead
```

## Verifier Contract

See `scripts/verifier/plan_contract_verify.json`:

```json
{
  "check_name": "carrier_layer_binding",
  "priority": "P0",
  "validation": "target_layer must be in FAMILY_LAYER_REQUIREMENTS[target_family]",
  "fail_if": "target_layer is missing or not in allowed layers for target_family",
  "blocks_plan_approval": true,
  "v453_experiment": "layer_validation_shift_left"
}
```

## Integration with Phase 0 Contract Gate

The layer validation happens during Phase 0 contract verification, BEFORE plan approval. This is earlier than the previous pre-slice validation, preventing wasted rounds.

## Related Files

- Script: `scripts/Invoke-Phase0ContractReconciliation.ps1`
- Verifier: `scripts/verifier/plan_contract_verify.json`
- Prompt: `prompts/phase0-contract-gate.prompt.md`
- Reference: `prompts/V446_FACADE_FIRST_CARRIER_SEARCH.md`

## Expected Impact

| Metric | Before | After Target | Delta |
|--------|--------|--------------|-------|
| wrong_test_surface at slice execution | 15+ | <3 | -12+ |
| S1 blocked for layer issues | 100% | <20% | -80% |
| Slices reaching execution | 0% | >60% | +60% |
| Rounds wasted on layer mismatch | 2-3 | 0 | -2 to -3 |
