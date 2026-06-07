---
name: ideate
description: "Use when user asks for 构思, 创意, 想法, ideate, brainstorm ideas, what to improve, 多方案, 方案未定, 先聊方案, 规划头脑风暴, 交叉追问, or 苏格拉底式盘问"
allowed-tools: Read,Write,Glob,Grep,Task
---

# 构思 (Ideation)

Generate grounded ideas through either dialogue-led design or divergent sub-agent ideation, then filter before planning.

**专家角色：** 创意架构师 — 先发散再收敛，每个想法必须接地。

**上游技能：** 无
**下游技能：** `req-alignment-check`, `deep-plan`（将幸存 idea 转成需求澄清和技术方案）

---

## 何时使用

用户说 "构思" / "创意" / "想法" / "ideate" / "brainstorm ideas" / "what to improve" / "多方案" / "方案未定" / "先聊方案" / "规划头脑风暴" / "交叉追问" / "苏格拉底式盘问"。

## 何时不使用

- 已有明确 feature request 时，不做 `divergent-ideation`；非平凡实现改用 `planning-brainstorm` 后再进入 `deep-plan`。
- Bug fix 若只有单一复现和单一局部落点，可跳过 ideation；若根因、落点、状态、副作用或数据来源不止一种，使用 `planning-brainstorm`。
- 已知任务（直接执行）

---

## References（按需加载）

| 文件 | 内容 | 加载条件 |
|------|------|----------|
| `references/planning-brainstorm-question-bank.md` | 规划头脑风暴风险问题库、合法 `skip_reason` 和最小行选择规则 | `planning-brainstorm` 命中数据源、状态/事务、用户可见/内部观测、多 surface、外部契约或用户已纠偏时 |

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 发散不够 | 至少 4 个 sub-agent，每个不同 bias |
| 过滤太严 | 保留 5-7 个幸存者，不是 1-2 个 |
| 不接地气 | 每个 idea 必须引用代码/issue/用户反馈 |
| 跳过深挖 | ideation 不直接进 plan，先做约束、风险、验证范围深挖 |
| 所有 agent 同质化 | 每个 agent 有明确的 bias profile |
| 忽略已有方案 | 先搜索 docs/ solutions/ 已有实现 |

---

## 红旗警告

| 想法 | 为什么错 |
|------|----------|
| "我有最好的想法" | 让 agent 独立生成，避免 anchor bias |
| "直接开始做" | 先 brainstorm 再 plan，避免方向错误 |
| "想法够多了" | 20-30 个候选是最低要求 |
| "这个想法太明显不需要验证" | 明显的想法也需要评估价值和成本 |

---

## Iron Law

1. **每个 idea 必须 grounded。** 引用代码路径 / issue 链接 / 用户反馈原文。
2. **不跳过深挖直接进 planning。** Ideation → 深挖约束/风险/验证范围 → Plan。
3. **幸存 idea 必须带验证范围。** 进入下游前必须写明验证范围、完成标准（DoD）与主要风险。
4. **对话式设计不进入实现。** 模糊创意先形成 Design Brief；只有用户接受方向或需求源已冻结后，才交给 `req-alignment-check` / `deep-plan`。
5. **有需求源也要盘问方案。** 已有 PRD / requirements / 验收清单时，不做无边界创意发散；改用 `planning-brainstorm` 在 `deep-plan` 冻结前自问自答，暴露替代方案、隐藏 surface、数据来源和验证缺口。

---

## Mode Router

| Mode | 适用 | 输出边界 |
|------|------|----------|
| `dialogue-design` | 方向模糊、用户想先聊方案、需要 2-3 个方向但还没有需求源 | 一问一答澄清 + 2-3 方案 + Design Brief |
| `planning-brainstorm` | 已有需求源，进入技术方案前需要 AI 自主盘问“为什么这样做/为什么不那样做” | Self-Socratic Matrix + 方案取舍 + 验证断言，交给 `deep-plan` |
| `divergent-ideation` | 用户明确要广泛发散、改进想法或大范围探索 | 20-30 候选 + 对抗过滤 + Top 5-7 |
| `improvement-mining` | 用户问 what to improve，且目标仓库/产品已存在 | 代码/文档 grounding 后输出改进候选 |

### Dialogue Design Mode

当请求是“方案未定 / 先聊方案 / 帮我想几个方向 / 像头脑风暴一样先问清楚”时使用：

1. 先做最小上下文扫描；没有仓库或产品上下文时，只冻结用户给出的约束。
2. 只在答案会改变方向、范围或成功标准时提问；每次只问一个问题，最多 3 轮，除非用户要求继续深挖。
3. 提出 2-3 个可选方案，逐项写明取舍、适用条件、主要风险和推荐方案。
4. 用户选择或默认接受后，输出 Design Brief：`problem / constraints / success criteria / chosen approach / non-goals / validation / open questions`。
5. 交接给 `req-alignment-check` 或 `deep-plan`；不得直接调用实现链路。

### Planning Brainstorm Mode

当已有需求文档、验收口径、bug 证据或冻结矩阵，但方案尚未写死时使用。目标不是新增需求，而是在规划阶段替用户先追问一轮，减少后续返工：

1. 输入必须来自 `req-alignment-check` 的冻结表、需求原文、代码事实或已确认约束；不得凭空扩范围。
2. 对每个高风险需求项至少问：`到底要改变什么？为什么当前落点对？为什么不选其他落点？会在哪个入口/状态/数据源/副作用上漏？用什么断言证明？`
3. 每行分配稳定 `PB-xx` ID（如 `PB-01`），后续 `tech-design.md`、测试、review finding 和 `sync-progress` 都引用同一个 ID；拆分行时新增 ID，已发布 ID 不重编号。
4. 输出 Self-Socratic Matrix：

```markdown
| PB id | requirement / fact | question | option A | option B | chosen | rejected because | risk | validation assertion |
|-------|--------------------|----------|----------|----------|--------|------------------|------|----------------------|
```

5. 固定字面量、must-not、多 surface、数据源/owner、状态/事务、副作用、外部契约、用户已纠偏、review pressure 任一命中时必须入矩阵；其余需求按风险取 Top 3-5。
6. 小型机械改动可跳过，但 `skip_reason` 只能是 `typo_or_comment_only`、`pure_formatting_no_behavior`、`generated_sync_no_behavior`、`single_file_mechanical_rename_with_static_guard` 或 `no_requirement_decision_surface`。`prd_exists`、`looks_simple`、`time_pressure`、`tests_pass`、`model_confident` 均无效。
7. 如果发现需求冲突、owner 不清、数据源不清或 must-not 行为空缺，返回 `req-alignment-check`；不要继续写技术方案。
8. 如果问题可由本地证据回答，给出推荐方案和放弃方案理由，合并到同一份 `tech-design.md`；不要创建第二套并行方案文档。

---

## 工作流程

```
[1] 代码库扫描 (parallel)
    ├── 快速上下文扫描: README, package.json, 主要目录结构
    ├── 搜索 docs/, solutions/, decisions/ 已有方案
    ├── 读取近期 issues/TODOs/FIXMEs
    └── 识别核心模块和边界
    ↓
[2] 发散构思 (Divergent Ideation)
    ├── 启动 4-6 个 sub-agent，每个 ~7-8 ideas
    ├── Agent biases:
    │   ├── User Pain: 摩擦点, 投诉, confusing APIs
    │   ├── Unmet Needs: 缺失功能, 不完整流程
    │   ├── Inversion: 如果反过来? 如果删除?
    │   ├── Leverage: 什么让未来工作更容易?
    │   ├── Edge Cases: 什么会坏? 不寻常用法?
    │   └── Performance: 瓶颈, 可扩展性限制
    ├── Merge + dedupe → 20-30 unique candidates
    └── 每个 idea 必须有代码引用 grounding
    ↓
[3] 对抗过滤 (Adversarial Filtering)
    ├── Skeptical agents attack merged list
    ├── Rubric scoring (1-5 each dimension):
    │   ├── Groundedness: 引用了代码/issues/反馈?
    │   ├── Value: impact vs effort ratio?
    │   ├── Novelty: 不是 README 里就能看出的?
    │   ├── Pragmatism: 一个 session 能 ship?
    │   ├── Leverage: 让未来工作更容易?
    │   ├── Burden: 持续维护成本?
    │   └── Overlap: 和其他 idea 重复?
    ├── 加权总分排序
    ├── 保留 Top 5-7 survivors
    └── 每个被拒 idea 附带 rejection reason
    ↓
[4] 展示幸存者
    └── Table: title, description, rationale, downsides, 验证范围, 完成标准（DoD）, key risks, confidence, complexity
    ↓
[5] 写入产出物
    ├── docs/ideation/YYYY-MM-DD-<topic>-ideation.md
    └── 包含: ranked ideas, rejection summary, session log
    ↓
[6] 精炼或交接
    ├── Option A: 选择 idea → req-alignment-check（深入澄清）
    ├── Option B: refine (调整过滤条件重新跑)
    └── Option C: end session (产出物已保存)
```

---

## 评分标准 (Rubric)

| 维度 | 5 (优秀) | 3 (中等) | 1 (差) |
|------|----------|----------|--------|
| Groundedness | 引用具体代码路径+行号 | 引用文件或模块 | 无引用 |
| Value | 高影响低投入 | 中等影响或中等投入 | 低影响高投入 |
| Novelty | 意想不到但有价值 | 合理但可预见 | 显而易见 |
| Pragmatism | 1 session 可 ship | 需要 2-3 sessions | 需要完整 sprint |
| Leverage | 解锁多个未来工作 | 有一定杠杆 | 一次性价值 |
| Burden | 零维护 | 低维护 | 高持续成本 |
| Overlap | 完全独立 | 与 1 个其他 idea 部分重叠 | 与多个高度重叠 |

---

## 产出物格式

**路径:** `docs/ideation/YYYY-MM-DD-<topic>-ideation.md`

```markdown
# Ideation: {Topic}
Date: YYYY-MM-DD | Candidates: {N} | Survivors: {N}

## Ranked Ideas
| # | Title | Score | 验证范围 | 完成标准（DoD） | Key Risks | Confidence | Complexity |
|---|-------|-------|------------------|-----|-----------|------------|------------|
| 1 | ... | 4.2/5 | 受影响模块+验证范围 | 明确完成标准 | 主要风险与代价 | High | Medium |
...

### Idea #1: {Title}
- **Description:** ...
- **Rationale:** ... (引用: `src/foo.ts:L42`, issue #123)
- **Downsides:** ...
- **验证范围:** 验什么、范围到哪、哪些链路必须覆盖
- **完成标准（DoD）:** 什么叫可交付/验证完成
- **Key Risks:** 这条想法最可能在哪些地方失败或走偏
- **Grounding:** ...

## Rejection Summary
| Idea | Rejection Reason |
|------|-----------------|
| ... | Low value, no grounding |

## Session Log
- Scanned: {file count} files, {N} TODOs, {N} issues
- Agents: {N} divergent, {N} adversarial
- Duration: ~{N} minutes
```

**幸存者硬规则：**

- 没写 `验证范围` 的 idea 不能进入下游需求澄清 / plan
- 没写 `完成标准（DoD）` 的 idea 不能作为推荐方案输出
- 没写 `Key Risks` 的 idea 不能作为最终幸存者
- `Downsides` 不能替代上述三项

---

## 跨技能集成

| 技能 | 集成方式 |
|------|----------|
| `req-alignment-check` | 选中的 idea 进入需求澄清、边界冻结和风险深挖 |
| `restore-context` | 恢复时显示上次 ideation 幸存者 |
| `compound-learning` | ideation 中发现的模式写入记忆 |
| `deep-plan` | 澄清后的 idea 转化为技术计划 |
| `quality-check` | 识别质量改进方向作为输入 |
