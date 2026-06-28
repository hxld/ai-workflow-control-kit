---
name: gen-tests
description: "Use when user says 生成测试, 写单元测试, generate tests, 补测试, 写测试, add tests, write unit tests, test failed, 修测试, or after implementation completes"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep,Skill
---

# 生成测试

检测项目测试模式，生成/补充/修复测试，执行 test-fix-verify 循环。

**专家角色：** QA 工程师

**上游技能：** `deep-plan`, `dev-workflow`, `auto-complete`
**下游技能：** `pre-flight-check` (预检)

---

## 何时使用

"生成测试" / "写单元测试" / "补测试" / "测试不通过" / "检查覆盖率" / 实现代码后

## 何时不使用

实现前的行为变更 → 回到 `dev-workflow` 的 RED/GREEN 门禁 | 没有框架 → 先建议搭建 | 用户说"不要测试"

## 预检查

**必须：** 先使用 `pre-flight-check` 技能。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：FIX 模式下的失败阶段判断与验证链路校正属于 Hard Gate，未通过不得直接改测试或业务代码
- **PARTIAL**：只表示测试验证范围未覆盖全量，不表示“测试修了一半”
- **完成标准（DoD）**：统一表示“当前 Mode 的目标已完成，并有对应验证证据”
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

---

## Mode 检测（内部路由）

| 用户意图 | Mode | 动作 |
|----------|------|------|
| "给这个文件写测试" / 无现有测试 | CREATE | 从零创建新测试 |
| "补充测试" / "补测试" | FILL | 检测现有模式，补充缺失场景 |
| "测试不通过" / "帮我修测试" | FIX | 诊断并修复失败测试 |
| "检查覆盖率" / "测试覆盖率" | AUDIT | 分析覆盖率，输出缺口报告 |
| "修 bug" 但缺少失败测试/日志/复现 | TRIAGE | 先输出采证计划或可写 RED，不直接改源码 |
| 模糊 | AUTO | 有现有测试 → FILL，无 → CREATE |

---

## 执行流程

```
[Phase 1] 检测框架
    ↓
[Phase 1.5] 识别构建拓扑与验证范围
    ↓
[Phase 1.6] 读取测试设计控制（Test Design Control）
    ↓
[Phase 2] 扫描现有测试 → 提取模式（10项）
    ↓
[Phase 3] 确定 Mode（CREATE / FILL / FIX / AUDIT）
    ↓
[Phase 4] 按 Mode 执行（见下方）
    ↓
[Phase 5] Test-Fix-Verify 循环（最多 3 轮）
    ↓
[Phase 6] 输出报告
```

## Phase 1: 框架检测

| 模式 | 框架 | 命令 |
|------|------|------|
| `jest.config.*` | Jest | `npx jest` |
| `vitest.config.*` | Vitest | `npx vitest run` |
| `pytest.ini` | Pytest | `pytest` |
| `pom.xml` / `build.gradle` | JUnit | `mvn test` |
| `go.mod` | Go | `go test ./...` |

无框架 → 建议搭建 → 等用户确认。

## Phase 1.5: 识别构建拓扑与验证范围

在运行任何测试命令前先确认：

- 单模块还是多模块 / monorepo / workspace
- 命令在哪个目录执行
- 测试过滤参数影响的是执行范围，还是也影响编译 / 收集 / 依赖解析
- 是否会自动拉起上游模块、其他测试文件、共享 setup

**如果项目存在 `.memory/build-test-profile.yaml`：**

- 必须先读取 profile，再决定 Maven/JUnit 命令
- 优先复用其中的 `targeted_test_template` 和 `full_verify_template`
- 不要在 profile 已存在时临时手拼另一套 Maven 命令，除非明确说明偏离原因
- 若 shell 为 PowerShell 且 Maven 参数被误解析，按 profile 中的 `powershell_passthrough` 规则决定是否使用 `--%`

**特别注意：**

- `-Dtest`、`--filter`、文件路径过滤，常常**只缩小执行范围**
- 它们**不一定**缩小 `testCompile`、discovery、workspace bootstrap 范围
- 出错时先判断是“测试逻辑失败”还是“验证链路失败”

**稳定错误锚点：** 日志编码不稳定或输出很长时，先抽取 `phase / exit code / module / file path / class / method / exception type / first failing symbol`；中文错误文案只能辅助判断，不能作为唯一证据。

## Phase 1.6: 读取测试设计控制（Test Design Control，硬门禁）

测试生成必须优先读取测试设计控制产物，再扫描现有测试模式。来源优先级：

1. `.doc/<feature>/tech-design.md` 中的 `测试设计控制 / Test Design Control`。
2. `.doc/<feature>/test-design.md` 或同等测试设计文档。
3. 分支覆盖计划或上游同症状分支矩阵中的验证 / must-not 行。
4. 用户显式给出的最终测试范围与风险分级。

命中以下任一情况时，若缺少测试设计控制或合法 mini form，输出 `test_design_gap` 并回到 `deep-plan`，不得自由生成一批测试后宣称覆盖完成：多 surface、状态流转、落库/事务、异步、外部接口、报表/导出、前端可见面、旧数据兼容、must-not 行为、明显高返工风险。

消费规则：

| 测试设计控制行 | 生成测试时必须使用 |
|----------------|--------------------|
| 影响范围 | 最终测试范围与排除项，不能自行扩大或遗漏 surface |
| 风险分级 | 每个接口/入口的测试深度与优先级 |
| 判定表 | 最小 Case 组合；组合外新增用例必须说明原因 |
| 可执行步骤 | Given / When / Then 操作步骤与多维断言 |
| 覆盖校验 | 输出覆盖矩阵状态：`covered`、`partial`、`blocked:<reason>`、`not_applicable:<reason>` |

小需求可使用 `references/test-design-control.md` 的 mini form；但仍必须有 scope、risk、case、assertion、coverage 五项最小闭环。
## Phase 2: 模式提取（10项）

| # | 类别 | 检测 |
|---|------|------|
| 1 | 基类 | extends? 或无？ |
| 2 | 注解 | @Slf4j? @Resource? @MockBean? |
| 3 | 注入 | 构造器？字段？ |
| 4 | 测试数据 | static final? @Before? 内联？ |
| 5 | 断言 | assertTrue("msg", x)? assertThat? |
| 6 | 异常 | try-catch? assertThrows? |
| 7 | 命名 | testMethod_Scenario? should_xxx? |
| 8 | 结构 | Given-When-Then? AAA? 扁平？ |

**关键：** 生成的测试必须与已有模式风格一致。多种风格 → 选最常见的或问用户。

## Phase 2.5: 需求风险转测试矩阵（Hard Gate）

已有测试设计控制时，以其中的范围、风险、判定表和覆盖矩阵为主；本阶段只补充未显式覆盖的 must-not、副作用、异常和真实入口断言，不得改写已确认范围。

当需求或审查反馈命中以下任一信号时，补测试不能只覆盖 happy path，必须先生成风险矩阵：

| 信号 | 必须生成的测试 |
|------|----------------|
| 固定展示 / 固定结果 / 固定空值 / 空集合 | 正向断言目标字段；反向断言禁止字段为空、不存在、被过滤或未被默认回填 |
| 失败分支 / 回退分支 / 不应发生副作用 | 断言失败文案或结果；同时断言不调用状态变更、写表、发消息等副作用 |
| 精确 A+B 维度 / 组合条件 | 断言 A+B 同时满足才通过；补“A 满足、B 缺失”不得通过的反例 |
| 禁止 fallback / 禁止降级 | 构造更宽松条件存在但精确条件缺失的用例，断言不会进入目标动作 |
| 多入口 / 多接口 / 多页面 / 多导出 | 每个 surface 至少一条独立断言，不能用同类 surface 的测试代表 |
| 复用 helper / builder / renderer | 断言 helper 的默认补值、默认推导、隐式副作用没有改变需求语义 |
| 明确异常堆栈 / 空值转换 | 构造命中第一业务首帧失败表达式的最小入参/配置；断言错误语义或修复后结果 |
| 外部接口 / 第三方协议 | 使用 request/response/config fixture 冻结 contract；区分外部错误、我方幂等跳过和我方处理 bug |
| 并行聚合 / 多数据源回填 | 构造任一来源失败、超时或返回空的用例；断言其它来源按契约继续回填或整体按契约 fail closed |
| 单活记录 / 唯一语义 / 幂等保存 | 构造重复有效记录、重复提交或并发保存场景；断言读取确定、更新范围正确、唯一约束或冲突处理明确 |
| 同症状多分支 / 生产热修 / 缓存修复 | 至少为目标分支和一个绕过目标修复的分支设计断言、静态 guard 或 blocker；证明本次覆盖范围与未覆盖范围 |

**Hard Gate：** 如果测试计划里只有 `should happen`，没有 `must not happen`，而需求涉及失败、空值、禁止 fallback、副作用边界或多 surface，则不得进入 Phase 4。
**分支门：** 上游存在同症状分支矩阵 / 分支覆盖计划时，测试报告必须逐行映射 `covered / static_only / blocked / out_of_scope_confirmed`；缺映射时只能 `PARTIAL`，不得写“热修验证完成”。

**断言粒度：** guard 测试优先断言需求行为、数据流、持久化、展示、消息、状态和副作用边界；除非需求显式指定内部 API，否则不得把非必要方法名、私有 helper 名或临时实现结构写成完成标准。

### Phase 2.5A: Behavior Test Charter Before Code（核心门禁）

高权重 `core_path`、明确 supporting surface 或 90%+ 自主实现目标，在改生产代码前必须先写行为测试宪章：`behavior -> real entry/carrier -> fixture/source -> side effects -> must-not -> assertion -> execution mode -> fallback/blocker`。必填场景：状态流转、事务/回滚、异步任务、生成物/非阻断后处理、报表/导出、外部 payload、前端/风险提示联动。若环境无法运行，仍需冻结断言与 `behavior_test_blocker`；不能用 compile、文件存在、helper-only 或 mock 返回值替代核心行为证据。stateful core path 还必须列 `side effect -> table/repository/service -> success assertion -> failure/must-not assertion -> test mode/blocker`。

### Phase 2.6: 小 GREEN 防误判门禁

当需求存在冻结表、surface 矩阵或预计变更矩阵时，测试通过不能只证明新增小测试通过。必须先建立完成覆盖表：

覆盖表模板见：`../dev-workflow/references/complex-requirement-delivery-kit.md` 的 TDD Coverage Plan 与 Final Completion Check。

| 来源 | 覆盖要求 |
|------|----------|
| 需求覆盖账本 / 90% 覆盖计划 | `core_path` 行必须有优先 RED/GREEN 或等效 static guard；supporting surface 逐项验证；optional/deferred 不计入完成率 |
| 显式需求冻结表 | 每行至少一个正向断言；涉及禁止行为时至少一个反向断言 |
| 字段与数据来源冻结表 | 断言数据来源、落库字段、展示字段，不允许默认值/回退值替代 |
| Exact Contract Freeze Gate | 断言 code symbol、DB/API/wire name、flag/type/enum、payload shape 或展示列精确匹配 |
| Surface 覆盖矩阵 | 每个 surface 至少一个独立断言，不允许用同类入口代表 |
| 预计变更矩阵 | 每个预计文件族至少有验证点，并在收口时标成 `changed+tested` / `changed+static_only+cap` / `deferred+reason+coverage_cap` / `blocker`；未预测文件需解释或回退规划 |
| 关键 Surface 分配计划 | 每个高权重 deploy-facing family 至少有一个可执行最小切片：真实承载文件族 + RED/GREEN、可运行契约测试或真实输出验证 |

**Hard Gate：** 只跑通自己新增的小测试，但覆盖表缺行时，结果只能是 `PARTIAL`，不得输出“测试完成”。
**90% Gate：** 自主实现目标下，测试报告必须按覆盖账本标出 `DONE / PARTIAL / BLOCKED / DEFERRED`；核心主链缺少测试或验证锚点时，不得声称达到 90%。
**RED Row Gate：** 对 guard / contract / 冻结表测试，不能只证明“整套测试在基线失败”。必须逐行核对每个 guard row 在未实现基线下会失败；若某一行基线已通过，该行不计入 RED 覆盖，必须改成能区分新旧行为的断言或标记为非覆盖项。
**Real Entry Test Gate：** `core_path` 测试必须至少覆盖一个真实入口或承载点（controller / facade / processor / worker / exporter / mapper / scheduler 等）。只测新 helper、新 service 或 mock 编排时，结论必须降级为 `mock_behavior_gap` 或 `helper_only_surface_gap`。
**Stateful Tracer Bullet Test Gate：** 真实入口的第一条 tracer bullet 只证明入口可达；若核心行为还包含状态/任务/进度/日志/持久化/事务/生成物或 deploy-facing surface，测试报告必须标记 `tracer_bullet_only`，并列出下一条必须补的 `stateful_success_slice` 或 `deploy_surface_first_slice`。只有负向隔离、hook 调用、placeholder service 或 mock-only 断言时，不能把 core path 或相关 surface 标 `DONE`。
**Transaction Depth Gate：** 状态流转、事务边界、进度/日志、持久化重写、任务推进等 stateful core path，必须有 DB/事务级测试宪章或 `needs_transaction_test` blocker；只有 mock 协作者测试时不得标 core `DONE`。若缺真实入口测试或 side-effect ledger，测试报告必须标 `real_entry_gap` / `side_effect_ledger_gap` 并降级覆盖。
**Side-Effect Ledger Execution Gate：** stateful core path 的 ledger 断言必须覆盖正向写入、禁止写入/旧副作用消失、事务提交/回滚边界，以及需求点名的 deploy 输出或外部可观察结果；只断言 mock 调用次数、日志字符串或 catch 分支时，报告必须标 `side_effect_ledger_gap` / `wrong_test_surface`，不得把 stateful success path 标 `DONE`。
**Exact Contract Test Gate：** deploy-facing 字段、列、flag、type、enum、payload casing/shape 或展示列必须有精确断言；只断言 Java 字段存在、常量存在或 JSON 大致包含不能证明 wire/DB/display 契约完成。字段大小写、数组/对象/字符串包装、SQL alias、页面参数名和导出列名都要按外部可观察形态断言。
**Surface Budget Test Gate：** 高权重 report/export/web、template/render/upload、external payload、stateful DB writes、transaction tests 等 family 若没有可执行最小切片，测试结论必须标 `surface_budget_gap` 或 `executable_surface_slice_gap`，不能用 core service 单测、static-only guard 或 blocker-only row 覆盖。
**Exact Contract First-Slice Test Gate：** 固定字段、列、flag、enum、payload shape、展示列或日志文案属于高权重 deploy-facing contract 时，首个相关测试 slice 必须直接断言可观察 carrier；若前两轮只测 core helper/service 而 contract 仍 untouched，第三轮前必须补 contract RED/GREEN 或标 `exact_contract_gap`。
**Report Query Test Gate：** 报表/导出/页面 surface 必须分开断言 query carrier、filter/select、header/value 和 UI/script parameter；只测导出 workbook 或只测 mapper SQL 不能代表查询入口闭环。
**Removed Side-Effect Regression Gate：** 需求要求删除、禁止或抑制某个日志、任务、消息、落库、回调或自动触发时，测试必须证明旧副作用不再发生，同时证明保留的成功路径仍发生；只看代码删除、只跑 compile 或只测新增字段不能证明删除型需求完成。
**Non-blocking Test Gate：** “失败不阻断”类需求要同时覆盖正向触发和失败隔离；只断言失败不阻断，不能证明图片/附件/通知/报表/异步后处理等功能已经完成。对模板/图片/附件/上传链路，测试或 blocker 必须覆盖 trigger、render/generate、file/content metadata、upload/persist entry 和 failure isolation；只能验证 try/catch 或 after-commit wrapper 时标 `executable_surface_slice_gap`。
**DAMP Test Gate：** 测试优先描述业务行为和契约，不为去重过度抽 helper；复杂场景的测试名、Given 数据和断言应能单独读成规格。只有当重复隐藏意图很少时才抽公共工具。
**Interface-as-Test-Surface Gate：** 测试优先穿过模块对外 interface 或真实业务入口；若必须测试私有 helper、内部调用次数或 mock 内部协作者才能证明行为，标记 `wrong_test_surface` 并回到设计/实现重新放置 seam。
**Terminal Artifact Test Gate：** 终态日志、状态 flag、最终消息、导出列或页面展示不能单独代表核心链路完成。若测试只断言终态信号被写出，却未证明触发入口、编排、状态/落库/进度/日志/外部输出副作用链路，标记 `small_green_false_positive` / `wrong_test_surface` / `feedback_loop_blocker`，并改写为真实入口或 side-effect ledger 断言。
**One-Behavior Cycle Gate：** RED/GREEN 按一个行为一轮推进；批量新增多条 imagined behavior 测试后再实现，结果只能算 `horizontal_test_risk`，不能作为高置信覆盖证据。
### Phase 2.7: 部分基线实现门禁

当基线已经部分实现需求时，每个冻结表或 guard row 必须标记：

| 状态 | 含义 | 处理 |
|------|------|------|
| `BASE_FAIL` | 基线行为不满足需求 | 可作为 RED/GREEN 覆盖 |
| `BASE_PASS_ALREADY_COVERED` | 基线已满足且有证据 | 不计入新增 RED，只保留回归验证 |
| `BASE_PASS_NEEDS_EVIDENCE_ONLY` | 可能已满足但证据不足 | 先补证据，不改生产代码 |
| `NOT_TESTABLE_STATIC_PROOF` | 不适合自动化断言 | 提供静态证据或人工验证 |
| `OUT_OF_SCOPE` | 不属于本轮实现 | 不生成生产代码测试 |

没有 row 状态表时，复杂需求测试结果只能是 `PARTIAL`。

基线探测失败必须另行标记为 `baseline_compile_blocker`、`test_runtime_blocker` 或 `environment_blocker`；这些阻塞不能当作业务 RED。

### Phase 2.8: Static Guard Fallback
没有稳定运行态测试但需求可静态证明时，允许使用静态 contract guard；必须先在基线失败、实现后通过，并标记 `static proof`。
静态 guard 只能降低漏改风险，不能冒充行为测试；若涉及逻辑分支、状态、副作用或外部可观察结果，优先补行为断言，失败则按 blocker 分类披露。

**Coverage Cap：**

- core_path 只有 static guard、没有行为断言时，相关 slice 最高 `PARTIAL`。
- 90% 自主实现目标下，static-only core_path 不得支撑 `Autonomous implementation target >=90%: met`。
- helper/constant/file-presence guard 只能证明“防漏改”，不能证明入口、状态、持久化、消息、导出或外部 payload 行为。
- 若 surface 只验证新增 helper，未验证真实 controller/service/exporter/worker 入口，surface 测试结论必须写 `helper_only_surface_gap`。
- 需求明确点名的报表、导出、图片、附件、异步或外部协议文件族若只有 static guard，必须写 `static_only_surface_gap`，并交给 `sync-progress` 做 coverage cap。
- 高权重 surface 若只有 static guard、文件存在断言或 blocker row，没有真实承载文件族验证，不能标 `DONE`，只能标 `PARTIAL/BLOCKED_WITH_CAP`。
- stateful core path 只有 mock 协作者测试、没有 DB/事务级验证时，不能支撑 70% 以上覆盖或 core `DONE`。

**Core Behavior Minimum：** 复杂需求的核心主链至少应有一个行为 RED/GREEN 或可执行契约测试；若无法做到，必须在报告中写 `behavior_test_blocker`，并由 `sync-progress` 对覆盖率封顶。

### Phase 2.9: Greenfield Skeleton Gate
从 0 新增 API/DTO/entity/mapper/service 等多模块能力时，先用 skeleton 让 `testCompile` 可达，再写行为 RED；缺类、缺 mapper、缺 bean 只能标记为 `skeleton_gap` / `build_graph_gap`，不能算业务 RED。

## Phase 3.5: 集成测试可行性检测与 Mock 降级策略（硬门禁）

需要 Spring 容器、数据库、外部 RPC 或重量级依赖时，先探测可行性，再在 `integration / integration_with_mocks / mock_unit / static_only` 中选择策略。Mock 降级优于零测试，但核心主链 mock_unit 最高 `PARTIAL`。细则见 `references/integration-test-fallback.md`。

## Phase 4: 按 Mode 执行

### Mode CREATE（无现有测试）

1. 问用户偏好（命名/断言/结构）— 如果没有明确指示
2. 生成测试（场景覆盖：正常/空/无效/边界/异常）
3. 运行 + Test-Fix-Verify 循环

### Mode FILL（补充缺失场景）

1. 分析缺口 → 确定缺失场景
2. 按已有模式风格生成补充测试
3. 运行 + Test-Fix-Verify 循环

### Mode TRIAGE（bugfix 证据不足）

先分类证据，能写断言则补 RED，不能写断言则输出采证计划；只允许输出 `NEEDS_REPRO`、`NEEDS_LOGS`、`NEEDS_CONTRACT`、`NEEDS_STACK_INPUT`、`NEEDS_ASYNC_STATE_CHAIN` 或 `STATIC_INFERENCE`。细则见 `references/test-fix-triage.md`。

### Mode FIX（修复失败测试）

先确定第一失败阶段、失败范围和证据类型，再分类为测试代码 bug、源代码 bug、环境、构建图/验证链路、运行态 blocker、runtime noise 或基线 blocker。没有根因不修复，三次失败后升级 `deep-plan`。细则见 `references/test-fix-triage.md`。

**Hard Gate：**

失败阶段在 `resolve / compile / testCompile / reactor build` 时，禁止直接修改断言或业务逻辑；只有进入目标测试执行/断言阶段，才允许按测试代码 bug / 源代码 bug 处理。完整 hard gates 见 `references/test-fix-triage.md`。

### Mode AUDIT（覆盖率审计）

1. 运行覆盖率命令：

| 框架 | 命令 |
|------|------|
| Jest | `npx jest --coverage` |
| Vitest | `npx vitest run --coverage` |
| Pytest | `pytest --cov` |
| JUnit/Maven | `优先使用 .memory/build-test-profile.yaml 中的 full_verify_template，再补 coverage 命令` |
| Go | `go test -cover ./...` |

2. 按 `<60% / 60-80% / >=80%` 输出补测建议、缺口或合格结论。
3. 同时检查场景覆盖、反向断言、多 surface 与小 GREEN 防误判矩阵；细则见 `references/test-fix-triage.md`。

## Phase 5: Test-Fix-Verify 循环

最多 3 轮：每轮 `修复 -> 运行 -> 检查`；超过 3 轮后 PAUSE 并输出诊断摘要。

### 降级规范

- `evidence gap: [缺失什么证据]`
- `降级原因: [具体原因]`
- 禁止裸写 "测试失败"

## 关键约束

1. **Mock 规则：** 外部依赖 mock，内部逻辑不 mock，纯函数从不 mock；系统边界可 mock，模块内部协作者默认不 mock
2. **修复上限：** 每个失败 3 次 — 然后升级
3. **FIX Mode 只修不生成** — 不增量生成新测试
4. **风格一致：** 必须遵循 Phase 2 提取的模式
5. **先分层：** 先区分环境 / 构建图 / 代码问题，再动测试或源码
6. **禁止误判：** 不能把“过滤后的测试执行”直接当成“完整验证”
7. **配置优先：** 项目已有 build/test profile 时，优先继承 profile，不手写分叉命令
8. **小 GREEN 防误判：** 新增测试全部通过不等于需求完成；缺冻结表覆盖、surface 覆盖或 must-not 断言时只能标记 PARTIAL
9. **行为断言优先：** 测试不能为了贴合当前实现而绑定非必要内部方法名；应验证对用户、调用方、数据或系统边界可观察的行为
10. **逐行 RED 优先：** guard / contract 测试的每一行断言都要能在基线区分新旧行为；整体 RED 不能替代行级 RED
11. **异步 surface 独立验证：** 轮询、定时、队列、状态回调、日志筛选和导出不能被入口 happy path 代表
12. **已有能力先给证据：** 基线已满足的 row 不改生产代码，只保留回归/静态证据
13. **命令可复制：** PowerShell 静态 Maven 命令含 `-Dtest` / `-Dsurefire` 时给出 `mvn --% ...`；含变量或动态路径时改用参数数组/逐参数引用
14. **Bugfix 先采证：** 没有失败测试、日志、trace、复现步骤或可观察断言时，先补证据链；不因“看起来像”直接改源码
15. **异步断言优先：** 定时任务、队列、回调、轮询、任务状态和完成日志问题，必须先证明哪个状态或下游结果不符合预期
16. **Mock 不替代行为：** mock 只能隔离外部边界；若测试主要依赖 mock 返回目标结果，降级为 `PARTIAL + mock_behavior_gap`。反模式见 `references/test-patterns.md`
17. **Mock 降级优于零测试：** 当集成测试不可行时（容器启动失败、外部依赖缺失），必须按 Phase 3.5 降级为 mock 单元测试，而非跳过测试。零测试 = `NO-GO`

## 搜索路径

Java: `src/test/**/*Test.java`；JS/TS: `**/*.test.ts`, `**/*.spec.ts`；Python: `tests/**/*.py`, `test_*.py`；Go: `**/*_test.go`。

## 输出格式

默认输出：模式、验证范围、失败阶段、RED/GREEN 证据、测试设计控制映射、分支覆盖测试映射、覆盖账本测试映射、遗留 blocker、下一步。完整模板见 `references/output-formats.md`。
