---
name: dev-workflow
description: "Use when user says 完整开发, 一键开发, 从需求到代码, full development workflow, end-to-end, requirements to code, or wants implementation from requirements to verified code"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep,Task,Skill
---
# 开发工作流
编排从需求分析到验证代码的完整构建流水线。
**专家角色：** 工程经理 — 编排完整构建流水线。
**上游技能：** `deep-plan`, `req-alignment-check`
**下游技能：** `gen-tests`, `add-comments`, `deep-review`, `sync-progress`, `backend-effort-estimate`（可选，如已安装）
---
## 何时使用

- "完整开发" / "一键开发" / "从需求到代码"
- "full development workflow" / "end-to-end"
- `planned-dev` 模式，或 `hotfix` 已有证据/RED 且需要进入最小实现与回归。
## 何时不使用

- 简单的单文件修改 | 只是添加注释或格式化 | 用户想跳到特定阶段
- `debug-only`：只排查、只写查询、只给证据和假设时不进入本技能。
- `review-only`：只审查或比较时不边审边改。
- `tooling`：技能、hook、配置平台维护走对应治理技能，不套完整开发链。
---
## ⚠️ Mandatory Workflow

**When triggered, MUST follow these phases IN ORDER. Each phase produces a deliverable before proceeding.**

```
[0] ⚠️ REQUIRED 预检查 + 模式确认 → 输出：MODE/SCOPE/CONTRACT/VERIFY/EXIT/SYNC + 任务清单 + 依赖DAG；命中多落点风险时先过 Intent Alignment Gate
[1] ⚠️ REQUIRED 需求分析 → 输出：隐藏需求清单（via req-alignment-check）
[2] ⚠️ REQUIRED 技术设计 → 输出：**同时生成** `openspec` 变更 + `.doc/` 设计 + Test Design Control
[3] ⛔ BLOCKING 用户审批 → 输出：用户确认（唯一暂停点）
[3.5] (optional) 工时评估 → 输出：工时评估报告（via `backend-effort-estimate`，如已安装）
[4] ⚠️ REQUIRED 实现 → 输出：代码 + tasks.md 勾选；自主实现目标按覆盖账本先做核心主链；若出现新设计约束则回退 `deep-plan`
[5] ⚠️ REQUIRED 测试 → 输出：测试报告（via gen-tests，必须消费 Test Design Control，并写明验证范围、失败阶段复验、反向断言与覆盖矩阵状态）
[6] (conditional) 注释 → 输出：注释代码（via add-comments）
[7] ⚠️ REQUIRED 验证 + `sync-progress` 收口 → 输出：Handoff Summary + `.doc` / `openspec` / `.memory` 三路同步账本
```

**必须：** 执行此技能前使用 `pre-flight-check` 技能。

---

## Quick Start Checklist

进入 Phase 4 前按 mode 检查，避免所有任务共用一张长清单。

### Always

- [ ] `pre-flight-check` 已执行。
- [ ] Mode 已确认：`planned-dev` 走完整链；`hotfix` 仅在证据、最小复现/RED、修复边界和回归命令明确后走轻量实现；`debug-only` / `review-only` / `tooling` 不进入本技能。
- [ ] 已冻结 `MODE / SCOPE / CONTRACT / VERIFY / EXIT / SYNC`，且 `EXIT` 写明何时回到需求/设计、何时停止修复。
- [ ] 构建/测试命令模板、验证范围、基线 blocker 分类已明确。
- [ ] 行为变更、bugfix、新功能已准备可运行反馈回路：RED/GREEN/REFACTOR、复现脚本、接口请求、UI 驱动或等效 static guard。
- [ ] 新增文件已区分 effective diff 与 generated artifacts。

### Planned-dev only

- [ ] `req-alignment-check` 和 `deep-plan` 已完成；技术设计已批准（Phase 3 通过）。
- [ ] 已生成项目约定的技术设计与规格产物；若仓库要求 `.doc` / OpenSpec，二者缺一不可。
- [ ] 固定文案、字段来源、结果列、失败场景、空值、fallback、副作用或多 surface 已进入 literal / surface / Expected Diff 矩阵。
- [ ] 复杂需求已完成 Scope 分类、Baseline Capability Scan、Verification Baseline Plan 和 capability slice 拆分。
- [ ] 非平凡、多 surface、状态流转、外部接口、报表/导出、前端可见面、异步或 must-not 需求已生成 Test Design Control；小需求有合法 mini form 或 skip reason。
- [ ] 若目标是自主实现或 90%+ 覆盖，已存在 Requirement Coverage Ledger / 90% Coverage Plan，并明确 `core_path`、权重、可后置项和暂停确认项。
- [ ] 已确认若实现阶段出现 DTO / 接口 / 配置 / 扩展性新约束，将回退 `deep-plan`，而不是继续补丁式推进。

### Replay/eval only

只有用户明确要求历史重跑、oracle 对比、技能实测或分支/提交复现时，读取 `references/replay-dev-workflow.md`；普通开发和 hotfix 不展开 replay/oracle 清单。

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 跳过设计审批 → 返工 | 绝不跳过 Phase 3 暂停 |
| 实现前不检查模式 / 过度抽象 | 先搜索代码库；只做满足已确认需求的最小实现 |
| 需求原文已经写死，但实现时按“大意”落地 | 进入 Phase 4 前先核对 literal 清单，并让测试直接断言这些 literal |
| 把内部排障诉求落到用户/业务可见 helper | 先过 Intent Alignment Gate，拆清可见契约与内部可观测面 |
| 用户已纠错仍沿旧落点继续修 | 暂停实现，回到 `req-alignment-check` 重新冻结意图和禁止改动点 |
| 遗漏隐藏需求 | Phase 1 运行检查清单 |
| 无限修复循环 | 修复限3次，然后升级 |
| 并行任务冲突 | 并行前分析依赖 |
| 没生成 `openspec` 变更 | 直接阻塞，不能进入实现 |
| 只有零散子需求 change，没有总 feature change | 视为未满足 OpenSpec gate，先补总目录再继续实现 |
| 只写了 `doc/` 或 `doc` | 统一改成 `.doc/`，禁止漂移 |
| `openspec/` 存在但未使用 | 必须生成对应 change，否则设计与实现脱节 |
| 过滤测试过了就进入交付 | 必须复验此前失败阶段，局部通过不等于整体通过 |
| 实现中途出现新约束还继续写代码 | 立即回退 `deep-plan`，重新冻结设计 |
| 小测试 GREEN 就宣布完成 | 用 Completion Gate 核对冻结表、surface 矩阵、Expected Diff Matrix |
| 测试设计控制只停在文档 | Phase 5 必须让 `gen-tests` 消费 Test Design Control，并在收口写覆盖矩阵状态 |
| 用户纠错后只修当前点 | 回退 `req-alignment-check`，执行 User Correction Escalation Gate，同类字段/入口/错误提示/数据源/文案一起扫 |
| 把局部编译或单测通过当作需求完成 | 收口前必须有 Proof Ledger、Final Completeness Gate 和真实 surface 证据；缺失只能 `PARTIAL` |
| 自主实现时先挑低风险旁路 slice | 按覆盖账本先实现 `core_path`，再做 supporting surface，收口用加权覆盖率 |
| 已有高权重 gap 还继续做无关支撑片段 | 触发 Gap Backpressure Gate；下一片必须直击最高权重缺口或停线报告 |
| guard 整体 RED 就算覆盖 | 逐行检查每个 guard row 在基线是否失败，基线已通过的行不计入覆盖 |
| 待定/前端/已存在需求混入实现 | 先做 Scope 分类；待确认项不进生产代码，已有项只给证据 |
| 基线已有一半却重复实现 | 先做 Baseline Capability Scan，部分不符才进入变更 |
| 基线编译坏了却当作需求 RED | 先分类 `baseline_compile_blocker` / `feature_diff_blocker` / `environment_blocker` |
| replay/eval 误写主工作区 | 命中 replay/eval 时读取 `references/replay-dev-workflow.md`，先确认隔离路径 |
| replay/eval 跑错仓库 | worktree 模式下构建命令必须指向隔离目录 root，不照抄主仓库 root |
| 从旧分支照搬实现 | 先拆有效切片与范围外漂移，只吸收本需求所需行为 |
| branch-derived 编译过/外部协议只看字段/共享文件按局部收口 | compile green 只证明结构；外部协议要冻结，共享影响要升级 |
| 运行产物混入交付 | 标记 generated artifacts，不计入有效 diff 或提交计划 |
| 小需求套重型模板 | 使用轻量档；只压缩表达，不跳过 source/literal/surface/diff/TDD/验证 |
| 没有可运行反馈回路就靠读代码修 bug | 先构造最小复现/失败测试/脚本；做不到就报告采证缺口 |
| 一次写一批测试再一次性补实现 | 采用 tracer bullet：一个行为 RED → 最小 GREEN → 下一个行为 |
| 原型代码留在仓库里腐烂 | 原型只回答问题；收口时删除、吸收或标记 generated/debug artifact |

---

## 安全护栏 & Iron Law

**破坏性操作前（rm -rf, force push, DROP TABLE, 生产部署）：暂停并警告。**

**关键约束（长规则见 `references/implementation-gates.md`）：**
- Phase 3 用户审批不可跳过；技术设计阶段必须同时维护 `.doc/` 与 `openspec/`，且使用 `.doc/`。
- Phase 7 必须执行 `sync-progress` 收口；有代码、测试、规格或工作流有效变更时，不能只给口头 Handoff。
- 已出现 `resolve / compile / testCompile / package` 失败时，进入 Phase 7 前必须复跑并通过同一失败阶段或项目约定验证命令。
- 需求源写死的 literal、字段来源、空值行为、状态流转和外部契约必须按冻结表实现并测试；实现中发现 contract drift，停止新增功能并回退 `req-alignment-check` / `deep-plan`。
- 实际 diff 必须与 Expected Diff Matrix 对齐；未预测文件、缺失预测文件、跨域文件或 scope drift 都要回退 `deep-plan`。
- 自主实现或 90%+ 目标按 `core_path -> supporting_surface -> closure` 推进；核心真实入口、副作用和行为验证未闭环时只能 `PARTIAL`。
- 小需求只压缩表达，不取消 source、literal、Expected Diff、RED/GREEN 和 final diff；多 surface、落库、外部契约或用户纠错必须升级完整链路。
- 用户指出遗漏、误解、原型不符、字段规则不符、提示文案不符或“你说完成但实际没完成”时，暂停补丁式推进，回退 `req-alignment-check` 的 User Correction Escalation Gate；同类扫描、更新冻结矩阵和验证计划未闭环前，状态最高只能 `PARTIAL`。
- 没有 Proof Ledger、Final Completeness Gate、真实 surface 证据和剩余风险披露时，禁止使用“完成 / 全部完成 / 已按需求完成 / 可以提交”这类完成态表述；只能说明已验证项、未验证项和 blocker。
- Phase 4 按可验证 slice 推进；每个 slice 必须记录 `changed files -> tests/build -> remaining risk -> rollback boundary`，未验证不得扩下一个 slice。
- 长任务或多 slice 必须维护 phase state checkpoint，使上下文压缩、暂停或交接后能恢复：`phase -> completed slice -> changed files -> validation -> blockers -> next slice`。
- 生成物、缓存、索引、日志、截图、临时脚本和工具输出必须与 effective diff 分离；原型在 Phase 7 前删除、吸收或登记。
- replay / eval / skill test 仅在明确命中时读取 `references/replay-dev-workflow.md`；普通开发不展开 oracle 术语。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：任一 Phase 的 blocking 条件未通过，不得进入下一 Phase
- **PARTIAL**：只表示“部分验证”，即验证范围未覆盖全量；不得表示“功能完成了一部分”
- **完成标准（DoD）**：统一表示“本 Phase 或整条开发链路在当前约束下何时可交付 / 可移交”
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

---

## Stop Reason（终止原因枚举）

每个 Phase 结束时必须声明终止原因：

| stop_reason | 含义 | 行动 |
|----------|------|------|
| `completed` | Phase 正常完成 | 进入下一 Phase |
| `user_cancelled` | 用户在 Phase 3 拒绝设计 | 保存进度，退出 |
| `gate_failed` | HARD-GATE 触发 | 暂停。等待修复 |
| `max_turns_reached` | 修复循环超过3次 | PAUSE。记录诊断 |
| `replan_required` | 实现阶段发现设计输入升级 | 回退 `deep-plan`，更新 `.doc/` + `openspec/` 后再继续 |
| `budget_exhausted` | Token/时间超限 | 输出已完成部分 + 剩余清单 |

**输出格式：** `[STOP: completed]` 或 `[STOP: max_turns_reached]` 等。

## 小需求轻量档
先选 mode，再决定文档和验证表达深度；轻量只压缩表达，不取消门禁。
| Subtype | 适用 | 升级条件 |
|------|------|----------|
| `simple-request` | 单接口、参数、helper/service 局部改动 | 出现多 surface、落库、外部集成或异步 |
| `field-propagation` | 少量字段透传 | source、carrier、recover/retry/rebuild path 任一不明 |
| `rule-gate` | 单规则判断 | 需要固定顺序、must-not、副作用或多条件优先级 |
轻量流程：`pre-flight -> source 分类 -> subtype -> 最小冻结矩阵 -> Expected Diff 小表 -> RED/static guard -> 最小实现 -> GREEN/定向验证 -> final effective diff -> 短报告`。

普通用户不暴露 replay/oracle 术语；若仓库规则要求 `.doc`、OpenSpec 或人工审批，仍生成最小必要版本。

## Phase 0: 任务分解 & 并行策略

| 条件 | 策略 |
|------|------|
| 无共享文件/无数据依赖 | 可并行计划；仅在用户明确允许 agent 并行且写入范围互不重叠时启动 |
| 共享文件但无逻辑依赖 | 串行或并行+合并 |
| 逻辑依赖（B需要A）| 串行，B等待A |

按依赖 DAG 分批；未获明确授权时在主会话串行推进，并保留每批的合并与验证计划。

---

## Phase 1: 需求分析

```
Phase 1 通过 Skill 工具调用 req-alignment-check。不内联分析，否则容易遗漏隐藏需求。
```

---

## Phase 2: 技术设计

```
技术设计阶段必须同时生成 `.doc/` 与 `openspec/`，并把测试设计控制写入技术方案。`openspec` 是规格来源，`.doc/` 是交付文档，二者缺一不可。
```

### 模式 A: OpenSpec + .doc/（标准模式，必须）

最低交付物：

- `.doc/<feature>/tech-design.md`
- `.doc/<feature>/task_plan.md`
- `openspec/changes/<change>/proposal.md`
- `openspec/changes/<change>/tasks.md`

**继续开发已有 feature 的附加规则：**

- 如果用户是在“继续完成已有 feature / 继续剩余功能点 / 按功能点提交”的上下文里工作：
  - 先检查是否存在 `openspec/changes/<feature>/`
  - 若只存在 `openspec/changes/<feature>-subtask-*` 这类零散子变更，视为 **不合格**
  - 必须先补齐总 feature change，再继续实现或提交

### 模式 B: 仓库尚无 OpenSpec（先初始化，再回到模式 A）

禁止退化为“仅 `.doc/` 模式”。

---

## Phase 3: 用户审批（唯一暂停点）

输出：设计摘要 → 关键决策 → 任务图 → 文件 → OpenSpec ID。用户回复 **"继续"** 继续。

---

## Phase 4-6: 实现、测试、注释

| 阶段 | 行动 | 工具 |
|------|------|------|
| 4 | 实现（按授权并行或串行 slice 推进）| — |
| 4.5 | 勾选 `openspec/changes/*/tasks.md` | — |
| 5 | 测试 + 修复循环（最多3次），消费 Test Design Control 并输出覆盖矩阵状态 | `gen-tests` |
| 6 | 添加注释 | `add-comments` |

```
Phase 5/6 通过 Skill 工具调用 gen-tests/add-comments。不内联执行，否则无法保证质量一致性。
```

### Phase 4 自主实现顺序

自主实现或 90%+ 目标按 `core_path -> deploy-facing supporting_surface -> closure` 推进；前 60% 预算仍未接入核心真实入口、行为测试宪章或事务深度验证计划时，输出 `[STOP: core_path_unclosed]`。详细顺序、static guard 纪律见 `references/implementation-gates.md`。

每个 Phase 4 slice 必须是可运行、可验证、可回退的最小单元；优先做纵向路径或最高风险路径，不按“先全量 DTO、再全量 service、最后测试”的横向堆叠方式推进。slice 验证失败时按 Stop-the-Line Gate 处理，不继续扩大 diff。

每个 slice 的第一步应是 tracer bullet：选一个真实入口或最接近真实入口的 carrier，写一个最小失败信号，做最小实现到 GREEN，再根据刚学到的事实扩展下一条行为。反馈回路越慢，slice 越要缩小。

### Phase State Checkpoint

长任务、多 slice、跨上下文或中途可能暂停时，每个 phase/slice 结束都要写 compact state。优先写到现有 `.doc/<feature>/phase-state.md`、已有 `.artifacts/phase-state.md` 或任务文档；没有合适本地文档时，在下一次用户更新中输出，并交给 `sync-progress` 收口。

```markdown
- phase:
- completed slice:
- changed files:
- validation:
- blockers:
- next slice:
- rollback boundary:
```

### Phase 4 设计回退触发器（Hard Gate）

实现阶段出现 DTO、接口、配置、扩展性或显式需求偏移新约束时，必须输出 `ESCALATE_UPSTREAM` 或 `[STOP: replan_required]`，回到 `deep-plan` 更新冻结表、任务拆分、`.doc`、`openspec`。完整触发器见 `references/implementation-gates.md`。

**修复循环：** 失败 → 调查 → 修复 → 重新测试 → 通过或失败3次 → PAUSE。

**Phase 5 Hard Gate：**

报告必须写明命令、失败阶段、验证范围、反向断言覆盖、原失败阶段复验；缺失时 Phase 5 只能是 `BLOCKED` 或 `PARTIAL`。细则见 `references/implementation-gates.md`。

---

## Phase 7: Handoff Summary

先调用 `sync-progress` 做最终收口，再输出 Handoff Summary。

核心要素：建了什么、怎么验证、关键文件、已知缺漏、回顾反思、`.doc` / `openspec` / `.memory` 三路同步账本。

Hard Gate：

- `.doc`、`openspec`、`.memory` 每项必须是 `updated`、`no_change:<reason>`、`missing_blocked:<reason>` 或 `not_applicable:<reason>`。
- 有代码、测试、规格或工作流有效变更，却没有对应三路同步账本时，最终状态最高只能是 `PARTIAL`。
- 若实现阶段触发 `replan_required`，必须先回写 `.doc` 与 `openspec`，再继续 Phase 4；不能把设计回退留到最终口头说明。

---

## 统一状态码

| 状态码 | 含义 | 自动路由 |
|--------|------|---------|
| `DONE` | Phase正常完成 | 下一Phase |
| `PARTIAL` | 仅部分验证完成，不得进入发布链路 | 回到验证/审查 |
| `DONE_WITH_CONCERNS` | 完成+遗留 | 下一Phase + 记录遗留 |
| `NEEDS_CONTEXT` | 缺信息 | 等用户输入 |
| `BLOCKED` | 无法继续 | 三级升级：补充→换策略→人工 |
| `ESCALATE_UPSTREAM` | 发现上游问题 | 回溯到 deep-plan |

---

## 任务拆分原则

按 capability slice 拆分；每步有路径、依赖和验证范围。共享文件先串行或声明合并策略。
