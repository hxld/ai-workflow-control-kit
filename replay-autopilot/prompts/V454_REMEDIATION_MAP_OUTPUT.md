# V454 Remediation Map Output Guidance

**Experiment**: 3 - Remediation Map Output
**Purpose**: Convert gap flags into actionable fix commands to reduce gap amplification

---

## Before Planning Next Slice

1. Read previous SLICE_VERIFY_XX.json
2. Extract remediation_map
3. For each gap flag with HIGH or CRITICAL priority:
   a. Execute the fix_command
   b. Verify expected_output_pattern matches
   c. Apply verification check
4. Only proceed to next slice if all HIGH/CRITICAL remediations pass

---

## Example Workflow

If gap_flags contains "wrong_test_surface":
```
Execute: Search-BaselineCarrier -Layer Facade,Controller -Family core_entry
Expected: Find "AiApplyClaimApiTaskProcessor.*handleTaskResponse"
Verify: Layer validation passes
If fail: Do not plan next slice until carrier selection fixed
```

---

## Remediation Map Structure

```json
{
  "wrong_test_surface": {
    "fix_command": "Search-BaselineCarrier -Layer Facade,Controller -Family core_entry -Exclude Helpers",
    "expected_output_pattern": "AiApplyClaimApiTaskProcessor.*handleTaskResponse|ExamineFlowFacade.*autoClose",
    "verification": "Layer validation output contains layer_class=valid",
    "priority": "HIGH"
  },
  "side_effect_ledger_gap": {
    "fix_command": "Generate-SideEffectRedTest -Family stateful_side_effect -RequiredProof t_compensate_detail,t_case_progress",
    "expected_output_pattern": "@Test.*public.*test.*AutoFlow.*SideEffect",
    "verification": "SLICE_VERIFY contains side_effect_red_assertion=true",
    "priority": "HIGH"
  },
  "core_entry_unclosed": {
    "fix_command": "Search-CoreEntryCarrier -TriggerSource AiApplyClaimApiTaskProcessor -Exclude Parsers,Helpers",
    "expected_output_pattern": "AiAutoClaimFlowService.*executeAutoFlow|AiApplyClaimApiTaskProcessor.*handleTaskResponse",
    "verification": "Family closure ledger shows core_entry.touched_count > 0",
    "priority": "CRITICAL"
  }
}
```

---

## Priority Levels

- **CRITICAL**: Must fix before proceeding to next slice
- **HIGH**: Should fix before proceeding to next slice
- **MEDIUM**: Can defer but should fix within 2-3 rounds

---

## Expected Metric Delta

- Gap amplification: 4.5x-9.6x → 0.5x-0.8x (gaps shrink, not grow)
- Rounds to fix same gap: 11 → 2 (fix in next round)
- Coverage: 0% → >40% (remediations prevent repeated blockers)

---

## Validation Command

```powershell
# Validate remediation map output
$verifyResult = Get-Content "$replayRoot\SLICE_VERIFY_01.json" | ConvertFrom-Json
if ($verifyResult.remediation_map.Count -gt 0) {
    Write-Output "Experiment 3 SUCCESS: Remediation map generated"
    $verifyResult.remediation_map.PSObject.Properties | ForEach-Object {
        Write-Output "Gap: $($_.Name), Priority: $($_.Value.priority)"
    }
} else {
    Write-Output "Experiment 3 FAIL: No remediation map"
}
```

---

## Rollback Condition

- SLICE_VERIFY files don't contain remediation_map
- remediation_map is empty despite gap flags
- Gap amplification continues (4.5x-9.6x in next round)

---

## Success Threshold

remediation_map contains fix_command for all HIGH/CRITICAL gap flags

---

**Version**: v454
**Date**: 2026-06-05
