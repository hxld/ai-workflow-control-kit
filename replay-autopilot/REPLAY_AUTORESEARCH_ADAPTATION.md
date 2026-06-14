# Replay Autoresearch Adaptation

Date: 2026-06-11

## Source

- External reference: https://github.com/karpathy/autoresearch
- Relevant files inspected:
  - `README.md`
  - `program.md`
  - `prepare.py`
  - `train.py`

## What Matters

`autoresearch` is useful here because it is not a large framework. Its effective control pattern is small:

1. One fixed evaluation harness that agents must not modify.
2. One narrow editable surface for each experiment.
3. One fixed metric.
4. One compact experiment ledger.
5. Keep/discard/crash decisions after each run.
6. Redirect noisy execution logs and only parse the metric summary.
7. Continue autonomously, but treat repeated non-improvement as an experiment-design problem, not as permission to replay blindly.

## Mapping To Replay Autopilot

| autoresearch pattern | replay-autopilot mapping | Current state |
|---|---|---|
| `prepare.py` is fixed evaluator | `Verify-PlanContract.ps1`, schema gates, slice closure verifiers | Already fixed; do not weaken |
| `train.py` is the only agent-edited file | replay worktree and allowed replay artifacts per phase | Partially present; Plan repair still edits multiple artifacts |
| `val_bpb` is the single metric | `verification_capped_coverage`, stage, `ROUND_RESULT.md` existence | Present but scattered |
| `results.tsv` records every attempt | `_control/REPLAY_EXPERIMENT_LEDGER.tsv/json/md` | Added in this pass |
| keep/discard/crash | keep if verification cap improves, discard if no round/no improvement, crash on executor/build failure | Added in this pass |
| no tee / parse summary only | artifact-only ledger scan, no git/worktree shelling | Added after fixing timeout |
| if stuck, change experiment design | stopline + focused tooling change before next r20 | Present; needs stricter next-experiment selection |

## Implemented In This Pass

Added:

- `scripts/Write-ReplayExperimentLedger.ps1`
  - Generates:
    - `_control/REPLAY_EXPERIMENT_LEDGER.json`
    - `_control/REPLAY_EXPERIMENT_LEDGER.tsv`
    - `_control/REPLAY_EXPERIMENT_LEDGER.md`
  - Uses round-number ordering, not directory timestamp ordering.
  - Reads only replay artifacts and `WORKTREE_HEAD_AUDIT.json`.
  - Does not shell into historical worktrees with `git`.
  - Ignores cross-round `RUN_CONTROL_SUMMARY.json` for per-root fingerprints to avoid stale blocker pollution.

- `scripts/Test-v484-ReplayExperimentLedger.ps1`
  - Covers baseline keep, PlanContract discard, metric regression discard, improvement keep, crash, audit head extraction, and stale RUN_CONTROL history isolation.

- `scripts/Run-ReplayLoop.ps1`
  - Refreshes replay experiment ledger before stopline and during final control sync.

Generated current policy replay ledger:

- `<REPLAY_EVIDENCE_ROOT>\policy-num-rebuild-bugfix\_control\REPLAY_EXPERIMENT_LEDGER.json`
- `<REPLAY_EVIDENCE_ROOT>\policy-num-rebuild-bugfix\_control\REPLAY_EXPERIMENT_LEDGER.tsv`
- `<REPLAY_EVIDENCE_ROOT>\policy-num-rebuild-bugfix\_control\REPLAY_EXPERIMENT_LEDGER.md`

Latest row after regeneration:

```text
round=19
status=discard
status_reason=no_round_result
stage=PlanContract
verification_capped_coverage=0
fingerprints=low_verification_cap,plan_format_drift
description=policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.RequestBuildFunction; policy_rebuild_plan_invalid:fixed_db_caseid
```

## What This Changes Operationally

Before continuing replay, read the ledger first:

```powershell
$ledgerPath = Join-Path $env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT 'policy-num-rebuild-bugfix\_control\REPLAY_EXPERIMENT_LEDGER.tsv'
Import-Csv -LiteralPath $ledgerPath -Delimiter "`t" |
  Select-Object -Last 5
```

The next replay should be treated as a new experiment only if the intervention changes the failed experiment design. For the current r20 candidate, the design change is:

1. PlanContract repair prompt now preserves Markdown backticks.
2. PlanContract repair prompt now requires exact `AiClaimDataAssemblyHelper.RequestBuildFunction`.
3. PlanContract repair prompt now requires removing fixed numeric caseId examples such as `12345L`.
4. The ledger will classify r20 as keep only if it reaches Phase 1 with improved verification evidence; otherwise it will be discard/crash with a compact reason.

## Next Improvements Not Yet Implemented

1. Add a `NEXT_EXPERIMENT_PLAN.json` gate before creating a new round.
   - It should declare one hypothesis, one intervention, expected failed fingerprint removal, and expected metric movement.
   - Stopline should block if the next run has no new hypothesis after three discards.

2. Make PlanContract repair single-surface where possible.
   - Today repair can edit eight artifacts.
   - A stricter mode could repair only the failing artifact family first, rerun verifier, then expand if needed.

3. Add bounded log parsing for Claude/Codex execution logs.
   - The ledger should ingest only final status lines and tail snippets, not large logs.

4. Add "complexity tax" to tooling evolution.
   - `autoresearch` explicitly values simpler changes when metrics tie.
   - Replay tooling should mark broad prompt growth without metric improvement as discard unless it removes repeated failures.

5. Add cross-run idea bank.
   - Near-miss fixes should be recorded as candidates.
   - Discarded ideas should not be retried without a changed premise.

## Go / No-Go For r20

GO, with one condition: r20 must be run after the ledger and v482/v483/v484 tests pass.

Expected r20 pass signal:

- `PLAN_SCHEMA_FAILFAST.json`: PASS
- `TEST_INFRASTRUCTURE_DRY_RUN.json`: claim-server `-am test-compile` success
- `PLAN_CONTRACT_VERIFY.json`: no `policy_rebuild_plan_missing:AiClaimDataAssemblyHelper.RequestBuildFunction`
- `PLAN_CONTRACT_VERIFY.json`: no `policy_rebuild_plan_invalid:fixed_db_caseid`
- `ROUND_RESULT.md` exists or a new concrete blocker is logged

If r20 stops at the same two PlanContract issues, do not run r21 directly. Add `NEXT_EXPERIMENT_PLAN.json` gating first.
