# Evolution v445 Integration

## Tooling Changes

### Modified Files

1. **.\scripts\Verify-PlanContract.ps1**
   - Lines 784-803: Removed invalid regex patterns for table format
   - Lines 840-873: Added table format validation logic

2. **<REPLAY_AUTOPILOT_ROOT>\tests\Test-v445-PlanTableFormat.ps1** (new)
   - Regression test for table format recognition
   - Tests table format is recognized
   - Tests empty carriers are still detected

### Changes Summary

**Before v445**:
- Only key-value format recognized: `existing_production_carriers: <value>`
- Table format caused false-positive `carrier_search_existing_carriers_missing` error

**After v445**:
- Both key-value and table formats recognized
- Table format: `### Existing Production Carriers Found` followed by table rows
- Table rows detected by patterns: `\| *[A-Z]\w* *\|` and `\| *[A-Z]\w*Service *\|`

### Validation

```powershell
# Run verification against replay with table format
powershell.exe -Command "& scripts\Verify-PlanContract.ps1 -ReplayRoot 'D:/opt/replay-evidence/aiClaimV2/claim-codex-replay-v444-autopilot-20260517-r01' -Stage Plan"

# Run regression test
powershell.exe -File "tests/Test-v445-PlanTableFormat.ps1"
```

### Results

- Verification: PASS (no `carrier_search_existing_carriers_missing` issue)
- Regression Test: PASSED
- Knowledge Repo: v444 → v445 (commit f163605)

---

**Evolution Source**: aiClaimV2 claim-codex-replay-v444-autopilot-20260517-r01
**Gap**: `carrier_search_existing_carriers_missing` in PLAN_CONTRACT_VERIFY.json
**Gate**: Surface Coverage Gate
**Category**: `tooling-evolution-needed`
