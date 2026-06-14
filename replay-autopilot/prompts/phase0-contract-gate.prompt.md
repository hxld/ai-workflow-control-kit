You are now executing Phase 0 Contract Gate. Plan-only validation, do not write production code, test code, or run Maven.

【Fixed Context】
- Main repository: {{PROJECT_ROOT}}
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
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}

## Phase 0 Goal
First complete high-quality exploration and first slice feasibility assessment, the goal is to provide a factual baseline for subsequent planning stages, not to code directly.

Phase 0 only allows:
1. Read requirement_source.
2. Read repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml.
3. Read isolated worktree current code.
4. Read `{{BASELINE_INDEX}}`, but only as a neutral structural index.
5. Read `{{SURFACE_CARRIER_SCAN}}`, but only as a neutral list of production carrier candidates, cannot replace `rg`/source code confirmation.
6. Read `{{CONTEXT_MANIFEST}}` and the `{{SYSTEM_CONTEXT_DIR}}` read-only context files listed in it; they can only be used as general project background, cannot replace requirements and code facts.
7. Read `{{ORACLE_DIFF_ANALYSIS}}`, structured analysis of oracle commit diff (file list, layer classification, weight), used to constrain carrier selection and oracle alignment during the exploration phase.
8. Write `{{REPLAY_ROOT}}\EXPLORATION_REPORT.md`.
9. Write `{{REPLAY_ROOT}}\ROUND_CONTRACT.md`.
10. Write `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`.
11. Write `{{REPLAY_ROOT}}\PHASE0_RESULT.md`.

`phase0_family_contract_strict_json`: `FAMILY_CONTRACT.json` must be strict JSON, forbidden to use Markdown fence, comments, trailing commas, missing commas, single quotes, unescaped newlines, or explanatory text. After writing, must confirm it can be read by a standard JSON parser; cannot treat “looks like JSON” fragments as completed output.

Phase 0 forbidden:
- Forbidden to directly read oracle branch/commit or run `git diff`/`git log`/`git show` to access oracle commit (only allowed to read the preprocessed structured analysis in `{{ORACLE_DIFF_ANALYSIS}}`). Forbidden to read historical implementations, old replays, historical session summaries, FINAL_REPLAY_REPORT.
- Forbidden to read feature documentation directories outside the snapshot where requirement_source is located; do not run `rg` / `Get-ChildItem` / batch reads on `.doc\<feature>` or original requirement parent directories. If requirement facts are needed, only read the `requirement_source` single-file snapshot given in this prompt.
- Forbidden to modify production code, test code, configuration, SQL, frontend files.
- Forbidden to run Maven/tests/builds.
- Forbidden to use supporting slice as the first slice.
- Forbidden to treat `BASELINE_INDEX.md` as a conclusion source; it cannot replace real entry discovery, candidate entry comparison, side-effect ledger, or exact contract ledger.
- Forbidden to treat `SURFACE_CARRIER_SCAN.md` as a conclusion source; it can only suggest “which existing production carriers to check first”, cannot prove requirements are covered.
- If `BASELINE_INDEX.md` contains selected entry, previous round gap, oracle information, old replay scores, or implementation suggestions, must mark `context_contamination_risk` and ignore the file.
- Forbidden to treat generic system descriptions in `.doc\example-system-context` as the oracle for the current feature; if it conflicts with requirement_source or code facts, rely on requirement_source and current code, and disclose the conflict in `EXPLORATION_REPORT.md`.

【Blind Replay Oracle Boundary Hard Requirement】
`{{ORACLE_DIFF_ANALYSIS}}` is only runner-preprocessed structured metadata, used to hint at high-weight file families and surface priorities; it is not oracle implementation source code, nor is it the authoritative source for Phase 0 signatures/DDL/schema.

Phase 0 must maintain executable blind replay:
- Forbidden to write `phase0_status: BLOCKED` because of “cannot confirm oracle method signature / oracle DDL / oracle JSON schema / oracle specific implementation”.
- Forbidden to write human-waiting conclusions like “waiting for Oracle verification”, “implement after user waives coverage cap”, “continue after oracle branch is provided”.
- If the current worktree has searchable real entries, similar implementations, or recent executable boundaries, must continue writing `PROCEED` based on requirement_source + current code facts, putting uncertainty into `Uncertainty Ledger`, `required_flags`, and coverage cap.
- Only when neither requirement_source nor the current code surface can find any real entry, recent executable boundary, or verifiable first slice, is `BLOCKED` allowed.
- `selected_real_entry` must come from the current baseline worktree or neutral surface scan candidates, and be confirmed to actually exist via source code/search evidence; cannot write “inferred from Oracle diff”.
- If search evidence shows a candidate is `not found in baseline`, `oracle addition`, `oracle new service`, or `NEW`, it cannot become the `selected_real_entry`. Such candidates can only be written into planned/new carrier, uncertainty, family cap, or implementation candidate.
- Forbidden to use oracle additions, oracle line count, oracle new service, oracle metadata, oracle evidence, oracle high-weight file in `Selected Real Entry`, `Key Decisions`, `Next Actions`, `required_flags` as implementation facts or entry authorization.
- Forbidden to write Oracle Post-Hoc, oracle verification pending, oracle commit pending, pending fetch, waiting for oracle, verify after oracle, or other statements that front-load the post-hoc phase in Phase 0 outputs; these will be treated as `phase0_manual_oracle_wait` by the verifier.

【Must Output EXPLORATION_REPORT.md】
`EXPLORATION_REPORT.md` must contain the following exact section headings (copy verbatim `##` headings, forbidden to write only table column names, forbidden to rewrite with synonyms, forbidden to merge sections). The machine verification script will match headings one by one; missing any heading will cause Phase0 validation failure:

- `## Source Boundary`
- `## Requirement Literal Inventory`
- `## Selected Real Entry`
- `## Domain Fact Sheet`
- `## Candidate Surface Map`
- `## Schema and Exact Contract Discovery Ledger`
- `## Uncertainty Ledger`
- `## Planning Input Summary`

Each section content requirements:
- Source Boundary: requirement, repo rules, system context, baseline index, code surface, forbidden sources
- Requirement Literal Inventory: List each key literal in the requirement (fields, enum values, status codes, copy text) one by one
- Selected Real Entry: Real production entry class name + method signature (see hard requirement below)
- Domain Fact Sheet: Business terms, fields, code facts for tables/services/entries
- Candidate Surface Map: core path, supporting surfaces, deploy-facing surfaces
- Schema and Exact Contract Discovery Ledger: Current code discovery evidence, gaps, cap, and executable next slice for schema / method signature / enum / field / payload
- Uncertainty Ledger: confirmed / inferred / blocked
- Planning Input Summary: Facts for the next stage plan tournament to use; must not contain oracle or old replay conclusions

【Must Output ROUND_CONTRACT.md】
`ROUND_CONTRACT.md` must include:
- source_of_truth classification
- forbidden_sources
- requirement coverage ledger
- 8-Gate Compliance Ledger
- Expected Diff Matrix
- Behavior Test Charter
- Real Entry Discovery Matrix
- Critical Surface Allocation Plan
- Requirement Family Ledger：core entry、stateful side effect、deploy-facing page/export、wire/API contract、configurable policy/threshold、generated artifact/template/upload、external integration、automation/test interface、lifecycle cleanup/retention，each family marked with required/weight/first executable slice/blocker/cap
- core_path first executable slice
- supporting_surface executable slices
- exact contract ledger
- side-effect ledger
- feedback loop plan
- coverage cap rules

The above section titles are machine-verified contract, cannot rename, merge, or write only synonymous titles. In particular, must write verbatim:

```markdown
## Critical Surface Allocation Plan

| Surface / family | Why required | First executable slice | Carrier / entry | Proof required | Deferred blocker / coverage cap |
| --- | --- | --- | --- | --- | --- |
```

If a surface is deferred, still write `deferred + blocker/cap` in this table; cannot only describe it in `Supporting Surface Executable Slices`, `Requirement Family Ledger`, or a risk paragraph.

## Real Entry Discovery Matrix Hard Requirement
Must be written as:

`requirement event/literal -> candidate production entries -> evidence from code -> rejected entries with reason -> selected real entry -> first RED test`

Rules:
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

This section must contain at least the following columns or equivalent `key: value` lines:

`contract item -> current code search command -> discovered source/file/symbol -> confirmed/inferred/blocked -> affected family -> coverage cap -> next executable proof`

Rules:
- First search the current worktree's entities, Mapper XML, SQL, DTO, Facade/Controller/Service method signatures, enums/constants, templates/JS/JSP/export columns, then draw conclusions.
- `exact_contract_gap`, `schema_verification_gap`, `interface_contract_gap`, `new_table_structure_gap` can only reduce the corresponding family's cap or split out an `exact_contract_discovery_slice`, cannot block the entire replay when a real entry and first slice already exist.
- If a family is completely unimplementable due to new table/new schema, only mark that family as `deferred + coverage_cap_if_open: 0`; the remaining executable core/stateful/deploy surfaces must continue into Phase 1.
- `PHASE0_RESULT.md` must not use `AWAIT_ORACLE_VERIFICATION_OR_WAIVER`, `Provide oracle branch access`, `Coverage Cap Waiver`, `awaiting oracle/schema verification` as next steps; the correct form is `next_action: PROCEED_WITH_CAPS_AND_DISCOVERY_SLICE`.
- If schema/exact discovery is still insufficient, the first slice should choose the minimum real behavior that can improve verification-capped coverage; the second or subsequent slices can address exact/schema discovery, must not let coverage cap repeatedly be 0.

## Deploy-Facing Surface Budget Hard Requirement
For any deploy-facing surface explicitly appearing in the requirement (pages, reports, exports, templates, images/attachments, OCR, automated test interfaces, external payload, tasks/scheduling, etc.), the Critical Surface Allocation Plan must write at least one executable first slice or `deferred + blocker/cap` for each high-weight surface. Static-only/file-presence-only cannot count as surface DONE.

## Slice Budget Reservation Hard Requirement
Phase 0 must convert the Critical Surface Allocation Plan into executable slice budget, not just list risks:
- `S1` defaults to the highest weight real entry/core path.
- `S2` defaults to the minimum stateful side-effect success path.
- From `S3` onwards, if there are still high-weight deploy-facing surfaces without an executable first slice, must reserve at least 1 `deploy_surface_first_slice`, with priority higher than continuing to deepen the same core/service file family.
- Not allowed to allocate all slice budget to the same conceptual family (e.g., only doing core service/log tests) and then mark deploy-facing surfaces as follow-up.
- If the number of high-weight deploy-facing surfaces in the requirement exceeds remaining slice count, must write `deferred + blocker/cap` and explain coverage cap; must not treat these surfaces as covered in blind self-scoring.
- If no deploy-facing executable slice can be arranged within the budget, `PHASE0_RESULT.md` must carry `surface_budget_gap`.

## Requirement Family Ledger Hard Requirement
Phase 0 must break down the requirement into cross-project generic families, not allowed to only write business function points:
- `core_entry`
- `stateful_side_effect`
- `deploy_export_page`
- `wire_payload_api_contract`
- `config_policy_threshold`
- `generated_artifact_template_upload`
- `external_integration`
- `automation_test_interface`
- `lifecycle_cleanup_retention`

Each detected family must write:
`family -> requirement evidence -> weight -> first executable carrier -> planned slice -> blocked/cap`

If a detected family has no planned slice, must add `family_budget_gap` in `PHASE0_RESULT.md` and reduce weight in coverage cap rules.

## Production Carrier Preference Hard Requirement
When planning the first executable carrier, by default prefer existing production carriers from `{{SURFACE_CARRIER_SCAN}}`, and confirm via source code reading that it is indeed on the business path.

Forbidden to use new helper/service/DTO/test-only files as the first closeable carrier for a family, unless all of the following are satisfied:
- It is called by an existing processor/controller/facade/mapper/worker real entry;
- At least one existing production carrier is also modified or verified in the same slice;
- `FAMILY_CONTRACT.json.proof_required` explicitly includes executable assertions from this entry to output/side effects.

## Source-of-Truth Search Gate Hard Requirement (v263)
During the planning phase, explicit search evidence must be provided for the following dimensions, assumptions or speculation cannot be used as substitutes:

1. **Similar implementation search**: For each key behavior of the requirement (MQ send, push, callback, notification, status change, task routing, document generation), must first search `rg` for existing similar implementations in the project, and record search commands, search result counts, and candidate class names. Forbidden to search only for DTOs/enums/constants and treat that as "found the implementation".

2. **Facade direction search**: When the requirement involves callback/push/send/notify/receive, must search Facades in **both directions** (e.g., `rg -i "Receive.*Facade|Push.*Facade|Send.*Facade|Notify.*Facade"`), record search results, candidate class names and method signatures for each direction in the `Selected Real Entry` section of `EXPLORATION_REPORT.md`, and give selection rationale. If only one direction was searched, `phase0_status` cannot write `PROCEED`.

3. **Behavior carrier vs data carrier**: When the requirement involves behavior (MQ/push/send/callback/notify/event), cannot choose enum/DTO/constant as the core carrier. `Selected Real Entry` must point to the production class that actually executes the behavior (Service/Handler/Listener/Consumer/Producer/Facade), not a class that defines data.

4. **Method signature and return type search**: For each candidate Facade/Service, must use `rg` to confirm method signature and return type, cannot assume parameter types or return values. If the requirement says "callback notification", must distinguish between "initiate callback" and "receive callback" Facade methods.

Search evidence must be written in `EXPLORATION_REPORT.md` in the following format:
```
搜索: rg -i "关键词" --include "*.java" 路径范围
结果: N 个匹配
候选: 类名1.方法签名1, 类名2.方法签名2
选择: 类名X.方法签名X
理由: ...
排除: 类名Y.方法签名Y (原因: ...)
```

The same batch of search evidence must also be summarized in an independent section `## Search Commands Used` in `PHASE0_RESULT.md`, otherwise the runner will stop directly at the Phase0 carrier evidence gate. Minimum format:

## Search Commands Used

rg -n "关键词1" {{WORKTREE}}\example-core {{WORKTREE}}\example-server {{WORKTREE}}\example-web
rg -n "关键词2" {{WORKTREE}}\example-api {{WORKTREE}}\example-domain {{WORKTREE}}\example-provider
rg -n "classOrMethodName" {{WORKTREE}} --glob "*.java"

- result_summary: 每条命令的命中数量、候选类/方法、选择/排除理由

Hard Gate:
- `PHASE0_RESULT.md` without verbatim heading `## Search Commands Used` = `BLOCKED`
- Section without `rg ` command = `BLOCKED`
- Claiming a carrier exists without corresponding `rg` command and result summary = `BLOCKED`

## Trigger Point Validation (v447 Experiment 1)

When the requirement involves task triggering (e.g., "after XX succeeds" pattern), must verify that the selected carrier matches the trigger point:

1. **Extract trigger point pattern**: Extract "after XX succeeds" pattern from requirement_text:
   - "AI核赔结果获取成功后" → Apply Claim task（ExampleApiTaskProcessor）
   - "赔款计算成功后" → Calculate Loss task（ExampleCalculatorApiTaskProcessor）

2. **Validate carrier matching**:
   - Calculate Loss task (ExampleCalculatorApiTaskProcessor) only calculates amount, does not trigger auto-flow
   - Apply Claim task (ExampleApiTaskProcessor) is a comprehensive API interface, triggers auto-flow after saving results
   - If trigger point says "after AI review result retrieval" but Calculate Loss processor is selected, this is a wrong carrier selection

3. **Record in EXPLORATION_REPORT.md**:
   In the `Selected Real Entry` section, must add:
   - `trigger_point_pattern: <extracted trigger point pattern, e.g., AI review result retrieval>`
   - `expected_processor: <mapped processor type>`
   - `processor_match_validation: PASS | FAIL`

4. **Verification command** (optional but recommended):
   ```bash
   python scripts/trigger_point_validator.py validate "<requirement_text_snippet>" "<selected_carrier>"
   ```

**Key distinction**:
- `ExampleCalculatorApiTaskProcessor`: Only calculates compensation amount, not an auto-flow trigger point
- `ExampleApiTaskProcessor`: Comprehensive API interface, triggers auto-flow after saving results, is the correct auto-flow entry

If validation fails (trigger point does not match carrier), `phase0_status` must write `INVALID_PLAN`, add `wrong_test_surface` to `required_flags`.

## Interface Contract Extraction (MANDATORY for external/public entries)
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

## FAMILY_CONTRACT.json Hard Requirement
In addition to the Markdown contract, must write a machine-checkable `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`, not just natural language. JSON must at least contain:

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

Each detected family must appear in `families`. If a family cannot be executed, `planned_slice` can be empty, but must write `blocker` and `coverage_cap_if_open`. Forbidden to write placeholder, file-presence, DTO/entity/constant existence, mock-only test as proof that can close a family.

**FAMILY_CONTRACT.json's `selected_real_entry` must write a real production class name or method signature that exists in the baseline worktree; each family's `first_executable_carrier` must also write a real production class name or method signature, placeholder words are forbidden** (pending, TBD, unknown, N/A, placeholder). If a family needs a new carrier, must explicitly write `carrier_status: NEW`, `planned_new_carrier`, or blocker/cap; cannot write NEW/oracle-added carrier as top-level `selected_real_entry`. If a real carrier cannot be found, the `blocker` field must specify the evidence gap, and `coverage_cap_if_open` must be set to 0.

## Oracle Structural Alignment (Allowed Metadata Only)

Before completing EXPLORATION_REPORT.md, you MUST complete oracle structural alignment, but can only use runner-preprocessed metadata from `{{ORACLE_DIFF_ANALYSIS}}` such as file names, layers, weights, line counts:

1. Read `{{ORACLE_DIFF_ANALYSIS}}`.
2. List ALL oracle-changed production files (non-test files) and line counts.
3. For each oracle production file, identify its layer (DTO/Enum/Service/Mapper/Controller/Resource).
4. Group oracle files by business weight:
   - HIGH: Files with business logic in Service/Controller layer
   - MEDIUM: Enum, Config, Mapper, Resource
   - LOW: DTO, VO, Test
5. Include oracle HIGH-weight files as priority references in Candidate Surface Map and Critical Surface Allocation Plan.
6. In the Planning Input Summary section of EXPLORATION_REPORT.md, add an `Oracle Alignment` subsection listing:
   - oracle production files 总数
   - HIGH-weight files 列表
   - 候选 carrier 与 oracle HIGH-weight files 的初步对齐情况
7. In the Requirement Family Ledger of ROUND_CONTRACT.md, mark families corresponding to oracle HIGH-weight files as `oracle_high_weight: true`.

Forbidden to infer or wait for confirmation of method bodies, interface signatures, DDL, JSON schema, test assertions, or business implementation details from oracle metadata. If these details do not exist in the current code or can only be inferred, write them into `Uncertainty Ledger` / `required_flags` / coverage cap, must not ask the user to provide oracle or wait for oracle post-hoc.

`Oracle Alignment` 只能记录结构优先级和 family cap，不得给 `selected_real_entry`、方法签名、DDL、JSON schema、测试断言、服务新建或实现步骤背书。不要写 “oracle additions / oracle new service / oracle evidence proves selected entry” 这类句子。

If `{{ORACLE_DIFF_ANALYSIS}}` does not exist or is empty, add `oracle_analysis_skipped` to `required_flags` in PHASE0_RESULT.md, but cannot `BLOCKED` solely for this reason.

## IMPLEMENTATION_CONTRACT.md Hard Requirement (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)

After completing EXPLORATION_REPORT.md and ROUND_CONTRACT.md, must create `IMPLEMENTATION_CONTRACT.md` containing the following exact fields:

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

**v438 Forbidden fields**: `IMPLEMENTATION_CONTRACT.md` must not contain the following oracle-wait fields and statements:
- Forbidden `verification_path: Oracle post-hoc after implementation`
- Forbidden `cap_reason: Cannot verify ... without oracle access`
- Forbidden `mitigation: verify during oracle post-hoc`
- Forbidden `not verified against oracle`
- Forbidden any form of "waiting for oracle", "awaiting oracle", "oracle verification pending"

To describe blind replay constraints, use the following substitute expressions:
- Use "Blind replay constraint: ...; coverage cap applied" instead of "without oracle access"
- Use "signature verification deferred to oracle post-hoc" instead of "Oracle post-hoc after implementation"
- Use "verified against requirement with coverage cap" instead of "not verified against oracle"

**验证规则**（runner 将自动检查）：
1. `IMPLEMENTATION_CONTRACT.md` 必须存在
2. `carrier_class` 必须是完整类名（如 `com.example.project.core.service.XxxService`）
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

## Oracle Entry Point Guidance (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)

如果 ORACLE_ENTRY_HINT.md 在 replay root 中存在，该文件包含正确的入口点签名。

**使用规则**：
- 读取 `{{REPLAY_ROOT}}/ORACLE_ENTRY_HINT.md`（如果存在）
- hint 包含正确的入口点类名和方法签名
- 使用 hint 验证你的 carrier 选择
- **你选择的 carrier 必须与 hint 匹配**

**触发点模式映射**：
- "AI核赔结果获取成功后" → Apply Claim task（ExampleApiTaskProcessor）
- "赔款计算成功后" → Calculate Loss task（ExampleCalculatorApiTaskProcessor）

**Key distinction**:
- `ExampleCalculatorApiTaskProcessor`: Only calculates compensation amount, not an auto-flow trigger point
- `ExampleApiTaskProcessor`: Comprehensive API interface, triggers auto-flow after saving results, is the correct auto-flow entry

**在 EXPLORATION_REPORT.md 的 Selected Real Entry 章节必须记录**：
- `oracle_entry_hint_available: true/false`
- `oracle_entry_hint_content: <hint 内容摘要>`
- `carrier_match_validation: <selected carrier 是否与 hint 匹配>`

如果 hint 存在但你选择的 carrier 不匹配，`phase0_status` 必须写 `INVALID_PLAN`，`required_flags` 加 `wrong_test_surface`。

---

## Test Surface Mapping (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)

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

## Phase 0 Judgment
Write in `PHASE0_RESULT.md`:

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

Immediately after the above machine fields, must write an independent section:

## Search Commands Used

rg ...
rg ...
rg ...

- result_summary: ...

`phase0_status` can only write `PROCEED`, `INVALID_PLAN`, or `BLOCKED` verbatim. Custom status values are forbidden, such as `PROCEED_WITH_*`, `PROCEED_WITH_CAVEATS`, `PROCEED_WITH_ORACLE_VERIFICATION`, `PARTIAL_PROCEED`, `READY`, `PASS`. If there are caveats, write them into `required_flags`, but the status itself must still be one of the three.

判定Rules:
- `PROCEED`: First slice is core_path, and the real entry, first RED test, side-effect ledger, and deploy-facing follow-up are all clear.
- `INVALID_PLAN`: First slice is supporting_surface/helper/static-only, or real entry evidence is insufficient, or no first real entry RED.
- `BLOCKED`: Requirement/code surface is insufficient to determine real entry, and cannot safely choose the first slice.
- The following reasons cannot be used as `BLOCKED`: `cannot verify exact oracle method signatures`, `cannot verify oracle DDL`, `cannot verify oracle JSON schema`, `awaiting oracle verification`, `user must waive coverage caps`, `schema_verification_gap`, `exact_contract_gap`, `interface_contract_gap`, `new_table_structure_gap`. These can only serve as discovery ledger / uncertainty / family cap, not Phase 0 stop-line reasons.
- If `selected_real_entry` and `first_executable_slice` have already been found, `phase0_status` must be `PROCEED` or `INVALID_PLAN`, must not write `BLOCKED` due to schema/exact/oracle uncertainty.

If `INVALID_PLAN`, must write at least one in `required_flags`:
- `real_entry_gap`
- `core_entry_unclosed`
- `surface_budget_gap`
- `helper_only_surface_gap`
- `wrong_test_surface`
- `interface_contract_gap`

Start executing Phase 0. Only write the above two Markdown outputs.
