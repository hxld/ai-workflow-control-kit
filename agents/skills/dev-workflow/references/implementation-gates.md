# Implementation Gates

本文件承接 `dev-workflow` Phase 4-5 的长规则。主 `SKILL.md` 只保留触发锚点；进入实现或测试收口时按需读取本文件。

## Phase 4 自主实现顺序

当本轮目标包含“尽量自主实现 / 少问 / 覆盖 90%+”时，Phase 4 按以下顺序推进：

1. 建立最小 skeleton 和 baseline capability scan，先让构建图可达。
2. 按 Requirement Coverage Ledger 实现 `core_path`，包括主入口、主状态流转、主要写入/输出和固定字段契约。
3. 为核心主链补接真实入口的行为 RED/GREEN；无法稳定执行时写 `behavior_test_blocker` 并让覆盖率封顶，static guard 只能补防漏改证据。
4. 实现被需求点名的 deploy-facing `supporting_surface`：报表/导出、前端、模板/生成物、OCR/外部 payload、日志、后台任务、通知等；每个 surface 独立验证，不能只停留在 mined。
5. 按 Expected Diff Matrix 逐文件族闭环：`changed+tested`、`changed+static_only+cap`、`deferred+reason+coverage_cap` 或 `blocker`。
6. 更新覆盖账本：`DONE / PARTIAL / BLOCKED / DEFERRED`，并记录未覆盖原因。

禁止把低风险 slice、只读证据、辅助脚本或局部小 GREEN 表述为 90% 完成；覆盖率必须由 `sync-progress` 用账本和验证证据收口。

若前 60% 实现预算结束时最高权重 `core_path` 仍未接入真实入口、没有行为测试宪章或缺少事务深度验证计划，必须停止输出 `[STOP: core_path_unclosed]`；除非下一个 slice 是核心主链或 deploy-facing surface 的直接前置，否则不得继续。

若已经完成真实入口 tracer bullet 或两个连续 core-only/internal slice，但高权重 deploy-facing contract/surface 仍为 untouched，第三个 core-only/internal slice 前必须先落 `exact_contract_first_slice` 或 `deploy_surface_first_slice`；否则输出 `[STOP: surface_budget_gap]` / `[STOP: exact_contract_gap]`。内部 helper、DTO、constant、日志壳或 mock 编排不能抵消这个预算切换点。

## Feedback Loop / Terminal Artifact Gate

复杂实现、bugfix 或 replay/eval 轮次在改生产代码前必须有 agent-runnable feedback loop：一个真实入口或最接近真实入口的 carrier、最小 fixture、预期失败信号、可重复命令或明确 blocker。无法构造时输出 `feedback_loop_blocker`，停止猜测式实现。

终态日志、状态 flag、最终消息、导出列或页面展示只能作为“产生链路已执行”的断言结果，不能作为首个替代实现目标。若测试只证明终态信号被直接写出，却没有证明上游编排、状态/写入/输出副作用已经发生，标记 `small_green_false_positive` + `wrong_test_surface`，下一片必须改为真实入口调用、side-effect ledger 或 deploy-facing surface 的可执行切片。

## Critical Surface Allocation Gate

当需求列出多个高权重 deploy-facing surface 时，Phase 4 不能把实现预算长期集中在单个 core service/helper。进入深度实现前，必须为每个高权重文件族安排至少一个可执行最小切片：

`surface family -> executable first slice -> target file family -> RED/GREEN or runnable contract -> static/blocker cap`

若 report/export/web、template/render/upload、external payload builder、stateful DB writes、transaction tests 等任一高权重 family 仍为 untouched，不得继续扩写低价值 helper 或内部 service；输出 `[STOP: surface_budget_gap]` 或先落该 family 的最小切片。static guard 只能防漏改，blocker 只能暂停并触发 coverage cap；static-only 或 blocker-only allocation 必须标 `executable_surface_slice_gap`，不能把该 surface 计为 `DONE`。

可执行最小切片必须穿过真实 carrier 或可观察输出：入口参数、查询/写入 carrier、渲染/生成、外部 payload、导出/页面输出、持久化或事务边界至少闭合一项。只新增字段、常量、mapper 片段、文件存在 guard 或计划中的 blocker row，只能作为 `static_only_surface_gap` 证据。

模板、图片、附件、上传、扫描件入库、消息通知这类 generated / uploaded artifact chain 不能只证明“失败不阻断”。若需求说需要生成或上传，即使失败不阻断主链，也必须至少有一个成功切片证明：触发点 -> 生成/渲染 -> 文件/内容/元数据 -> 上传或持久化入口 -> 失败隔离。缺任一环只能标 `executable_surface_slice_gap` 或 `DEFERRED_WITH_CAP`。

## Core Entry Closure Gate

高权重 `core_path` 不能只“识别”真实入口，必须在实现队列和实际 diff 中闭环真实入口文件族。Phase 4 前先写：

`core requirement -> real production entry family -> invocation point -> orchestration -> state/write/output side effects -> behavior/transaction test -> blocker if absent`

规则：

- 真实入口可以是 controller、facade、processor、worker、scheduler、exporter、mapper/select/filter 或外部 payload builder 的真实承载点。
- 前 60% 实现预算必须优先修改真实入口或其直接前置承载点；若实际 diff 没有核心入口文件族，输出 `[STOP: core_entry_unclosed]`。
- 已新增 service/helper/DTO/constant 但未接真实入口时，只能算 supporting evidence，core 覆盖最高 `PARTIAL`。
- 若真实入口因 owner、环境或需求边界不可改，必须写 `core_entry_blocker` 和 coverage cap；不得继续用低价值 slice 冲进度。

## Stateful Tracer Bullet Closure Gate

首个 tracer bullet 命中真实入口后，不能把“入口被调用 + 异常隔离”当作 stateful core path 闭环。若同一需求还存在状态推进、任务流转、进度/日志、持久化重写、事务边界、生成/上传物或 deploy-facing surface，下一片必须从以下两类中选一类推进：

- `stateful_success_slice`：真实入口 -> 编排 -> 关键写入/状态/日志/任务副作用 -> success 与 must-not 断言。
- `deploy_surface_first_slice`：需求点名 surface -> 真实承载文件族 -> 可执行契约/输出验证 -> coverage cap 或 DONE 判定。

若只完成了 hook、adapter、placeholder service、负向隔离测试或 mock-only 断言，Phase 4 必须输出 `tracer_bullet_only=true`，并把下一片绑定到 `core_entry_unclosed`、`side_effect_ledger_gap`、`exact_contract_gap` 或 `executable_surface_slice_gap`。无法绑定时停止并报告 `[STOP: tracer_bullet_only]`，不得继续扩 helper、DTO、常量或静态 guard。

## Stateful Side-Effect Ledger

状态流转、事务边界、持久化重写、进度、日志、任务推进或失败隔离属于 stateful core path 时，实现前必须列账本：

| side effect | table/repository/service | transaction boundary | success assertion | failure/must-not assertion | test mode/blocker |
|-------------|--------------------------|----------------------|-------------------|----------------------------|-------------------|

缺少状态、任务、进度、日志、落库、回滚/失败隔离任一高权重副作用时，core path 不得标 `DONE`；只能标 `PARTIAL`、`BLOCKED` 或 `DEFERRED_WITH_CAP`。

账本必须同时覆盖正向写入、禁止写入/旧副作用消失、事务提交/回滚边界，以及需求点名的 deploy 输出或外部可观察结果。只验证协作者调用次数、日志字符串或异常被 catch，不能证明 stateful success path 完成。

## Exact Contract Implementation Gate

实现 deploy-facing 字段、列、flag、type、enum、payload shape 或展示列前，必须把冻结行落实为：`literal -> code symbol -> DB/API/wire name -> serializer/mapper/display alias -> assertion`。命名、大小写、snake/camel、枚举值或 payload 结构存在假设时，停止并回退 `deep-plan`；不能边写边猜。

## Static Guard 纪律

- static guard 只能作为防漏改证据，不能替代核心行为测试。
- core_path 只靠字段/常量/方法名/文件存在断言时，Phase 4/5 最多输出 `PARTIAL`。
- helper-only supporting surface 必须追到真实入口引用；未接入 controller/service/exporter/worker/mapper 查询链时，不计为完成。
- must-not 行为必须在生产代码前有反向 RED 或明确 blocker。
- 非阻断后处理必须同时验证“成功链路已实现/被触发”和“失败不阻断”；只验证“不阻断”不能证明该功能已实现。
- 非阻断生成物/上传链路必须验证成功路径的可观察结果或明确 blocker；只写 try/catch、日志或 after-commit 壳不算 surface 完成。

## Transaction Depth Gate

状态流转、事务边界、进度/日志、持久化重写、任务推进等 stateful core path，必须在实现队列中包含 DB/事务级测试或明确 `needs_transaction_test` blocker。只有 mock 协作者验证时，core path 最高 `PARTIAL`，不能标 `DONE`，覆盖率自动封顶在 70 以下；若同时缺真实入口测试和 side-effect ledger，覆盖率应继续下调。

## Phase 4 设计回退触发器

实现阶段出现以下任一信号，必须停止当前实现，输出 `ESCALATE_UPSTREAM` 或 `[STOP: replan_required]`，并回退到 `deep-plan`：

- **DTO 新约束**：原计划未冻结的字段分层、命名、顶层/嵌套结构、通用壳/专属 detail 边界发生变化。
- **接口新约束**：新增调用方、兼容性要求、外部 JSON 契约、鉴权/幂等等关键条件发生变化。
- **配置新约束**：新增配置 key、namespace、缓存刷新、fallback、旧 key 兼容/清理策略被提出或被推翻。
- **扩展性新约束**：用户明确要求未来新增渠道/来源/调用方要复用，导致当前实现边界不再成立。
- **显式需求偏移**：需求源已经写死 literal，但当前实现只能落成“类似行为”或当前 helper / 展示层无法承载该 literal。

禁止发现上述信号后继续补丁式前进、只改代码不回写 `.doc` / `openspec`、用“先写完再说”替代设计回退、把字面量对齐降级成后续微调。

回退动作：暂停实现，记录新约束与影响范围，回到 `deep-plan` 更新冻结表、任务拆分、`.doc`、`openspec`，重新经用户确认后恢复 Phase 4。

## Phase State Checkpoint / Resume Gate

长任务、多 slice、跨上下文压缩、可能暂停或需要交接时，每个 phase/slice 完成后必须留下 compact state：

```markdown
- phase:
- completed slice:
- changed files:
- validation:
- blockers:
- next slice:
- rollback boundary:
```

优先写到当前仓库已有的 `.doc/<feature>/phase-state.md`、`.artifacts/phase-state.md` 或任务文档；没有合适文档面时，在用户更新和 Phase 7 `sync-progress` 中输出。恢复上下文时先对比 checkpoint 与实际 diff/test 状态，再继续下一 slice；无法对齐时输出 `resume_state_gap`，不得直接宣告 DONE。

## Phase 5 Hard Gate

- 测试报告必须写明执行命令、失败阶段、验证范围。
- 若需求包含固定空值、禁止字段、禁止 fallback、禁止副作用或多 surface，报告必须写明反向断言覆盖。
- 如果之前失败的是 `compile` / `testCompile` / `package`，报告中必须包含该阶段已重新通过的证据。
- 如果只有局部测试或缺少完整复验证据，Phase 5 状态只能是 `PARTIAL`。
- 缺少关键信息时，Phase 5 状态只能是 `BLOCKED` 或 `PARTIAL`，不得进入 Phase 7 Handoff。
