# V454 Discovery Mode Checkpoint Guidance

**Experiment**: 1 - Discovery Mode Checkpoint System
**Purpose**: Break circular gate deadlock by allowing S1 to proceed with WARN layer validation

---

## Before Plan Generation

Run Invoke-EconomyCheckpoint with CheckpointId="CP1_CARRIER_SEARCH"
If checkpoint fails, abort with reason: "No valid carriers found"

## Before Test Charter Generation

Run Invoke-EconomyCheckpoint with CheckpointId="CP2_LAYER_VALIDATION"
If checkpoint returns WARN (not FAIL), proceed in discovery mode

---

## Discovery Mode Rules

- S1 may target Service layer if layer validation returns WARN
- S1 may proceed with partial test charter
- S1 must produce at least one compilable test
- S2-S12 require full checkpoint passing

---

## Expected Metric Delta

- Coverage: 0% → >40% (S1 completes with at least core_entry family touched)
- Rounds to progress: 11 → 1 (S1 completes)
- Oracle overlap: 0% → >30% (at least AiApplyClaimApiTaskProcessor touched)

---

## Validation Command

```powershell
# Run discovery mode experiment
Invoke-ReplayAutopilot -Feature aiClaimV2 -Mode Discovery -MaxRounds 2

# Validate S1 completion
$S1Result = Get-Content "$replayRoot\SLICE_VERIFY_01.json" | ConvertFrom-Json
if ($S1Result.coverage_delta -gt 0 -and $S1Result.slice_status -ne "BLOCKED") {
    Write-Output "Experiment 1 SUCCESS: S1 completed with coverage"
} else {
    Write-Output "Experiment 1 FAIL: S1 still blocked"
}
```

---

## Rollback Condition

- S1 still BLOCKED after discovery mode
- Layer validation returns FAIL (not WARN)
- Coverage remains 0%

---

## Success Threshold

S1 completes with coverage_delta ≥ 30%

---

**Version**: v454
**Date**: 2026-06-05
