你现在要执行 replay 后的技能进化，但必须严格受控。

【输入】
- replay root: {{REPLAY_ROOT}}
- evolution proposal: {{EVOLUTION_PROPOSAL}}
- verifiable rules: {{VERIFIABLE_RULES}}
- skill source root: {{SKILL_SOURCE_ROOT}}
- replay autopilot root: {{AUTOPILOT_ROOT}}
- knowledge repo: {{KNOWLEDGE_REPO}}
- project root: {{PROJECT_ROOT}}
- current knowledge version: {{CURRENT_KNOWLEDGE_VERSION}}
- expected next knowledge version: {{EXPECTED_KNOWLEDGE_VERSION}}

【硬边界】
1. 只允许吸收可跨项目复用的工作流门禁、路由、验证纪律或报告格式。
2. 禁止把业务项目路径、表名、类名、oracle 文件名、commit、replay root 写进通用技能正文。
3. 禁止修改 {{PROJECT_ROOT}} 的生产代码、测试或业务文档。
4. 修改技能时只改 canonical source：{{SKILL_SOURCE_ROOT}}。
5. 如果分类为 `tooling-evolution-needed`，或 replay root 中存在 `STOP_OR_CONTINUE_DECISION.md` 且决策包含 `STOP_AND_EVOLVE`，允许且优先修改 replay autopilot root 下的 scripts/prompts/contracts/tests：{{AUTOPILOT_ROOT}}。这类修改不是通用技能正文修改，但必须有最小回归测试。
6. 修改通用技能后必须同步到 knowledge repo 的 custom-skills-zh，并更新 custom-skills-guide.md、guide-sections/changelog.md、custom-skills-history；只修改 replay autopilot tooling 时，也必须在 knowledge repo 写 history/changelog 记录本次工具进化证据。
7. 必须执行：
   - source -> backup hash equality
   - project/external identity pollution scan
   - git diff --check
   - 当且仅当本轮存在真实 source/tooling/prompt/verifier/test 变更并通过验证时，commit and push knowledge repo current upstream branch
   - 如果本轮是 no-source-change / no-op / already-covered 审计，must not edit/commit/push knowledge repo，不能推进版本
8. 版本推进必须显式闭环：
   - 只有在本轮实际修改 canonical skill source，或实际修改并验证 replay autopilot runner/prompt/verifier/test 后，才能把知识库推进到 `{{EXPECTED_KNOWLEDGE_VERSION}}`，包括 `custom-skills-history/{{EXPECTED_KNOWLEDGE_VERSION}}-*.md`、changelog/guide 同步、commit/push。
   - 如果判定为 `already-covered-by-existing-gate` 且不改 canonical skill source / replay autopilot tooling，不得写 `{{EXPECTED_KNOWLEDGE_VERSION}}-*-noop-evolution.md`，不得更新 changelog / `CURRENT_VERSION.md`，不得 commit/push knowledge repo。必须写 `NO_VERSION_ADVANCE_REASON.md`，并让 `actual_knowledge_version_after_push` 保持真实当前版本。
   - 但如果存在 `STOP_AND_EVOLVE`、`NEXT_EXPERIMENT_PLAN.md`、或任何 gap 被归类为 `already-covered-but-not-enforced` / `tooling-evolution-needed`，禁止 no-op / no-source-change 版本推进；必须实际修改 {{AUTOPILOT_ROOT}} 的 runner/prompt/verifier/test，或写 `NO_VERSION_ADVANCE_REASON.md` / `EVOLUTION_RESULT.md` 标明 BLOCKED。
   - 如果证据不足或不应推进版本，必须在 replay root 写 `NO_VERSION_ADVANCE_REASON.md`，说明为什么不能推进到 `{{EXPECTED_KNOWLEDGE_VERSION}}`。
   - `NO_SOURCE_CHANGE`、`NO_SKILL_SOURCE_CHANGE`、`noop-evolution`、`no-source-change` 不能和 `VALIDATED_TOOLING_EVOLUTION`、`verification_results: PASS`、`actual_knowledge_version_after_push: {{EXPECTED_KNOWLEDGE_VERSION}}` 同时出现。

【任务】
1. 阅读 evolution proposal。
1.1 如果 `verifiable rules` 文件存在，必须阅读并逐条处理 `must_fix=true` 的 rule；成功结果必须在 `EVOLUTION_RESULT.md` 中明确引用对应 `machine_gate`、回归验证和下一步验证证据。
2. 先把每个 gap 归入 8 个产品化门禁之一：
   - Source-of-Truth Gate
   - Oracle Isolation Gate
   - Requirement Contract Gate
   - Surface Coverage Gate
   - Core-First Budget Gate
   - Executable Evidence Gate
   - Coverage Cap Gate
   - Evolution Abstraction Gate
3. 再将 gap 分类为：
   - already-covered-by-existing-gate
   - already-covered-but-not-enforced
   - workflow-gate-needs-evolution
   - tooling-evolution-needed
   - scoring-only-not-execution
   - project-specific-do-not-absorb
   - needs-more-replay-evidence
4. 如果 gap 已被现有 gate 覆盖，但 replay 仍重复出现，禁止直接 no-op；必须归为 `already-covered-but-not-enforced`，并优先进化 runner / prompt / verifier 的强制执行逻辑。
5. 只对 workflow-gate-needs-evolution 或 tooling-evolution-needed 做最小修改。
6. 禁止新增同义 gate 名称；若已有 gate 能承载，必须合并到已有门禁，不要继续叠加规则。
7. 如果 `STOP_AND_EVOLVE` 要求实现具体 experiments，必须先实现 experiments 或一个等价的可执行 enforcement，不允许只把 experiments 写成“下一步计划”。本轮 `EVOLUTION_RESULT.md` 必须说明这些 experiments 已经如何落到 tooling。
8. 不允许把不存在的 runner 文件、脚本语言或工具名当作已实现方案。先检查 `{{AUTOPILOT_ROOT}}\scripts`、`{{AUTOPILOT_ROOT}}\prompts`、`{{AUTOPILOT_ROOT}}\contracts` 的真实结构；默认优先修改现有 PowerShell runner/verifier/prompt/test。如果你提出新的 JS/Python/其他脚本，必须同时新增脚本、把它接入现有 runner，并补回归测试。
9. 如果 validation 要求 `tooling_changes_applied: true`，你必须实际修改 `{{AUTOPILOT_ROOT}}` 下的脚本、prompt、contract 或测试；只写“需要实现 / not implemented / blocked”不能作为成功的 `EVOLUTION_RESULT.md`。
10. 提交/推送失败时禁止写 `VALIDATED_TOOLING_EVOLUTION`。如果 git commit/push 被 hook、权限、冲突或环境阻止，必须写 `BLOCKED_NEEDS_EVIDENCE` 或 `NO_VERSION_ADVANCE_REASON.md`，并把 `actual_knowledge_version_after_push` 写成真实当前版本，不能写 expected 版本。
11. 修改 replay-autopilot 文件时，必须证明该文件被当前 runner/verifier 调用，或同时把它接入现有 runner 并补测试；禁止只修改未被调用的旁路脚本后声称 gate 生效。
12. `verification_results: PASS` 必须来自可复跑命令（测试、ValidateOnly、git diff --check、hash/pollution scan 等）；“manual review / 手工看过”不能作为唯一 PASS 证据。
13. 禁止把“runner should integrate / next steps: integrate these scripts / 后续接入 runner”写成成功状态。只要工具尚未接入当前 runner/verifier，本轮必须是 BLOCKED 或继续实现接入。
14. 如果新增脚本，必须同时在 `Run-ReplayLoop.ps1` / `Run-SliceLoop.ps1` / verifier / prompt 中出现真实调用链，并在 `EVOLUTION_RESULT.md` 写出调用入口；只被测试脚本调用不算 runner 生效。
15. `actual_knowledge_version_after_push` 必须和 knowledge repo 的 `CURRENT_VERSION.md` 真实版本一致；不能只写历史文件或 changelog 后声称版本已推进。
16. 输出技能进化报告，包含：
   - absorbed patterns
   - deliberately not absorbed
   - 8-gate mapping
   - changed files
   - eval evidence
   - verification result
   - pushed commit
   - current knowledge version
   - expected next knowledge version
   - actual knowledge version after push

如果 proposal 证据不足，不要强行进化；输出 BLOCKED/NEEDS_EVIDENCE。
 
Runner completion artifact:
- After commit/push, no-version decision, or BLOCKED/NEEDS_EVIDENCE handling is complete, write `{{REPLAY_ROOT}}\EVOLUTION_RESULT.md`.
- Include final_status, changed_files, verification_commands, verification_results, pushed_commit, current_knowledge_version, expected_knowledge_version, actual_knowledge_version_after_push.
- Also include these machine-readable lines exactly when `STOP_AND_EVOLVE` or `NEXT_EXPERIMENT_PLAN.md` exists:
  - `- final_status: VALIDATED_TOOLING_EVOLUTION` or `- final_status: BLOCKED_NEEDS_EVIDENCE`
  - `- tooling_changes_applied: true` only after actual {{AUTOPILOT_ROOT}} script/prompt/verifier/test changes
  - `- stop_and_evolve_satisfied: true` only after the required experiments or equivalent enforcement are implemented and validated
  - `- verification_results: PASS` only after regression/eval commands pass
  - `- changed_files: ...` must list actual changed replay-autopilot files, not only knowledge repo history files
  - `- closed_machine_gates: ...` must list machine_gate values from verifiable rules that were actually closed
  - `- pushed_commit: ...` must contain the pushed knowledge repo commit hash
  - `- actual_knowledge_version_after_push: {{EXPECTED_KNOWLEDGE_VERSION}}` must match the real latest knowledge version after push
- If no concrete source/tooling change is applied, write `NO_VERSION_ADVANCE_REASON.md` and `EVOLUTION_RESULT.md` with `- final_status: BLOCKED_NO_SOURCE_CHANGE`; do not edit/commit/push knowledge repo, and keep `actual_knowledge_version_after_push` equal to the real current version.
- Write this file only after the evolution side effects are complete, so the unattended runner can treat it as the completion signal.
