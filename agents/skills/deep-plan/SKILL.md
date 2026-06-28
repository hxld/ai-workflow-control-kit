---
name: deep-plan
description: "Use when user asks 深度规划, 技术设计, deep plan, 技术方案, 需求转技术文档, generate technical doc, or before coding a non-trivial requirement"
allowed-tools: Bash,Read,Write,Edit,Glob,Grep,Task
---

# 深度规划

把需求对齐结果转成可审查、可实现、可验证的技术计划。

**专家角色：** 首席架构师。

**上游技能：** `req-alignment-check`, `ideate:planning-brainstorm`
**下游技能：** `deep-review`, `dev-workflow`, `gen-tests`, `backend-effort-estimate`

## 何时使用

- 用户要求技术方案、深度规划、需求转技术文档。
- 需求涉及多模块、多接口、外部集成、状态流转、报表/导出、任务或落库。
- `req-alignment-check` 已输出矩阵，需要落到设计。
- 无 PRD 但已有 branch / commit reconstruction 结果，需要转成可验证计划。

## 何时不使用

- 无需求源，且没有后验重建材料。
- 单文件机械修改。
- 用户明确只要快速口头建议。

## Iron Law

没有冻结表、Surface 矩阵、必要的预计变更矩阵（Expected Diff Matrix）和风险缩放后的测试设计控制（Test Design Control），不得把规划标记完成。
技术方案、任务计划和评审材料默认中文优先；英文术语只作为括号别名或内部状态码。

复杂需求交付矩阵模板见：`../dev-workflow/references/complex-requirement-delivery-kit.md`。

## Optional Design Subagent Mode

当需求为 large、review pressure、多 surface、外部集成或跨上下文证据采集，且当前宿主支持并允许并行代理时，可派只读设计子 agent。详细契约见 `references/subagent-design-contracts.md`。

子 agent 只提供 context/evidence/candidate rows；主会话必须合并回同一份 `tech-design.md`、OpenSpec 和实现切片。禁止子 agent 直接写主方案、扩大范围、把历史/oracle 材料当需求源，或替代用户审批与 Implementation Readiness 判定。

## 工作流

1. Resume + Scope：定位 feature、需求源、已有 `.doc` / `openspec`。
2. Source Boundary：把需求原文、本轮方案、历史文档、后验 oracle 分开；实现前不得用 oracle。
3. 分支/提交反推：若无 PRD，保留反推需求置信度、Diff 角色矩阵和验证缺口。
4. Baseline Capability Scan：确认已有、部分已有但口径不符、缺失、无需改但需证据的能力。
5. **Domain Fact Sheet Gate（硬门禁）**：对需求中提到的每个表名/字段名/服务名，grep 确认实际类型、方法签名和可复用方法。产出 Domain Fact Sheet。未完成不得进入步骤 6。
6. **隐含架构决策 Checklist（硬门禁）**：逐项回答触发方式、事务边界、失败处理、幂等性、状态依赖、afterCommit 需求、数据字典依赖。未回答不得进入步骤 7。
7. Domain Language Alignment：继承需求阶段术语表；若发现代码/文档冲突，回到 `req-alignment-check` 冻结。
8. 验证基线计划：定义基线探测、RED/GREEN 命令和 blocker 分类。
9. 研究现有实现：入口、服务、mapper、DTO、状态、日志、测试。
10. Surface 挖掘：把真实入口、编排服务、副作用、生成物、前端/导出和测试承载面挖出来。
11. 改动影响搜索：对规则、字段、枚举、数据来源、方法签名和 shared helper 做只读影响搜索。
12. 审查接口契约、对标实现、可观测性、显式需求契约。
13. 若上游有同症状分支矩阵（Same Symptom Branch Matrix），生成分支覆盖计划，说明覆盖、排除、验证和 blocker。
14. 规划盘问门（Planning Brainstorm Gate）：对非平凡需求执行自我苏格拉底式方案盘问，输出为什么这样做、为什么不那样做、隐藏 surface 和验证断言。
15. 对新增/重构模块执行架构深度检查，确认接口是否够小、测试面是否正确、seam 是否真实。
16. 生成预计变更矩阵（Expected Diff Matrix）；若复用既有实现，先拆 `intended_change_slice` 与 `out_of_scope_drift`。
17. 生成测试设计控制（Test Design Control）：影响范围、风险分级、判定表、可执行步骤、覆盖校验；小需求可用 mini form。
18. 大需求先生成能力切片矩阵（Capability Slice Matrix），再结构化实现单元。
19. 用户要求自主实现或 90%+ 覆盖时，生成 90% 覆盖计划，明确必须实现、可后置和必须暂停确认的项。
20. 对跨边界、不可逆、高返工或高置信但不可由编译器证明的决策，生成决策反证点（Decision Doubt Checkpoint）；命中决策记录条件时写决策记录候选。
21. 设计问题不清但可低成本实证时，生成一次性原型计划，并定义删除或吸收条件。
22. 命中 L2/L3、review pressure、多 surface、自主实现 90%+ 或高返工成本时，生成“实现前方案审查包”，交给 `deep-review` 的 `PRE-IMPLEMENTATION-REVIEW` 模式。
23. 同步产出 `.doc/<feature>/tech-design.md` 与 `openspec/changes/<change>/...`。
24. 进入用户审批门。

## 用户可见文档语言

`tech-design.md`、`task_plan.md`、方案审查包和人审问题默认中文优先。表头使用中文；英文只放括号别名，例如“预计变更矩阵（Expected Diff Matrix）”。代码符号、命令、文件路径、状态枚举、协议字段和已有英文文件名保持原文。

## 必须冻结

### 领域事实表门（Domain Fact Sheet Gate，硬门禁）

编码前必须对需求中提到的每个表名/字段名/服务名执行 grep/Read 确认实际类型、方法签名和可复用方法，产出：

```markdown
| 需求提及 | 代码搜索结果 | 真实类型/签名 | 可复用方法 | 需新建 | assumption |
|----------|-------------|---------------|-----------|--------|-----------|
```

规则：

- 需求说"XX金额字段" → 必须找到对应实体类并确认字段是 `String`、`BigDecimal` 还是 `Long`
- 需求说"写入XX表" → 必须找到对应 Mapper 的实际方法名（不能假设叫 `insert`）
- 需求说"查询XX配置" → 必须找到实际 Service/Mapper 并确认字段名（不能从需求文字推测字段名）
- 需求说"默认值=XX类型/XX名称" → 必须找到数据字典或配置表查询方法（不能硬编码字符串）
- 每行的 assumption 列必须是 `confirmed` / `assumed_type` / `assumed_existence` / `needs_external_doc` 之一
- **Hard Gate：** Domain Fact Sheet 有任一 `assumed_existence` 行且无后续确认时，`Implementation Readiness = NO-GO`

### 隐含架构决策 Checklist（硬门禁）

每个涉及自动触发、状态流转、异步编排的需求，必须逐项回答：

```markdown
| 决策项 | 决策结论 | 实现方式 | 证据/假设 |
|--------|---------|---------|----------|
| 触发方式区分 | 系统触发 vs 人工触发如何区分？ | 具体字段/参数/请求头 | |
| 事务边界 | 哪些步骤同一事务？哪些可异步？ | @Transactional 边界 | |
| 失败处理 | 哪些失败阻断主链？哪些独立重试？ | 异常分类 | |
| 幂等性 | 重复触发怎么办？ | 去重机制 | |
| 状态依赖 | 前置条件是否依赖存储层实时状态？ | 查询时机 | |
| afterCommit 需求 | 是否有"成功后才执行"的副作用？ | 回调机制 | |
| 数据字典/配置依赖 | 是否需要查询配置表、枚举或数据字典？ | 查询方法 | |
```

规则：

- 每行必须有决策结论和实现方式，不能空白
- "触发方式区分"的答案必须映射到具体代码实现方式（字段值、参数、用户ID 等）
- 涉及多步骤编排时，事务边界必须标注哪些步骤在事务内、哪些在事务外
- **Hard Gate：** 涉及自动流转的需求若未回答"触发方式区分"，`Implementation Readiness = NO-GO`

### Source Boundary

```markdown
| 材料 | 分类 | 实现前可用 | 用途 | 风险 |
|------|------|------------|------|------|
```

分类：`requirement_source`、`current_plan_source`、`historical_source`、`oracle_source`。
历史最终态、目标提交、上一轮 replay 结果只能做后验审查；若用户要求按 diff 移植，必须显式改成 diff-port 模式。

### 分支 / 提交反推

当需求来自分支、commit range、patch 或目标 diff，且没有 PRD 时，技术方案必须保留：

```markdown
| 反推需求 | 置信度 | 证据 | 缺失来源 | 验证缺口 | 计划动作 |
|----------|--------|------|----------|----------|----------|
| 文件族 | 角色 | 预期内/意外 | 共享影响 | 验证方式 |
```

规则：

- 低/中置信推断不得变成已确认需求。
- bugfix 没有原始失败证据时，验证计划只能承诺 `compile_pass + verification_gap`，不能承诺已复现修复。
- 外部接口必须冻结 request / response / signature / config / empty-case / idempotency 合约，并标出外部 owner 证据。
- 命中共享 enum、base handler、framework、shared DTO、shared util 或公共配置时，升级为 shared-impact 设计。

### Baseline Capability Scan

```markdown
| 能力/行为 | 当前状态 | 证据链 | 缺口 | 处理方式 |
|-----------|----------|--------|------|----------|
```

当前状态只能是：`EXISTS`、`PARTIAL_MISMATCH`、`MISSING`、`OUT_OF_SCOPE`。写“应该已有”但无证据 = `NO-GO`。

### 验证基线计划（Verification Baseline Plan）

```markdown
| 阶段 | 命令/证据 | 预期 | blocker 分类 | 通过后才能说明什么 |
|------|-----------|------|--------------|-------------------|
```

分类：`none`、`baseline_compile_blocker`、`feature_diff_blocker`、`test_runtime_blocker`、`environment_blocker`。
PowerShell 下静态 Maven 命令含 `-Dtest` / `-Dsurefire` 时，优先给出可复制的 `mvn --% ...` 模板；若命令含变量或动态拼接，必须改用参数数组或逐参数引用。
基线 blocker 不是需求 RED，必须在实现计划里单独处理。

### 接口契约冻结表

```markdown
| 接口/入口 | 调用方 | 请求 | 响应 | 兼容性 | 鉴权/幂等 | 错误语义 | 测试 |
|-----------|--------|------|------|--------|-----------|----------|------|
```

外部接口、DTO、配置或异步任务有任一项不清 = `NO-GO`；字段、列、flag、enum、payload shape 必须能追到 `literal -> code symbol -> DB/API/wire name -> exact value/shape -> test assertion`。

外部错误或第三方协议问题还需补责任边界：`raw request -> raw response -> status/code -> retry/idempotency -> config version -> owner evidence -> conclusion`。

配置、缓存或数据链路问题还需补：`expected rule -> actual config/data source -> precedence/filter -> transform -> persistence -> output -> verification`。

### 对标实现继承表

需要复用旧逻辑时：

```markdown
| 现有行为/文件族 | 新需求是否需要 | intended_change_slice | out_of_scope_drift | 处理方式 | 原因 |
|-----------------|----------------|-----------------------|--------------------|----------|------|
```

不能用“沿用旧逻辑”替代逐项判断。
不能把旧分支、旧补丁、示例实现中的无关重构、生成物、格式化或旁路功能带入新需求。

### 显式需求契约冻结表

来自 `req-alignment-check`，必须保留：

`literal -> order -> must happen -> must not happen -> ownership/surface -> code location -> test assertion`

固定文案、字段来源、失败场景、空值、顺序、精确维度、多 surface 均必须进入表。

### 分支覆盖计划（Branch Coverage Plan）

若 `req-alignment-check` 产出 Same Symptom Branch Matrix，技术方案必须把每个分支落到实现或明确排除，防止“修了目标函数”被误认为“修了整个症状”。

```markdown
| 症状分支 | 前置条件/入口 | 计划动作 | 预计文件族 | 验证 / must-not | 状态 |
|----------|--------------|----------|------------|-----------------|------|
```

规则：

- `plan action` 只能是 `implement`、`verify_existing`、`defer_with_reason`、`out_of_scope_confirmed`、`blocked_needs_evidence`。
- `implement` 行必须进入 Expected Diff Matrix 和 Capability Slice Matrix。
- `verify_existing` 行必须进入 Test Design Control、静态证据或生产采证计划。
- `defer_with_reason` / `blocked_needs_evidence` 不能计入完成覆盖率，并必须由 `sync-progress` 写入 Review Tier Closure。
- L2/L3 风险任务缺 Branch Coverage Plan 时，`Implementation Readiness = NO-GO:same_symptom_gap`。

### 规划盘问门（Planning Brainstorm Gate）

非平凡需求在技术方案冻结前必须有一轮 grounded 自我盘问；有需求文档不代表方案已充分成立。

```markdown
| PB 编号 | 需求/事实 | 追问 | 方案A | 方案B | 选择方案 | 放弃理由 | 风险 | 验证断言 |
|---------|-----------|------|-------|-------|----------|----------|------|----------|
```

PB-ID 规则：

- 使用稳定 `PB-xx`，并在实现单元、测试策略、审查发现和收口账本中沿用。
- 固定字面量、must-not、多 surface、数据源/owner、状态/事务、副作用、外部契约、用户已纠偏或 review pressure 命中时必须有 PB 行；其余需求按风险取 Top 3-5。
- 高风险场景可按需读取 `ideate/references/planning-brainstorm-question-bank.md` 的相关问题，不把整份问题库复制进技术方案。

最少追问：

- 为什么选这个入口、数据源、状态点、事务边界或测试面？
- 为什么不选相邻 helper、旧链路、展示层、持久化层或异步后置点？
- 哪个入口、surface、must-not、副作用、空值或 fallback 最容易漏？
- 这条选择靠什么本地证据证明，靠什么 RED/GREEN 或静态断言收口？

Hard Gate：非平凡需求、review pressure、自主实现、用户已纠偏、多 surface 或高返工成本任一命中时，缺少 Planning Brainstorm Matrix = `Implementation Readiness = NO-GO`。小型机械改动可跳过，但 `skip_reason` 只能是 `typo_or_comment_only`、`pure_formatting_no_behavior`、`generated_sync_no_behavior`、`single_file_mechanical_rename_with_static_guard` 或 `no_requirement_decision_surface`；`prd_exists`、`looks_simple`、`time_pressure`、`tests_pass`、`model_confident` 均无效。

### Surface 覆盖矩阵

```markdown
| Surface | 入口 | 编排服务 | 查询/写入点 | 输出字段 | 用户可见结果 | 独立测试点 |
|---------|------|----------|-------------|----------|--------------|------------|
```

每个 surface 必须有承载链路和验证点。

### Surface 挖掘（Surface Mining Pass，硬门禁）

多 surface、大需求或同时出现自动流转、报表/导出、前端、日志、任务、图片/附件/模板、外部协议时，Expected Diff Matrix 之前必须先做只读挖掘：

```markdown
| 能力 | 运行时入口 | 编排服务 | 副作用/表 | 生成物/模板 | 前端/导出 surface | 测试/harness | 证据 | 缺口 |
|------|------------|----------|-----------|------------|----------------|--------------|------|------|
```

规则：

- 缺少核心入口、编排服务、生成物链路或测试承载面时，`Implementation Readiness = BLOCKED_NEEDS_SURFACE_DISCOVERY`。
- 前端、展示、导出、风险提示等需求点名的 surface 不能默认降为范围外，除非用户明确限定 backend-only。
- 只找到 helper/DTO/constant 而没有真实承载点时，该 capability 不能进入 `core_path DONE`。
- **Same-Term Surface Split Gate：** 当一个业务词同时出现在多个任务族、接口族、报表族、前端族或外部 payload 族中，Surface Mining 必须逐族列出 entry / owner / payload-or-output / tests，并明确选择或排除理由；命名相似不是同一 surface 的证据。
- **Core Entry / Deploy Surface Lock Gate：** 最高权重 `core_path` 必须锁定真实生产入口文件族、调用点、副作用和行为/事务验证；需求点名的 report/export/frontend/template/generated artifact/OCR/external payload 等 deploy-facing surface，必须锁定为 `locked_for_implementation`（具体文件族 + 实现动作 + 验证点）或 `BLOCKED_BY_OWNER`；只写 `mined/deferred` = `NO-GO`。
- **Exact Contract First-Slice Gate：** 固定字段、列、flag、enum、payload shape、展示列或日志文案属于高权重 deploy-facing contract 时，不能只放在收口核对；必须绑定到首个相关可执行 slice：`contract row -> carrier file family -> executable proof -> must-not/fallback assertion -> cap if blocked`。若计划的前两个实现 slice 都不触达该 contract，第三个 core-only/internal slice 前必须先回补 contract slice 或写 `exact_contract_gap`。

### 改动影响搜索与一致性矩阵

涉及规则、条件顺序、字段来源、枚举值、数据源切换、方法签名、shared helper 或重复实现时，Expected Diff Matrix 前必须做影响搜索：

```markdown
| 改动轴 | 搜索证据 | 必改位置 | 可能改动位置 | 明确排除 | 一致性规则 |
|--------|----------|----------|--------------|----------|------------|
```

搜索至少覆盖：方法名/字段读写、赋值点、枚举反查、SQL/filter/select、调用方、反序列化/序列化、模板/导出列、测试 fixture。`must-change locations` 不清时，不得进入实现；`explicitly-excluded` 必须写排除原因，不能只写“未涉及”。

### 预计变更矩阵（Expected Diff Matrix）

跨模块、多 surface、报表/导出、任务、日志、配置或落库时必须产出：

```markdown
| 需求项 | 范围分类 | 预计模块 | 预计文件族 | 预计新增/修改类型 | 不应触碰文件族 | 验证方式 | 闭环条件 |
|--------|----------|----------|------------|-------------------|----------------|----------|----------|
```

实现后实际 diff 不匹配时，必须回退规划。

新增文件必须标记为 effective diff 或 generated artifact；未分类文件不得进入实现完成态。

**Expected Diff Closure Gate：** 矩阵不能只做预测清单。每个预计文件族在设计阶段必须写明闭环条件；收口阶段必须落成 `changed+tested`、`changed+static_only+cap`、`deferred+reason+coverage_cap` 或 `blocker` 之一。需求明确点名的图片/附件/报表/异步/自动流转/外部协议文件族若没有闭环条件，`Implementation Readiness = NO-GO`。

文件族粒度细则见 `../dev-workflow/references/complex-requirement-delivery-kit.md` §4A。主文件只保留硬门禁：Expected Diff 不得只写泛称；`core_path` 必须包含真实生产入口/承载点；需求点名的 deploy-facing surface 必须有实现动作和验证点；stateful core path 必须写 transaction-depth test plan 或 coverage cap。

### 测试设计控制（Test Design Control）

非平凡需求、多 surface、状态/事务、外部接口、报表/导出、前端/页面、异步任务、旧数据兼容、must-not 或高返工风险命中时，技术方案必须生成测试设计控制模块。

完整模板见 `../gen-tests/references/test-design-control.md`。主方案至少保留：

```markdown
| 步骤 | 产出 | 人工决策 | AI 辅助 | 状态 |
|------|------|----------|---------|------|
| 影响范围 | 受影响接口/页面/任务/surface | 最终测试范围 | 代码/diff/入口扫描 | |
| 风险分级 | 每个对象的风险和测试深度 | 风险等级和深度 | 改动/分支/旧数据分析 | |
| 判定表 | 最小用例组合 | 保留/合并业务用例 | 展开并合并组合 | |
| 可执行步骤 | 前置数据/操作/断言 | 特殊场景和 blocker | 步骤生成 | |
| 覆盖校验 | surface x 维度状态 | 接受缺口/blocker | 覆盖矩阵 | |
```

Hard Gate:

- `gen-tests` must consume this module before writing tests.
- If a complex requirement lacks Test Design Control, output `Implementation Readiness = NO-GO:test_design_gap`.
- Small requirements may use the mini form from the reference, but must still include impact, risk, test point, must-not, and status.

**Nonblocking Feature Required Gate：** “失败不阻断主链”只表示失败隔离，不表示功能可跳过；图片、附件、通知、报表、异步后处理等必须同时规划成功链路和失败隔离验证，除非明确 `BLOCKED_BY_OWNER/deferred` 并从 90% 分子剔除。

### 能力切片矩阵（Capability Slice Matrix）

跨模块、多 surface、从 0 新增模块、外部集成或大量文件族时，不得只生成一个巨型计划，必须先切能力包：

```markdown
| 切片 | 需求行 | surfaces | 数据/模型 | 预计文件族 | 测试 | 完成标准 | 依赖 |
|------|--------|----------|-----------|------------|------|----------|------|
```

每个 slice 必须有独立完成标准、验证范围和回退边界；不能把多个无依赖能力塞进一个大任务。

**Task Size Gate：** 每个实现任务必须有依赖、验收条件、验证命令和预计文件族；超过 5 个文件、验收条件超过 3 条、标题含多个“和/以及/并且”或跨两个独立子系统时，默认继续拆分。高风险或依赖不确定的 slice 排前面，先失败早暴露。

自主实现或 90%+ 目标还必须标出 Core Slice Plan：

```markdown
| 切片 | 权重 | core/supporting/optional | 首个实现目标 | 行为测试宪章 | 停止条件 |
|------|------|--------------------------|--------------|----------------|----------|
```

高权重核心 slice 的首个实现目标必须落到真实入口、状态/写入/输出、side-effect ledger 和行为/事务测试；核心 slice 未闭环时，计划必须写 `STOP_AND_REPORT`，不能靠低风险 helper/DTO/log slice 补覆盖率。

高权重 deploy-facing supporting surface 还必须生成 Critical Surface Allocation Plan：`surface family -> executable first slice -> target file family -> RED/GREEN or runnable contract -> cap if static/blocker only`。报表/导出/前端、模板/生成/上传、外部 payload、stateful DB writes、transaction tests 等被识别后，不能等 core service 扩写完再处理。

当同一需求同时存在 core path 与高权重 deploy-facing contract/surface 时，Capability Slice Plan 必须显式标出“何时从 core-only 转向 surface/contract”。若已经完成一个真实入口 tracer bullet，但 contract/surface 仍未触达，下一到两个 slice 必须闭合 `stateful_success_slice`、`deploy_surface_first_slice` 或 `exact_contract_first_slice`；否则计划状态只能是 `PARTIAL_WITH_CAP`。

### 90% 覆盖计划（90% Coverage Plan）

当目标是“需求文档后自主实现 90%+”时，技术方案必须把覆盖目标转成可执行计划。90% 不是所有边角全做完，而是核心主链、关键 surface、固定 literal、字段/数据来源和 must-not 行为达到可验收覆盖。

```markdown
| 切片 | 优先级 | 覆盖权重 | 90% 必做项 | 后置/需确认 | 完成标准 | 验证方式 | 阻断项 |
|------|--------|----------|------------|-------------|----------|----------|--------|
```

规则：

- `core_path` 权重大于支撑面；核心主链未完成时，不得用旁路能力补足 90%。
- `must implement for 90%` 必须覆盖需求覆盖账本中的 `core_path` 行和关键 `supporting_surface` 行。
- `defer / ask` 只能放入低权重、外部 owner、前端-only、DDL/迁移/发布需确认或需求未冻结项，并说明不计入 90% 完成率。
- 预计文件族必须能反推到 Expected Diff Matrix；缺失主链文件族时，输出 `Implementation Readiness = NO-GO`。
- deploy-facing 字段/列/flag/payload shape 仍是 assumption 时，该 slice 只能 `PARTIAL`，不得作为 90% 的 `DONE` 分子；命名或形态偏差必须回退契约冻结。
- 关键 supporting surface 被需求显式点名时，必须有真实承载文件族、独立验证点和闭环条件；不得用低风险旁路 slice 冲抵覆盖率。
- 每个高权重 supporting surface 必须至少有一个可执行最小切片：真实承载文件族进入 diff，并有 RED/GREEN、可运行契约测试或真实输出验证；static guard 只能防漏改，blocker 只能暂停或剔除分子，二者不能作为 90% 的 `DONE` 分子。
- 若时间/上下文预算不足以闭环高权重文件族，应在计划中写 `STOP_AND_REPORT` 条件，而不是继续实现低权重 helper。

### 决策反证点（Decision Doubt Checkpoint）

非平凡决策在进入实现前必须写成可反驳的小块：

```markdown
| 设计判断 | 为什么重要 | 产物/契约 | 反证问题 | 对齐结果 |
|----------|------------|-----------|----------|----------|
```

### 实现前方案审查包

命中 L2/L3、review pressure、多 surface、自主实现 90%+ 或高返工成本时，进入实现前必须生成本包，并交给 `deep-review` 审查：

```markdown
## 实现前方案审查包

| 审查项 | 证据位置 | 主要风险 | 反证问题 | 当前状态 |
|--------|----------|----------|----------|----------|
| 需求冻结 | | | | |
| 规划盘问 | | | | |
| 预计变更 | | | | |
| 测试设计 | | | | |
| 能力切片 | | | | |
| 开放假设 | | | | |
```

规则：

- P0/P1 审查发现必须回到本技能修正 `tech-design.md`、预计变更、测试设计和 OpenSpec。
- 审查通过后，在 `tech-design.md` 增加“实现前方案审查结果”章节，记录审查模式、发现数量、修正项和剩余风险。
- 小型机械改动可跳过，但必须写合法 `skip_reason`。

适用：跨模块/共享接口、状态/事务、外部协议、安全/数据迁移、不可逆发布、高置信但证据不完整的设计判断。若 doubt 暴露契约缺失，回到 `req-alignment-check`；若暴露实现风险，回到 Expected Diff 或 slice 拆分。

### 架构 / 原型 / 决策门

- **Architecture Depth Gate:** 新增模块、接口、adapter 或测试 seam 前，用 `module -> interface facts -> hidden complexity -> deletion test -> adapter count -> test surface -> decision` 判断是否真有 leverage。删除后复杂度只是消失、只有一个真实 adapter、或测试必须绕过 interface 时，回到设计。
- **Decision Record Candidate:** 只有“反悔成本高 + 看代码会意外 + 有真实替代方案取舍”同时成立时，才写入仓库约定的 ADR/决策文档/技术方案决策区；否则只写当前实现说明。
- **Throwaway Prototype Plan:** 状态机、数据模型、复杂交互或 UI 方案不清时，原型必须写 `question -> type -> location -> run command -> decision -> delete/absorb condition`；收口前删除、吸收或标记 generated/debug artifact。

## 实现单元

```markdown
- [ ] U01: {用例} -> {入口/服务}
  - 需求: REQ-001
  - 文件族: {expected files}
  - 测试: {assertions}
  - 验证范围: 文件 / 模块 / workspace / 全仓库
```

## OpenSpec 门

非平凡实现必须同时产出：

- `.doc/<feature>/tech-design.md`
- `.doc/<feature>/task_plan.md`
- `openspec/changes/<change>/proposal.md`
- `openspec/changes/<change>/tasks.md`

`openspec/` 或 `.doc/` 位于 ignore 边界时，必须用绝对路径确认存在性。

## 输出

默认输出 `状态 / 范围内外 / 领域语言差异 / 冻结表 / 分支覆盖计划 / 规划盘问矩阵 / Surface 矩阵 / 预计变更矩阵 / 测试设计控制 / 90% 覆盖计划 / 验证基线计划 / 架构深度检查 / 决策反证点 / 决策记录候选 / 一次性原型计划 / 子 agent 证据账本 / 实现前方案审查包 / 实现单元 / 测试策略 / OpenSpec / 人审问题`。长模板见 `references/plan-template.md`。

## 完成标准

进入 `dev-workflow` 前必须满足：阻断问题清零、冻结表完整、L2/L3 或上游同症状矩阵已形成分支覆盖计划、规划盘问矩阵带稳定 PB-ID 且完整或有合法 `skip_reason`、多 surface 有验证点、预计变更矩阵完整、测试设计控制完整或有合法 mini/skip reason、能力切片/90% 覆盖计划/验证基线计划完整、命中触发条件时实现前方案审查 P0/P1 清零、`.doc` 与 OpenSpec 落盘且用户审批通过。否则输出 `Implementation Readiness = NO-GO`，按 delivery kit 补齐缺口。
