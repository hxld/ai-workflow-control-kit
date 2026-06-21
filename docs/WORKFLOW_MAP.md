# 工作流编排地图

> 本文档将 ai-workflow-control-kit 的 skills 按完整交付流水线编排为一张导航图。
> 目的是让用户一眼看清：什么阶段该用哪个 skill、产出喂给谁、质量门禁在哪。

## 完整链路

```
需求输入 ──→ [评估/对齐] ──→ [规划] ──→ [实现] ──→ [测试] ──→ [审查] ──→ [发布] ──→ [复盘]
                 │                                    │
                 └──→ [预检]（每次修改文件前）───────────────┘
```

---

## 第一阶段：需求接入与评估

```
┌─────────────────────────────────────────────────────────────┐
│                    需求评估阶段                              │
│                                                             │
│  raw input (BRD/PRD/口述)                                    │
│       │                                                     │
│       ▼                                                     │
│  requirement-assessment (P0 评分 + 否决权)                   │
│       │ 100分制 → ≥阈值放行                                 │
│       ▼                                                     │
│  req-alignment-check (隐藏需求挖掘 + 对齐检查)                │
│       │ 输出：对齐报告 + 需求缺失清单                        │
│       ▼                                                     │
│  [可选] deep-plan (技术方案 + 任务拆解 + 依赖DAG)            │
│       │ 输出：plan.md + 工作量估算                            │
│       ▼                                                     │
│  [可选] backend-effort-estimate (工时/成本评估)               │
│       │ 输出：effort report                                  │
│       ▼                                                     │
│  → 产出：对齐的需求 + 技术方案 + 任务清单                    │
│     → 传递给实现阶段                                        │
└─────────────────────────────────────────────────────────────┘
```

**关键门禁**：
| 门禁 | skill | 通过条件 |
|------|-------|---------|
| 价值过滤 | `requirement-assessment` | 得分 ≥ 阈值 |
| 需求对齐 | `req-alignment-check` | 隐藏需求清单已处理 |
| 方案评审 | `deep-plan` | plan.md 含依赖 DAG |

---

## 第二阶段：实现

```
┌─────────────────────────────────────────────────────────────┐
│                    实 现 阶 段                               │
│                                                             │
│  ← 来自需求阶段：需求 + 方案 + 任务清单                      │
│       │                                                     │
│       ▼                                                     │
│  pre-flight-check (强制门禁，每次修改前必过)                  │
│       │ 检查：记忆/边界/构建/隔离/工作模式                   │
│       │ 通过 → 可进入实现                                    │
│       ▼                                                     │
│  dev-workflow (主实现流水线)                                 │
│       │ 阶段：                                              │
│       │  [0] 预检查 + 模式确认                               │
│       │  [1] 需求分析（结合 req-alignment-check）             │
│       │  [2] 任务规划（产出：任务清单 + DAG）                 │
│       │  [3] 实现（按任务逐一）                               │
│       │  [4] 验证                                                                    │
│       │  [5] 同步进度                                       │
│       │                                                     │
│       可选模式：                                             │
│       ├── hotfix：最小实现 + 回归验证（跳过需求阶段）         │
│       ├── planned-dev：完整流水线                             │
│       └── tooling：走治理技能，不套开发链                     │
│                                                             │
│  → 产出：实现代码 + 本地验证通过                            │
└─────────────────────────────────────────────────────────────┘
```

**关键门禁**：
| 门禁 | skill | 通过条件 |
|------|-------|---------|
| 预检 | `pre-flight-check` | 工作模式确认 + 隔离检查 |
| 进度同步 | `sync-progress` | 与 plan.md 对比无遗漏 |

---

## 第三阶段：质量保障

```
┌─────────────────────────────────────────────────────────────┐
│                    质 量 保 障 阶 段                         │
│                                                             │
│  ← 来自实现阶段：代码变更                                    │
│       │                                                     │
│       ▼                                                     │
│  quality-check (客观质量评分 0-10)                           │
│       │ 自动检测工具 + 趋势跟踪                               │
│       │ 得分 < 阈值 → 不通过                                  │
│       ▼                                                     │
│  gen-tests (测试生成 + 修复 + 验证循环)                       │
│       │ 上游：deep-plan / dev-workflow / auto-complete       │
│       │ 模式：test-fix-verify 循环                            │
│       │ 输出：测试覆盖率报告 + 通过/失败                      │
│       ▼                                                     │
│  deep-review (多专家代码审查)                                 │
│       │ specialist 派遣 + 置信度门控                          │
│       │ 结构化发现 + Fix-First                              │
│       │ 输出：review report + fix 清单                       │
│       ▼                                                     │
│  [可选] sync-progress (进度状态同步到 wiki/workflow-history)  │
│       │ 比较 plan.md vs 实际代码变更                              │
│       │ 输出：差异报告 + sync 状态                            │
│       │                                                     │
│  → 产出：测试通过 + quality ≥ 阈值 + review 通过                      │
└─────────────────────────────────────────────────────────────┘
```

**关键门禁**：
| 门禁 | skill | 通过条件 |
|------|-------|---------|
| 质量评分 | `quality-check` | 0-10 分 ≥ 团队阈值（默认 6） |
| 测试 | `gen-tests` | 所有用例通过 |
| 审查 | `deep-review` | 无 P0/P1 issues，或已修复 |
| 进度对齐 | `sync-progress` | 方案 vs 代码无重大偏差 |

---

## 第四阶段：交付与复盘

```
┌─────────────────────────────────────────────────────────────┐
│                    交 付 与 复 盘                            │
│                                                             │
│  ← 来自质量阶段：验证通过的代码                               │
│       │                                                     │
│       ▼                                                     │
│  pre-flight-check (发布前预检)                               │
│       │ 检查：构建/制品/依赖/回滚预案                         │
│       ▼                                                     │
│  ship-release (发布流水线)                                   │
│       │ 步骤：tag → 构建 → 发布 → 验证                      │
│       │ 输出：release note + CHANGELOG 更新                  │
│       ▼                                                     │
│  retro (复盘)                                                │
│       │ 输入：本次交付的完整 trace                            │
│       │ 活动：什么好/什么不好/下次改进                         │
│       │ 输出：改进项 → 反哺到 knowledge-base                 │
│       │       → [纠错反哺循环] 更新 references/           │
│       │                                                     │
│  → 产出：发布的版本 + 复盘记录 + 知识库更新                  │
└─────────────────────────────────────────────────────────────┘
```

**关键门禁**：
| 门禁 | skill | 通过条件 |
|------|-------|---------|
| 发布预检 | `pre-flight-check` | 回滚预案就绪 |
| 复盘记录 | `retro` | 改进项已写入 workflow-history |

---

## 全局技能编排（非流水线固定节点）

以下技能在多个阶段都可能被调用，不是流水线的固定节点：

| skill | 触发时机 | 用途 |
|-------|---------|------|
| `ideate` | 需求模糊时 | 头脑风暴、方案探索 |
| `compound-learning` | 遇到不熟悉的领域 | 快速上下文建立 |
| `dialogue-learning` | 复杂场景需逐步对话 | 渐进式明确需求 |
| `auto-complete` | 实现中补充逻辑 | 代码补全，轻量级 |
| `knowledge-refresh` | 知识库过时 | 刷新领域知识索引 |
| `restore-context` | 中断恢复 | 阅读 health history、重载上下文 |
| `add-comments` | 代码审查后 | 补注释提升可读性 |
| `resolve-feedback` | 收到外部反馈 | 结构化处理反馈事件 |
| `workflow-router` | 路由决策时 | 决定下一个合适 skill |
| `pre-flight-check` | 每次写入操作前 | 安全检查（贯穿全流程） |

---

## 跨阶段质量门禁总表

| ID | 门禁 | skill | 门禁类型 | 触发阶段 |
|----|------|-------|---------|---------|
| G1 | 需求价值 | `requirement-assessment` | 软性（推荐） | 需求接入 |
| G2 | 需求对齐 | `req-alignment-check` | 硬性 | 需求 → 方案 |
| G3 | 预检 | `pre-flight-check` | 硬性 ⛔ | 每次写入前 |
| G4 | 质量评分 | `quality-check` | 硬性（配置阈值） | 实现后 |
| G5 | 测试通过 | `gen-tests` | 硬性 ⛔ | 发布前 |
| G6 | 代码审查 | `deep-review` | 硬性（P0/P1） | 发布前 |
| G7 | 进度对齐 | `sync-progress` | 推荐 | 实现后 |
| G8 | 发布预检 | `pre-flight-check` | 硬性 ⛔ | 发布前 |
| G9 | 复盘改进 | `retro` | 推荐 | 发布后 |

> ⛔ 硬性门禁：不通过则阻断流程，直到问题修复。
> 无标记：推荐但不强制，视风险缩放。

---

## 与本仓库其他方法论的关系

| 方法论 | 对应关系 |
|--------|---------|
| [Goal 模式](./docs/GOAL_PATTERN.md)（规划中） | 每个 skill 的调用可封装为 Goal：定义 title/inputs/success_criteria/failure_modes |
| [知识库分类体系](./agents/reference/knowledge-base-design/knowledge-taxonomy.md) | 各阶段消费的知识类型不同：需求阶段吃 Knowledge，实现阶段吃 Facts |
| [系统蒸馏](./agents/reference/distillation-methodology/OVERVIEW.md) | S3（用例级 API）影响 skill 粒度设计；S6（验证）影响 replay 策略 |
| [replay-autopilot](../replay-autopilot/) | 端到端验证工作流编排的正确性 |

## 新增组件引用

以下是在本地图基础上新增的组件：

### Goal 模式 skill（`agents/skills/goal-mode/`）
- 用途：将长程任务封装为结构化 Goal，定义 title/inputs/constraints/success_criteria/failure_modes/deliverables
- 位置在工作流中：可以在任何阶段启动 —— 一个复杂需求可以用 Goal 封装后由 Agent 自主执行
- 与 BDD/TDD 的关系：BDD 定方向、TDD 定质量、Goal 定执行
- 机器校验：`node scripts/verify-control-contracts.js` 会检查无人值守 GoalSpec 模板是否包含成功标准、停线策略、预算和审计字段

### PRD 质量流水线（`requirement-assessment` 的增强）
- 用途：在需求评估阶段对 PRD 执行三层体检（规范层/完备层/自洽层）
- 影响：在现有 100 分制基础上增加 ±10 分的 PRD 质量附加分
- 反哺：检测到的系统性 PRD 问题可反哺到知识库

### 需求工作空间隔离（`scripts/start-requirement-workspace.js`）
- 用途：为跨服务需求创建隔离工作空间（PRD + 方案 + 多服务 worktree）
- 位置：紧接需求评估之后，在规划/实现之前
- 适用：涉及 2+ 服务的需求
