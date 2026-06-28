---
name: sync-progress
description: "Use when user says 同步进度, sync progress, 更新进度, 提交代码, 进度同步, code-change.md, final-state review, or after completing significant work"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep
---
# 进度同步
收口前核对代码、测试、文档、OpenSpec、进度和 Git 边界。
**专家角色：** 收口审查员。
**上游技能：** `deep-plan`, `dev-workflow`, `deep-review`, `gen-tests`, `add-comments`, `backend-effort-estimate`
**下游技能：** `ship-release`
## 何时使用

- 完成重要实现后。
- 用户要求同步进度、更新文档、准备提交、生成 code-change。
- 发布或 PR 前。
## 何时不使用

- 还在需求/设计阶段。
- 测试失败尚未排查。
- 用户明确只要局部代码修改且不收口。
## Iron Law

没有完整验证和 final completeness gate，不得进入提交、推送或“已完成”表述。
`planned-dev`、`hotfix`、`tooling` 收口时必须给出 `.doc` / `openspec` / `.memory` 三路同步账本；缺少应更新项且没有明确 `not_applicable` 原因时，状态最高只能是 `PARTIAL`。
任何完成态声明都必须能被 Proof Ledger 和 Final Completeness Gate 反查。若本轮出现用户纠错、返工或“之前说完成但实际未完成”的信号，还必须给出纠错闭环账本；缺失时不得提交、推送或宣称完成。

## Short Close-out Model

`sync-progress` 是收口技能，不负责重新规划整条工作流。先识别本轮 mode，再选择收口深度：

| Mode | 收口重点 |
|------|----------|
| `planned-dev` | Proof Ledger、覆盖账本、文档/规格同步、完整验证、Final Completeness Gate、提交边界 |
| `hotfix` | 原证据/RED、最小修复 diff、原失败阶段复验、must-not 反向断言、剩余风险 |
| `debug-only` | 已确认事实、高置信推断、证据缺口、可复跑查询、是否升级修复 |
| `review-only` | findings、影响范围、验证缺口、是否需要后续修复，不写完成态 |
| `tooling` | canonical source、backup mirror、changelog、smoke/eval、污染扫描、回滚路径 |

行为或共享工作流发生变化时，默认要做短收口：`final effective diff -> proof/verification -> open gaps -> sync/changelog need -> next action`。不要把临时日志、缓存、截图、索引或工具输出混进有效交付。

只读模式不强制 Proof Ledger：

```markdown
debug-only: 查询入口 / 已确认 / 高置信推断 / 证据缺口 / 是否升级
review-only: findings / severity / evidence / verification gap / follow-up
```

只有 `planned-dev`、`hotfix` 和 `tooling` 需要 Proof Ledger 或等效完成证据。

## Review Tier Closure Ledger

收口前必须消费 `workflow-router` 或当前任务事实推导出的 `review_tier`。缺少显式 tier 时按风险补判，不能用未声明规避审查。

```markdown
| review tier | trigger evidence | review lenses executed | counter-evidence checked | same-symptom branches | unresolved gaps | final cap |
|-------------|------------------|------------------------|--------------------------|-----------------------|-----------------|-----------|
```

规则：

- `L0/L1`：可用轻量自检，写明验证范围即可。
- `L2`：生产结论、热修、修数、缓存、外部接口或跨组件归因必须至少有证据链、同症状分支矩阵或反证检查；缺失时最终状态最高 `PARTIAL`。
- `L3`：发布、批量数据影响、资金/状态推进、用户纠错后继续、曾提前完成或多 surface review pressure，必须有 `deep-review` 多镜头或等效审查账本；缺失时不得提交、推送或宣称完成。
- `same-symptom branches` 不能只写“无”；必须说明查过哪些入口、配置、缓存、异步、下游或展示分支，或写 `not_applicable:<reason>`。

## Review Independence Disclosure

当本轮存在多轮审查、第二视角、子 agent、Codex 线程隔离或外部 reviewer 信号时，按 `references/review-independence-disclosure.md` 填写 `Review Independence`，避免把同一上下文多镜头误写成外部独立复核。

最低门禁：`single_context_lens` 只能披露为 `same_context_lens`；未被主会话复核的隔离线程、子 agent 或外部结果不得支撑 `DONE`；没有真实外部 reviewer 时必须写 `external model used=no`。

## Subagent Intake Ledger

`sync-progress` 只消费子 agent 结果，不负责派遣。若本轮使用过子 agent，收口必须把结果并入主会话证据账本：

```markdown
| subagent result | accepted rows | rejected rows | main verification | final status impact |
|-----------------|---------------|---------------|-------------------|---------------------|
```

子 agent 输出不能单独支撑 `DONE`、提交、发布或“验证通过”。未被主会话复核的 P0/P1、核心事实、需求 literal、DB/API/wire contract 和测试证据必须降为 `verification_gap`；若这些缺口影响核心交付，最终状态最高只能是 `PARTIAL` 或 `BLOCKED`。

## Ignore / Ownership Gate

`.doc/`、`openspec/`、`.memory/` 命中 ignore 时：

- 不得默认 `git add -f`。
- 必须说明是本地真值同步还是 Git 交付物。
- SQL、DDL、配置、发布脚本先确认 ownership。

## Tooling / Base Close-out Gate

当本轮修改的是通用研发工作流基座、技能、hook、模板、治理文件或备份镜像时，收口账本必须包含：

- canonical source：实际修改的源文件，禁止只改镜像或宿主副本。
- backup mirror：是否已同步；未同步必须给 blocker 或 `not_applicable:<reason>`。
- changelog：工作流行为、触发、门禁、输出格式或同步规则变化必须记录；纯备份同步可写 `no_change:<reason>`。
- project-neutrality：确认没有项目名、仓库绝对路径、业务类名、表名、固定业务文案、事故原文或团队专属命令进入通用正文。
- adapter boundary：宿主、CLI、session、云服务或公司流程依赖只能作为 adapter/reference，不得变成 core base 的运行时前提。
- rollback path：列出回滚源文件或镜像同步方式。

缺 canonical source、backup mirror、changelog 判断或污染扫描时，`tooling` 收口最高只能是 `PARTIAL`。

## Phase 1: 变更盘点

记录：

- `git status`
- `git diff --name-only`
- ignored 本地文档是否变更
- 是否有未讨论的额外文件
- 新增文件属于 effective diff 还是 generated artifacts
- Generated Artifact Ledger：`path -> source -> generated/effective -> keep/delete -> commit/no-commit`
- 原型、临时 harness、调试脚本是否已删除、吸收或标记为 generated/debug artifact
- Scope 分类：范围内、前端-only、已有需证据、待确认、支撑工具、无关漂移
- Phase State Ledger：长任务或多 slice 时，收集 `.doc/<feature>/phase-state.md`、已有 `.artifacts/phase-state.md` 或任务文档中的 phase checkpoint；对比 final diff/test 状态，缺失或不一致时标 `resume_state_gap`，整体最高 `PARTIAL`

## Expected Diff Closure Ledger

大需求、自主实现、replay/eval 或多 surface 收口时，必须把计划中的 Expected Diff Matrix 转成闭环账本：

```markdown
| expected file family | requirement/slice | actual diff status | verification | closure status | coverage effect |
|----------------------|-------------------|--------------------|--------------|----------------|-----------------|
```

`closure status` 只能是：`changed+tested`、`changed+static_only+cap`、`deferred+reason+coverage_cap`、`blocker`、`out_of_scope_confirmed`。

需求明确点名的主入口、图片/附件、报表/导出、异步/自动流转、外部协议等文件族若缺少闭环行，整体状态最多 `PARTIAL`；若它们属于 core_path，90% 自主覆盖自动判定 `not met`。

## Test Design Closure Ledger

非平凡 `planned-dev`、多 surface、状态流转、外部接口、报表/导出、前端可见面、异步或 must-not 需求收口时，必须把 `deep-plan` 产出的 Test Design Control 转成测试闭环账本：

```markdown
| test design row | target/surface | planned risk/depth | executed evidence | coverage status | gap/action |
|-----------------|----------------|--------------------|-------------------|-----------------|------------|
```

`coverage status` 只能是：`covered`、`partial`、`blocked:<reason>`、`not_applicable:<reason>`。

如果 `gen-tests` 没有消费 Test Design Control，或覆盖矩阵缺少高风险 surface / must-not / 副作用行，整体状态最多 `PARTIAL`，不得进入“完成 / 可提交”表述。

## Diff Role Matrix

大需求、历史对比、replay/oracle 对比或 final diff 收口时，实际 diff 必须按角色分类：

```markdown
| file family | role | reason | verification | commit/include |
|-------------|------|--------|--------------|----------------|
```

角色枚举：`effective_business_diff`、`supporting_infrastructure`、`frontend_or_external_surface`、`release_config_or_sql`、`local_docs_or_generated_artifacts`、`unrelated_drift`。

`supporting_infrastructure` 必须说明服务于哪个 requirement/slice；`release_config_or_sql` 先确认 ownership；`unrelated_drift` 不得进入完成态。

## Phase 2: 文档 / OpenSpec / 记忆三路同步

先定位当前 feature/change；若无法定位，必须输出缺口，状态最高只能是 `PARTIAL`。三路同步账本每行只允许：
`updated`、`no_change:<reason>`、`missing_blocked:<reason>`、`not_applicable:<reason>`。

| target | required when | action |
|--------|---------------|--------|
| `.doc/<feature>/tech-design.md` | 设计、接口契约、字段来源、风险或实现边界变化 | 回写最终决策、Test Design Control 消费结果、验证计划和偏差原因 |
| `.doc/<feature>/task_plan.md` | 任务状态、剩余项、阻塞项变化 | 勾选或更新任务状态，不保留过期 TODO |
| `.doc/<feature>/code-change.md` | 有代码、测试、SQL、配置或交付文档有效变更 | 写 final-state review：最终范围、关键代码/SQL、验证结果、未覆盖项 |
| `openspec/changes/<change>/proposal.md` / `tasks.md` / specs | 需求、契约、验收任务或实现状态变化 | 更新 proposal/spec 口径并勾选 tasks；不能只更新 `.doc` |
| 仓库约定的 ADR/决策记录/范围记录 | 决策反悔成本高、看代码会意外、存在真实取舍，或明确拒绝/暂缓某类需求 | 记录决策、理由、替代方案或 out-of-scope 原因；没有仓库约定时写入当前 feature 文档 |
| `.memory/progress.md` | 完成重要阶段、收口、阻塞或工作流治理 | 追加会话级进度 |
| `.memory/findings.md` | 产生可复用项目模式或稳定技术发现 | 追加抽象发现，不写一次性流水账 |
| `.memory/skill-feedback.md` | 暴露技能、路由、门禁或收口缺陷 | 记录缺陷、改进点和下沉位置 |

`code-change.md` 默认 final-state review，不默认展开 commit-by-commit。若 `.doc/`、`openspec/` 或 `.memory/` 被 ignore，仍按本地真值同步，但不得默认 `git add -f`。

## Proof Ledger

`planned-dev`、`hotfix`、`tooling` 收口报告必须把“为什么算完成”压缩成可核对证据表：

```markdown
| requirement/slice | source_ref | code/doc location | verification command/result | lossy/disclosure | status |
|-------------------|------------|-------------------|-----------------------------|------------------|--------|
```

`status=DONE` 不能只依赖局部编译、局部单测或“代码已改”。涉及 UI、表单、下拉、错误提示、接口出参、数据来源、落库、导出或异步副作用时，Proof Ledger 必须包含可见 surface 证据；未跑通真实入口时，在 `lossy/disclosure` 写明 `not_run`、原因和剩余风险。

小需求至少 1 行；大需求按 capability slice 分行。没有 `source_ref`、落点或验证结果的行不能标 `DONE`。若证据来自摘要、跨工具转换、会话恢复、自动记忆或压缩上下文，必须在 `lossy/disclosure` 写明丢失、推断或未验证部分；`debug-only` / `review-only` 使用上方只读模板，不伪造完成态。

## Planning Brainstorm Trace Ledger

非平凡 `planned-dev`、review pressure、自主实现、用户已纠偏、多 surface 或高返工成本任一命中时，收口必须反查 `deep-plan` / `tech-design.md` 中的 Planning Brainstorm Matrix：

```markdown
| PB id | chosen decision | rejected option | implemented evidence | validation assertion | final status |
|-------|-----------------|-----------------|----------------------|----------------------|--------------|
```

规则：

- 每行必须引用 `PB-xx`；没有稳定 ID 或 ID 无法追到 `tech-design.md` / 测试 / review finding 时，标记 `brainstorm_trace_gap`。
- `chosen decision` 没有代码/文档落点，或 `validation assertion` 没有进入测试/静态验证/明确 blocker，整体最高 `PARTIAL`。
- `rejected option` 为空且该需求存在真实替代落点、数据源、状态入口或副作用时，标记 `brainstorm_formalism_gap`。
- Planning Brainstorm Matrix 缺失且没有合法 `skip_reason` 时，整体 `Implementation Readiness` 不能从收口阶段补成 `DONE`；必须回到 `deep-plan`。
- `skip_reason` 只接受 `typo_or_comment_only`、`pure_formatting_no_behavior`、`generated_sync_no_behavior`、`single_file_mechanical_rename_with_static_guard`、`no_requirement_decision_surface`；其他理由标记 `invalid_brainstorm_skip`。
- `code-change.md` / final-state review 应保留关键取舍、被拒方案理由和验证结果，不能只写最终改了哪些文件。

## Decision / Scope Memory Ledger

收口时若本轮产生长期有效的拒绝、暂缓、边界或架构取舍，必须判断是否沉淀：

```markdown
| decision/scope item | keep where | source_ref | confidence | last_verified | future trigger | status |
|---------------------|------------|------------|------------|---------------|----------------|--------|
```

沉淀条件：以后反悔成本高、只看代码会意外、真实比较过替代方案，或未来很可能再次被问到同一 rejected/deferred scope。临时“不做”不沉淀；自动记忆、会话摘要或跨工具转换内容默认 `candidate`，必须复核后才能标 `verified`；已沉淀的范围结论要在后续需求对齐时先读取，避免重复争论。

## Weighted Coverage Ledger

当本轮目标包含“自主实现 / 少问 / 覆盖 90%+”时，收口报告必须用覆盖账本声明是否达标：

```markdown
| requirement/slice | priority | weight | implementation status | verification | counted coverage | gap reason |
|-------------------|----------|--------|-----------------------|--------------|------------------|------------|
```

规则：

- `core_path` 权重大于 `supporting_surface`；核心主链未完成时，整体状态最多 `PARTIAL`。
- `DONE` 必须同时有代码落点和验证证据；只有代码无验证只能是 `PARTIAL`。
- `DEFERRED`、`frontend_or_external`、`out_of_scope` 不计入 90% 分子；若它们影响核心主链，整体必须 `BLOCKED` 或 `PARTIAL`。
- 最终声明必须包含：`Autonomous implementation target >=90%: met / not met / not applicable`。

覆盖率封顶规则：

- core_path 只有 static guard、没有行为断言或可执行契约测试时，整体 verification-capped coverage 最高 45%。
- core_path 有局部行为测试但缺状态/持久化/消息/导出等关键副作用验证时，整体最高 60%。
- deploy-facing contract 仍是 assumption 时，相关 slice 最高 `PARTIAL`，不得计入 `DONE`。
- helper-only surface 未被真实入口引用时，相关 surface counted coverage 最高 30%，并标记 `helper_only_surface_gap`。
- must-not 行为缺反向断言时，相关 slice 不能 `DONE`。
- core_path 只有自建 service/mock-only GREEN、未证明真实入口或真实承载点时，整体 verification-capped coverage 最高 35%，并标记 `mock_behavior_gap`。
- core_path 只有入口 hook、负向隔离、placeholder service 或第一条 tracer bullet，尚未证明 stateful success path 与关键副作用时，整体 verification-capped coverage 最高 40%，并标记 `tracer_bullet_only + side_effect_ledger_gap`。
- Expected Diff Closure Ledger 中高权重文件族为 `deferred+reason+coverage_cap` 或 `blocker` 时，相关 slice 不得计入 `DONE`；缺闭环行时整体最多 `PARTIAL`。
- “失败不阻断”后处理如果只验证不阻断、未验证功能被触发，相关 slice 不得 `DONE`，并标记 `nonblocking_feature_gap`。

自主实现或 replay 报告建议同时列出：

```markdown
| coverage view | score | basis |
|---------------|-------|-------|
| self-assessed | | 实现者自评 |
| verification-capped | | 按测试/入口/契约证据封顶 |
| oracle-adjusted | | 仅后验 oracle/eval 使用 |
```

## Phase 3: 验证门

必须形成：

| 项目 | 必填 |
|------|------|
| 验证命令 | 实际执行命令 |
| 验证范围 | 文件 / 模块 / workspace / 全仓库 |
| 原失败阶段 | resolve / compile / testCompile / test / package / none |
| 复验结果 | passed / failed / not-run |
| runner 退出码 | 0 / non-zero / unknown |
| 成功后运行态噪音 | none / `runtime_noise_with_success` + 摘要 |

原失败阶段未复验通过 = `BLOCKED`。只有局部测试 = `PARTIAL`。

## Phase 3.5: Final Completeness Gate

收口前检查：

完整模板见：`../dev-workflow/references/complex-requirement-delivery-kit.md`。

| 门禁 | 要求 |
|------|------|
| 需求冻结矩阵 | 每行有代码落点和测试/验证锚点 |
| 字段与数据来源冻结表 | 数据来源、落库、展示有验证 |
| Surface 覆盖矩阵 | 每个 surface 有独立验证点 |
| Test Design Control | 影响范围、风险分级、判定表、可执行步骤、覆盖校验已被测试生成消费并闭环 |
| Expected Diff Matrix | 实际 diff 未缺预测文件，未混入未解释文件，且每个预计文件族有闭环状态 |
| TDD 证据 | RED/GREEN 命令、失败阶段、逐行 RED 证据、复验结果完整 |
| Planning Brainstorm Trace | 非平凡需求有带 PB-ID 的 Planning Brainstorm Matrix 或合法 `skip_reason`，关键取舍已落到实现证据和验证断言 |
| Baseline blocker | 基线/环境/运行时阻塞已单独分类，未被当作需求 RED |
| Copy-ready 命令 | 验证命令能在当前 shell 直接复跑；PowerShell 动态命令未误用 `--%` |
| Must-not 断言 | fallback、副作用、状态回填、空字段等已覆盖 |
| Artifact Ledger | 生成物、缓存、索引、日志、截图、临时脚本有 ledger，未混入 effective diff |
| Scope Diff 分类 | 未预测文件已分类，范围外文件不计入完成态 |
| 90% 自主覆盖 | 覆盖账本已计算加权完成度；核心主链、关键 surface、literal 和 must-not 均有证据 |
| 真实入口覆盖 | core_path 不是仅 helper/service/mock-only，至少一个真实入口或承载点有行为证据或 blocker |
| 纠错闭环账本 | 用户纠错项已映射到同类扫描、更新后的需求合同、代码落点和验证证据 |
| Review Tier Closure | L2/L3 风险任务有审查镜头、反证检查、同症状分支和 unresolved gap；缺失则最高 `PARTIAL` |
| Review Independence Disclosure | 多轮/第二视角/隔离线程/外部 reviewer 已披露 review mode、independence level、外部模型使用和主会话复核 |
| 完成态表述门禁 | “完成 / 全部完成 / 已按需求完成 / 可以提交”有 Proof Ledger 支撑；否则只能写 `PARTIAL` 或 blocker |
| 可见 Surface 证据 | UI、表单、下拉、错误提示、接口出参、数据来源、落库、导出等用户可见或业务可见 surface 有静态/运行时证据 |

任一缺失 = `PARTIAL`，不得提交、推送或宣称完成。

小需求轻量档可用一页式收口：最小冻结矩阵、Expected Diff 小表、RED/static guard、GREEN 命令、final effective diff、Artifact Ledger。缺 source、literal、surface、must-not、验证命令或 final diff 时仍为 `PARTIAL`。

## Phase 3.6: Replay / Eval Disclosure

只有本轮真实执行 replay、eval、技能审计、历史提交重跑或 oracle 对比时，报告才必须声明；普通 commit 静态审查只声明基准版本和验证缺口：

| 项目 | 必填 |
|------|------|
| 模式 | `blind_from_scratch` / `oracle_port` / `hybrid_replay` / `static_audit` / `branch_derived_replay` / `commit_derived_replay` |
| 隔离 | worktree / sandbox / none |
| oracle 使用 | before-implementation / after-implementation / none |
| 验证 root | 实际 workspace root 或 root pom |
| 技能修改 | yes / no |
| 备份同步 | yes / no / n-a |

未声明 = `PARTIAL`。

若报告来自多轮 replay/eval，还要说明哪些验证可并行、哪些集成测试因全局状态默认串行；不能把 oracle 对比结果表述成纯盲写能力。

branch/commit-derived 报告必须附 `Inferred Requirement Matrix`、`Diff Role Matrix` 和 verification gap；compile green 只能算结构验证。

## Phase 4: Git 边界

提交、推送或 PR 前读取 `references/pre-commit-check-rules.md` 的 Git Boundary / Staging Guard。最低门禁：不混合任务、不自动 push、不用 `git add .`、不把 generated artifacts 混入 effective diff，暂存区必须能由 `git diff --cached --name-status` 解释。

## 输出

```markdown
## 同步结果
- 状态: DONE / PARTIAL / BLOCKED
- 变更范围:
- 三路同步账本:
- Proof Ledger:
- Review Tier Closure:
- Review Independence:
- Correction Closure Ledger:
- Planning Brainstorm Trace:
- Weighted Coverage Ledger:
- Subagent Intake:
- 验证:
- Final Completeness Gate:
- Replay/Eval Disclosure:
- Phase State / Staging:
- Tooling/Base Close-out:
- Git 边界:
- 下一步:
```
