你现在执行 Phase 0 Contract Gate，只做 plan-only 验证，不写生产代码、不写测试代码、不跑 Maven。

【固定上下文】
- 主仓库: {{PROJECT_ROOT}}
- feature_name: {{FEATURE_NAME}}
- requirement_source: {{REQUIREMENT_SOURCE}}
- oracle identity: redacted in Phase 0; direct oracle refs are forbidden
- base commit: {{BASE_COMMIT}}
- replay root: {{REPLAY_ROOT}}
- isolated worktree: {{WORKTREE}}
- neutral baseline index: {{BASELINE_INDEX}}
- context manifest: {{CONTEXT_MANIFEST}}
- surface carrier scan: {{SURFACE_CARRIER_SCAN}}
- oracle diff analysis: {{ORACLE_DIFF_ANALYSIS}}
- feature classification: {{FEATURE_CLASSIFICATION}}
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}

【Phase 0 目标】
先完成高质量探索和第一刀可行性判断，目标是给后续规划阶段提供事实基线，而不是直接编码。

Phase 0 只允许：
1. 读取 requirement_source。
2. 读取 repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml。
3. 读取 isolated worktree 当前代码。
4. 读取 `{{BASELINE_INDEX}}`，但只能把它当作中性结构索引。
5. 读取 `{{SURFACE_CARRIER_SCAN}}`，但只能把它当作中性生产承载点候选清单，不能替代 `rg`/源码确认。
6. 读取 `{{CONTEXT_MANIFEST}}` 以及其中列出的 `{{SYSTEM_CONTEXT_DIR}}` 只读上下文文件；它们只能作为项目通用背景，不能替代需求和代码事实。
7. 读取 `{{ORACLE_DIFF_ANALYSIS}}`，oracle commit diff 的结构化分析（文件列表、layer 分类、weight），用于在探索阶段就约束 carrier 选择与 oracle 对齐。
8. 读取 `{{FEATURE_CLASSIFICATION}}`，runner 预处理的 feature class 和 verifier adjustment，用于判定不适用 family；该文件不是 oracle 实现源码。
9. 写 `{{REPLAY_ROOT}}\EXPLORATION_REPORT.md`。
10. 写 `{{REPLAY_ROOT}}\ROUND_CONTRACT.md`。
11. 写 `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`。
12. 写 `{{REPLAY_ROOT}}\PHASE0_RESULT.md`。

Phase 0 shell command whitelist：
- 只允许执行只读发现命令：`rg`、`Get-Content`、`Select-String`、`Get-ChildItem`、`Test-Path`。
- 源码路径参数只能指向 `{{WORKTREE}}`，产物路径只能指向上面列出的 `{{REPLAY_ROOT}}` 文件。
- 禁止运行任何包含 `mvn`、`mvn.cmd`、`maven`、`gradle`、`compile`、`test-compile`、`surefire`、`failsafe`、`install`、`deploy` 的命令。
- 禁止运行任何包含 protected/original project root、受保护主仓库、或 `{{WORKTREE}}` 之外 `pom.xml` 路径的命令；Phase 0 不需要也不允许验证 Maven 编译。

`phase0_family_contract_strict_json`：`FAMILY_CONTRACT.json` 必须是严格 JSON，禁止 Markdown fence、注释、尾随逗号、缺逗号、单引号、未转义换行或解释性文字。写完后必须自行确认它能被标准 JSON parser 读取；不能把“看起来像 JSON”的片段当作完成产物。

【Feature Classification 校准规则】
读取 `{{FEATURE_CLASSIFICATION}}`。如果 classification 为 `narrow_backend_read_only_fix` 或 `base_classification=narrow_backend_fix` 且 `read_only=true`：
- `stateful_side_effect`、schema、前端、配置、生成物、外部集成、生命周期清理 family 默认不适用，除非 requirement_source 正向要求写入、状态流转、迁移、外部调用或 UI/config 改动。
- 水平切片最低要求是 Backend + Test 两类，不强制 Frontend/Database。
- RED phase 可写成 `GREEN-only accepted because baseline already contains or replay worktree already applies the minimal fix`，但必须补结构化行为证据和可执行 GREEN 命令。
- `FAMILY_CONTRACT.json` 中不适用 family 必须写 `required:false`、`planned_slice:"not_required"`，并在 blocker/cap 字段说明 `feature_classifier_not_applicable`。

Phase 0 禁止：
- 禁止直接读取 oracle branch/commit 或运行 `git diff`/`git log`/`git show` 访问 oracle commit（只允许读取 `{{ORACLE_DIFF_ANALYSIS}}` 中 runner 预处理的结构化分析）。禁止读取历史实现、旧 replay、历史会话总结、FINAL_REPLAY_REPORT。
- 禁止读取 requirement_source 所在快照以外的 feature 文档目录；不要对 `.doc\<feature>` 或原始需求父目录执行 `rg` / `Get-ChildItem` / 批量读取。若需要需求事实，只读本 prompt 给出的 `requirement_source` 单文件快照。
- 禁止修改生产代码、测试代码、配置、SQL、前端文件。
- 禁止跑 Maven/测试/构建。
- 禁止用 supporting slice 作为第一刀。
- 禁止把 `BASELINE_INDEX.md` 当成结论来源；它不能替代真实入口发现、候选入口比较、side-effect ledger 或 exact contract ledger。
- 禁止把 `SURFACE_CARRIER_SCAN.md` 当成结论来源；它只能提示“优先检查哪些已有生产承载点”，不能证明需求已覆盖。
- 如果 `BASELINE_INDEX.md` 包含 selected entry、上一轮 gap、oracle 信息、旧 replay 分数或实现建议，必须标记 `context_contamination_risk` 并忽略该文件。
- 禁止把 `.doc\example-system-context` 里的通用系统说明当成当前 feature 的 oracle；若它与 requirement_source 或代码事实冲突，以 requirement_source 和当前代码为准，并在 `EXPLORATION_REPORT.md` 披露冲突。

【Blind Replay Oracle Boundary 硬要求】
`{{ORACLE_DIFF_ANALYSIS}}` 只是 runner 预处理的结构化元数据，用于提示高权重文件族和 surface 优先级；它不是 oracle 实现源码，也不是 Phase 0 的签名/DDL/schema 权威来源。

Phase 0 必须保持可执行 blind replay：
- 禁止因为“无法确认 oracle 方法签名 / oracle DDL / oracle JSON schema / oracle 具体实现”写 `phase0_status: BLOCKED`。
- 禁止写“等待 Oracle 验证”“用户放弃 coverage cap 后再实现”“提供 oracle branch 后再继续”等人工等待型结论。
- 如果当前 worktree 已有可搜索的真实入口、相似实现或最近可执行边界，必须基于 requirement_source + 当前代码事实继续写 `PROCEED`，把不确定性放入 `Uncertainty Ledger`、`required_flags` 和 coverage cap。
- 只有当 requirement_source 与当前代码表面都无法找到任何真实入口、最近可执行边界或可验证第一刀时，才允许 `BLOCKED`。
- `selected_real_entry` 必须来自当前 baseline worktree 或中性 surface scan 的候选，并经源码/搜索证据确认实际存在；不能写 “inferred from Oracle diff”。
- 如果搜索证据显示某候选 `not found in baseline`、`oracle addition`、`oracle new service` 或 `NEW`，它不能成为 `selected_real_entry`。这类候选只能写入 planned/new carrier、uncertainty、family cap 或 implementation candidate。
- `Selected Real Entry`、`Key Decisions`、`Next Actions`、`required_flags` 中禁止使用 oracle additions、oracle line count、oracle new service、oracle metadata、oracle evidence、oracle high-weight file 作为实现事实或入口授权。
- 禁止在 Phase 0 产物中写 Oracle Post-Hoc、oracle verification pending、oracle commit pending、pending fetch、waiting for oracle、verify after oracle 等把后验阶段前置的语句；这些会被 verifier 视为 `phase0_manual_oracle_wait`。

【必须产出 EXPLORATION_REPORT.md】
`EXPLORATION_REPORT.md` 必须包含以下精确章节标题（逐字照写 `##` 标题，禁止只写表格列名、禁止改写成近义词、禁止合并章节）。机器校验脚本会逐标题匹配，缺失任何标题将导致 Phase0 验证失败：

- `## Source Boundary`
- `## Requirement Literal Inventory`
- `## Selected Real Entry`
- `## Domain Fact Sheet`
- `## Candidate Surface Map`
- `## Schema and Exact Contract Discovery Ledger`
- `## Uncertainty Ledger`
- `## Planning Input Summary`

每个章节内容要求：
- Source Boundary：requirement、repo rules、system context、baseline index、code surface、forbidden sources
- Requirement Literal Inventory：需求中的每个关键字面量（字段、枚举值、状态码、文案）逐条列出
- Selected Real Entry：真实生产入口的类名+方法签名（见下方硬要求）
- Domain Fact Sheet：业务词、字段、表/服务/入口的代码事实
- Candidate Surface Map：core path、supporting surfaces、deploy-facing surfaces
- Schema and Exact Contract Discovery Ledger：schema / method signature / enum / field / payload 的当前代码发现证据、缺口、cap 和可执行下一刀
- Uncertainty Ledger：confirmed / inferred / blocked
- Planning Input Summary：给下一阶段 plan tournament 使用的事实，不得包含 oracle 或旧 replay 结论

【必须产出 ROUND_CONTRACT.md】
`ROUND_CONTRACT.md` 必须包含：
- source_of_truth 分类
- forbidden_sources
- requirement coverage ledger
- 8-Gate Compliance Ledger
- Expected Diff Matrix
- Behavior Test Charter
- Real Entry Discovery Matrix
- Critical Surface Allocation Plan
- Requirement Family Ledger：core entry、stateful side effect、deploy-facing page/export、wire/API contract、configurable policy/threshold、generated artifact/template/upload、external integration、automation/test interface、lifecycle cleanup/retention，每个 family 标 required/weight/first executable slice/blocker/cap
- core_path first executable slice
- supporting_surface executable slices
- exact contract ledger
- side-effect ledger
- feedback loop plan
- coverage cap rules

以上章节标题是机器校验契约，不能改名、合并或只写近义标题。尤其必须逐字写出：

```markdown
## Critical Surface Allocation Plan

| Surface / family | Why required | First executable slice | Carrier / entry | Proof required | Deferred blocker / coverage cap |
| --- | --- | --- | --- | --- | --- |
```

如果某个 surface 暂缓，仍要在这个表中写 `deferred + blocker/cap`；不能只在 `Supporting Surface Executable Slices`、`Requirement Family Ledger` 或风险段落里描述。

【Real Entry Discovery Matrix 硬要求】
必须写成：

`requirement event/literal -> candidate production entries -> evidence from code -> rejected entries with reason -> selected real entry -> first RED test`

规则：
- 至少比较 2 个候选真实入口；如果只找到 1 个，必须记录搜索关键词、路径范围和为什么没有第二候选。
- selected real entry 必须是 processor/controller/facade/worker/exporter/mapper/scheduler 等真实生产入口或其最近可执行边界。
- 第一条 executable slice 必须从 selected real entry 触发业务行为。
- DTO/entity/mapper/config/log/OCR/report/export/helper/static guard 都不能作为第一刀，除非它们本身就是该需求的最高权重真实入口。
- **selected_real_entry 必须写 baseline worktree 中已存在的真实生产类名+方法签名**（如 `ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)`）。机器校验脚本会逐字匹配，以下占位词全部禁止：`待确认`、`待 Oracle 对比确认`、`TBD`、`unknown`、`N/A`、`后续确认`、`placeholder`、`未确认`。如果无法从当前代码中找到真实入口，`phase0_status` 必须写 `BLOCKED` 并在 `required_flags` 写 `real_entry_gap`，不能写 `PROCEED`。
- 新服务、新 Controller、新 Facade 或 oracle 新增类可以是实现计划里的 `planned_new_carrier`，但不能代替 Phase 0 的 `selected_real_entry`。第一刀应绑定到最近的既有生产入口或可执行边界，再由该入口驱动新增 carrier。

【Minimum Stateful Core Slice 硬要求】
如果需求涉及状态流转、落库、任务、进度、日志、事务、生成物、导出或外部 payload，Phase 0 的 first executable slice 不能只证明“入口被调用”或“终端日志/flag 出现”。必须在 ROUND_CONTRACT.md 写出最小可交付核心闭环：

`selected real entry -> orchestration -> persistence/query/write -> state/task/progress/log side effects -> failure isolation -> executable proof`

缺任一高权重副作用时，必须写明该副作用的首个可执行验证点和 coverage cap；不能把它归入可选 follow-up。

【Exact Contract Naming 硬要求】
业务术语、字段、列名、flag、enum、payload type、展示列不允许自由翻译。编码前必须先搜索 requirement_source 与当前代码中的既有命名证据，并在 exact contract ledger 写：

`business literal -> candidate symbol/wire/db/display names -> selected name -> evidence -> assertion`

如果只能推断命名，必须标 `exact_contract_gap` 风险，并在 coverage cap rules 中降权。

【Schema / Exact Contract Discovery Ledger 硬要求】
当需求涉及新表、旧表写入、DTO/API payload、状态枚举、任务/进度/日志、导出列、模板字段、外部回调或任何 exact contract 时，Phase 0 不能只写“schema 不确定 / exact contract 不确定”。必须在 `EXPLORATION_REPORT.md` 写精确标题：

`## Schema and Exact Contract Discovery Ledger`

该章节至少包含以下列或等价 `key: value` 行：

`contract item -> current code search command -> discovered source/file/symbol -> confirmed/inferred/blocked -> affected family -> coverage cap -> next executable proof`

规则：
- 先搜索当前 worktree 的实体、Mapper XML、SQL、DTO、Facade/Controller/Service 方法签名、枚举/常量、模板/JS/JSP/导出列，再下结论。
- `exact_contract_gap`、`schema_verification_gap`、`interface_contract_gap`、`new_table_structure_gap` 只能降低对应 family 的 cap 或拆出 `exact_contract_discovery_slice`，不能在已有真实入口和第一刀时阻塞整个 replay。
- 若一个 family 因新表/新 schema 完全不可实现，只把该 family 标 `deferred + coverage_cap_if_open: 0`；其余可执行 core/stateful/deploy surface 必须继续进入 Phase 1。
- `PHASE0_RESULT.md` 禁止把 `AWAIT_ORACLE_VERIFICATION_OR_WAIVER`、`Provide oracle branch access`、`Coverage Cap Waiver`、`awaiting oracle/schema verification` 作为下一步；正确写法是 `next_action: PROCEED_WITH_CAPS_AND_DISCOVERY_SLICE`。
- 如果 schema/exact 发现仍不足，第一刀应选择能提升 verification-capped coverage 的最小真实行为；第二刀或后续刀再补 exact/schema discovery，不得让 coverage cap 反复为 0。

【Deploy-Facing Surface Budget 硬要求】
凡需求显式出现页面、报表、导出、模板、图片/附件、OCR、自动化测试接口、外部 payload、任务/调度等 deploy-facing surface，Critical Surface Allocation Plan 至少要为每个高权重 surface 写一个 executable first slice 或 `deferred + blocker/cap`。static-only/file-presence-only 不能算 surface DONE。

【Slice Budget Reservation 硬要求】
Phase 0 必须把 Critical Surface Allocation Plan 转成可执行 slice 预算，而不是只列风险：
- `S1` 默认给最高权重真实入口/core path。
- `S2` 默认给最小 stateful side-effect success path。
- 从 `S3` 开始，若仍存在高权重 deploy-facing surface 没有 executable first slice，必须至少预留 1 个 `deploy_surface_first_slice`，且优先级高于继续深化同一 core/service 文件族。
- 不允许把全部 slice 预算分配给同一概念族（例如只做 core service/log tests）后再把 deploy-facing surface 记为 follow-up。
- 如果需求中高权重 deploy-facing surface 多于剩余 slice 数，必须写 `deferred + blocker/cap` 并说明 coverage cap；不得在 blind 自评分中把这些 surface 当作已覆盖。
- 若无法在预算内安排任何 deploy-facing executable slice，`PHASE0_RESULT.md` 必须带 `surface_budget_gap`。

【Requirement Family Ledger 硬要求】
Phase 0 必须把需求拆成跨项目通用 family，不允许只写业务功能点：
- `core_entry`
- `stateful_side_effect`
- `deploy_export_page`
- `wire_payload_api_contract`
- `config_policy_threshold`
- `generated_artifact_template_upload`
- `external_integration`
- `automation_test_interface`
- `lifecycle_cleanup_retention`

每个 detected family 必须写：
`family -> requirement evidence -> weight -> first executable carrier -> planned slice -> blocked/cap`

如果 detected family 没有 planned slice，必须在 `PHASE0_RESULT.md` 加 `family_budget_gap`，并在 coverage cap rules 中降权。

【Production Carrier Preference 硬要求】
规划 first executable carrier 时，默认优先选择 `{{SURFACE_CARRIER_SCAN}}` 中已有生产承载点，并用源码读取确认它确实处在业务链路上。

禁止把新建 helper/service/DTO/test-only 文件作为 family 的首个可关闭承载点，除非同时满足：
- 它被已有 processor/controller/facade/mapper/worker 真实入口调用；
- 至少一个已有生产承载点也在同一 slice 中被修改或验证；
- `FAMILY_CONTRACT.json.proof_required` 明确包含该入口到输出/副作用的可执行断言。

【Source-of-Truth Search Gate 硬要求 (v263)】
在规划阶段必须为以下维度提供显式搜索证据，不能用假设或推测替代：

1. **相似实现搜索**：对需求的每个关键行为（MQ发送、推送、回调、通知、状态变更、任务流转、资料生成），必须先 `rg` 搜索项目中已有的类似实现，并记录搜索命令、搜索结果数量和候选类名。禁止只搜索 DTO/枚举/常量就当作"找到了实现"。

2. **Facade 方向搜索**：当需求涉及回调/推送/发送/通知/接收时，必须搜索 **两个方向** 的 Facade（如 `rg -i "Receive.*Facade|Push.*Facade|Send.*Facade|Notify.*Facade"`），在 `EXPLORATION_REPORT.md` 的 `Selected Real Entry` 章节记录每个方向的搜索结果、候选类名和方法签名，并给出选择理由。只搜索了单方向的，`phase0_status` 不能写 `PROCEED`。

3. **行为承载点 vs 数据承载点**：当需求涉及行为（MQ/push/send/callback/notify/event）时，不能选择 enum/DTO/constant 作为核心承载点。`Selected Real Entry` 必须指向实际执行行为的生产类（Service/Handler/Listener/Consumer/Producer/Facade），不能是定义数据的类。

4. **方法签名与返回类型搜索**：对每个候选 Facade/Service，必须用 `rg` 确认方法签名和返回类型，不能假设参数类型或返回值。如果需求说"回调通知"，必须区分"发起回调"和"接收回调"对应的不同 Facade 方法。

搜索证据必须写在 `EXPLORATION_REPORT.md` 中，格式：
```
搜索: rg -i "关键词" --include "*.java" 路径范围
结果: N 个匹配
候选: 类名1.方法签名1, 类名2.方法签名2
选择: 类名X.方法签名X
理由: ...
排除: 类名Y.方法签名Y (原因: ...)
```

同一批搜索证据也必须摘要写入 `PHASE0_RESULT.md` 的独立章节 `## Search Commands Used`，否则 runner 会在 Phase0 carrier evidence gate 直接停止。最低格式：

## Search Commands Used

rg -n "关键词1" {{WORKTREE}}\<candidate-core-module> {{WORKTREE}}\<candidate-test-module> {{WORKTREE}}\<candidate-web-module>
rg -n "关键词2" {{WORKTREE}}\<candidate-api-module> {{WORKTREE}}\<candidate-domain-module> {{WORKTREE}}\<candidate-provider-module>
rg -n "classOrMethodName" {{WORKTREE}} --glob "*.java"

- result_summary: 每条命令的命中数量、候选类/方法、选择/排除理由

Hard Gate:
- `PHASE0_RESULT.md` 中没有逐字标题 `## Search Commands Used` = `BLOCKED`
- 该章节没有 `rg ` 命令 = `BLOCKED`
- 声称某 carrier 存在但没有对应 `rg` 命令与结果摘要 = `BLOCKED`

【Trigger Point Validation (v447 Experiment 1)】

当需求涉及 AI 任务触发时（如"XX成功后"模式），必须验证选中的 carrier 与触发点匹配：

1. **提取触发点模式**：从 requirement_text 中提取"XX成功后"模式：
   - "AI处理结果获取成功后" → Apply Claim task（ExampleApplyTaskProcessor）
   - "金额计算成功后" → Calculate Loss task（ExampleCalculateTaskProcessor）

2. **验证 carrier 匹配**：
   - Calculate Loss task（ExampleCalculateTaskProcessor）仅计算金额，不触发 auto-flow
   - Apply Claim task（ExampleApplyTaskProcessor）是综合 AI 接口，在结果保存后触发 auto-flow
   - 如果触发点说"AI处理结果获取成功后"但选了 Calculate Loss processor，这是错误的 carrier 选择

3. **在 EXPLORATION_REPORT.md 记录**：
   在 `Selected Real Entry` 章节必须增加：
   - `trigger_point_pattern: <提取的触发点模式，如 AI处理结果获取成功后>`
   - `expected_processor: <映射的处理器类型>`
   - `processor_match_validation: PASS | FAIL`

4. **验证命令**（可选但推荐）：
   ```bash
   python scripts/trigger_point_validator.py validate "<requirement_text_snippet>" "<selected_carrier>"
   ```

**关键区分**：
- `ExampleCalculateTaskProcessor`：仅计算损失金额，不是 auto-flow 触发点
- `ExampleApplyTaskProcessor`：综合 AI 接口，结果保存后触发 auto-flow，是正确的 auto-flow 入口

如果验证失败（触发点与 carrier 不匹配），`phase0_status` 必须写 `INVALID_PLAN`，`required_flags` 加 `wrong_test_surface`。

【Interface Contract Extraction (MANDATORY for external/public entries)】
如果 `Selected Real Entry` 是 Facade/Controller/API/Endpoint/Route 等外部或公共入口，或需求涉及 RPC 回调/推送/通知/外部集成，Phase 0 必须显式提取以下接口契约：

1. **Return Type**：入口方法的返回类型（如 `SomeResponse`、`void`、`ResultModel`）。禁止假设 `void`。必须从源码 `rg` 确认方法签名中声明的返回类型。如果源码中该入口尚未声明（新接口），从 `SURFACE_CARRIER_SCAN.md` 或同方向已有 Facade 方法推断，并在 Uncertainty Ledger 标记 `interface_contract_inferred`。

2. **Error Handling Pattern**：入口的错误报告方式。对外部 RPC 回调/推送/通知/接收，默认假设 response-code + structured error object 模式（如 `result.setCode("500"); result.setMsg(msg); return result;`），而不是 exception-throwing 模式。只有当源码证据明确显示同方向 Facade 使用 exception propagation 时才允许用 exception 模式。

3. **Similar Implementation Evidence**：用 `rg` 搜索项目中已有同方向 Facade/Controller 入口的返回类型和错误处理方式。记录搜索命令、候选方法签名。格式同 Source-of-Truth Search Gate 搜索证据格式。

在 `EXPLORATION_REPORT.md` 的 `Selected Real Entry` 章节，必须在 `selected_real_entry` 后增加以下 `key: value` 行：
- `interface_contract_return_type: (具体类型，禁止 TBD/unknown/N/A/placeholder/待确认)`
- `interface_contract_error_handling: (response_codes / exception_propagation，禁止占位词)`
- `interface_contract_similarity_evidence: (搜索命令+候选签名)`

如果 requirement source 未指定返回类型且无法从源码推断：
- `interface_contract_return_type` 必须写 `CONTRACT_INFERRED_FROM_SIMILAR` 并附搜索证据
- 若完全无法推断，`phase0_status` 必须写 `BLOCKED`，`required_flags` 加 `interface_contract_gap`

【FAMILY_CONTRACT.json 硬要求】
除 Markdown 合约外，必须写机器可检查的 `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`，不能只写自然语言。JSON 必须至少包含：

```json
{
  "schema_version": 1,
  "source_boundary": {},
  "selected_real_entry": "",
  "first_executable_slice": "",
  "families": [
    {
      "id": "core_entry",
      "required": true,
      "weight": 100,
      "first_executable_carrier": "",
      "planned_slice": "S1",
      "proof_required": [],
      "forbidden_proof": ["helper_only", "static_only", "mock_only"],
      "coverage_cap_if_open": 60
    }
  ]
}
```

每个 detected family 必须出现在 `families` 中。若某 family 无法执行，`planned_slice` 可为空，但必须写 `blocker` 和 `coverage_cap_if_open`。禁止把 placeholder、file-presence、DTO/entity/constant existence、mock-only test 写成可关闭 family 的 proof。

**FAMILY_CONTRACT.json 的 `selected_real_entry` 必须写 baseline worktree 已存在的真实生产类名或方法签名；每个 family 的 `first_executable_carrier` 也必须写真实生产类名或方法签名，禁止写占位词**（待确认、TBD、unknown、N/A、placeholder）。如果某 family 需要新增 carrier，必须显式写 `carrier_status: NEW`、`planned_new_carrier` 或 blocker/cap；不能把 NEW/oracle-added carrier 写成 top-level `selected_real_entry`。如果无法找到真实 carrier，`blocker` 字段必须写明证据缺口，`coverage_cap_if_open` 必须设为 0。

【Oracle Structural Alignment (Allowed Metadata Only)】

在完成 EXPLORATION_REPORT.md 之前，你 MUST 完成 oracle 结构对齐，但只能使用 `{{ORACLE_DIFF_ANALYSIS}}` 中的文件名、layer、weight、line count 等 runner 预处理元数据：

1. 读取 `{{ORACLE_DIFF_ANALYSIS}}`。
2. 列出 ALL oracle-changed production files（非 test 文件）及 line counts。
3. 对每个 oracle production file，识别其 layer（DTO/Enum/Service/Mapper/Controller/Resource）。
4. 按 business weight 分组 oracle files：
   - HIGH: Service/Controller 层有业务逻辑的文件
   - MEDIUM: Enum、Config、Mapper、Resource
   - LOW: DTO、VO、Test
5. 把 oracle HIGH-weight files 纳入 Candidate Surface Map 和 Critical Surface Allocation Plan 的优先级参考。
6. 在 EXPLORATION_REPORT.md 的 Planning Input Summary 章节增加 `Oracle Alignment` 子节，列出：
   - oracle production files 总数
   - HIGH-weight files 列表
   - 候选 carrier 与 oracle HIGH-weight files 的初步对齐情况
7. 在 ROUND_CONTRACT.md 的 Requirement Family Ledger 中，将 oracle HIGH-weight files 对应的 family 标注 `oracle_high_weight: true`。

禁止从 oracle metadata 推断或等待确认方法体、接口签名、DDL、JSON schema、测试断言或业务实现细节。若这些细节在当前代码中不存在或只能推断，把它们写入 `Uncertainty Ledger` / `required_flags` / coverage cap，不得因此要求用户提供 oracle 或等待 oracle 后验。

`Oracle Alignment` 只能记录结构优先级和 family cap，不得给 `selected_real_entry`、方法签名、DDL、JSON schema、测试断言、服务新建或实现步骤背书。不要写 “oracle additions / oracle new service / oracle evidence proves selected entry” 这类句子。

如果 `{{ORACLE_DIFF_ANALYSIS}}` 不存在或为空，在 PHASE0_RESULT.md 的 `required_flags` 加 `oracle_analysis_skipped`，但不能仅因此 `BLOCKED`。

【IMPLEMENTATION_CONTRACT.md 硬要求 (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)】

在完成 EXPLORATION_REPORT.md 和 ROUND_CONTRACT.md 后，必须创建 `IMPLEMENTATION_CONTRACT.md`，包含以下精确字段：

```markdown
# Implementation Contract

## Carrier
- carrier_class: (完整类名，禁止 TBD/unknown/待确认)
- carrier_status: EXISTING | NEW
- reason_for_new: (仅当 carrier_status=NEW 时填写)

## Method Signature
- method_signature: (完整方法签名，包括参数类型)
- parameter_types: (参数类型列表，精确到 DTO vs Entity)
- return_type: (返回类型，禁止假设 void)

## Call Path
- called_by: (调用者类名.方法名)
- trigger_event: (触发事件名称)
- trace: (调用链路: 入口A -> 入口B -> 目标carrier)
```

**v438 禁止字段**：`IMPLEMENTATION_CONTRACT.md` 中禁止包含以下 oracle-wait 字段和语句：
- 禁止 `verification_path: Oracle post-hoc after implementation`
- 禁止 `cap_reason: Cannot verify ... without oracle access`
- 禁止 `mitigation: verify during oracle post-hoc`
- 禁止 `not verified against oracle`
- 禁止任何形式的 "waiting for oracle", "awaiting oracle", "oracle verification pending"

如需描述盲打约束，使用以下替代表述：
- 用 "Blind replay constraint: ...; coverage cap applied" 替代 "without oracle access"
- 用 "signature verification deferred to oracle post-hoc" 替代 "Oracle post-hoc after implementation"
- 用 "verified against requirement with coverage cap" 替代 "not verified against oracle"

**验证规则**（runner 将自动检查）：
1. `IMPLEMENTATION_CONTRACT.md` 必须存在
2. `carrier_class` 必须是完整类名（如 `com.example.core.service.XxxService`）
3. 如果 `carrier_status=EXISTING`，runner 将验证该类在 baseline worktree 中存在
4. `method_signature` 必须包含完整参数类型，不能使用 `Object` 或模糊类型
5. `return_type` 不能假设为 `void`，必须从源码确认或写 `INFERRED`
6. v438: 文件中不得包含 oracle-wait 语言模式

**如果验证失败**：
- `phase0_status` 必须写 `BLOCKED`
- `required_flags` 加 `implementation_contract_validation_failed`
- 不能进入 Phase 1

**验证命令**（runner 将执行）：
```bash
python scripts/plan_contract_verify.py \
    PLAN_RESULT.json \
    ORACLE_FILES.json \
    strict-blind \
    {{WORKTREE}} \
    --enable_carrier_verify \
    --enable_exact_contract_verify
```

**EXPERIMENT 1: Pre-Implementation Contract Verification Gate**

此门禁的目标：在 Phase 0.5（plan 选择后）验证：
1. 选择的 carrier 真实存在于代码库
2. 方法签名与实际代码匹配
3. 参数类型精确（不是 "Object" 占位符）
4. 返回类型已确认
5. v438: IMPLEMENTATION_CONTRACT.md 不包含 oracle-wait 语言

如果 carrier 声称 `EXISTING` 但在 baseline 中找不到，或签名不匹配，plan 将被拒绝。

---

【Oracle Entry Point Guidance (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)】

如果 ORACLE_ENTRY_HINT.md 在 replay root 中存在，该文件包含正确的入口点签名。

**使用规则**：
- 读取 `{{REPLAY_ROOT}}/ORACLE_ENTRY_HINT.md`（如果存在）
- hint 包含正确的入口点类名和方法签名
- 使用 hint 验证你的 carrier 选择
- **你选择的 carrier 必须与 hint 匹配**

**触发点模式映射**：
- "AI处理结果获取成功后" → Apply Claim task（ExampleApplyTaskProcessor）
- "金额计算成功后" → Calculate Loss task（ExampleCalculateTaskProcessor）

**关键区分**：
- `ExampleCalculateTaskProcessor`：仅计算损失金额，不是 auto-flow 触发点
- `ExampleApplyTaskProcessor`：综合 AI 接口，结果保存后触发 auto-flow，是正确的 auto-flow 入口

**在 EXPLORATION_REPORT.md 的 Selected Real Entry 章节必须记录**：
- `oracle_entry_hint_available: true/false`
- `oracle_entry_hint_content: <hint 内容摘要>`
- `carrier_match_validation: <selected carrier 是否与 hint 匹配>`

如果 hint 存在但你选择的 carrier 不匹配，`phase0_status` 必须写 `INVALID_PLAN`，`required_flags` 加 `wrong_test_surface`。

---

【Test Surface Mapping (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)】

在完成 EXPLORATION_REPORT.md 和 ROUND_CONTRACT.md 后，必须在 PHASE0_RESULT.md 中增加 test_surface_mapping 字段：

```markdown
## Test Surface Mapping

对于每个 NEW_SERVICE carrier，必须确定测试表面（TEST SURFACE）：

1. 如果新服务将从现有 Facade 调用：
   - test_surface_carrier: ExistingFacadeName
   - test_surface_layer: Facade
   - rationale: "New service will be invoked from this existing Facade"

2. 如果新服务需要新的 Facade：
   - test_surface_carrier: NEW: NewServiceFacade
   - test_surface_layer: Facade
   - rationale: "No existing Facade provides this function; new Facade required"

3. 仅用于纯内部服务（无外部接口）：
   - test_surface_carrier: SERVICE_LAYER_ONLY: NewServiceName
   - test_surface_layer: Service
   - rationale: "Justification for Service layer testing"

输出 JSON 格式：
```json
"test_surface_mapping": {
  "ExampleFlowService": {
    "test_surface_carrier": "ExampleFacade",
    "test_surface_layer": "Facade",
    "rationale": "Auto-flow will be invoked from existing ExampleFacade"
  }
}
```
```

【Phase 0 判定】
在 `PHASE0_RESULT.md` 写：

```markdown
# Phase 0 Result

- phase0_status: PROCEED | INVALID_PLAN | BLOCKED
- selected_core_path:
- selected_real_entry:
- first_executable_slice:
- family_contract: {{REPLAY_ROOT}}\FAMILY_CONTRACT.json
- test_surface_mapping: {{REPLAY_ROOT}}\test_surface_mapping.json
- first_slice_type: core_path | supporting_surface | helper_static | unknown
- invalid_reason:
- required_flags:
- exploration_report: {{REPLAY_ROOT}}\EXPLORATION_REPORT.md
- implementation_contract: {{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md
- next_action:
```

紧跟上述机器字段后，必须写独立章节：

## Search Commands Used

rg ...
rg ...
rg ...

- result_summary: ...

`phase0_status` 只能逐字写 `PROCEED`、`INVALID_PLAN` 或 `BLOCKED`。禁止自造状态值（custom status values），如 `PROCEED_WITH_*`、`PROCEED_WITH_CAVEATS`、`PROCEED_WITH_ORACLE_VERIFICATION`、`PARTIAL_PROCEED`、`READY`、`PASS`。如果有 caveat，把 caveat 写入 `required_flags`，但状态本身仍必须是三选一。

判定规则：
- `PROCEED`：第一刀是 core_path，且真实入口、首个 RED 测试、side-effect ledger、deploy-facing follow-up 都已明确。
- `INVALID_PLAN`：第一刀是 supporting_surface/helper/static-only，或真实入口证据不足，或没有首个真实入口 RED。
- `BLOCKED`：需求/代码表面不足以判断真实入口，且不能安全选择第一刀。
- 以下原因不能作为 `BLOCKED`：`cannot verify exact oracle method signatures`、`cannot verify oracle DDL`、`cannot verify oracle JSON schema`、`awaiting oracle verification`、`user must waive coverage caps`、`schema_verification_gap`、`exact_contract_gap`、`interface_contract_gap`、`new_table_structure_gap`。这些只能作为 discovery ledger / uncertainty / family cap，不是 Phase 0 停线理由。
- 如果已经找到 `selected_real_entry` 和 `first_executable_slice`，`phase0_status` 必须是 `PROCEED` 或 `INVALID_PLAN`，不得因为 schema/exact/oracle 不确定写 `BLOCKED`。

如果 `INVALID_PLAN`，必须在 `required_flags` 至少写入一个：
- `real_entry_gap`
- `core_entry_unclosed`
- `surface_budget_gap`
- `helper_only_surface_gap`
- `wrong_test_surface`
- `interface_contract_gap`

开始执行 Phase 0。只写上述两个 Markdown 产物。
