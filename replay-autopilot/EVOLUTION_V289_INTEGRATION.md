# Evolution v289 Integration Guide

## Overview

This document describes the workflow evolution implemented for v289 to address the STOP_DEEP_REVIEW_REQUIRED decision from v288.

## Background

Replay v288 triggered stop-loss decision with:
- Oracle coverage: 0% across 11 consecutive rounds (v274-v288)
- All rounds blocked at environment, plan, or first slice
- Repeated gaps: wrong_test_surface, side_effect_ledger_gap, core_entry_unclosed

## Implemented Experiments

### Experiment 1: Pre-Flight Test Environment Validation

**Purpose**: Reduce environment-blocked rounds from 60% to <10%

**Files Created**:
- `scripts/pre_flight_check.py` - Core Python module
- `scripts/Invoke-PreflightComprehensive.ps1` - PowerShell wrapper

**Checks Implemented**:
1. Test compilation check
2. JUnit dependency check
3. Existing test errors check
4. Oracle accessibility check

**Integration Point**: Call from `Run-ReplayLoop.ps1` before Phase 1 execution

```powershell
# In Run-ReplayLoop.ps1, after worktree setup:
& $scriptRoot\scripts\Invoke-PreflightComprehensive.ps1 `
    -ReplayRoot $replayRoot `
    -Worktree $worktree `
    -MavenSettings $mavenSettings `
    -RootPom $rootPom `
    -OracleBranch $oracleBranch

if ($LASTEXITCODE -ne 0) {
    # Pre-flight blocked, do not proceed
    return
}
```

### Experiment 2: Zero Executable Delta Enforcement After Blocked RED

**Purpose**: Reduce "implementation_after_blocked_red" from 40% to 0%

**Files Created**:
- `scripts/evaluate_slice_result.py` - Core Python module
- `scripts/Invoke-SliceZeroDeltaEvaluation.ps1` - PowerShell wrapper

**Rules Enforced**:
1. If RED phase is blocked: implementation_allowed = false, executable_delta = 0
2. If business assertion not observed: implementation_allowed = false, executable_delta = 0
3. If TDD RED not replayed: implementation_allowed = false, executable_delta = 0

**Integration Point**: Call from `Run-SliceLoop.ps1` after RED phase completes

```powershell
# In Run-SliceLoop.ps1, after RED phase:
$zeroDeltaResult = & $scriptRoot\scripts\Invoke-SliceZeroDeltaEvaluation.ps1 `
    -SliceResultPath $sliceResultPath `
    -Phase0ContractPath $phase0ContractPath

if ($LASTEXITCODE -ne 0) {
    # Zero-delta enforced, do not proceed to GREEN
    # Write BLOCKED status to slice result
    $sliceResult.status = "BLOCKED"
    $sliceResult | ConvertTo-Json | Set-Content $sliceResultPath
    continue
}
```

### Experiment 3: Carrier Search Requirement Before New Service Creation

**Purpose**: Reduce "carrier_search_new_service_unjustified" from 80% to <20%

**Files Created**:
- `scripts/verify_plan_carrier_search.py` - Core Python module
- `scripts/Invoke-PlanCarrierSearchVerification.ps1` - PowerShell wrapper

**Checks Implemented**:
1. Carrier search queries documented
2. Codebase searched for existing carriers
3. Oracle diff searched for similar carriers
4. New service justified

**Integration Point**: Call from `Verify-PlanContract.ps1` during plan verification

```powershell
# In Verify-PlanContract.ps1, after plan contract validation:
$carrierResult = & $scriptRoot\scripts\Invoke-PlanCarrierSearchVerification.ps1 `
    -PlanResultPath $planResultPath `
    -Worktree $worktree `
    -OracleCommit $oracleCommit

if ($LASTEXITCODE -ne 0) {
    # Carrier search failed, block plan
    $planResult.status = "BLOCKED_CARRIER_SEARCH"
    $planResult | ConvertTo-Json | Set-Content $planResultPath
    return
}
```

## Expected Outcomes

| Metric | Before | After (Target) | Measurement |
|--------|--------|----------------|-------------|
| Environment-blocked rounds | 60% | <10% | PREFLIGHT_COMPREHENSIVE.json |
| implementation_after_blocked_red | 40% | 0% | SLICE_RESULT_*.json |
| carrier_search_unjustified | 80% | <20% | PLAN_CONTRACT_VERIFY.json |
| Oracle-adjusted coverage (best) | 0% | >=30% | FINAL_REPLAY_REPORT |

## Success Criteria

Evolution considered successful if:
- At least 2 of 3 experiments achieve success threshold
- Combined oracle-adjusted coverage across 3 rounds >30%
- No new critical gap categories introduced

## Rollback Conditions

| Experiment | Rollback Threshold | Rollback Action |
|------------|-------------------|-----------------|
| Pre-Flight | >20% false positives | Soften to warnings only |
| Zero-Delta | >30% false negatives | Allow single retry |
| Carrier Search | >40% plan blocking | Relax to warning |

## Next Steps

1. Integrate the PowerShell wrappers into the appropriate run scripts
2. Test with a small feature (optional canary run)
3. Run v289 replay with evolution enabled
4. After 3 rounds (v289, v290, v291), run deep review to assess impact

## Files Created

```
replay-autopilot/
├── scripts/
│   ├── pre_flight_check.py (new)
│   ├── evaluate_slice_result.py (new)
│   ├── verify_plan_carrier_search.py (new)
│   ├── Invoke-PreflightComprehensive.ps1 (new)
│   ├── Invoke-SliceZeroDeltaEvaluation.ps1 (new)
│   └── Invoke-PlanCarrierSearchVerification.ps1 (new)
└── EVOLUTION_V289_INTEGRATION.md (this file)
```

## Knowledge Evolution Impact

This is a **workflow tooling evolution**, not a knowledge evolution. The changes are in the replay-autopilot tool scripts, not in the knowledge repository.

- **Current knowledge version**: v288
- **Expected next knowledge version**: v288 (no advance, this is tooling only)
- **Knowledge repo commit**: Not required for this evolution

## References

- NEXT_EXPERIMENT_PLAN.md - Full experiment specifications
- STOP_OR_CONTINUE_DECISION.md - Decision context
- ROOT_CAUSE_LEDGER.json - Evidence for gaps
