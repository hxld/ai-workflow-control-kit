# Replay Report Template

用于 `replay-eval` / skill-audit 场景。普通 delivery 不默认使用本模板。

## ROUND_RESULT Template

```markdown
# ROUND_RESULT

## Metadata

- round_id:
- mode:
- status: PASS / PARTIAL / BLOCKED
- baseline:
- oracle_used: false
- context_contamination_risk: true / false
- source_of_truth:
- worktree:

## Changed Files

- production:
- tests:
- docs:
- generated/local:

## Verification Commands

| command | exit | result | blocker_class |
| --- | ---: | --- | --- |
| | | | |

## Requirement Coverage Ledger

| requirement | result | evidence | coverage cap |
| --- | --- | --- | --- |
| | DONE / PARTIAL / BLOCKED / OUT_OF_SCOPE_CONFIRMED | | |

## Expected Diff Closure Ledger

| expected surface | closure | evidence |
| --- | --- | --- |
| | changed+tested / changed+static_only+cap / deferred+reason+coverage_cap / blocker | |

## Weighted Coverage

| area | weight | blind score | verification-capped score | rationale |
| --- | ---: | ---: | ---: | --- |
| | | | | |

- blind_self_assessed_coverage:
- verification_capped_coverage:
- 90_percent_met_before_oracle:

## Flags

- oracle_used:
- context_contamination_risk:
- small_green_false_positive:
- helper_only_surface_gap:
- static_only_core_path:
- mock_behavior_gap:
- expected_diff_unclosed:
- real_entry_gap:
- nonblocking_feature_gap:
- behavior_test_blocker:
- test_runtime_blocker:

## Known Gaps

- 

## Oracle Post-Hoc

Only append after the initial blind result exists.

- oracle_used_after_initial_result:
- oracle_diff_commands:
- oracle_diff_shape:
- oracle_adjusted_coverage:
- 90_percent_met_after_oracle:

| area | blind closure | oracle-adjusted finding |
| --- | --- | --- |
| | | |
```

## FINAL_REPLAY_REPORT Template

```markdown
# Final Replay Report

## Metadata

- replay_root:
- baseline:
- oracle:
- requirement_source:
- mode:

## Execution Summary

| round | exit | contract | result | blind capped coverage | oracle-adjusted coverage | 90% met |
| --- | ---: | --- | --- | ---: | ---: | --- |
| | | yes/no | yes/no | | | |

## Verification Summary

| round | passing verification | blocking verification | notes |
| --- | --- | --- | --- |
| | | | |

## Key Findings

- 

## Coverage Cap Analysis

| cap | affected rounds | reason |
| --- | --- | --- |
| no real entry test | | |
| nonblocking feature gap | | |
| payload contract unverified | | |
| report/frontend unverified | | |
| helper/static-only evidence | | |

## Workflow Findings

- delivery/replay boundary:
- source isolation:
- contract quality:
- verification quality:
- oracle post-hoc quality:
- promotion recommendation:

## Final Assessment

- 90_percent_met:
- best_round:
- practical_ceiling:
- next_replay_contract:
```

## Scoring Rules

| Evidence | Meaning |
| --- | --- |
| `changed+tested` | Behavior is implemented and verified by an assertion at the right entry level. |
| `changed+static_only+cap` | Code exists and compiles/static guards pass, but runtime behavior is not proven. |
| `helper_only_surface_gap` | Tests cover helper logic but not the real entry/carrier path. |
| `static_only_core_path` | Core workflow lacks a real entry, DB, transaction, browser, or external contract test. |
| `nonblocking_feature_gap` | Failure may not block the main flow, but the feature itself is still missing. |
| `small_green_false_positive` | Green tests passed but did not cover high-weight or explicit contract surfaces. |

Do not average away hard caps. If a cap says the result cannot exceed a threshold, the final score must respect that threshold even when the weighted table sums higher.

