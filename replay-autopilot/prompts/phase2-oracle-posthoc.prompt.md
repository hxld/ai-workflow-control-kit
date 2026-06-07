You are running Phase 2 Oracle Post-Hoc scoring.

Inputs:
- replay root: `{{REPLAY_ROOT}}`
- worktree: `{{WORKTREE}}`
- feature_name: `{{FEATURE_NAME}}`
- oracle branch: `{{ORACLE_BRANCH}}`
- oracle commit: `{{ORACLE_COMMIT}}`
- Phase 1 result: `{{REPLAY_ROOT}}\ROUND_RESULT.md`

Hard rules:
1. You may read oracle branch / oracle commit / oracle diff only now.
2. Do not continue implementation.
3. Do not modify Phase 1 `blind_self_assessed_coverage` or `verification_capped_coverage`.
4. Append only an Oracle Post-Hoc section to `{{REPLAY_ROOT}}\ROUND_RESULT.md`.
5. Create `{{REPLAY_ROOT}}\FINAL_REPLAY_REPORT.md`. Do not write the final report to the worktree root.
6. `oracle_adjusted_coverage` is the overlap between the Phase 1 replay implementation and the oracle. It is not oracle completeness.
7. If Phase 1 has `verification_capped_coverage: 0`, no authorized slice, no production diff, or no executable behavior evidence, then `oracle_adjusted_coverage` must be `0` even if the oracle implementation is complete.
8. If you inspect oracle by changing git state, restore the replay worktree to its pre-Phase2 HEAD before finishing. If restoration is impossible, disclose it explicitly in the report.

Required analysis:
- 8-gate effectiveness matrix:
  1. Source-of-Truth Gate
  2. Oracle Isolation Gate
  3. Requirement Contract Gate
  4. Surface Coverage Gate
  5. Core-First Budget Gate
  6. Executable Evidence Gate
  7. Coverage Cap Gate
  8. Evolution Abstraction Gate
- exact file-family overlap
- conceptual role overlap
- missing deploy-facing family penalty
- exact contract gaps
- core_entry_unclosed
- side_effect_ledger_gap
- executable_surface_slice_gap
- wrong_test_surface / shallow_module / feedback_loop_blocker
- whether workflow gates were effective

Output:
- Keep the reported Phase 1 coverage unchanged.
- Report `oracle_adjusted_coverage` using replay evidence only.
- State whether the next round needs workflow evolution.
- Evolution points must map to the 8 gates. If a point is only feature-specific, scoring-specific, or oracle-specific, mark it as `not_absorbed`.

Start Phase 2 now.
