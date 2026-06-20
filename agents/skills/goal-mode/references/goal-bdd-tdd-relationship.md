# Goal 模式与 BDD/TDD 的关系

## 核心命题

BDD、TDD、/goal 是 AI 编程工程化的三个互补维度。它们不是替代关系，而是从不同角度约束 AI 行为。

```
BDD 定方向（做什么） → TDD 定质量（做得对） → Goal 定执行（执行稳）
                            ↓
                    完整的 AI 工程化交付
```

---

## 一维：BDD（行为驱动开发）

**解决"做什么"的问题**

BDD 用自然语言行为描述前置需求，确保 AI 理解用户意图：

```gherkin
Feature: 合同录入
  Scenario: 创建有效合同
    Given 用户已登录
    When 用户录入一份完整合同
    Then 系统创建合同并触发审批流
```

**在 Goal 模式中的映射：**
- Goal 的 `description` 和 `success_criteria` 应是 BDD 场景的浓缩
- 复杂 BDD 场景可放入 Goal 的 `inputs.ref_docs`
- BDD 的验收条件直接对应 Goal 的 `success_criteria`

---

## 二维：TDD（测试驱动开发）

**解决"做得对"的问题**

TDD 用测试先行约束 AI 输出，防止"改一增三"的代码退化：

```
RED（写失败测试） → GREEN（最小实现） → REFACTOR（重构）
```

**在 Goal 模式中的映射：**
- Goal 的 `short_test` 通常是测试套件的入口
- `success_criteria` 中至少包含"所有测试通过"
- `common_failure_modes` 中包含常见的测试陷阱
- TDD 的 RED 阶段应在目标定义中显式声明

---

## 三维：/goal（面向目标的执行模式）

**解决"执行稳"的问题**

/goal 用结构化目标定义驱动 Agent 长程任务的自主执行：

```
定义目标 → 一次性给齐 → Agent 自主执行 → 自我验证 → 交付
```

**与 BDD/TDD 的关系：**

| 维度 | BDD | TDD | /goal |
|------|-----|-----|-------|
| 关注点 | 做什么 | 做得对 | 执行稳 |
| 核心工具 | Feature 文件 / 行为描述 | 测试用例 / 红绿循环 | Goal 模板 / GoalSpec |
| 执行时机 | 开发前 | 开发中 | 整个长程任务 |
| 输入 | 用户需求 | BDD 行为描述 | Goal 模板 |
| 输出 | 行为规范 | 测试用例集 | 交付物（PR/标签/报告） |
| 验证方式 | 行为评审 | 测试通过 | short_test + deliverables |
| 失败成本 | 做错需求 | 有 Bug | 任务中断或结果偏离 |
| 适合场景 | 需求对齐 | 质量保障 | 自主长程任务 |

---

## 融合工作流

```
[BDD] 需求 → 行为描述
   ↓
[/goal] 目标定义 → 封装为 Goal 模板
   ↓
[TDD] RED → GREEN → REFACTOR（在 Goal 执行过程中）
   ↓
[/goal] short_test + deliverables → 交付验收
```

**示例：重构任务的三维融合**

```yaml
# BDD: "重构支付模块，保持行为不变，提升可测试性"
# Goal:
title: "支付模块重构"
description: "重构支付模块，保持行为不变"
success_criteria:
  - "所有已有单测通过"            # TDD 红线不可破
  - "新增可测试性接口（DI 就绪）"  # BDD 行为契约
  - "代码审查通过"                 # 质量门禁
# TDD: Agent 执行中先写表现有行为的测试再重构
constraints:
  - "已有 API 签名不可变"          # BDD 行为契约
  - "覆盖率不得下降"              # TDD 质量红线
```

---

## 适用边界

| 场景 | 推荐方案 | 理由 |
|------|---------|------|
| 需求不明确 | BDD 先行 | 先对齐做什么，再定怎么做 |
| 质量敏感 | TDD 先行 | 先织安全网，再改代码 |
| 任务明确但量大 | /goal 先行 | 先封装目标，再自主执行 |
| 需求模糊+质量敏感+任务大 | BDD → TDD → /goal | 三者串联，缺一不可 |

## 关联

- [../templates/goal-refactor.yaml](../templates/goal-refactor.yaml) — 代码重构模板
- [../templates/goal-release.yaml](../templates/goal-release.yaml) — 发布流水线模板
- [../templates/goal-test-fix.yaml](../templates/goal-test-fix.yaml) — 测试修复模板
- [../../knowledge-base-design/knowledge-taxonomy.md](../../knowledge-base-design/knowledge-taxonomy.md) — 知识分类体系（Goal 的约束来源）
