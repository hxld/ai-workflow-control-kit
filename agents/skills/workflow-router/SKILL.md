---
name: workflow-router
description: "Use when user says 开始工作, what should I do, 用哪个技能, 先用什么技能, session start, when routing a request to the right custom skill, or when the user says Claude Code/Codex/another reviewer will review the result"
allowed-tools: Read,Glob
---

# 工作流路由

把用户意图路由到最小必要技能链，并优先处理风险门禁。

**专家角色：** 工作流调度员。

## 何时使用

- 用户问先做什么、用哪个技能、开始工作。
- 会话启动，需要选择技能链。
- 用户请求横跨需求、实现、测试、审查、发布。
- 用户说会让 Claude Code、Codex、外部 AI 或第二视角审查结果，需要切换到证据优先路由。

## 何时不使用

- 用户直接点名一个具体技能，且无冲突风险。
- 简单只读问答。
- 已在明确技能流程中执行。

## Iron Law

路由只做分流和门禁提示，不在路由层内联执行下游技能。先选工作模式，再选技能链；不要把所有门禁默认套到所有请求上。

## Mode Router

每次进入非简单问答前，先用 6 字段冻结本轮工作形态：

`MODE -> SCOPE -> CONTRACT -> VERIFY -> EXIT -> SYNC`

| Mode | 适用 | 默认动作 | 不做什么 |
|------|------|----------|----------|
| `planned-dev` | 有需求、设计、功能实现、多 surface 交付，或用户要求基于需求文档尽量自主实现 | 需求冻结 → 技术设计 → 审批/风险暂停 → TDD 实现 → 收口 | 不跳过计划和规格门禁；不把 replay/eval 混入普通开发 |
| `hotfix` | 有失败测试、堆栈、日志、复现输入或明确 contract 的小修 | 先锁证据和最小修复面 → RED/复现 → 最小 diff → 回归 | 不把局部修复扩成完整重构 |
| `debug-only` | 只排查、查日志、写 SQL/查询、给结论 | 先给最短可执行查询/证据锚点 → 假设表 → 信息缺口 | 默认不改代码 |
| `review-only` | 只审查、只分析、比较分支/提交、输出报告 | findings first → 风险/缺口 → 验证建议 | 默认不边审边改 |
| `tooling` | 技能、hook、配置、模板、平台同步或工作流治理 | canonical source → 备份同步 → smoke/eval → 回滚路径 | 不写入项目特定细节 |

升级规则：

- `hotfix` 有失败测试或可写复现 RED，且首帧/失败点已足够定位时，优先 `gen-tests` FIX / `dev-workflow` 轻量档；`log-investigator` 只补缺失的首帧、变量来源或外部证据。
- `debug-only` 只有在证据足以定位修复边界时，才升级为 `hotfix`。
- `hotfix` 命中共享入口、外部契约、数据迁移、多 surface 或需求 literal 时，升级为 `planned-dev`。
- `review-only` 只有用户明确要求修复时，才切换到写入模式。
- `tooling` 修改通用技能时，必须保持项目中立，并完成 source → backup → changelog → 污染扫描。

## Review Pressure Mode

触发信号：用户说“我会让 Claude Code/Codex 审查你”、“外部 AI 会复核”、“十轮深度审查”、“第二视角审校”或同义表达。

路由规则：
- 这只提高证据标准，不默认扩大产物数量、不默认生成第二套方案、不默认进入 replay/eval。
- 如果当前任务是代码、方案、技能或知识库审查，路由到 `deep-review`，并按任务类型读取 `references/review-lens-templates.md`。
- 如果用户已经给出 Claude Code/Codex/人工 reviewer 的反馈，路由到 `resolve-feedback`，先验证再接受。
- 本工作流默认只使用 Codex。只要出现 review pressure、第二视角、多轮/十轮、发布前/提交前高风险、怕漏问题、要求交叉审查或类似信号，就设置 `review_mode=codex_only_cross_review`，路由到 `deep-review` 并读取 `references/codex-only-cross-review.md`；用户无需记住或说出该路由名。
- 只有用户明确要求外部模型/人工 reviewer，或已经提供外部反馈时，才进入外部 review / `resolve-feedback` 语义。
- 如果任务仍在实现链路中，保持原技能链，但把 `CONTRACT` 标为 `review_pressure`，`VERIFY` 必须包含证据来源、确定性、验证方式和无法验证的假设。

Codex-only 选择规则：默认 `single_context_lens`；若宿主支持只读 Codex 线程/分叉，且任务为 L3、review pressure、大 diff 或多 surface，可升级为 `codex_thread_isolated`。不允许把同一上下文多镜头说成外部独立审查。

## Adaptive Review Tier Router

进入非简单问答后先给出 `review_tier`，让多轮审查按风险触发，而不是所有任务机械十轮。

| Tier | 触发信号 | 路由 / 验证 |
|------|----------|-------------|
| `L0` | 纯问答、单命令、查枚举/路径、无写入无生产风险 | 直接答复或轻量自检，不强制 `deep-review` |
| `L1` | 小代码改动、普通 SQL、单 surface、局部文档/配置 | 目标技能 + 定向验证；收口说明验证范围 |
| `L2` | 生产/线上结论、热修、修数、缓存刷新、外部接口、跨组件归因、状态/数据链路 | `log-investigator` 或 `req-alignment-check` 先建证据链与同症状分支矩阵；修复前进入 `deep-plan` 或轻量 hotfix |
| `L3` | 发布/提交前高风险、批量数据影响、资金/状态推进、用户已纠错、曾提前完成、review pressure + 多 surface | 必须有反证挑战、`deep-review` 多镜头或等效审查账本；默认 `review_mode=codex_only_cross_review`，`sync-progress` 缺审查闭环时只能 `PARTIAL` |

升级规则：从 L1 以后，只要出现“同一个业务症状可能来自多个入口/配置/缓存/异步/下游分支”，必须要求 `Same Symptom Branch Matrix`；只修目标分支不能宣称整个症状已闭环。

## Subagent Eligibility Gate

路由层只判断子 agent 是否适合，不在路由层内联派遣。输出三态：`no` / `optional-readonly` / `optional-write-isolated`。

- 默认 `no`：quick/small、单命令、用户决策、pre-flight、发布/提交、生产操作、权限或密钥相关事项。
- `optional-readonly`：large、多 surface、review pressure、技术方案/技能/知识库审查、跨上下文证据采集，且宿主支持并允许并行代理。
- `optional-write-isolated`：只有用户明确授权，且写入范围互不重叠或位于隔离 worktree / 临时目录时才允许。

合并门禁必须写清：允许角色、只读/隔离边界、主会话如何复核 P0/P1 与核心事实、最终唯一产物落点。子 agent 不能替代用户审批、需求冻结、OpenSpec、收口验证或 Git/发布确认。

## Size / Brake Gate

路由后先判定任务大小，避免小题大做或大需求无刹车：

| Size | 信号 | 路由 |
|------|------|------|
| `quick` | 只问答、单命令、无文件写入 | 直接答复或执行命令 |
| `small` | ≤2 个文件、单入口/单规则、无落库/外部契约 | `pre-flight-check` → 目标技能轻量档 → 定向验证 |
| `medium` | 3-10 个文件或 2-3 个 surface | 正常 `planned-dev` / `hotfix` |
| `large` | >10 个文件、跨服务/DB/schema、公共 API、异步任务、报表/导出、模板/附件、外部协议 | 先 `req-alignment-check` + `ideate:planning-brainstorm` + `deep-plan`，再按 slice 实现 |

刹车规则：

- `small` 只压缩表达，不取消 source、literal、Expected Diff、verification。
- `large` 写文件前必须有 Expected Diff Matrix、Capability Slice Matrix，以及可独立验证/回退的 phase checkpoint。
- 长任务每个 phase/slice 的状态必须能在上下文压缩后恢复：`phase -> changed files -> validation -> blocker -> next slice`。

## Runtime State Model

路由输出以 Mode 为主，不再把旧 Lane 当主状态。旧 Lane 只作为兼容别名：

| Legacy lane | Mode |
|-------------|------|
| `small-fix` | `hotfix` 或 `planned-dev` 的轻量子类 |
| `full-feature` | `planned-dev` |
| `bug-with-evidence` | `hotfix` 或 `debug-only`，取决于用户是否要修 |
| `review-only` | `review-only` |
| `skill-governance` | `tooling` |

`review-only` 再分两档：`static-review` 只读 diff/对话/代码，不建隔离工作区；`replay-eval` 仅在用户明确要求重跑、oracle 对比、技能实测或历史复现时启用隔离和 replay disclosure。

若 mode 不明确，先输出 `NEEDS_CONTEXT`，不要把普通请求默认升级成 replay/eval。

## Autonomous Delivery Route

当用户说“给定需求文档后自主实现 / 尽量少问 / 覆盖 90% 以上 / 自主完成大部分代码”时，归入 `planned-dev` 的 `autonomous-delivery` 子场景，而不是 `replay-eval`。

默认冻结：

- `CONTRACT`: 目标是需求文档驱动的 `>=90% autonomous implementation coverage`，覆盖口径必须来自需求覆盖账本，不来自文件命中率。
- `VERIFY`: 核心主链、关键 surface、固定 literal、字段/数据来源、must-not 断言和完整构建/测试证据。
- `EXIT`: 核心主链未实现、覆盖账本无法量化、固定字段/DDL/外部 owner/发布动作不清，必须回到需求或设计阶段。
- `SYNC`: 收口时输出加权覆盖率、DONE/PARTIAL/BLOCKED 行、未覆盖原因、是否达到 90% 目标，以及 `.doc` / `openspec` / `.memory` 三路同步状态。

推荐技能链：`pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` → `dev-workflow` → `gen-tests` → `deep-review` → `sync-progress`。

普通自主开发不读取 oracle、不做历史重跑、不执行 replay disclosure；只有用户明确要求“重跑 / oracle 对比 / 技能实测 / 历史复现”时，才切到 `review-only:replay-eval` 或对应审计链路。

## Company Skill Boundary

- `rdc-git` 属于公司 Git 规范技能，不是个人工作流主链。
- 常规提交收口仍走 `sync-progress` → `ship-release`；只有用户明确要求慧择/RDC Git 规范、当前仓库规则要求或发布流程要求时，才切入 `rdc-git`。

## Creative Direction Gate

当用户要“先聊方案 / 方案未定 / 多方案 / 头脑风暴 / 帮我想几个方向”，且没有已接受需求源或固定验收口径时，路由到 `ideate:dialogue-design`。该模式先一问一答澄清，再给 2-3 个方案和 Design Brief；不得直接进入实现。

如果用户已经有 PRD、固定字段/文案、验收清单、设计稿或明确 bug 证据，则不进入无边界创意发散；非平凡实现仍必须在 `req-alignment-check` 后、`deep-plan` 冻结前执行 `ideate:planning-brainstorm`，让 AI 自主回答“为什么这样做 / 为什么不那样做 / 哪个 surface 会漏 / 用什么断言证明”。小型机械改动可跳过，但必须有合法 `skip_reason`：`typo_or_comment_only`、`pure_formatting_no_behavior`、`generated_sync_no_behavior`、`single_file_mechanical_rename_with_static_guard` 或 `no_requirement_decision_surface`。

推荐规划链：`pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan`。若 planning brainstorm 暴露需求冲突、数据源不清或 owner 不清，回到 `req-alignment-check`，不得继续实现。

## Intent Alignment Gate

当用户给出开放式需求、bug 修复或流程改进，且存在多个合理实现落点时，路由层必须先触发轻量“需求意图对齐门”，再进入实现。

触发信号：

- 用户说“修复 / 优化 / 为什么不对 / 日志 / 展示 / 工作流 / 先看下怎么改”等开放型请求。
- 同时涉及用户、业务、客户可见结果与内部排障、应用日志、监控或审计结果。
- 需求里出现固定文案、固定字段、状态流转、落库字段、展示字段、共享 helper 或禁止改动项。
- 用户明确说“这是产品给的 / 给业务看的 / 客户能看到 / 不能改这个口径”。
- 同一问题已被用户纠正一次，或实际 diff 可能落到共享入口、旧链路、模板、日志方法、渲染层。

轻量输出模板：

```markdown
## 需求意图对齐
- 用户想改变:
- 必须保持不变:
- 用户/业务可见面:
- 内部可观测/排障面:
- 推荐改动落点:
- 禁止改动落点:
- 验证方式:
- 是否需要用户确认:
```

路由规则：

- 只要能用本地上下文安全确认上述项，就在 `pre-flight-check` / `req-alignment-check` 里冻结后继续推进。
- 影响固定文案、枚举、字段来源、落库/展示字段、共享入口或旧链路时，必须先让用户确认。
- “需求意图对齐”是短对齐，不等同于完整创意发散；但有需求文档的非平凡规划仍需要 `ideate:planning-brainstorm` 做自我盘问后再进入 `deep-plan`。

## 优先级

1. 错误沉淀：用户说“记住/总结错误/下次不要再犯” → `compound-learning`。
2. 安全与边界：写文件、构建、replay 前 → `pre-flight-check`。
3. 后验需求重建：无 PRD 但有 branch / commit / diff → `req-alignment-check` 的 branch-derived 模式。
4. 需求冻结：有需求文档或固定验收口径 → `req-alignment-check`。
5. 规划头脑风暴：有需求源的非平凡实现 → `ideate:planning-brainstorm`。
6. 技术设计：非平凡实现 → `deep-plan`。
7. TDD：行为变更、bugfix、新功能 → `dev-workflow` / `gen-tests`，在对应技能内执行 RED/GREEN 门禁。
8. 实现：方案通过 → `dev-workflow`。
9. Bug / Debug：先按证据分型；测试红灯 → `gen-tests` FIX；生产日志/事故，或“生产环境/线上环境 + 业务 selector + 排查现象” → `log-investigator`；无复现/无日志 → 先采证或静态假设，不直接修。跨组件问题先追数据流，三次修复/查询仍无闭环 → `deep-plan`。
10. 收口：实现后 → `gen-tests` → `deep-review` → `sync-progress`。

## 高风险路由

| 信号 | 路由 | 原因 |
|------|------|------|
| 开放式修复/日志/展示/流程需求，且可能有多个改动落点 | `pre-flight-check` → `req-alignment-check` 轻量意图对齐 | 先冻结“改什么 / 不改什么 / 哪个面可见” |
| 同时涉及业务可见结果与内部排障结果 | `pre-flight-check` → `req-alignment-check` → 目标技能 | 先拆用户可见面与内部可观测面 |
| 用户已纠正一次理解偏差 | `pre-flight-check` → `req-alignment-check`，必要时 `deep-plan` | 防止继续沿错误落点补丁式推进 |
| 固定文案/字段来源/结果列/失败场景/条件顺序 | `pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` | 先冻结 literal，再盘问实现落点和断言 |
| 有需求文档但方案可能不止一种，或用户要求自主实现/少追问 | `pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` | 规划阶段先替用户交叉追问，避免实现后靠多轮纠偏 |
| 领域术语混用、同词多义、代码词和业务词冲突 | `pre-flight-check` → `req-alignment-check` Domain Language Ledger → `deep-plan` | 先统一 canonical term，避免实现和测试命名漂移 |
| 多入口/接口/页面/导出/任务/日志/展示面 | `pre-flight-check` → `req-alignment-check` | 先建 Surface 矩阵 |
| 跨模块/报表/异步/外部集成/落库 | `pre-flight-check` → `deep-plan` | 先建 Expected Diff Matrix |
| 跨边界、不可逆、状态/事务、外部协议或高置信但证据不足的决策 | `pre-flight-check` → `deep-plan` Decision Doubt Checkpoint，必要时 `deep-review` | 先把 assertion、contract 和反证问题写清，避免自信推进错误方向 |
| 新增抽象、重构模块、接口/adapter/seam 设计 | `pre-flight-check` → `deep-plan` Architecture Depth Gate，必要时 `deep-review` | 用 deletion test、adapter count 和 interface-as-test-surface 防浅模块 |
| 复杂状态机、数据模型或 UI 方案不确定但可低成本验证 | `pre-flight-check` → `deep-plan` Throwaway Prototype Plan | 原型只回答问题，收口必须删除或吸收 |
| 小需求/简单接口/字段透传/单规则判断 | `pre-flight-check` → `dev-workflow` 小需求轻量档 | 压缩表达，不取消门禁 |
| 给定需求文档后要求自主实现、少问、覆盖 90%+ | `pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` → `dev-workflow` → `gen-tests` → `deep-review` → `sync-progress` | 作为 `planned-dev:autonomous-delivery` 推进，用覆盖账本和核心主链优先级收口；不是 replay/eval |
| 行为变更/bugfix/新功能 | `dev-workflow` / `gen-tests` | 在目标技能内先 RED/GREEN |
| 小测试已绿但需求复杂 | `gen-tests` → `sync-progress` | 防小 GREEN 误判 |
| 被矩阵门禁拦住但要继续推进 | `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` | 使用 delivery kit 补齐 Implementation Readiness |
| 无 PRD 但有分支/提交/diff，需要反推需求 | `pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` | 先重建需求和置信度，不把 diff 当 PRD |
| replay/eval/技能实测/历史提交重跑 | `pre-flight-check` → `skill-audit` 或显式 replay/eval 流程 | 只做验证/审计，必须隔离 worktree；不进入普通开发主链 |
| 构建失败/测试失败/Maven 报错 | `pre-flight-check` → `gen-tests` FIX | 先定位失败阶段并复跑原失败命令 |
| 有失败测试或可写复现断言的 bug | `pre-flight-check` → `gen-tests` FIX / `dev-workflow` | 先复现 RED，再最小修复 |
| 有日志/trace/生产现象的 bug，或生产环境/线上环境 + 业务 selector + 排查/为什么/异常现象 | `pre-flight-check` → `log-investigator` | 先冻结五元组，再查代码链路 + 日志证据 + 假设表 |
| 生产结论、热修、修数、缓存刷新、外部接口或跨组件归因 | `review_tier=L2`；必要时 `log-investigator` → `req-alignment-check` Same Symptom Branch Matrix → `deep-plan` / `deep-review` | 防止局部日志或单个修复分支被误报为整体根因闭环 |
| 发布、批量数据影响、资金/状态推进、用户纠错后继续、曾提前宣称完成 | `review_tier=L3`；`deep-review` 多镜头 + `sync-progress` Review Closure Ledger | 需要前置反证和完成态门禁 |
| 明确异常堆栈/NPE/类型转换/空值转换 bug，且已有失败测试或可写 RED | `pre-flight-check` → `gen-tests` FIX / `dev-workflow` 轻量档 | 先用 RED 锁最小修复面，日志调查只补缺失证据 |
| 明确异常堆栈/NPE/类型转换/空值转换 bug，但缺复现 | `pre-flight-check` → `log-investigator` → `gen-tests` FIX | 先锁第一业务首帧、异常变量来源和最小复现输入 |
| 外部接口/第三方协议/加密报文/响应错误 | `pre-flight-check` → `log-investigator` → `deep-plan`（如需改契约） | 先冻结 request/response/config/幂等和责任边界 |
| 空集合/字段丢失/数据不一致/SQL 反查 | `pre-flight-check` → `log-investigator` | 先追数据来源、过滤条件、映射、落库和输出链路 |
| 配置开关不生效/环境缓存/配置更新时间争议 | `pre-flight-check` → `log-investigator` | 先锁实际配置源、优先级、缓存刷新和请求时间 |
| 预期日志缺失/无法搜到日志 | `pre-flight-check` → `log-investigator` | 先确认日志发射点、级别、payload 是否实际打印 |
| 异步任务未触发/状态卡住/完成日志缺失/重复告警 | `pre-flight-check` → `log-investigator` → `deep-plan`（如需改行为） | 先追父子任务、状态流转、调度和下游触发 |
| Claude Code/OpenCode/Cursor 的 hook、settings、MCP、权限、技能不同步、duplicate skill 或会话发送失败 | `pre-flight-check` → `skill-platform-maintenance` | 先做宿主平台健康检查，不把平台故障误判为业务技能问题 |
| 无日志、无复现、只有口头描述的 bug | `pre-flight-check` → `deep-review` / `deep-plan` 轻诊断 | 只能输出假设、信息缺口和采证计划 |
| 跨组件 bug、状态/数据在链路中变形、单点日志解释不了全局现象 | `pre-flight-check` → `log-investigator` → `deep-plan`（证据断裂时） | 先建立 `source -> transform -> persistence/message/cache -> consumer -> visible result` 证据链 |
| 三次修复仍失败或暴露设计矛盾 | `deep-plan` | 升级为设计/架构问题，不继续叠补丁 |
| 用户催促“给结论/先说结论” | 当前技能继续，但先输出 `已确认 / 高置信推断 / 证据缺口` | 先给可用结论，再继续采证 |
| 不要动/只新增/只保留/只填剩余 | `pre-flight-check` → 目标技能 | fill-only 边界 |
| 处理审查反馈 | `resolve-feedback` | 先验证反馈 |
| 发布/提交/PR | `sync-progress` → `ship-release` | 先完成收口门禁 |

## 常规路由表

| 用户意图 | 路由 |
|----------|------|
| 需求评估 | `requirement-assessment` |
| 需求对齐 | `req-alignment-check` |
| 技术方案 | `deep-plan` |
| 从需求到代码 | `pre-flight-check` → `req-alignment-check` → `ideate:planning-brainstorm` → `deep-plan` → `dev-workflow` → `gen-tests` → `deep-review` → `sync-progress` |
| 从需求文档到 90%+ 自主实现 | `pre-flight-check` → `req-alignment-check` 覆盖账本 → `ideate:planning-brainstorm` → `deep-plan` 90% Coverage Plan → `dev-workflow` 核心主链优先 → `gen-tests` → `deep-review` → `sync-progress` |
| 小需求到代码 | `pre-flight-check` → `dev-workflow` 小需求轻量档 → `gen-tests` → `sync-progress` |
| 分支/提交反推需求 | `pre-flight-check` → `req-alignment-check` branch-derived 模式 → `ideate:planning-brainstorm` → `deep-plan` |
| 分支/提交审查报告 | `skill-audit` REPLAY-AUDIT |
| 写测试/补测试 | `gen-tests` |
| 代码审查 | `deep-review` |
| 架构改善/重构机会 | `pre-flight-check` → `deep-plan` Architecture Depth Gate → `deep-review` |
| 质量评分 | `quality-check` |
| 处理反馈 | `resolve-feedback` |
| 同步进度 | `sync-progress` |
| 发布 | `ship-release` |
| 复盘 | `retro` |
| 平台技能/插件/hook/settings/MCP 故障 | `pre-flight-check` → `skill-platform-maintenance` |
| 技能审计 | `skill-audit` |
| 技能进化 | `skill-evolution` |

## 推荐下一步 / 状态码

常用后继：`req-alignment-check -> ideate:planning-brainstorm -> deep-plan`；`deep-plan -> 用户审批 -> dev-workflow`；`dev-workflow -> gen-tests -> deep-review -> sync-progress`；`sync-progress -> ship-release` 仅在发布时使用；`retro -> compound-learning` 仅在有教训时使用。

状态码：`DONE` 可继续；`PARTIAL` 仅局部验证、不得发布；`BLOCKED` 需修阻断；`NEEDS_CONTEXT` 需补上下文；`ESCALATE_UPSTREAM` 回到需求或设计。

## 输出

```markdown
## 路由建议
- MODE:
- SIZE:
- SCOPE:
- CONTRACT:
- VERIFY:
- EXIT:
- SYNC:
- Review Tier:
- Review Mode:
- Subagent Eligible:
- 推荐技能链:
- 升级条件:
- 下一步:
```
