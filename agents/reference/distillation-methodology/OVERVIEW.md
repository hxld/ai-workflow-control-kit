# 系统蒸馏方法论 → AI Workflow Control Kit 映射

## 什么是系统蒸馏

系统蒸馏是一套将存量 IT 业务系统逆向工程为"AI 可理解、可调用的领域能力中心"的标准化方法论。由何明璐（人月聊IT）提出，经过合同管理系统的实跑验证。

**核心思想**：把一个面向人使用的业务系统，转化为一组面向 AI Agent 的结构化领域描述（语义层 + 能力层 + 明细层），使 AI 无需反复阅读源码就能理解业务语义并完成操作。

## 为什么这对 Kit 重要

ai-workflow-control-kit 提供了**工作流执行框架**（skills、hooks、replay），但缺少"工作流的认知燃料从哪来"的回答：

```
当前 Kit：agent → skill → 执行 → 回放验证
            ↑ 缺少"skill 的领域知识怎么来"这一环
```

系统蒸馏填补了这个缺口——它提供了从**业务系统到领域知识包**的标准流程，而 Kit 的 skills 正是这些知识包的可执行封装。

## 蒸馏产出 → Kit 组件映射

| 蒸馏产出 | 内容 | 对应 Kit 组件 | 用途 |
|---------|------|--------------|------|
| **语义层**（domain/） | 领域模型、关系、业务规则 | `agents/skills/<skill>/SKILL.md` 的上下文定义 + `references/` | 决定 skill 的触发条件、领域上下文和约束 |
| **能力层**（api/） | 用例级 API 说明 | `agents/skills/<skill>/` 的执行流程步骤 | 定义 skill 如何编排 API 调用完成业务用例 |
| **明细层**（reference/） | Schema、枚举、错误码 | `agents/skills/<skill>/references/` | skill 执行时的按需检索数据 |

## 方法论全貌

```
业务系统
  │  S0 准备与盘点
  │  S1 识别业务对象与边界（语义骨架）
  │  S2 抽取业务规则并标注执行方
  │  S3 定义能力层 API（用例级）
  │  S4 整理明细层
  │  S5 建立交叉引用与编排说明
  │  S6 验证（实跑）
  ▼
distilled/ 领域知识包              ← 本方法论输出
  │  skill 封装（人工或半自动化）
  ▼
agents/skills/<skill>/             ← Kit 的可执行技能
  │  SKILL.md + references/
  ▼
Agent 执行（通过 replay-autopilot 验证效果）
```

## 六条设计原则

| 蒸馏原则 | Kit 中的对应 |
|---------|-------------|
| 语义层/明细层分离 | skill 上下文常驻（SKILL.md body）vs references/ 按需加载 |
| 用例级 API 粒度（非 CRUD） | skill 命令应以"完整业务动作"为粒度（如"录入合同"，非"创建合同记录"） |
| 规则标注执行方 | skill 中区分【服务端强制】和【调用方需预判】约束 |
| 事实优先级明确 | 与 `replay-autopilot` 的 source-of-truth 分类一致 |
| 写权限分级机制化 | skill 的 dry-run → 确认 → 提交三步态 |
| 可验证 | replay-autopilot 的 oracle 对比验证可直接复用 |

## 扩展阅读

- [process-s0-to-s6.md](./process-s0-to-s6.md) — 七阶段蒸馏流程详解
- [../knowledge-base-design/knowledge-taxonomy.md](../knowledge-base-design/knowledge-taxonomy.md) — 知识库四类知识框架（蒸馏产物的分类消费规则）
- [../knowledge-base-design/three-loops.md](../knowledge-base-design/three-loops.md) — 三循环运营模型（蒸馏产物的持续维护）
