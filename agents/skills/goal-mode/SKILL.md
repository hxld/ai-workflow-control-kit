---
name: goal-mode
description: "Use when user says /goal, goal mode, 目标驱动, 结构化任务, structured goal, set a goal, define goal, or wants a long-running autonomous task with explicit success criteria"
allowed-tools: Bash,Read,Write,Edit,Glob,Grep,Task
---

# 面向目标的 Agent 执行模式（Goal Mode）

通过结构化目标定义驱动 Agent 长程任务的自主执行——区别于"聊天式"逐轮交互，一次性给出完整的任务规范，Agent 据此独立完成执行并自我验证。

**专家角色：** 目标定义师 — 将模糊需求编码为结构化目标契约。

**上游技能：** `req-alignment-check`, `deep-plan`
**下游技能：** `dev-workflow`, `gen-tests`, `ship-release`, `sync-progress`

---

## 何时使用

- 需要 Agent 自主执行长程任务（30 分钟+）的场景
- 代码重构、发布流水线、依赖升级、数据清理、测试修复
- 需要将任务封装为可复现、可验证的"目标包"
- "用 goal 模式跑这个需求" / "/goal" / "set a goal for this"
- 需要离线或异步交付的工作（定义后 Agent 可独立执行）

## 何时不使用

- 简单的单文件修改或机械操作 → 直接做，不需要 Goal
- 开放式头脑风暴或探索性任务 → 用 `ideate`
- 仅评估需求不执行 → 用 `requirement-assessment`
- Agent 环境不支持长程自主执行 → 降级为分步交互

---

## Iron Law

1. **歧义随执行时间放大** — 初始定义的微小歧义在 30 分钟以上的自主执行中会被持续放大，必须在目标定义阶段一次性消除。
2. **成功标准必须可观察** — 必须映射到可自动验证的客观事实（CI 通过、tag 落地、文件生成），而非 Agent 的主观判断。
3. **常见失败模式前置** — 将历史踩坑经验编码为 `common_failure_modes`，相当于给 Agent 一份避坑地图。
4. **短测不可省略** — `short_test` 是执行质量的最后一道门，确保 Agent 执行后不会遗漏验证。
5. **/goal 不替代 BDD/TDD** — BDD 定方向，TDD 定质量，/goal 定执行。三者互补。

---

## 目标定义七要素

### Goal 模板 YAML

```yaml
# goal.yaml — 目标契约
title: "<任务名称/需求标题>"
description: "<一段话描述目标>"

inputs:
  repo_url: "<仓库 URL>"
  branch: "<目标分支>"
  config_path: "<配置文件路径（可选）>"
  ref_docs: ["<参考文档路径>"]

constraints:
  - "已有 API 接口签名不可变"
  - "不得修改数据库 Schema"
  - "保持向后兼容"
  - "不引入新的外部依赖"

success_criteria:
  - "所有单测通过（`npm test` exit 0）"
  - "生成的文件列表与预期一致"
  - "代码审查无 P0/P1 问题"
  - "tag vX.Y.Z 已落地"

common_failure_modes:
  - "scope creep — 当涉及多个子系统时，Agent 容易过度扩展"
  - "忘记更新文档 — 实现后需同步更新 README"
  - "环境差异 — CI 环境与本地环境不一致"
  - "边界遗漏 — 只测了正常路径，漏了异常路径"

short_test: |
  # 快速验证命令，exit 0 为通过
  npm test
  npm run build

deliverables:
  - "PR（含变更描述和 CHANGELOG）"
  - "验证报告（通过项/失败项/覆盖率）"
```

### 字段说明

| 字段 | 作用 | 设计原则 |
|------|------|---------|
| `title` | 任务名称，明确 scope | 避免 scope creep |
| `description` | 清晰描述目标 | 一句话让 Agent 理解上下文 |
| `inputs` | 输入参数 | 补齐所有外部依赖（repo URL、路径、配置） |
| `constraints` | 约束条件 | API 不可变、时间预算、保留已有行为 |
| `success_criteria` | 成功标准 | **可观察的完成信号** |
| `common_failure_modes` | 常见失误 | 提前告知 Agent 易踩的坑 |
| `short_test` | 收尾短测 | shell 命令快速验证 |
| `deliverables` | 交付物 | PR、报告、迁移说明等 |

---

## 工作流程

### 模式 A：标准 Goal（全流程）

```
[1] 解析用户意图 → 生成 Goal 定义
    ↓
[2] 用户审核 Goal 定义 → 确认/调整
    ↓
[3] Agent 读取 Goal → 开始独立执行
    ↓
[4] 执行过程中自我检查 success_criteria
    ↓
[5] 执行 short_test → 快速验证
    ↓
[6] 产出 deliverables
    ↓
[7] 用户验收 → 确认/返工
```

### 模式 B：GoalSpec（云端/无人值守）

当面向云端执行器或无人值守循环时，使用紧凑的 GoalSpec 格式：

```yaml
# GoalSpec — 面向治理层的精简目标契约
target:            "<需求ID或任务编号>"
desired_outcome:   "mr_draft | release | report"
success_criteria:
  - "所有单测通过"
  - "MR 描述完整且含变更类型"
stop_policy:
  ask_on_high_risk:        true
  ask_before_schema_change: true
  no_merge:                 true
budget:
  max_minutes: 60
  max_steps:   20
```

GoalSpec 只说"要什么"和"边界在哪"，怎么推进 Agent 自己决定。治理层（门禁/审计/恢复）与执行层分离。

---

## 六类预置 Goal 模板

本 skill 提供 6 个可直接复用的 Goal 模板：

| 模板 | 场景 | 文件 |
|------|------|------|
| 代码重构 | 模块级重构，可回归、无行为改变 | [templates/goal-refactor.yaml](./templates/goal-refactor.yaml) |
| 发布流水线 | main → release，含 CHANGELOG 与制品 | [templates/goal-release.yaml](./templates/goal-release.yaml) |
| 数据清理 | 幂等、可追溯、异常隔离机制 | [templates/goal-cleanup.yaml](./templates/goal-cleanup.yaml) |
| 测试修复 | 红转绿 + 回归护栏 | [templates/goal-test-fix.yaml](./templates/goal-test-fix.yaml) |
| 无人值守 GoalSpec | 云端/自动执行器目标契约 | [templates/goalspec-autonomous-task.yaml](./templates/goalspec-autonomous-task.yaml) |
| 依赖升级 | 安全基线 + 兼容性报告 + 回滚指南 | [templates/goal-upgrade.yaml](./templates/goal-upgrade.yaml) |
| 内容创作 | brief → 博文/文档，含元信息 | [templates/goal-content.yaml](./templates/goal-content.yaml) |

使用方式：复制对应模板，填充 `inputs`、`constraints`、`success_criteria` 和 `common_failure_modes` 后执行。

无人值守或云端执行前，先运行：

```bash
node scripts/verify-control-contracts.js
```

该校验会确保 GoalSpec 至少包含可观察成功标准、停线策略、预算和审计字段；治理层只保留否决权，执行层由 Agent 在这些边界内推进。

---

## Goal 与 BDD/TDD 的关系

```
BDD  → 做什么（行为描述约束 AI 理解用户意图）
TDD  → 做得对（测试先行防止代码退化）
Goal → 执行稳（结构化目标驱动长程自主执行）
```

三者互补而非替代，共同构成 AI 编程工程化的完整拼图。

详细关系说明见 [references/goal-bdd-tdd-relationship.md](./references/goal-bdd-tdd-relationship.md)

---

## 输出

```markdown
## Goal 定义确认

**任务标题：** <title>

**输入：**
- repo: <url>
- branch: <branch>

**约束：**
- [ ] 约束 1
- [ ] 约束 2

**成功标准：**
- [ ] 标准 1
- [ ] 标准 2

**常见失败模式：**
- ⚠️ 模式 1
- ⚠️ 模式 2

**验证命令：**
```bash
<short_test>
```

**交付物：**
- [ ] <deliverable 1>
- [ ] <deliverable 2>

**状态：** [等待审核 / 执行中 / 完成 / 需返工]
```
