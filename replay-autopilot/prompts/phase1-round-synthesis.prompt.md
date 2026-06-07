你现在执行 Phase 1 strict blind 的收口汇总。只根据本轮 blind 产物、slice 结果、worktree diff 和测试证据生成 ROUND_RESULT.md，不读取 oracle。

【固定上下文】
- 主仓库: {{PROJECT_ROOT}}
- feature_name: {{FEATURE_NAME}}
- requirement_source: {{REQUIREMENT_SOURCE}}
- oracle identity: redacted in Phase 1; direct oracle refs are forbidden
- base commit: {{BASE_COMMIT}}
- replay root: {{REPLAY_ROOT}}
- isolated worktree: {{WORKTREE}}
- neutral baseline index: {{BASELINE_INDEX}}
- context manifest: {{CONTEXT_MANIFEST}}
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}
- max slices: {{MAX_SLICES}}
- slice progress json: {{SLICE_PROGRESS}}
- slice progress md: {{SLICE_PROGRESS_MD}}
- requirement family ledger: {{REQUIREMENT_FAMILY_LEDGER}}
- requirement family cap: {{REQUIREMENT_FAMILY_CAP}}
- runner enforcement contract: {{RUNNER_ENFORCEMENT_CONTRACT}}
- slice results:
{{SLICE_RESULTS}}
- slice verifies:
{{SLICE_VERIFIES}}
- ROUND_RESULT target: {{ROUND_RESULT}}

HARD CAP OVERRIDE:
- Read REQUIREMENT_FAMILY_CAP.md and FAMILY_ROUTER_AND_CAP.json if present.
- verification_capped_coverage MUST equal min(sum adjusted_coverage_delta, coverage_cap_from_ledger).
- If final_pass_allowed=false or any required family remains OPEN/PARTIAL, final status cannot be PASS and coverage cannot be >=90.
- Do not use the final slice coverage_cap as the round cap; the family ledger cap is the authoritative cap source.

【允许读取】
1. requirement_source。
2. repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml。
3. isolated worktree 当前代码和 git diff/status。
4. 本轮 Phase 0/0.5 产物。
5. 本轮 SLICE_RESULT_*.json、SLICE_VERIFY_*.json、SLICE_PROGRESS.*。
6. FAMILY_CONTRACT.json、REQUIREMENT_FAMILY_LEDGER.json、REQUIREMENT_FAMILY_CAP.md 与 RUNNER_ENFORCEMENT_CONTRACT.md。
7. BASELINE_INDEX.md 只能作为中性结构索引。

【禁止】
- 禁止读取 oracle branch/commit/diff、历史实现、旧 replay、历史会话总结、FINAL_REPLAY_REPORT。
- 禁止继续实现或修改生产/测试代码。
- 禁止输出 oracle_adjusted_coverage。

【汇总要求】
ROUND_RESULT.md 必须写到 `{{ROUND_RESULT}}`，并包含：
- replay root / worktree / base commit
- oracle_used=false
- forbidden_source_check
- plan_files_used
- slice execution ledger
- slice verification ledger
- implemented files / changed files
- tests run with commands and results
- Expected Diff Closure Ledger
- exact contract ledger
- side-effect ledger
- executable surface slice ledger
- requirement family closure ledger
- family contract closure ledger
- runner enforcement contract result
- tracer_bullet_only 判定
- gap flags
- blind_self_assessed_coverage
- verification_capped_coverage
- coverage cap reason
- final status: PASS / PARTIAL / BLOCKED / INVALID_REPLAY
- gap root cause: requirement / design / implementation / test / verification / workflow gate

【评分纪律】
- 只有入口 hook、负向隔离、placeholder service 或 mock-only 断言时，verification_capped_coverage 不得超过 40。
- 缺真实入口测试不得报 90。
- 缺 stateful side-effect ledger 不得超过 60。
- 缺 DB/事务或等效事务深度验证不得超过 70。
- 高权重 deploy-facing surface 没有可执行最小切片，不得报 90。
- static-only / helper-only / blocker-only 不能计 DONE。
- REQUIREMENT_FAMILY_LEDGER 中仍有高权重 required family 为 OPEN/PARTIAL 时，必须按 REQUIREMENT_FAMILY_CAP.md 降分。
- 如果存在 no_progress_slice，必须计入 workflow gate root cause，且对应 slice 的 coverage_delta 不得贡献高分。
- 如果任一 `SLICE_VERIFY_*.json` 写明 `authorized_for_next_slice=false` 或 `authorized_for_synthesis=false`，必须在 `ROUND_RESULT.md` 写 `tooling_authorization_stop`，不得把该 slice 计为正向可交付覆盖。
- Family closure 只能来自 `authorized_for_synthesis=true` 且 `required_proof_type` 与 `actual_proof_type` 匹配的 slice；`proof_type_mismatch_families` 非空时必须保留对应 family 为 OPEN/PARTIAL。
- `blind_self_assessed_coverage` 也必须诚实受 family ledger cap 和 authorization 信号约束。若存在 `wrong_test_surface`、`core_entry_unclosed`、`side_effect_ledger_gap`、`non_authorizing_evidence`、`authorized_for_synthesis=false`、`final_pass_allowed=false` 或 required family OPEN/PARTIAL，blind 自评不得写成 90+；它必须不高于 `coverage_cap_from_ledger`，并写出 `self_assessment_honesty_override`。

开始生成 ROUND_RESULT.md。
