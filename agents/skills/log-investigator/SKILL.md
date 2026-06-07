---
name: log-investigator
description: "Use when user says 查日志, search logs, investigate logs, 排查问题, 查生产, 日志调查, 生产问题, pod crash, Kubernetes logs, Elasticsearch logs"
allowed-tools: Bash,Read,Edit,Grep,Skill
---

# 日志调查员

通过代码优先的日志分析追踪生产事件 — 先读源码再搜日志。

**专家角色：** SRE 侦探 — 通过代码优先的日志分析追踪生产事件。

**上游技能：** `pre-flight-check` (MEMORY.md), `gen-tests` FIX（若由失败验证升级）
**下游技能：** `compound-learning`（root cause lessons / skill feedback）, `sync-progress` (if fix applied)

---

## 何时使用

- "查 [环境] [项目] [问题]" — 如 "查 生产 订单服务 重试失败"
- "search logs" / "investigate logs"
- Kubernetes pod 错误、容器崩溃循环
- Elasticsearch 日志查询

## 何时不使用

- 没有日志上下文的简单错误（用 `gen-tests` FIX 或 `dev-workflow` 失败处理）
- 实时日志流（用直接 kubectl/logs 工具）
- 性能监控（用指标工具）
- 没有代码库可供分析

---

## ⚠️ 预检查（必读）

**必须：** 执行此技能前使用 `pre-flight-check` 技能。

---

## 常见陷阱（先读这个！）

| 失败 | 预防 |
|------|------|
| 不分析代码就搜日志 | 总是先分析源码 |
| 关键词太多 → 查询太宽 | 最多10个关键词，从代码优先 |
| 生产查询未确认 | 生产查询前总是确认 |
| 配置路径硬编码 | 用 `{skill_dir}` 变量 |
| 堆栈解析失败 | 回退到消息级搜索 |
| 知识匹配不准确 | 允许手动覆盖 |
| 根因分析浅 | 修复前必须有假设表 |
| 已知问题被重新调查 | 总是先检查知识库 |
| 没有保留经验 | 每次调查后提供记录选项 |
| 局部日志就下结论 | 证据不完整时只能输出待验证假设 |

---

## 红旗警告（停止）

| 想法 | 为什么错 |
|------|----------|
| "我知道这个错误，直接修" | 每个事件都值得新调查 |
| "跳过假设表" | "明显"的修复会导致级联故障 |
| "不问就查生产" | 生产查询是不可逆的 |
| "不需要检查 knowledge.json" | 历史问题省80%调查时间 |

---

## 安全护栏

- **生产查询需要用户明确确认**
- **生产只读授权可推断**：用户明确说生产/prod/Kibana/日志后端且给出 selector 时，视为本次窄范围只读查询已授权；扩大范围、写入、修复或缺 selector 时仍需确认。
- **修复上限：** 最多3次修复尝试，然后升级给用户
- **观测不完整时禁止落锤根因**
- **无复现/无日志时禁止直接修复**：只能输出假设、信息缺口和采证计划
- **结论优先**：用户催促“给结论”时，先输出 `已确认 / 高置信推断 / 证据缺口`，再继续展开证据。
- **只读默认**：日志调查默认是 `debug-only`。除非用户明确要求修复，且证据已足以锁定最小修复面，否则不得写生产代码。

---

## Iron Law（铁律）

- 没有根因调查就没有修复。禁止看到错误日志就直接改代码，必须追踪根因、理解完整链路，然后再修复。
- 日志只覆盖局部链路、或缺少构建/发布/版本证据时，不得输出“已确认根因”；只能输出假设、信息缺口与下一步验证。
- 跨组件问题必须追数据流，不得只在报错组件内局部猜测；连续 3 次查询或修复仍无法闭环时，升级为设计/观测性问题。
- 用户要的是可复制查询或现场排障 SQL/日志检索时，先给最短可执行查询和前提条件，再展开代码深挖；不得把排障入口做成只能由模型继续执行的长链路。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：证据充分性门槛与根因假设表属于 Hard Gate，未满足不得输出“已确认”
- **PARTIAL**：在本技能中表示证据充分性不足，只能支持部分确认或待验证假设
- **完成标准（DoD）**：统一表示“代码分析、日志证据、根因假设与下一步验证建议都已形成闭环”
- **验证范围**：在本技能中主要表示证据链覆盖到哪一层链路，而非测试执行范围

---

## 配置 & 前置条件

需要 `{skill_dir}/config.json`、`projects.json`，生产 ES 查询还需要 `.env`；缺少配置时回退到仅代码分析模式。`knowledge.json` 可选，调查前仍应匹配历史问题。

---

## 输入分型

| 输入证据 | 路由/动作 | 允许结论 |
|----------|-----------|----------|
| 有 traceId / businessId / 时间窗 / 错误日志 | 正常调查 | 可在证据闭环后确认根因 |
| 明确异常堆栈/NPE/类型转换/空值转换 | 第一业务首帧 + 异常变量来源 + 最小输入/配置复现 | 待验证假设或 RED/GREEN |
| 有堆栈但缺业务上下文 | 代码链路 + 堆栈锚点 | 待验证假设，补业务 ID 或时间窗 |
| 有失败测试 | 直接转 `gen-tests` FIX；本技能只补第一业务首帧、变量来源或外部证据 | RED/GREEN/FIX |
| 只有口头现象、无日志无复现 | 输出采证计划 | `PARTIAL`，不得确认根因或改代码 |
| 外部系统/协议疑似问题 | 冻结请求/响应/签名/配置/空值 contract | 待验证假设 |
| 空集合/字段丢失/数据不一致 | 追数据链路与过滤条件 | 待验证假设或数据修复建议 |
| 配置开关不生效/环境缓存争议 | 锁实际配置源、优先级、缓存和时间线 | 待验证假设 |
| 预期日志缺失/搜不到日志 | 反查日志发射点与查询条件 | 只能说明未观测到，不能说明未发生 |
| 异步任务未触发/状态卡住/完成日志缺失 | 追状态链与触发链 | 必须覆盖父子任务、状态、调度、完成日志、下游触发 |

三次查询或修复尝试仍无法闭环时，升级为设计/架构/观测性问题，交给 `deep-plan` 做补采证方案，不继续叠补丁。

---

## Evidence-First Debugging Model

调查前先建立 `Symptom -> Flow -> Cause -> Fix Boundary` 证据链。多组件链路至少输出 `source -> transform -> persistence/message/cache -> consumer -> visible result`；缺任一关键环节时只能写 `PARTIAL`。

### Evidence Packet Builder

问用户前先从 prompt、SQL 行、截图 OCR、日志片段和会话上下文自动抽取 `Evidence Packet`：

`environment / system / time_window / selector / log_source / version_basis`

- `environment`：用户说生产、prod、线上即为 prod；否则按项目默认或写 `unknown`。
- `selector`：优先 traceId/runId/taskId/requestId，其次 caseId/businessId/policyNo/userId，再次 exact error keyword。
- `time_window`：优先用户给的绝对时间；日志/SQL 中有时间则取前后 15-30 分钟；只有日期取当天；仍缺则用 `now-7d` 并披露。
- `system/log_source`：从项目映射、代码发射点、URL、app 名、日志文案推断；不确定时先用最可能的窄候选并说明。
- 同一会话内保留 Evidence Packet；用户说“继续/我切分支了/时间在 X 左右”只更新对应字段，不重跑完整预检。

### Production Read-only Consent Gate

当用户明确要求查生产、生产日志、Kibana、ES 后端或“直接查”，且 Evidence Packet 有 selector 时，可执行窄范围只读查询。输出前先披露：`consent=inferred_readonly`、范围、selector、时间窗。

必须停下确认：没有 selector 只能宽查生产；要扩大到默认窗口之外、跨系统扫全量、导出大量明细或查敏感集合；要写库、重试任务、改配置、发布、修复或触发外部副作用。

### Runtime Version Gate

代码深挖前先确认当前源码是否可能对应运行时：当前分支/HEAD、用户声明的生产分支或发布单、`.memory/progress.md`、最近相关提交。若当前检出与运行时不一致：

- 不在当前分支上落锤根因；标记 `code_evidence=branch_scoped`，用 `git grep <candidate branch>` / `git show <commit>:path` 搜候选生产分支，并区分 `runtime evidence`、`current-worktree evidence`、`branch-only inference`。

### Unknown Project / Service Discovery Gate

项目、系统、容器名或 Kibana 服务名未知时，不先要求用户补全。进入 `discovery_mode=true`：

- 从 cwd、仓库名、配置文件、构建元数据、启动类、日志配置、Kubernetes/Docker 配置中抽取候选 `project/system/appId/indexPattern`。
- 在 Kibana/ES 可用时，先用强 selector 或 exact error keyword 在环境级候选索引中窄扫，命中后反推真实 app、index、日志字段。
- 将候选按 `confirmed / likely / rejected` 输出；只有没有 selector 且候选过多会导致宽查生产时才停下确认。
- 命中并复用两次以上的映射，应建议沉淀到 `projects.json`；一次性发现只留在本次 Evidence Packet。

### Minimum Routing Tuple Gate

查询日志前冻结五元组：`environment / system / time_window / selector / log_source`。

Hard Gate：
- 缺 `selector` 或无法收窄到系统/日志源时，不跑宽泛查询；输出 copy-ready 查询计划和证据缺口。
- 缺时间但有强 selector 时，不反问；按 Evidence Packet 默认窗口执行或给最短链接。
- 页面/业务日志若有 DB 表、业务接口或代码发射点可查，先走代码/DB/API 链路；浏览器或 Kibana UI 只作认证、截图或后端 API 不可用时的 fallback。
- 未命中只能说明“当前五元组下未观测到”，不能证明事件未发生。

### Kibana Known Backend Fast Path

If a Kibana URL or Discover URL is available and `config.kibanaBackendSearch.enabled=true`, do not start with endpoint exploration. Treat the configured Kibana backend path as the first query transport.

- First attempt order: freeze routing tuple -> resolve index from Discover `_a.index` or project `indexPattern` -> POST `config.kibanaBackendSearch.msearchPath` with configured NDJSON body and headers.
- Only resolve `/api/saved_objects/index-pattern/{id}` when the input contains a Discover index-pattern id or the first `_msearch` fails because the index pattern is unresolved.
- Do not probe `/api/status`, navigate Kibana UI, search for alternate ES paths, or ask the user to manually search before one concrete configured `_msearch` attempt has failed.
- Rebuild a narrow DSL from environment, app/service, selector, and time window; do not blindly reuse an overly broad URL query.
- On failure, classify once: `auth/session`, `path/version`, `index_pattern`, `empty_result`, or `network`; then use the matching fallback instead of repeating endpoint discovery.
- Pivot on trace id once a relevant hit is found, then sort ascending to reconstruct the call chain.
- Browser/Kibana UI is fallback only when backend endpoints are unavailable, authentication requires the user's browser session, or the user explicitly asks for UI screenshots.
- Cache the session capability as `direct_es` / `kibana_backend` / `link_only` / `code_only`; do not rediscover the same endpoint on every follow-up turn.

### Query-First Slice

当用户明确要“先查一下 / 给我 SQL / 给我日志查询 / 先看生产现象”时，先输出一段最短可执行查询或检索条件，并写清：

- `selector`：时间窗、trace/business id、服务、类/方法、错误关键词等最小锚点。
- `expected evidence`：命中后要看哪些字段或日志片段。
- `fallback`：无结果时如何缩小/扩大时间、减少关键词或改用代码锚点。
- `decision`：什么证据会让问题保持 `debug-only`，什么证据会升级为 `hotfix`。

查询先行不等于跳过代码分析；它只保证排障现场先拿到可执行入口，随后仍需用代码链路解释日志含义。

### Debug-only Quick Output

用户只要查询、SQL、排查入口或“能确认什么”时，默认一页式输出：`Evidence Packet / 最短查询 / 字段怎么看 / 已确认 / 高置信推断 / 证据缺口 / 是否升级 hotfix`。只有用户要求继续深挖、查询结果返回、或证据足以进入修复时，才展开完整根因假设表和链路报告。

### Production Final Evidence Report Gate

生产问题排查收口时必须输出 `Final Evidence Report`，不能只给口头结论：

- `Evidence Packet`：环境、系统、时间窗、selector、日志源、版本依据。
- `Query Ledger`：实际查询语句/链接、索引或数据源、命中数、时间排序方式。
- `Evidence Table`：日志/DB/API/代码/版本证据逐条列出，标明支持或排除哪条假设。
- `End-to-End Chain`：入口 -> 处理 -> 状态/落库/消息/cache -> 下游 -> 用户可见结果。
- `Hypothesis Matrix`：已确认、已排除、待验证及其证据。
- `Conclusion Level`：`已确认` / `高置信推断` / `PARTIAL`，并说明证据缺口。
- `Next Action`：保持 debug-only、hotfix、数据修复、外部系统确认、继续采证或转设计/观测性改造。

缺任一关键链路时，最终状态只能是 `PARTIAL` 或 `高置信推断`，不得写“已确认根因”。

---

## 非异步 Bug 门禁

### 明确堆栈型

- 先锁**第一业务首帧**，不要被框架/反射/线程池栈帧带偏。
- 读首帧附近代码，标出失败表达式、空值/类型来源、请求字段、配置字段、默认值或转换 helper。
- 输出 `异常变量 -> 来源 -> 是否 contract 缺失 -> 最小复现输入/配置 -> 修复责任`。
- 修复不能只加 null guard；若真实缺口是配置 contract、请求 contract 或外部响应 contract，先冻结 contract，再决定代码防御。

### 外部接口 / 协议型

- 输出责任边界矩阵：`stage -> raw request -> raw response -> business code/message -> idempotency/retry -> config version -> owner evidence -> conclusion`。
- 区分“我方未请求/幂等跳过”“我方请求后收到外部错误响应”“我方等待外部超时”“外部响应 body 中声明其内部超时”。
- 没有 request/response 原文、配置版本或外部 owner 证据时，不得把外部系统问题改成我方代码 bug。

### 数据链路型

- 输出 `source rows -> filters -> mapping/config -> transform -> persistence -> output payload -> visible result`。
- 空集合/字段丢失时，必须证明是源数据为空、过滤条件排除、映射缺失、转换丢失、未落库，还是日志未打印 payload。
- SQL 反查只能证明某时刻数据状态；若配置或数据会变，必须加请求时间、配置更新时间、缓存刷新时间。

### 配置 / 观测性型

- 配置问题先锁 `expected config -> actual source -> precedence/fallback -> cache/version -> request time -> retry/new request`；搜不到日志时先查 app/index/time range/traceId/message 和 payload 发射点。

---

## 异步状态链门禁

遇到任务卡住、结果未触发、完成日志缺失、重复告警或轮询异常时，不得只看单条报错。至少追踪：

| 链路点 | 要确认什么 |
|--------|------------|
| 父任务 | 创建时间、类型、入参、状态、runId/requestId |
| 子任务/明细 | 明细状态是否与父任务一致，是否存在部分成功/失败/执行中 |
| 状态流转 | 待执行、执行中、待查询、成功、失败、取消之间的转移证据 |
| 调度/worker | 定时任务或消费线程是否实际捞到目标任务 |
| 持久化 | 保存结果、错误信息、状态更新是否在同一事务/异常边界内 |
| 完成日志 | 完成/失败/跳过日志是否由真实状态推进产生 |
| 下游触发 | 下游任务、消息、回调或展示是否依赖上一步完成状态 |
| 补偿/重试 | 重试是否会被历史失败状态、幂等键或旧任务卡住 |

若某一环缺证据，根因状态只能是 `待验证`；若调查发现是需求规则与旧实现冲突，转 `deep-plan` 冻结新规则，不直接补丁式修改。

---

## 工作流程

```
[1] 知识匹配 → 类似历史问题？→ 是 → 执行已知修复 → [7]
                                ↓ 否
[2] Evidence Packet → Runtime Version Gate → 代码分析 → [3] 提取关键词（最多10个）
    ↓
[4] 构建 ES 查询（多级降级）→ [5] 搜索 & 分析 → [6] 根因假设表 → [7] 报告
```

**证据充分性门槛：**

在把某条假设标记为“已确认”前，至少确认以下几类证据中的足够组合：

- 日志链路证据：覆盖关键请求/处理阶段
- 代码链路证据：能解释日志为何产生
- 版本/发布证据：确认问题对应的实际发布产物与时间窗口
- 构建/验证证据：如相关，确认近期 `compile/testCompile/test/package` 失败是否可能影响现象

缺少关键证据时，状态只能是“待验证假设”，不能写成单一根因。

---

## 知识库（Step 1）

调查前扫描 `knowledge.json`：≥2 触发词可作为高信心起点，1 个触发词只作线索，无匹配则完整调查。调查后可追加：`trigger / query / rootCause / solution`。

---

## 关键步骤详情

### 代码分析
1. 读取 `projects.json` 获取路径
2. 在代码中 Grep 关键词
3. 提取日志模式

### 查询降级

优先级：`traceId/runId/taskId/requestId` → `businessId/caseId/policyNo + method/app` → `class + method` → `app + exact keyword`。详见 `references/kibana-dsl-examples.md`。

---

## 异常场景处理

- `hits=0`：不要立刻问人；先按 `index/app/time/selector/message/version/log_source` 六类诊断未命中原因，再决定扩大时间、换索引、减关键词或回代码锚点。
- 日志量过大：缩小时间、加 `level:ERROR`、保留强 selector、分批查询。
- ES/Kibana 失败：记录 capability，回退到 link-only 或 code-only，不重复探测。
- 堆栈解析失败：锁第一业务首帧失败时，回退 message 级全文搜索。

### 提取关键词：中文 + 异常 + 英文（len≥2）

### ES 查询：`{"query":{"bool":{"must":[{"query_string":{"query":"{selector} AND message:({keywords})"}}],"filter":[{"range":{"@timestamp":{"gte":"{timeRange}","lte":"now"}}}]}},"size":100}`

---

## 根因分析（必须）

任何修复前必须产出假设表：

```markdown
## 根因分析
| # | 假设 | 证据 | 状态 |
|---|------|------|------|
| 1 | [理论] | [证据] | 已确认/已排除 |

### 根因: [带证据链的陈述]
```

**状态规则：**

- `已确认`：证据链闭环，且已排除关键竞争假设
- `待验证`：日志/代码/发布/构建证据仍有缺口
- `已排除`：有反证或与现象不符

---

卡住时读取 `references/investigation-checklists.md`，按 7 项检查清单和常见借口表复核。

---

## 报告格式

快速入口用 `Debug-only Quick Output`；生产问题收口必须用 `Production Final Evidence Report Gate`。下一步：`/compound-learning` 记录。

---

默认时间范围：未指定时间时使用 `now-7d`；常用输入可映射为 5 分钟、1 小时、今日、3 天、7 天。**搜索：** `查 [环境] [项目] [问题] [时间]`
