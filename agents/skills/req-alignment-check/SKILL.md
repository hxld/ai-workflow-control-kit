---
name: req-alignment-check
description: "Use when user says 校验需求, 需求对齐, check requirements, 核对需求, 需求检查, 需求完整性检查, or before implementing a requirements document"
allowed-tools: Bash,Read,Write,Glob,Grep,Task
---
# 需求对齐检查
在实现前发现隐藏需求、未决问题、字面量契约和多 surface 风险。
**专家角色：** 需求风险分析师。
**下游技能：** `ideate:planning-brainstorm`, `deep-plan`, `dev-workflow`
## 何时使用

- 有需求文档、PRD、用户验收口径。
- 无 PRD 但有 branch / commit / diff，需要后验重建需求。
- 用户要求需求校验、需求对齐、需求完整性检查。
- 从需求进入设计或开发前。
## 何时不使用

- 没有需求源，且也没有 branch / commit / diff 可用于后验重建。
- 用户明确要求直接做一个很小的机械改动。
- 纯 bug 修复且已有明确失败测试。
## Iron Law
需求中已经写死的内容就是实现契约；未冻结成矩阵前不得进入编码。
复杂需求矩阵模板见：`../dev-workflow/references/complex-requirement-delivery-kit.md`。
## 工作流

1. 加载需求来源。
2. 命中开放式需求、多落点风险或用户已纠错时，先生成 Intent Alignment Gate；若属于纠错场景，还必须执行 User Correction Escalation Gate。
3. 命中领域术语混用、跨上下文或业务口径不一致时，生成 Domain Language Ledger。
4. 命中生产症状、热修、修数、缓存、外部接口、状态/数据链路或用户纠错时，生成 Same Symptom Branch Matrix。
5. 分类 scope：范围内、前端-only、已有需证据、待确认、支撑工具、无关漂移。
6. 用户要求自主实现或 90%+ 覆盖时，生成 Requirement Coverage Ledger，并标出核心主链优先级。
7. 识别业务目标、范围内、范围外。
8. 扫描隐藏需求与未决问题。
9. 生成 Decision Ledger。
10. 命中显式契约时生成冻结矩阵。
11. 命中多 surface 时生成 Surface 覆盖矩阵。
12. 输出 APPROVED / REJECTED / NEEDS_CLARIFICATION，并为非平凡需求交接 `ideate:planning-brainstorm` 后再进入 `deep-plan`。
## Intent Alignment Gate
当用户只描述现象、期望修复或改进方向，但没有明确“改哪个落点、保留哪个口径、谁能看到结果”时，先做轻量意图对齐。
触发信号：
- 需求可能落到多个层：服务、展示、日志、持久化、模板、helper、配置或共享入口。
- 同时存在用户/业务可见面与内部可观测/排障面。
- 用户强调某些文案、字段、状态或结果是产品/业务/客户可见口径。
- 用户说“不应该改这里 / 应该只在某方法 / 别动旧链路 / 按产品需求那几个字段”。
- 已发生一次理解偏差或返工。
必须产出：
```markdown
| 对齐项 | 结论 | 证据/来源 | 状态 |
|--------|------|-----------|------|
| 用户想改变的结果 | | | |
| 必须保持不变的内容 | | | |
| 用户/业务可见面 | | | |
| 内部可观测/排障面 | | | |
| 推荐改动落点 | | | |
| 禁止改动落点 | | | |
| 验证方式 | | | |
```
判断规则：
- 若“推荐改动落点”和“禁止改动落点”无法同时写清，状态必须是 `NEEDS_CLARIFICATION`。
- 若用户/业务可见面与内部排障面混在同一 helper、模板或写入方法中，必须在技术方案里显式拆边界。
- 这是轻量对齐，不要求完整创意发散；但非平凡需求在进入 `deep-plan` 前应交给 `ideate:planning-brainstorm` 做方案盘问。
## User Correction Escalation Gate
用户指出一次遗漏、误解、原型不符、字段规则不符、提示文案不符或“你说完成但实际没完成”时，当前工作必须从单点补丁升级为全量再对齐；不得只修用户刚指出的一行。
必须产出：
```markdown
| correction | likely family | same-family scan | updated contract | verification | status |
|------------|---------------|------------------|------------------|--------------|--------|
```
规则：
- `same-family scan` 必须覆盖同类字段、同类按钮/入口、同类错误提示、同类数据源、同类显示文案或同类运行时出口；不能只搜索当前报错行。
- 若需求源、原型图、用户最新口径冲突，以用户最新明确口径为当前冻结契约；旧文档要标为 `stale_or_conflict`，不得继续按旧文档解释。
- 纠错后重新输出 APPROVED 前，每个受影响 requirement 行都必须有代码落点和测试/静态/运行态验证计划。
- 未完成本门禁时，状态最高只能是 `PARTIAL`，不得进入“已完成”或提交收口。

## Same Symptom Branch Matrix

当同一个用户可见或生产业务症状可能由多个入口、配置、缓存、异步任务、数据来源、外部系统或展示面造成时，必须先列分支，不能把目标 bug 分支等同于整个症状。

触发信号：

- 生产/线上问题、热修、修数、缓存刷新、外部接口、状态推进、异步链路、跨组件归因。
- 需求说“同样现象 / 还是不行 / 某单也这样 / 修了之后仍出现”。
- 用户已纠错，或之前的结论只覆盖了某个函数、日志、配置或下游响应。

```markdown
| symptom | possible branch | entry / precondition | evidence to check | covered by this change? | must-not / regression | status |
|---------|-----------------|----------------------|-------------------|-------------------------|-----------------------|--------|
```

规则：

- `possible branch` 至少覆盖当前目标分支、绕过目标修复的入口、配置/缓存分支、异步/重试分支、外部/下游分支和展示/查询分支；确实不适用时写 `not_applicable:<reason>`。
- `covered by this change? = no/partial` 的行必须进入范围外说明、后续采证或 `deep-plan` blocker；不能在最终回答中说整个症状已修复。
- 同症状矩阵中的 `must-not / regression` 必须交给 `deep-plan` / `gen-tests`，至少形成一个反向断言、静态检查或明确 blocker。
## Domain Language Ledger
需求、用户口述、代码注释、已有文档或界面文案对同一业务概念使用多个词，或同一词可能指向多个概念时，先冻结共享语言；不能让实现阶段靠猜测命名。

```markdown
| raw term | canonical term | meaning | avoid/alias | source evidence | code/doc impact | unresolved? |
|----------|----------------|---------|-------------|-----------------|-----------------|-------------|
```

规则：

- 只记录领域专家也会使用的业务概念；通用技术词、临时类名、工具名不进入此表。
- 若术语冲突影响字段来源、状态含义、展示文案、报表列或测试命名，状态必须是 `NEEDS_CLARIFICATION`，不得继续编码。
- 若仓库已有领域词表、上下文文档或 ADR/决策记录约定，必须优先读取并对齐；新增术语只写入仓库约定的文档位置，不在通用技能正文里固化项目词。

## Imported Requirement Normalize Gate

当需求源来自导出文档、网页复制、长表格、图片占位、单行 Markdown、混排更新记录或格式明显破碎的材料时，先规范化为：

```markdown
| block | type | source location | normalized requirement | owner/surface | status |
|-------|------|-----------------|------------------------|---------------|--------|
```

类型枚举：`business_goal`、`in_scope`、`out_of_scope`、`update_note`、`ui_reference`、`field_table`、`process_rule`、`acceptance_rule`、`non_requirement_context`。

未完成 normalize 时，复杂需求不得直接生成冻结矩阵；图片、原型和更新记录只能作为线索，不能替代文字契约。

## Decision Ledger

```markdown
| # | 类别 | 问题 | 阻断原因 | 建议决策 | 状态 |
|---|------|------|----------|----------|------|
```

以下缺失直接 `REJECTED`：

- 外部依赖未确认
- 数据来源不清
- 状态/副作用不清
- 多入口范围不清
- 发布/配置/SQL ownership 不清

## Scope 分类矩阵

复杂需求必须先分类每个需求项：

```markdown
| 需求项 | 分类 | 是否实现 | 证据/原因 | 风险 | 下一步 |
|--------|------|----------|-----------|------|--------|
```

分类枚举：

- `IN_SCOPE`
- `FRONTEND_ONLY`
- `ALREADY_IMPLEMENTED_NEED_EVIDENCE`
- `OUT_OF_SCOPE_PENDING_CONFIRMATION`
- `SUPPORTING_TEST_OR_TOOLING`
- `UNRELATED_DRIFT`

`FRONTEND_ONLY`、`OUT_OF_SCOPE_PENDING_CONFIRMATION`、`UNRELATED_DRIFT` 不得进入后端实现计划；`ALREADY_IMPLEMENTED_NEED_EVIDENCE` 必须追到可核验证据链。

## Requirement Coverage Ledger

当用户要求“基于需求文档自主实现 / 尽量少问 / 覆盖 90%+ / 完成大部分代码”时，必须把需求拆成覆盖账本。覆盖账本用于后续设计、实现、测试和收口，不得用文件命中率替代。

```markdown
| Req ID | requirement item | priority | literal / wire fields | surface | expected files | verification | status |
|--------|------------------|----------|-----------------------|---------|----------------|--------------|--------|
```

`priority` 只能使用：

- `core_path`: 业务主链、状态流转、主要写入/输出、核心验收路径。
- `supporting_surface`: 报表、导出、日志、通知、后台任务等支撑面。
- `optional_or_later`: 需求明确可后置，或需要用户另行确认的非阻断项。
- `frontend_or_external`: 后端无法单独完成，或依赖外部 owner。
- `out_of_scope`: 明确不属于本轮。

核心主链优先级规则：

- `core_path` 行必须先进入技术方案和实现顺序，不能先做报表、日志、OCR、导出或旁路 slice 冒充总体进度。
- `core_path` 行存在数据来源、字段契约、DDL、外部 owner 或验收文案不清时，状态必须是 `NEEDS_CLARIFICATION` 或 `REJECTED`。
- 90% 覆盖目标只统计 `core_path + supporting_surface` 的加权完成度；`optional_or_later`、`frontend_or_external`、`out_of_scope` 不得用来冲高覆盖率。

### Deploy-facing Contract Gate

凡需求会形成对外、跨模块或落库契约，必须先冻结精确名称和值；不能按中文大意自行命名后计入 `DONE`。

命中信号：

- DTO / request / response / JSON payload 字段名
- DB column / SQL alias / mapper result 字段名
- 配置 key、枚举、状态码、任务类型、日志类型
- 报表列、导出列、页面展示列
- 外部接口 request/response 字段与 payload shape

处理规则：

- 需求已写死：逐字进入冻结表和测试断言。
- 需求未写死但会成为 deploy-facing contract：状态只能是 `NEEDS_CLARIFICATION`、`ASSUMED_NEEDS_CONFIRMATION` 或 `DEFERRED`；不得标 `DONE`。
- 若必须先推进，可把假设写进 `assumption`，但该 slice 覆盖率最高 `PARTIAL`，并在 `deep-plan` 中列为 ask/defer。
- 字段名、列名、payload 名、展示名不一致时，必须显式说明 mapping；无 mapping 视为契约缺口。
- **Contract Triangulation Gate：** deploy-facing 名称和值不能只来自需求中文或 agent 自行命名，必须三方核对：`requirement literal -> current schema/code/API evidence -> wire/display/test assertion`。三方任一缺失时，该行状态只能是 `ASSUMED_NEEDS_CONFIRMATION` 或 `NEEDS_CLARIFICATION`，不得进入 `DONE`。
- **Surface Family Disambiguation Gate：** 同一业务词同时可能指向查询、重试、上报、导出、展示、任务或回调等不同 file family 时，必须先列候选 family、runtime entry、payload/result owner 和排除理由；只按关键词命中一个相似文件族直接实现 = `REJECTED`。
- **Exact Contract Freeze Gate：** 字段、列、flag、type、enum、payload shape 或展示列必须冻结成 `literal -> code symbol -> DB/API/wire name -> exact value/shape -> owner -> test assertion`；任一 `assumption` 行不得计入 `DONE`。

### Observable Behavior Contract Gate

公共 API、跨模块接口、导出、页面展示、任务状态、日志/审计或外部集成一旦被消费者观察到，都按契约处理；不能只冻结字段名。必须补充：

```markdown
| observable behavior | consumer | current/source evidence | preserve/change | compatibility risk | test assertion |
|---------------------|----------|-------------------------|-----------------|--------------------|----------------|
```

至少覆盖输出 shape、错误语义、排序/分页、空值行为、幂等/重试、状态码/状态流转、展示文案和兼容/废弃策略。未冻结时，涉及共享或对外 surface 的需求状态最多 `NEEDS_CLARIFICATION`。

## Branch / Commit Reconstruction Mode

无 PRD 但用户提供分支、commit range、patch 或目标 diff 时，先做后验需求重建，状态只能是 `RECONSTRUCTED` / `NEEDS_CONFIRMATION` / `NEEDS_EVIDENCE`，不得直接写 `APPROVED`。

```markdown
| 反推需求 | confidence | evidence | missing source | verification gap | next step |
|----------|------------|----------|----------------|------------------|-----------|
```

规则：

- `confidence` 只能是 `high`、`medium`、`low`。
- evidence 可来自提交信息、文件族、代码行为、测试或日志；没有证据的推断必须降级。
- diff 不是 PRD；外部协议、失败日志、签名样例、空值行为缺失时必须写入 `verification gap`。
- 命中共享模块、外部集成或 bugfix 无失败证据时，必须升级给 `deep-plan`。

## 显式需求冻结矩阵

触发信号：

- 固定文案、展示文本、结果列
- 固定枚举值、类型值
- 固定失败场景
- 固定字段来源、数据归属
- 固定空值、空字符串、空操作
- 条件链顺序、优先级
- 精确维度、组合条件、联合筛选
- 多入口、多接口、多页面、多导出、多任务、多展示面
- SQL、DDL、配置、发布单、外部交付物

必须产出：

```markdown
| 需求原文 | 顺序/优先级 | must happen | must not happen | ownership/surface | 代码落点 | 测试断言 | 状态 |
|----------|-------------|-------------|-----------------|-------------------|----------|----------|------|
```

Hard Gate：

- 任一必填列为空 = `REJECTED`
- `must not happen` 缺失且需求涉及失败、空值、fallback、副作用或展示字段 = `REJECTED`
- 写“实现时再看 / 沿用旧逻辑 / TBD” = `REJECTED`

## 字段与数据来源冻结表

相邻业务字段不能按中文大意合并。需求含“来源/类型/数量/目录/状态/结果/金额”等字段时必须产出：

```markdown
| 需求标签 | 数据来源 | 领域字段 | DB/外部字段 | 落库值 | 展示字段 | 禁止回退/默认值 | 测试断言 |
|----------|----------|----------|-------------|--------|----------|-----------------|----------|
```

缺失 = `REJECTED`。

对 deploy-facing contract，表中还必须能回答：

```markdown
| contract item | exact name/value | source quote/evidence | assumption? | owner | code location | test assertion | status |
|---------------|------------------|-----------------------|-------------|-------|---------------|----------------|--------|
```

`assumption? = yes` 时，该行不得计入 `DONE`。

## Surface 覆盖矩阵

用户或需求列出多个入口、接口、页面、导出、任务、日志或展示面时必须产出：

```markdown
| Surface | 入口 | 编排服务 | 查询/写入点 | 输出字段 | 用户可见结果 | 独立测试点 | 状态 |
|---------|------|----------|-------------|----------|--------------|------------|------|
```

不能用入口 A 的完成状态代表入口 B。缺失 = `REJECTED`。

异步、轮询、定时任务、状态回调、消息消费、日志/审计筛选、导出、后台任务均视为独立 surface，不得被 Controller/Service happy path 代表。
报表/查询/导出/页面类需求必须拆成独立 surface：查询条件与默认值、参数载体、SQL/filter、页面/脚本入参、结果列、导出列和值断言；只做导出列不能代表查询筛选已完成。

## 隐藏需求扫描

至少检查：

- 权限与角色
- 异步任务、轮询、重试、幂等
- 错误处理与用户可见文案
- 数据迁移、兼容、回滚
- 日志、审计、进度、状态流转
- 多端、多入口、多导出
- 异步任务、轮询、定时任务、状态回调、消息消费
- 外部接口、超时、降级、限流
- 测试与验收口径

## 输出

```markdown
## 需求对齐结果
- 状态: APPROVED / REJECTED / NEEDS_CLARIFICATION
- 阻断项:
- Intent Alignment Gate:
- User Correction Escalation Gate:
- Domain Language Ledger:
- Decision Ledger:
- Scope 分类矩阵:
- Requirement Coverage Ledger:
- 显式需求冻结矩阵:
- 字段与数据来源冻结表:
- Surface 覆盖矩阵:
- Same Symptom Branch Matrix:
- 下一步补齐模板: dev-workflow/references/complex-requirement-delivery-kit.md
- 下一步: ideate:planning-brainstorm / deep-plan / 用户确认 / 停止
```
