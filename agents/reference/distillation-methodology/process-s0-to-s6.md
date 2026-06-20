# 系统蒸馏七阶段流程

> 来源：何明璐（人月聊IT）《AI大模型逆向工程-将IT业务系统蒸馏为独立的Skills技能包》
> 适配：ai-workflow-control-kit 的 skill 封装体系

## 流程总览

```
S0 准备与盘点 → S1 业务对象与边界 → S2 规则抽取与标注 → S3 用例级 API 定义
    → S4 明细层整理 → S5 交叉引用 → S6 实跑验证
```

每个阶段向后传递明确的制品。前期产出是后期输入。

---

## S0：准备与盘点

**目标**：收集素材，评估蒸馏范围。

| 输入素材 | 优先级 | 说明 |
|---------|--------|------|
| 原始需求文档 | ⭐⭐⭐ 必需 | 最接近业务意图的来源 |
| 数据库 Schema + 实例数据 | ⭐⭐⭐ 必需 | 了解对象结构和状态空间 |
| 本体/领域模型 | ⭐⭐ 推荐 | 已有抽象可节省时间 |
| 源代码（服务层+接口层） | ⭐⭐ 推荐 | 验证实际行为 |
| 接口文档/Swagger | ⭐ 可选 | 加速 API 抽取 |

**对 Kit 的适配**：
- 使用 `scripts/` 下的扫描工具收集信息
- 本项目蒸馏结果放在 `agents/skills/<新skill>/` 目录
- 初始阶段可运行 `node scripts/verify-ai-workflow-kit.js` 确认环境

---

## S1：识别业务对象与边界（语义骨架）

**目标**：识别核心领域对象、关系、状态机。

**活动**：
1. 领域对象清单（Entity）：合同、客户、发票、付款单……
2. 对象间关系：1:1 / 1:N / N:M
3. 对象状态机：草稿 → 生效 → 过期 / 已开票 → 已收款 → 已核销

**产出物**：`semantic/_index.md` + `semantic/<entity>.md`

**Kit 对应**：SKILL.md 的 `## Context` / `## Domain Model` 章节。

**示例**（合同管理）：

```markdown
## 领域对象：合同 (Contract)

### 状态
- draft → active → expired
- active → terminated

### 关键属性
- contractId: string (主键)
- contractName: string
- status: ContractStatus 枚举
- totalAmount: decimal
- customerId: string → Customer

### 规则
- 【服务端强制】active 状态的合同不可删除
- 【调用方需预判】合同金额超 100 万需二级审批
```

---

## S2：抽取业务规则并标注执行方

**目标**：识别每个业务规则，标注谁负责保证。

| 标注 | 含义 | Kit skill 中的处理 |
|------|------|-------------------|
| 【服务端强制】 | API 会拒绝违反 | 可设为默认假设，无需 AI 预判 |
| 【服务端维护】 | 服务端自动维护 | AI 不需要操作 |
| 【调用方需预判】 | 服务端不拦截，AI 调用前需判断或问人 | 需写入 skill 的约束章节 + success_criteria |
| 【副作用】 | 操作触发其他影响（消息/异步） | skill 需包含验证步骤 |

**产出物**：`rules.md`（按服务端强制/调用方需预判分组）

**Kit 对应**：SKILL.md 的 `## Constraints` / `## Common Failure Modes`

---

## S3：定义能力层 API（用例级）

**目标**：按业务用例定义 API，非 CRUD 级、非界面级。

| 粒度 | 判据 | 示例 |
|------|------|------|
| ✅ 用例级 | 一个完整、自洽的业务动作 | `录入合同`、`确认收款`、`发起审批` |
| ❌ CRUD 级 | 太细，AI 需自行编排多步 | `插入合同记录`、`更新合同状态` |
| ❌ 界面级 | 夹带 UI 态，语义噪音大 | `提交合同表单`、`加载合同列表页` |

**产出物**：`api/_index.md` + `api/<用例>.md`（每个文件四要素）

| 要素 | 内容 |
|------|------|
| 用途 | 这个 API 做什么业务操作 |
| 入参 | JSON Schema 或表格 |
| 出参 | JSON Schema 或表格 |
| 规则约束 | 受哪些业务规则影响 |

**Kit 对应**：SKILL.md 的 `## Steps` / `## Inputs` / `## Outputs`

---

## S4：整理明细层

**目标**：字段级 Schema、枚举、错误码，按需检索。

**产出物**：

| 文件 | 内容 |
|------|------|
| `reference/schema/<表>.md` | 表结构 + 字段说明 + 业务含义 |
| `reference/enums.md` | 枚举值 + 含义 |
| `reference/error-codes.md` | 错误码 + 原因 + 处理建议 |
| `reference/model-code-conflicts.md` | ⚠️ 需求文档与代码不一致的差异清单 |

**关键原则**：字段/枚举/错误消息**以代码实际行为为准**，而非需求文档。

**Kit 对应**：
- skill 子目录下的 `references/` 文件夹
- 通过 SKILL.md 的加载策略声明（常驻 vs 按需）

---

## S5：建立交叉引用与编排说明

**目标**：对象 ↔ 接口 ↔ Schema 互相链接。

**格式**：`[[slug]]` 交叉引用

**产出**：
- `api/_index.md` 中列出常用编排序列（典型业务流水线）
- 每个编排序列标注：涉及哪些 API、数据流向、门禁条件

**Kit 对应**：workflow-router + skills 编排文件

---

## S6：验证（实跑）

**目标**：AI 仅凭蒸馏文档完成真实操作，验证文档可用性。

**验证集四类场景**：

| 类型 | 示例 | 通过标准 |
|------|------|---------|
| 读 | "查合同 123 的状态" | 返回值与真实系统一致 |
| 写 | "录入一份新合同" | API 调用参数与真实系统匹配 |
| 统计 | "本月待收款总额" | 统计逻辑正确 |
| 规则反例 | "尝试删除 active 合同" | 按文档预测被拒 |

**Kit 对应**：`replay-autopilot` 的回放评估可直接用于 S6 验证：
1. 将蒸馏文档作为 oracle
2. 构造验证任务（四类场景）
3. 运行 replay 对比实际输出 vs 预期
4. 落差不通过则返回 S1-S5 修正

---

## 与 Kit 现有 skill 的关系

```
S0-S6 流程 ──→ distilled/ 领域知识包
                     │
                     ├──→ adapt to existing skill: 将领域知识注入已有 skill 的 references/ 目录
                     │    例：dev-workflow 接入合同管理领域的 knowledge-base
                     │
                     └──→ new skill: 将蒸馏产出封装为新 skill
                          例：agents/skills/contract-management/
                            ├── SKILL.md (引用语义层 + 能力层)
                            └── references/ (明细层)
```
