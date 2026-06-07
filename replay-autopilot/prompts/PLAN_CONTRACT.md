# Plan Contract Validation

## Blind Mode Validation

When `replay_mode == strict-blind`:

### Primary Metrics

1. **Requirement Family Coverage** >= 70%
   - Count of requirement families with identified carriers
   - Measurable from REQUIREMENT_SOURCE_SNAPSHOT.md

2. **High Weight Family Coverage** >= 60%
   - Count of families with weight >= 80
   - Core families: core_entry, stateful_side_effect, wire_payload_api_contract

3. **First Slice Targets Core Entry**
   - S1 must target core_entry family if present in requirements
   - Prevents validator drift (v291 pattern)

4. **Side Effects Identified** >= 3
   - At least 3 side effects must be identified in plan
   - DB writes, state changes, external calls

### Skipped Metrics (Not Measurable in Blind Mode)

- ~~oracle_overlap_percent~~ - Cannot know oracle file names in blind mode
- ~~oracle_missing_production_files~~ - Cannot know oracle files in blind mode
- ~~carrier_search_new_service_unjustified~~ - Cannot justify without oracle

## Non-Blind Mode Validation

When `replay_mode != strict-blind`:

- Use domain-filtered oracle overlap validation
- Apply domain filter to oracle files based on `oracle_primary_domain` before calculating overlap
- Require 50%+ oracle file overlap on domain-filtered set
- Require 70%+ HIGH-weight oracle file overlap on domain-filtered set
- Validate all oracle files accounted for or documented in `oracle_out_of_scope_files`

### Domain Filtering Behavior (v423)

The verifier filters oracle files to the primary domain before overlap calculation:
- Extract domain keywords from oracle file paths (e.g., `ai/`, `push/`, `examine/`)
- Map domain keywords to directory patterns (e.g., AI核赔自动化 → ai/claim/calculation/auto-flow)
- Calculate overlap on domain-filtered subset only
- This prevents cross-domain oracle files from inflating/deflating overlap percentage

## Service Layer Allowlist (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)

If SERVICE_LAYER_ALLOWLIST.json exists in replay root, it contains allowed Service layer testing patterns.

**Allowlist Purpose**:
- Identify valid Service layer classes created by oracle implementation
- Prevent false positive wrong_test_surface blocks
- Allow testing against specific Service layer carriers

**Allowlist Schema**:
```json
{
  "schema_version": 1,
  "source": "oracle_post_hoc_analysis",
  "patterns": [
    "AiAutoClaimFlowService",
    "AiApplyClaimApiTaskProcessor",
    "*TaskProcessor",
    "*FlowService"
  ],
  "rationale": "Oracle implementation created these Service layer classes. Testing at Service layer is valid for orchestration and task processor patterns."
}
```

**Validation Rules**:
- If selected carrier matches allowlist pattern, Service layer testing is valid
- layer_validation_status must be PASS
- If not matched, layer_validation_status is REVIEW requiring manual audit
- Carriers matching allowlist patterns are VALID for testing, even if in Service layer

## Validation Output

```json
{
  "stage": "Plan",
  "verification_status": "PASS|FAIL",
  "replay_mode": "strict-blind",
  "requirement_family_coverage": 80,
  "high_weight_family_coverage": 70,
  "first_slice_targets_core_entry": true,
  "side_effects_identified": 6,
  "oracle_overlap_skipped": "Blind mode validated via requirements"
}
```
