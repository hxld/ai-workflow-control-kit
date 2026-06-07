# V453 Minimum Viable Progress Gate

## Experiment 3: Minimum Viable Progress Gate

This prompt enforces **minimum viable progress** to prevent wasted tokens on rounds with <5% improvement.

## Problem Statement

Currently, stop-loss triggers only when catastrophic_or_blocked AND low_verification_cap_streak. This allows multiple rounds of 0% coverage before intervention, wasting tokens and delaying evolution.

## Minimum Viable Progress Requirement

After 3 rounds of replay, the runner calculates:

```bash
absolute_improvement = max(recent_oracle_scores) - min(recent_oracle_scores)
```

**Stop Condition**: If `absolute_improvement < 5` across 3+ rounds, the runner triggers:

```
decision: STOP_MINIMUM_PROGRESS_NOT_MET
no_minimum_viable_progress: improvement=<X> required=5 rounds=<N>
```

## Example

**Before v453**:
- Round 01: 0% coverage
- Round 02: 0% coverage (decision: CONTINUE_NO_IMPROVEMENT_1)
- Round 03: 0% coverage (decision: CONTINUE_NO_IMPROVEMENT_2)
- Round 04: 0% coverage (circuit_breaker: STOP_NO_IMPROVEMENT after 2 rounds no improvement)
- **Result**: 4 rounds, ~4M tokens wasted

**After v453**:
- Round 01: 0% coverage (recent_oracle_scores: [0])
- Round 02: 0% coverage (recent_oracle_scores: [0, 0], min_viable_progress_check: improvement=0 required=5 rounds=2)
- Round 03: 0% coverage (recent_oracle_scores: [0, 0, 0], improvement=0 < 5)
- **Result**: decision: STOP_MINIMUM_PROGRESS_NOT_MET after 3 rounds
- **Saved**: ~1M tokens (25% reduction)

## Integration with Evolution Proposal

When STOP_MINIMUM_PROGRESS_NOT_MET is triggered:

1. The evolution prompt must recommend STOP_AND_EVOLVE
2. Must specify which workflow changes will address the lack of progress
3. Must NOT recommend "continue" based on blind self-assessed coverage alone

## Related Files

- Script: `scripts/Run-ReplayLoop.ps1` (lines 1508, 4025-4040)
- Verifier: `scripts/verifier/plan_contract_verify.json`
- Integration: Stop-loss decision logic in main replay loop

## Expected Impact

| Metric | Before | After Target | Delta |
|--------|--------|--------------|-------|
| Rounds with 0% coverage before stop | 4-11 | 3 | -1 to -8 |
| Tokens wasted on 0% rounds | ~4-11M | ~3M | -1 to -8M (-25% to -73%) |
| Stop triggered by | catastrophic+cap | minimum_progress | Earlier |
