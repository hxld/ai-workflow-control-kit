# Deep Replay Review Prompt

You are reviewing replay workflow failures. Do not continue implementation and do not rescore oracle from source. Your job is to do a ten-lens meta-review and identify why automatic evolution did or did not improve real delivery coverage.

## Inputs

- current_replay_root: `{{REPLAY_ROOT}}`
- stop_loss_decision: `{{STOP_LOSS_DECISION}}`
- review_roots:
{{REVIEW_ROOTS}}

## Allowed Reads

For each review root, read only these files if they exist:

- `AUTOPILOT_SUMMARY.md`
- `AUTOPILOT_DECISION.md`
- `FINAL_REPLAY_REPORT.md`
- `EVOLUTION_PROPOSAL.md`
- `ROUND_RESULT.md`
- `STOP_LOSS_DECISION.md`
- `STOP_LOSS_DECISION.json`
- `REQUIREMENT_FAMILY_LEDGER.json`
- `WORKTREE_HEAD_AUDIT.json`
- `ORACLE_COVERAGE_ENFORCEMENT.md`
- `SLICE_VERIFY_*.json`
- `SLICE_RESULT_*.json`

You may also read `{{STOP_LOSS_DECISION}}`.

## Forbidden Reads

- Do not read replay worktree source code, tests, diffs, or full logs.
- Do not read oracle branch / oracle commit source code or diff.
- Do not read historical chat transcripts.
- Do not modify production code, tests, skill source, or scripts.

Report files may contain oracle post-hoc conclusions; those are allowed inputs. Review them as reported evidence, not as authorization to inspect oracle source.

## Worktree Head Evidence Rule

Do not infer the replay's initial baseline from the worktree's current HEAD after Phase 2. Phase 2 may temporarily inspect oracle and leave the worktree on a different commit.

Use `WORKTREE_HEAD_AUDIT.json` when available:
- `initial_after_start_replay_round` is the baseline evidence.
- `post_phase1` is the implementation-stage evidence.
- `pre_phase2` / `post_phase2` are Phase 2 mutation evidence.

If the audit file is missing, mark initial HEAD as `unknown`; do not claim oracle contamination from final current HEAD alone.

## Required Output Files

Write these files into the current replay root:

1. `DEEP_REVIEW_REPORT.md`
2. `ROOT_CAUSE_LEDGER.json`
3. `NEXT_EXPERIMENT_PLAN.md`
4. `STOP_OR_CONTINUE_DECISION.md`

## Ten-Lens Review

In `DEEP_REVIEW_REPORT.md`, review these lenses. Each lens must include evidence, judgment, and the concrete gate/script/prompt to change:

1. Metrics lens: whether blind / capped / oracle scores diverge and whether real progress exists.
2. Objective lens: whether optimization is rewarding "writing more" instead of closing real carriers.
3. Carrier lens: whether the agent invents substitute carrier/service/DTO instead of using existing production carriers.
4. Plan lens: whether plan artifacts bind exact contract, real entry, side effects, and executable evidence.
5. Slice lens: whether slices follow high-weight business flow or easy helper/static surfaces.
6. Verifier lens: whether verifier blocks synthetic carriers, static-only green, and test-only closure.
7. Test lens: whether tests prove real entry, transaction/side effects, export/page/async behavior instead of replay-only abstractions.
8. Token/cost lens: which exploration can be compressed through `example-system-context`, baseline index, or reusable plan contracts.
9. Generalization lens: whether the improvement is cross-project and not feature-specific.
10. Next experiment lens: at most 3 falsifiable next-round hypotheses and their success/rollback metrics.

## ROOT_CAUSE_LEDGER.json Schema

Write a JSON object with at least:

```json
{
  "version": 1,
  "current_replay_root": "",
  "reviewed_roots": [],
  "root_causes": [
    {
      "id": "RC1",
      "category": "objective|planning|carrier|verification|testing|token|generalization",
      "evidence": [],
      "impact": "high|medium|low",
      "recurrence_count": 0,
      "workflow_change": ""
    }
  ],
  "blocked_patterns": [],
  "success_metrics": []
}
```

## NEXT_EXPERIMENT_PLAN.md

Propose at most 3 next experiments. Each must include:

- hypothesis
- script_change
- prompt_change
- expected_metric_delta
- validation_command
- rollback_condition

Do not propose vague changes such as "be stricter" or "add tests" unless they map to a specific script, prompt, or verifier.

## STOP_OR_CONTINUE_DECISION.md

Must include:

- decision: `STOP_AND_EVOLVE` or `CONTINUE_REPLAY`
- reason
- allowed_next_action
- max_next_rounds_before_next_stoploss

If oracle remains below 90 and stop-loss triggered, default to `STOP_AND_EVOLVE`.
