---
name: pre-flight-check
description: "Use when modifying code, editing files, fixing bugs, refactoring, implementing features, running build/test/release steps, replaying requirements, or before executing any skill that changes files"
allowed-tools: Bash,Read,Glob
---

# 预检查

在修改文件或运行会改变状态的技能前，先做记忆、边界、构建和隔离检查。

**专家角色：** 安全检查员。

**上游技能：** `compound-learning`
**下游技能：** 所有会修改文件或运行验证的技能。

## 何时使用

- 修改代码、文档、配置、测试或技能。
- 实现需求、修 bug、重构、跑构建/测试/发布。
- replay / eval / 技能实测 / 从历史提交重跑需求。

## 何时不使用

- 纯只读问答。
- 用户明确说跳过检查，且不涉及写入或构建。
- 本会话已为同一技能和同一目标完成预检查。

## Iron Law

没有通过预检查，不得进入批量写入、实现、构建、发布或 replay。预检查必须先判断工作模式，再按风险缩放门禁；不得把完整开发、热修、只读排查、只读审查和工具治理混成同一套重型流程。

## 必须读取

执行任何批量操作前：

1. 读取 `.memory/MEMORY.md`。
2. 读取 `.memory/error-lessons.md`。
3. 如涉及构建/测试，读取 `.memory/build-test-profile.yaml`。
4. 如存在 `docs/solutions/`，搜索相关历史方案。
5. 如涉及技能编辑、技能审计、技能同步或技能发布，读取 `.agents/AGENTS.md`（若存在）与 `skills-manifest.md`。
6. 输出：`已重读 MEMORY.md，识别到 {N} 条相关教训`。

Windows PowerShell 读取中文 Markdown/YAML/JSON 时必须显式 `-Encoding UTF8`。

## Mode / Gate Scaling

写入或运行验证前先声明：

`MODE -> SCOPE -> CONTRACT -> VERIFY -> EXIT -> SYNC`

| Mode | 最小门禁 | 升级条件 |
|------|----------|----------|
| `planned-dev` | Goal/Scope/Exit、需求 literal、surface、Expected Diff、TDD/验证、收口同步 | 已是完整功能、多 surface、外部契约、落库、异步或高返工成本 |
| `hotfix` | 证据来源、最小复现或 RED/static guard、最小修复面、must-not 边界、原失败阶段复验 | 修复面碰到共享入口、数据迁移、外部契约、多 surface 或需求口径不清 |
| `debug-only` | 查询/日志/代码证据锚点、假设表、信息缺口、下一步采证计划 | 证据足以定位修复且用户要改，才切到 `hotfix` 或 `planned-dev` |
| `review-only` | 只读范围、基准版本、findings 输出格式、验证缺口 | 用户明确要求修复，才重新跑写入预检查 |
| `tooling` | canonical source、镜像/备份规则、smoke/eval、回滚路径、项目污染扫描 | 修改触发器、Hard Gate、输出格式或同步脚本时补最小 eval |

缩放规则：

- 轻量不是跳过门禁，而是把门禁压缩到当前模式需要的字段。
- 只读模式不得暗中写文件；需要写入时必须重新声明 mode 和 Go/No-Go。
- 工具治理和通用技能正文必须保持项目中立；项目名、仓库路径、类名、表名、事故原文和团队专属命令只能进入项目规则或项目记忆。
- 任一模式出现固定文案、字段来源、状态/落库/展示契约、共享入口、外部协议或用户纠错，都必须升级到对应 Hard Gate。
- `tooling` 的 eval 深度按变更风险选择：触发器、Hard Gate、输出格式或 downstream routing 变化需要 EVAL-MIN / EVAL-TEST；纯错字、路径说明、备份同步或 changelog 可用 `no_eval_reason`。

## Hard Gates

### Goal / Scope / Exit

非平凡任务写入前，必须先明确：

- `deliverable`：本轮最终产出什么文件、代码、配置或结论。
- `verification`：用什么测试、编译、diff、文档核对或人工评审证明完成。
- `exit_condition`：什么结果可停止；什么结果必须回到需求、方案或用户确认。

有效 diff 中每一项都必须映射到用户请求、已接受方案 / spec，或本次变更必要清理。无法映射的重构、格式化、旧链路改造、模板扩张、生成物或旁路修复，默认归为 `UNRELATED_DRIFT`，不得进入完成结论。

轻微不确定可写明假设继续；影响固定文案、枚举、字段来源、落库/展示字段、DDL、兼容策略、共享入口、旧链路、提交、推送、发布或生产操作时，必须停下确认。

### Intent Alignment / 需求意图对齐

用户给出开放式需求、bug 修复、日志/展示/流程调整，且存在多个合理实现落点时，写入前必须先冻结“用户到底想改变什么”和“哪些内容不能改变”。

触发信号：

- 同一需求可落到服务层、展示层、日志层、持久化层、helper、模板或共享入口中的多个位置。
- 同时存在用户/业务/客户可见结果与内部排障、应用日志、监控、审计或开发诊断结果。
- 用户强调“产品给的 / 业务看的 / 客户能看到 / 不要改这个 / 只在某处记录”。
- 需求包含固定文案、固定字段、状态流转、落库字段、展示字段、空值行为、禁止 fallback 或禁止副作用。
- 用户已经纠正过一次理解偏差。

必须输出并冻结：

```markdown
| 项 | 冻结内容 | 证据/来源 | 需要确认 |
|----|----------|-----------|----------|
| 用户想改变 | | | |
| 必须保持不变 | | | |
| 用户/业务可见面 | | | |
| 内部可观测/排障面 | | | |
| 推荐改动落点 | | | |
| 禁止改动落点 | | | |
| 验证方式 | | | |
```

Hard Gate：

- `必须保持不变`、`推荐改动落点`、`禁止改动落点` 任一为空，且需求涉及固定展示、日志、状态、落库或共享 helper = `NO-GO`。
- 不能为了内部可观测性改写用户/业务可见契约；不能为了复用现有 helper 改变固定文案、字段、展示值或副作用边界。
- 用户纠正后必须重新跑本门禁；不得在旧错误落点上继续补丁式推进。

### Ignore 三态

涉及 `.doc/`、`openspec/`、`.memory/` 的存在性判断时，必须区分：

- 目录不存在
- 目录存在但不完整
- 工具因 ignore 规则未返回

仅凭搜索空结果下结论 = `NO-GO`。

### Memory Evidence / Promotion

使用长期记忆、自动记忆、会话摘要、外部知识库或跨工具 resume 内容作为依据前，必须先分类：

- `authoritative_rule`：当前仓库/组织/用户确认的规则，可直接作为约束。
- `verified_memory`：有 `source_ref`、最近复核和当前文件/命令/函数存在性证据，可作为辅助约束。
- `candidate_memory`：来自自动总结、历史会话、外部工具或旧环境，必须先验证再使用。
- `stale_or_conflict`：证据过期、与当前代码/规则冲突或无法定位来源，不能驱动写入。

Hard Gate：`candidate_memory` 不得直接改变实现、技能正文或收口结论；必须先复核事实、抽象成跨项目模式，并落到 owner 层级。涉及通用基座时，任何依赖特定 agent、CLI、session 路径或 hook 的记忆只能作为 adapter/reference 候选。

### General Base Pollution Gate

修改通用研发工作流基座、技能、hook、模板或治理文件时，先把每条候选规则分类：

- `core_base`：跨项目成立，可进入 owner skill 或 manifest。
- `optional_adapter`：依赖宿主、CLI、会话格式、平台 API 或本地路径，只能进入 adapter/plugin/reference。
- `project_rule`：依赖仓库结构、构建命令、发布约定或团队局部流程，进入仓库规则。
- `project_memory`：依赖具体事故、功能、类名、表名、业务文案或一次性上下文，进入项目记忆。
- `reject_project_pollution`：无法抽象成跨项目控制信号，不写入通用基座。

Hard Gate：
- 通用技能正文不得包含项目名、仓库绝对路径、功能名、业务类名、表名、固定业务文案、事故原文或团队专属命令。
- 项目/会话证据只能作为原材料；进入通用基座前必须抽象成“触发信号 -> 门禁 -> 输出/验证”的 compact control signal。
- 若一条规则离开具体项目后无法执行或验证，必须下沉到项目规则/项目记忆，不能留在通用基座。
- 收口前必须对 changed canonical source 和 backup mirror 做项目污染扫描，并报告 `pollution_scan=pass/fail`。
- 发现污染时状态为 `NO-GO`，先移除或下沉，再继续同步、changelog 或完成态声明。

### 需求字面量

需求含固定文案、字段来源、固定值、固定失败场景、空值行为、条件顺序、精确维度或禁止副作用时，编码前必须整理：

`requirement literal -> order -> must happen -> must not happen -> ownership/surface -> code location -> test assertion`

缺失 = `NO-GO`。

### Surface 覆盖

需求列出多个入口、接口、页面、导出、任务、消息、日志或展示面时，必须有 Surface 覆盖矩阵：

`surface -> entry -> orchestration -> query/write -> output/display -> validation`

不能用同类入口推断覆盖。缺失 = `NO-GO`。

### Expected Diff / Scope

跨模块、多 surface、报表/导出、异步任务、日志展示、配置、数据落库或外部集成时，编码前必须有 Expected Diff Matrix：

`requirement -> modules -> expected file families -> change type -> out-of-scope file families -> validation`

缺失 = `NO-GO`；实现后实际 diff 不匹配必须回退规划。

### 小需求轻量档

当需求预估为单接口、少量字段透传或单规则判断，且无 DB schema、复杂异步、多端 surface 或外部集成时，可以使用轻量档；但只能压缩文档表达，不能取消门禁。

轻量档必须输出：`type -> requirement source -> mini freeze matrix -> expected diff mini table -> RED/static guard -> GREEN/verify -> final diff check`。

发现数据源不明、多入口副作用、显式顺序约束、历史材料冲突、用户已纠错或实际 diff 超出预测时，退出轻量档并升级为完整需求链。

### Scope 分类

复杂需求进入编码前，必须把需求项和候选文件族分类：

- `IN_SCOPE`
- `FRONTEND_ONLY`
- `ALREADY_IMPLEMENTED_NEED_EVIDENCE`
- `OUT_OF_SCOPE_PENDING_CONFIRMATION`
- `SUPPORTING_TEST_OR_TOOLING`
- `UNRELATED_DRIFT`

需求写着“待定 / 需确认 / 先沟通 / 前端工作”时，默认不得进入生产代码实现。

### Historical / Replay / Eval

普通开发不展开 replay/eval 细则。只有用户明确要求历史重跑、oracle 对比、技能实测、分支/提交复现、或从旧实现吸收补丁时，才读取 `references/replay-eval-gates.md` 并执行其中的 source-of-truth、slice、isolation 和 disclosure 门禁。

静态 `review-only` 只需要声明基准版本、证据来源和验证缺口；不得因为输入包含 commit range 就默认创建隔离 worktree 或进入完整 replay。

### 技能源头治理

修改技能时：

- 只改 canonical source。
- 镜像和知识库备份只能由 source 同步生成。
- 通用技能正文不得写入项目名、仓库路径、类名、表名、事故文案或团队专属命令。
- 改完必须同步知识库备份、更新技能 changelog/历史记录、验证 source 与 backup 一致；若存在备份 Git 仓库，还必须提交并推送当前 upstream 分支。
- 备份仓库工作区不干净、无 upstream、push 失败或不能证明 hash 一致时，完成状态只能是 `BLOCKED`，并报告阻断分支与路径。

### Artifact Ownership

涉及 SQL、DDL、配置、发布脚本、数据修复、运维命令或外部交付物时，先确认 ownership：

- 代码仓库
- 文档
- 发布单/DBA
- 运维平台
- 外部系统

ownership 未确认 = `NO-GO`。

### Generated Artifacts

实现、测试、构建、截图、索引、缓存、日志、临时脚本或工具输出产生的文件必须先归类：

- effective diff：需求需要交付或审查的代码/文档/规格。
- generated artifacts：可再生成、临时、环境相关或仅供本地验证的产物。

未分类的新增文件不得进入完成结论或提交计划。

### Helper 默认行为

复用 helper、builder、renderer、mapper、gateway、日志/审计方法前，检查：

- 默认补值
- fallback / 降级
- 隐式写表、消息、状态、审计
- 展示层二次推导

冲突时必须扩展或绕开 helper。

### 边界词

用户说“不要动 / 只新增 / 只填剩余 / 只保留 / 不要改前端 / 旧的不要动”时，先输出：

- 保留项
- 仅补充项
- 禁止改动项

未冻结边界 = `NO-GO`。

### 构建/测试

涉及构建/测试时：

- 优先用 `.memory/build-test-profile.yaml`。
- 明确工作目录、模块、验证范围。
- PowerShell 下仅在参数误解析或 `-Dtest` 含过滤符时使用 `mvn --%`。
- `--%` 会阻止后续变量展开；命令包含运行时变量、路径拼接或动态参数时，改用参数数组/逐参数引用，不要用 stop-parsing。
- 不带项目要求的 settings/root pom 不得宣称构建失败。

### 基线 Blocker 分类

首次 RED、编译、测试或 replay 探测失败时，先分类失败来源，不得直接写成需求失败：

- `baseline_compile_blocker`：起点或未改生产代码前已无法编译。
- `feature_diff_blocker`：本轮有效 diff 引入的编译或测试阻塞。
- `test_runtime_blocker`：测试能编译但运行环境、数据、容器或外部依赖阻塞。
- `environment_blocker`：依赖解析、权限、网络、工具链、shell 参数解析阻塞。

`baseline_compile_blocker` 和 `environment_blocker` 只能阻塞验证或要求隔离处理，不能当作业务 RED 证据。

## 输出

```markdown
📋 预检查
- [x] 记忆: .memory/MEMORY.md / error-lessons.md
- [x] 相关教训: {N}
- [x] 边界模式: 普通 / fill-only / replay-isolated
- [x] 矩阵: literal / surface / expected-diff / simple-lane / n/a
- [x] 构建配置: {profile 或 n/a}
- [x] 基线/命令: blocker 分类 / copy-ready 命令 / n-a
- [x] Go/No-Go: GO / NO-GO
```
