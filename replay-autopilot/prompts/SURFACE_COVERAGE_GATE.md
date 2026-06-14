# Surface Coverage Gate - Real-Time Verification

## S1 Requirements

When `slice_number == 1`:

### Must Target

- **core_entry family** (weight 100) if present in requirement ledger
- Example: `ExampleFlowService`, `ClaimCalculationBookService`

### Must Verify

- At least 1 side effect (DB write, state change, external call)
- Example: `CompensateDetailMapper.insert()`, `CaseFlowStatusService.update()`

### Forbidden in S1

- ❌ `config_policy_threshold` family (validators, utils)
- ❌ Helper-only surfaces without state changes
- ❌ Static-only methods
- ❌ Mock-only tests

## Enforcement

### Real-Time Blocking

After each slice execution, run `slice_verify.py`:

1. Check `helper_only_surface_gap` → Block if detected
2. Check `side_effect_ledger_gap` → Block if no side effects verified
3. Check `mock_only_proof` → Block if tests use mocks only
4. Check `core_entry_unclosed` → Block if core_entry not closed

### Blocker Messages

```
BLOCKED: helper_only_surface_gap
S1 must target core_entry (ExampleFlowService), not validator (FreeReviewAmountValidator)
```

```
BLOCKED: side_effect_ledger_gap
Slice must verify at least 1 side effect (DB write, state change, external call)
```

## Output Format

```json
{
  "slice_number": 1,
  "target_family": "core_entry",
  "authorized_for_next_slice": true,
  "side_effects_verified": 3,
  "core_entry_closed": true,
  "blockers": [],
  "gaps": []
}
```

## v291 Pattern Prevention

The v291 round failed because:
- S1 targeted `FreeReviewAmountValidator` (validator, weight 87)
- S1 should have targeted `ExampleFlowService` (core_entry, weight 100)
- No side effects were verified
- 0% oracle coverage despite 225 lines written

This gate prevents v291 recurrence by blocking S1 if:
- target_family != core_entry (when core_entry exists)
- side_effects_verified == 0
