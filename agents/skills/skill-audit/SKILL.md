---
name: skill-audit
description: "Use when user says 审查技能, 技能审查, 审计技能, 评估技能, audit skill, review skill, 测试技能效果, 实测技能, eval skill, replay 报告审查, branch-derived replay audit"
allowed-tools: Bash,Read,Glob,Task
---

# 技能审计

根据行业最佳实践评估技能，提供量化评分。支持实测验证（带技能 vs 不带技能对比输出质量）。

**专家角色：** 技能质检员

**下游技能：** `skill-evolution`

---

## 何时使用

- "审查技能" / "技能审查" / "审计技能" / "评估技能"
- "测试技能效果" / "实测技能" / "eval skill"
- "replay 报告审查" / "branch-derived replay audit"
- 写完新技能后、发布前、审查会话期间

## 何时不使用

- 非 Claude Code 提示 | 简单一句话指令 | 只需快速语法检查

---

## Route Table

| 用户意图 | 路由 | 执行路径 |
|----------|------|----------|
| "审查技能 X" | `FULL` | Phase 1→6（完整审计）|
| "快速检查技能" | `QUICK` | P0 清单 + 8维评分（跳过深度检查）|
| "比较技能版本" | `DIFF` | 读新旧版本 → 差异分析 → 评分变化 |
| "批量审查" | `BATCH` | 遍历目录，每个执行 QUICK |
| "运行评估用例" | `EVAL` | 读 evals.json → 逐条断言验证 → 输出通过率 |
| "技能改动回归 / 最小 eval" | `EVAL-MIN` | 设计 should-trigger / should-not-trigger / pressure scenario → 输出轻量回归结论 |
| "实测技能" / "测试技能效果" | `EVAL-TEST` | 设计测试 prompt → 子 agent 对比跑 → 维度8评分 |
| "重跑失败报告 / replay 报告审查" | `REPLAY-AUDIT` | 读取 replay 报告 → 提取失败模式 → 映射到技能门禁 |
| "分支/提交重建报告审查" | `REPLAY-AUDIT` | 检查 Inferred Requirement / Diff Role / verification gap 是否进入正确技能层 |

**EVAL 路由：** 读 `evals/evals.json` 逐条断言验证，输出通过率。

**EVAL-MIN 路由：** 用于技能进化后的轻量回归，不替代完整 EVAL-TEST。至少包含 2 条 should-trigger、1 条 should-not-trigger、1 条 pressure scenario 或 `no_eval_reason`；若影响输出格式，再补 1 条 golden output。详见 `references/eval-test-guide.md`。

**EVAL-TEST 路由：** 为技能设计测试 prompt，用子 agent 带技能跑 vs 不带跑，对比输出质量。详见 `references/eval-test-guide.md`。

**Eval Evidence Schema：** 技能改动报告必须能回答：真实 prompt 是什么、`with_skill` 相比 `without_skill` 或 `old_skill` 改善在哪里、断言证据是什么、是否有人类反馈、耗时/token 成本是否可接受、transcript 是否支持结论。缺少这些字段时，eval_mode 最多是 `dry_run` 或 `minimal_regression`。

**Foundation Drift Audit：** 审计通用技能、工作流原则或外部模式吸收时，必须检查是否偏离基座身份。若变更把体系退化成外部技能合集、普通 plan/review/TDD 包、公司流程复制品或项目事故复盘，应标记 drift risk。检查项：是否保留“需求源到可验证交付覆盖率”的 North Star；是否强化假完成防线；是否把 replay/eval 专用规则压入普通主链；是否引入外部身份、项目路径、公司命令或业务细节；是否有 runner / prompt / verifier 执行证据而不是只加文案。

**Trace Distillation Audit：** 审查从论文、知识库、历史会话或 replay 轨迹吸收的技能变化时，必须检查是否完成 trace -> rule -> control 的蒸馏链：raw trace / 因果证据、已验证根因或最小 proof、重复/高权重模式、紧凑控制信号、落点层级。只有摘要、金句或单次未验证经验时，最多标 `candidate_only` 或 `needs_more_trace_evidence`。

**Harness Tuning Audit：** 当结论声称“优化 replay / autopilot / runner / prompt / verifier”时，审查重点不是文案是否更完整，而是执行器是否能 fail closed。必须检查 artifact acceptance、schema validation、停线条件、RED 失败证据、生产边界 proof 和 verifier assertion；缺少执行证据时标 `text_only_harness_change`，不得算完成。

**REPLAY-AUDIT 路由：** 当已有真实重跑报告时，不再只做静态评分；必须提取“小 GREEN 误判、需求后置对齐、surface 漏覆盖、scope drift、隔离失败”等失败模式，并检查这些模式是否已经写入正确层级的技能门禁。

**Replay Coverage Audit：** replay 报告必须区分 `self-assessed coverage`、`verification-capped coverage`、`oracle-adjusted coverage`。若 GREEN 主要来自 static guard、helper-only surface、字段/常量存在、或 mock-only test，必须标记为 `small_green_false_positive` / `helper_only_surface_gap` / `static_only_core_path` / `mock_behavior_gap`，不得把自评覆盖率当成最终能力结论。

**Replay Oracle Calibration Audit：** oracle 后验必须拆成 `exact file-family overlap`、`conceptual role overlap`、`missing deploy-facing family penalty` 三项；概念命中核心入口不能抵消 report/export/frontend/template/generated artifact/OCR/external payload/test family 的缺失。

**Replay Exact Contract Audit：** oracle 后验发现字段名、DB/API/wire name、flag/type/enum、payload shape 或展示列偏差时，必须标记 `exact_contract_gap`；不能用代码字段存在、常量存在或概念相近抵消精确契约错误。

**Replay Deliverability Audit：** 审查“工作流可交付”结论时，必须检查两阶段证据：代表性复杂需求连续 3 轮 strict blind replay 均 `verification_capped_coverage >= 90` 且 `oracle_adjusted_coverage >= 90`，再换至少 1 个不同类型需求达到同一标准；否则只能标为 `candidate_workflow` 或 `improving_workflow`。

**Replay Report Template：** 生成或审查 replay 报告时，优先使用 `references/replay-report-template.md` 中的 `ROUND_RESULT` / `FINAL_REPLAY_REPORT` 模板；模板只用于 replay/eval，不进入普通 delivery 交付报告。

**Replay Diff Closure Audit：** replay 报告若包含 Expected Diff Matrix，必须检查每个高风险文件族是否闭环为 `changed+tested`、`changed+static_only+cap`、`deferred+reason+coverage_cap` 或 `blocker`。图片/附件/报表/异步/自动流转/外部协议只被列出但未落到真实承载文件族、真实入口或验证证据时，必须标记 `expected_diff_unclosed`，并检查该失败是否已映射到 `deep-plan`、`dev-workflow`、`gen-tests`、`sync-progress` 的门禁。

**Replay Implementation Depth Audit：** 审查 replay 报告时必须额外检查四项：是否做了 Surface Mining Pass、是否按 Core-First Budget 推进、核心 slice 是否有 Behavior Test Charter、是否把 untracked diff 纳入覆盖计算。缺失时分别标记 `surface_mining_gap`、`core_first_budget_gap`、`behavior_test_charter_gap`、`untracked_diff_gap`，并判断应映射到 `deep-plan`、`dev-workflow`、`gen-tests` 或 `pre-flight-check`。

**Replay Real Entry Audit：** core_path 只通过自建 service、mock-only 行为或 helper 测试时，不得算真实主链完成；必须标记 `real_entry_gap` 或 `mock_behavior_gap`。显式 surface 只改 DTO/helper/constant，未接入 controller/service/exporter/worker/mapper/select/filter 时，必须标记 `helper_only_surface_gap`。

**Replay Core Entry Closure Audit：** replay 若已识别核心生产入口但实际 diff 未修改该入口或直接前置承载点，必须标记 `core_entry_unclosed`；新增 helper/service/DTO 不能抵消真实入口缺失。

**Replay Side-Effect Ledger Audit：** stateful core path 必须审查状态、任务、进度、日志、落库、事务/回滚和失败隔离账本；缺项标记 `side_effect_ledger_gap`，mock-only 测试不能把该 core path 标为 DONE。

**Replay Missing Family Backpressure Audit：** oracle 后验缺失的高权重文件族要抽象成下一轮门禁类别，例如 stateful DB writes、template/render/upload、report/page script、external payload builder、transaction tests；不得把具体 oracle 文件名写进 blind prompt。

**Replay Budget Routing Audit：** 若高权重 deploy-facing family 在 blind diff 中完全 untouched，而实现集中在 core service/helper，必须标记 `surface_budget_gap`；若只用 static guard、文件存在断言或 blocker row 占位，必须标记 `executable_surface_slice_gap`。审计建议应改预算分配和可执行首个切片，不只继续加评分 cap。

**Replay Non-blocking Audit：** “失败不阻断”被实现者解释成“功能可不做”时，必须标记 `nonblocking_feature_gap`。审计结论要区分“功能缺失”和“失败处理缺失”，不得把非阻断失败处理当作功能完成证据。

**Replay Isolation Audit：** 多轮 replay 若复用同一模型上下文，即使 worktree 隔离，也必须声明 `context_contamination_risk`；不得表述为严格独立多次盲写。

**Replay Mode Gate：** 报告必须声明 `blind_from_scratch` / `oracle_port` / `hybrid_replay` / `static_audit` / `branch_derived_replay` / `commit_derived_replay`。用过目标提交、历史最终态或 oracle diff 时，不得把结论表述成纯盲写能力。

**Replay Scheduling Gate：** 多轮 replay/eval 中，静态分析、文件切片、diff 对比和编译探测可并行；涉及容器启动、RPC/远程注册、调度器、端口、全局缓存等共享运行态的集成测试默认串行。首次失败但串行复跑通过时，分类为 `test_runtime_isolation_issue`，不得要求修改生产代码。

**技能写作规则内置：** description 必须只写触发条件；主 `SKILL.md` 默认预算 120-250 行，复杂执行技能可到 300 行但必须有拆分理由；引用的下游技能必须真实存在；外部方法论只能被吸收，不能作为本地 downstream 依赖。

**源头治理内置：** 审计自定义技能前读取 `.agents/AGENTS.md`（若存在）与 `skills-manifest.md`，确认 source、mirror、backup、changelog 边界。

---

## Decision Tree

```
开始
  ├─ 找到 SKILL.md？
  │   ├─ 是 → 有 YAML frontmatter？
  │   │   ├─ 是 → 检查 P0 清单
  │   │   │   ├─ 通过 → 8维评分 → 深度检查 → 输出报告
  │   │   │   └─ 失败 → 标记 P0 问题 → 输出报告
  │   │   └─ 否 → P0 失败（缺少 frontmatter）→ 输出报告
  │   └─ 否 → 报告"技能文件不存在"
```

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 评分前不读 | 总是先读完整 SKILL.md |
| 标准不一致 | 严格使用此技能的评分表 |
| 遗漏风险评估 | 评分纪律前识别风险级别 |
| 反馈模糊 | 提供具体示例和行号 |

---

## Iron Law

1. **没有阅读就没有评估** — 评分前必须读完整 SKILL.md
2. **没有部分审计** — 必须评估所有8个维度（结构审计至少7维，EVAL-TEST 至少测效果）
3. **硬编码路径不能通过** — 如严重硬编码则通用性 F

---

## 红旗警告

| 想法 | 为什么错 |
|------|----------|
| "一眼看没问题" | 表面审查会遗漏结构问题 |
| "描述很好地解释了功能" | description = 触发器，不是功能 |
| "能用就够了" | 能用 ≠ 遵循最佳实践 |

---

## 审计维度（8维，满分100）

### 结构维度（85分）— 静态分析

| # | 维度 | 权重 | 关键检查 | A | B | C |
|---|------|:----:|----------|:-:|:-:|:-:|
| 1 | Description 纯净度 | 12% | 纯触发器，无功能摘要 | 12 | 8 | 4 |
| 2 | 角色化设计 | 8% | 清晰专家 + 职责 | 8 | 6 | 3 |
| 3 | 纪律性设计 | 18% | Iron Law / Red Flags / Guardrails | 18 | 13 | 7 |
| 4 | 流程定位 | 12% | Sprint Position + Skill Chain | 12 | 8 | 4 |
| 5 | 通用性 | 12% | 无硬编码 | 12 | 8 | 0 |
| 6 | 完整性 | 13% | Overview + When NOT + Gotchas | 13 | 9 | 4 |
| 7 | 易用性 | 10% | 触发词 + 行数预算 + token 效率 | 10 | 7 | 4 |

### 效果维度（15分）— 需要实测（EVAL-TEST 路由）

| # | 维度 | 权重 | 关键检查 | A | B | C |
|---|------|:----:|----------|:-:|:-:|:-:|
| 8 | 实测表现 | 15% | 带技能 vs baseline 对比 | 15 | 10 | 5 |

**维度8 评分方式：**
- `EVAL-TEST` 路由：实际跑测试 prompt 对比，标注 `full_test`
- `EVAL-MIN` 路由：轻量 trigger/output 回归，标注 `minimal_regression`
- 其他路由：模拟推演评估，标注 `dry_run`
- 详见 `references/eval-test-guide.md`

### 等级

| 分数 | 等级 |
|:----:|:----:|
| 90-100 | A |
| 80-89 | B+ |
| 70-79 | B |
| 60-69 | C+ |
| < 60 | F |

---

## 按风险级别的纪律

| 风险 | 必须 |
|------|------|
| 高 | Iron Law + Hard Gate + Red Flags |
| 中 | Red Flags + Common Rationalizations |
| 低 | 清晰边界 |

---

## Frontmatter 检查

| 字段 | 必需 | 说明 |
|------|:----:|------|
| `name` | ✅ | 技能名称（kebab-case）|
| `description` | ✅ | 纯触发器描述 |
| `allowed-tools` | 推荐 | 限制可用工具 |
| `context` | 可选 | `fork`（隔离）或默认 |
| `effort` | 可选 | `low` / `medium` / `high` |

---

## 工作流程

```
[1] 读完整 SKILL.md
    ↓
[2] 读 .memory/skill-feedback.md（如存在）获取已知问题
    ↓
[3] 识别风险级别
    ↓
[4] 检查 P0 清单 → 评分8个维度 → 深度检查
    ↓
[5] 与 skill-feedback.md 中该技能的条目交叉引用
    ↓
[6] 计算总分 → 生成报告（含 eval_mode 标记）
```

### EVAL-TEST 流程（维度8）

```
[1] 为目标技能设计 2-3 个测试 prompt（happy path + 复杂场景）
    ↓
[2] 对比执行（子 agent）：
    ├── with_skill: 带技能执行 prompt
    └── baseline: 不带技能执行同一 prompt
    ↓
[3] 对比评分：意图完成度 / 质量提升 / 负面影响
    ↓
[4] 记录 eval_mode：full_test 或 dry_run
```

### EVAL-MIN 流程（技能变更轻量回归）

```
[1] 从 description 和正文提取触发边界
    ↓
[2] 写 2 条 should-trigger + 1 条 should-not-trigger
    ↓
[3] 写 1 条 pressure scenario；输出格式变化时补 golden output
    ↓
[4] 判定：PASS / FAIL / NEEDS_FULL_EVAL / SKIPPED(no_eval_reason)
```

EVAL-MIN 只证明“这次技能变更没有明显误触发、漏触发或输出漂移”；不能用来替代复杂技能的真实子 agent 对比或 replay/eval。

### Eval 证据字段

字段模板见 `references/eval-test-guide.md`。缺少 `assertions` 或 `evidence` 时，不能把结果写成 `PASS`；最多写 `NEEDS_EVIDENCE`。

---

## P0 检查清单（必须修复，可验证）

完整清单见 `references/audit-checklists.md`。必须覆盖 description、硬编码、Iron Law、行数、上下游、frontmatter、references、源头治理、replay/eval 分层、oracle 披露和最小 eval 证据。

---

## 深度检查维度

必须检查验证纪律、红旗词汇、证据分级、增量验证、失败处理、上下文隔离、结构化流程、覆盖率审计、外部集成、专家派遣、结构化发现、双轨道知识、Replay 失败吸收、Source Governance、Mode Separation。细则见 `references/audit-checklists.md`。

---

## 行数预算审计

默认按 `references/audit-checklists.md` 的预算表审计：超过 300 行默认 P1，超过 350 行默认 P0；长案例、模板和历史教训应外移到 `references/`。

---

## 反馈集成

如果 `.memory/skill-feedback.md` 存在，评分前读取：

| 反馈类型 | 对评分的影响 |
|----------|-------------|
| "技能在错误时间触发" | 检查 Description 纯净度 |
| "输出太冗长/缺失" | 检查易用性 |
| "遗漏重要维度" | 检查完整性 |
| "工作流步骤顺序不对" | 检查流程定位 |

---

## CSO 合规性检查

检查 description 只含触发条件、关键词覆盖充分、命名使用 kebab-case、Token 预算符合 manifest；严重偏离时按 P0/P1/P2 分级。

---

## 收敛保护

审查循环最多 3 轮。超过 3 轮 → 停止 + 标记未解决项为 [Reviewer Concerns]。

---

## 输出格式

按路由选择对应模板。所有路由输出必须包含：P0/P1/P2 行动项 + eval_mode 标记。
