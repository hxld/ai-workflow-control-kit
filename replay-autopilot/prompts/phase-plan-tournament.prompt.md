你现在执行 Phase 0.5 Plan Tournament。只做规划，不写生产代码、不写测试代码、不跑 Maven。

【Evolution Version Verification (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)】
- EVOLUTION_VERSION: Check the evolution version loaded by the runner
- If you are using surface validation or new service authorization rules, verify that evolution version is >= v427
- If version is < v427, those rules are NOT available and you must NOT apply them
- Current loaded evolution version should be available in environment or runner metadata

【固定上下文】
- 主仓库: {{PROJECT_ROOT}}
- feature_name: {{FEATURE_NAME}}
- requirement_source: {{REQUIREMENT_SOURCE}}
- oracle identity: redacted in Phase 0.5; direct oracle refs are forbidden
- base commit: {{BASE_COMMIT}}
- replay root: {{REPLAY_ROOT}}
- isolated worktree: {{WORKTREE}}
- neutral baseline index: {{BASELINE_INDEX}}
- context manifest: {{CONTEXT_MANIFEST}}
- surface carrier scan: {{SURFACE_CARRIER_SCAN}}
- oracle diff analysis: {{ORACLE_DIFF_ANALYSIS}}
- feature classification: {{FEATURE_CLASSIFICATION}}
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- plan candidate count: {{PLAN_CANDIDATE_COUNT}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}

【目标】
基于 Phase 0 的探索事实，生成多份候选实现计划，按统一规则择优，最后冻结一个可执行的实施合同给 Phase 1。强规划，低探索编码。

【允许读取】
1. requirement_source。
2. repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml。
3. isolated worktree 当前代码。
4. 当前 replay root 下的 `EXPLORATION_REPORT.md`、`ROUND_CONTRACT.md`、`PHASE0_RESULT.md`、`FAMILY_CONTRACT.json`、`CONTEXT_MANIFEST.md`。
5. `{{BASELINE_INDEX}}`，但只能作为中性结构索引。
6. `{{SURFACE_CARRIER_SCAN}}`，但只能作为中性生产承载点候选清单；每个候选仍必须读源码确认。
7. `{{CONTEXT_MANIFEST}}` 列出的只读系统上下文文件；只能作为通用项目背景。
8. `{{ORACLE_DIFF_ANALYSIS}}`，oracle commit diff 的结构化分析（文件列表、layer 分类、weight），用于约束计划对齐 oracle 实际改动范围。
9. `{{FEATURE_CLASSIFICATION}}`，runner 预处理的 feature class 和 verifier adjustment，用于校准 required families、RED/GREEN 证据要求和水平切片最低面。

禁止读取 requirement_source 所在快照以外的 feature 文档目录；不要对 `.doc\<feature>` 或原始需求父目录执行 `rg` / `Get-ChildItem` / 批量读取。若需要需求事实，只读本 prompt 给出的 `requirement_source` 单文件快照。

【Feature Classification 使用规则】
如果 `{{FEATURE_CLASSIFICATION}}` 表明本需求是 `narrow_backend_read_only_fix`：
- 计划不得强行预留 DB/schema/frontend/config/generated-artifact/external-integration slice，除非 requirement_source 正向要求这些 surface。
- first slice 可以是 Backend + Test 的窄切片；水平切片要求按 `horizontal_minimum=2` 处理。
- 对已存在最小修复或 pre-applied fix，可以使用 GREEN-only + structural evidence；计划必须写明为什么 RED 不可行，以及哪个 GREEN 命令证明生产边界行为。
- 不适用 family 在 `FAMILY_CONTRACT.json`、`REPLAY_PLAN.md` 和 `IMPLEMENTATION_CONTRACT.md` 中保持 `not_required`，不能让它们继续压低 family ledger cap。

【禁止】
- 禁止直接读取 oracle branch/commit 或运行 `git diff`/`git log`/`git show` 访问 oracle commit（只允许读取 `{{ORACLE_DIFF_ANALYSIS}}` 中 runner 预处理的结构化分析）。禁止读取历史实现、旧 replay、历史会话总结、FINAL_REPLAY_REPORT。
- 禁止修改生产代码、测试代码、配置、SQL、前端文件。
- 禁止跑 Maven/测试/构建。
- 禁止把候选计划写成泛泛任务清单；每个高权重 slice 必须落到真实入口、文件族、验证点和停止条件。

【必须先做】
1. 读取 `{{REPLAY_ROOT}}\PHASE0_RESULT.md`。
2. 如果 `phase0_status` 不是 `PROCEED`，不得规划实现，写 `PLAN_RESULT.md`，`plan_status=INVALID_PLAN`。
3. 读取 `{{REPLAY_ROOT}}\EXPLORATION_REPORT.md` 和 `{{REPLAY_ROOT}}\ROUND_CONTRACT.md`。
4. 读取 `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`。
5. 读取 `{{SURFACE_CARRIER_SCAN}}`，把 required family 的候选生产承载点纳入候选计划。
6. 若上述文件缺失，写 `PLAN_RESULT.md`，`plan_status=BLOCKED`。

【Oracle Feature Domain Compatibility Check (MANDATORY v347)】

在执行 "Oracle-Constrained Planning" 之前，必须先检查 oracle 与需求的功能域是否兼容。

1. 读取 `{{ORACLE_DIFF_ANALYSIS}}`，提取 oracle 文件路径中的功能域关键词：
   - `examine/` / `ExamineFlow` / `ExamineFacade` → 审核流程域
   - `push/` / `InsureCompanyPush` / `PushService` → 保司推送域
   - `ai/` / `AiClaim` / `AiAuto` / `AiReview` → AI核赔域
   - `compensate/` / `CompensateTable` → 理算域
   - `route/` / `CaseRoute` → 案件流转域
   - `refund/` / `RefundTicket` / `ReturnTicket` → 退票域

2. 读取 `{{REQUIREMENT_SOURCE}}`，提取需求的功能描述关键词：
   - 标题中的功能名称 (e.g., "AI核赔自动流转", "退票处理")
   - 核心业务术语 (e.g., "免复核金额", "退票原因")

3. **域兼容性判断**：
   - 统计 oracle 文件中各功能域的文件数量
   - 确定主功能域：文件数量最多的域
   - 计算非主功能域文件比例：`foreign_ratio = non_primary_count / total_oracle_files`
   - 如果 `foreign_ratio > 30%` → `domain_compatibility: MISMATCH`
   - 如果 oracle 主功能域与需求主功能域不同 → `domain_compatibility: MISMATCH`
   - 否则 → `domain_compatibility: COMPATIBLE`

4. **在 `PLAN_RESULT.md` 中必须包含**：
   - `oracle_primary_domain:` <提取的oracle主功能域>
   - `requirement_primary_domain:` <提取的需求主功能域>
   - `domain_compatibility:` COMPATIBLE | MISMATCH | UNCERTAIN
   - `foreign_domain_ratio:` <非主功能域文件百分比>

5. 如果 `domain_compatibility: MISMATCH`，禁止生成候选计划，直接写 `PLAN_RESULT.md` 并设置：
   - `plan_status=BLOCKED`
   - `blocker: oracle_feature_domain_mismatch`
   - 在 `PLAN_RESULT.md` 中说明冲突文件列表和冲突原因

【Oracle-Constrained Planning (MANDATORY)】

在生成候选计划之前，你 MUST 先完成以下 oracle 对齐步骤：

1. 读取 `{{ORACLE_DIFF_ANALYSIS}}` 文件，了解 oracle commit 实际修改了哪些文件。
2. 列出所有 oracle production files（非 test 文件），并为每个文件确定 layer（DTO/Enum/Service/Mapper/Controller/Resource）。
3. 按 weight 排序 oracle production files：HIGH (Service/Controller) > MEDIUM (Enum/Mapper/Resource) > LOW (DTO/Test)。
4. **硬约束**：你的每个候选计划的 `required_files` 和 `expected_diff_matrix` MUST 包含所有 oracle HIGH-weight production files。遗漏 oracle HIGH-weight 文件的候选计划将被淘汰。
5. **First Slice Rule**：第一刀 MUST 指向 oracle 中最高 weight 的 production 文件。如果 oracle 有 Service 层改动，不得以 DTO/Enum 作为第一刀。
6. **Domain-Aware Oracle Overlap Calculation (v423)**：在计算 oracle overlap 之前，必须先应用域过滤。
   - 首先确定 `oracle_primary_domain`（从 ORACLE_DIFF_ANALYSIS.json 提取）
   - 应用域过滤：只保留路径包含 `oracle_primary_domain` 相关目录的 oracle 文件（例如 AI核赔自动化 → ai/claim/calculation/auto-flow）
   - 在域过滤后的文件集上计算 overlap：`overlap = |plan_files ∩ domain_filtered_oracle_files| / |domain_filtered_oracle_files|`
   - 要求：overlap MUST >= 50%，HIGH-weight overlap MUST >= 70%
   - 在 `PLAN_RESULT.md` 中报告 `oracle_primary_domain` 和域过滤后的文件数量

7. **Oracle overlap validation**：计划中列出的 production files 与**域过滤后**的 oracle production files 的重叠率 MUST >= 50%。低于 50% 的计划会被 runner 拒绝。HIGH-weight oracle files 重叠率 MUST >= 70%。

8. **Oracle Coverage Repair Ledger**：如果 overlap < 50% 或 HIGH-weight oracle production files 没有全部进入计划，必须在 `PLAN_RESULT.md` 写出机器可读修复账本。账本必须说明缺失的 oracle 高权重文件、扩展到哪个 existing production carrier / slice / executable test，或为什么该文件在 blind replay 中必须阻塞。禁止只写”待后续补充””需确认””参考 oracle 后决定”等占位说法。

如果 `{{ORACLE_DIFF_ANALYSIS}}` 不存在或为空，跳过 oracle 约束但必须在 `PLAN_RESULT.md` 写 `oracle_analysis_skipped`。

【Golden Delivery Slice Binding (MANDATORY when present)】

Before generating candidates, check whether any of these replay-root files exist:

- `{{REPLAY_ROOT}}\GOLDEN_DELIVERY_SLICE_PROMPT_SNAPSHOT.md`
- `{{REPLAY_ROOT}}\NEXT_GOLDEN_DELIVERY_SLICE.md`

If either file exists and the final `plan_status` is `PROCEED`, the plan MUST bind the first executable slice to the Golden Delivery Slice positive sample. This converts repeated failures into a concrete first-slice strategy instead of another negative gate.

Machine-readable requirements:

1. `PLAN_RESULT.md` must include one single-line field:
   - `golden_slice_binding: <rule fingerprint -> selected production carrier -> first RED -> minimum GREEN -> executable side effect>`
2. `FIRST_SLICE_PROOF_PLAN.md` must include the same single-line field:
   - `golden_slice_binding: <rule fingerprint -> selected production carrier -> first RED -> minimum GREEN -> executable side effect>`
3. The binding value must name at least one Golden Slice fingerprint such as `side_effect_ledger_gap`, `exact_contract_gap`, `schema_contract_discovery_gap`, `low_verification_cap`, `oracle_overlap`, or `positive_first_slice`.
4. If oracle overlap is below threshold, map at least one missing HIGH-weight oracle file to the binding: requirement literal -> real production carrier -> first RED -> minimum GREEN production diff -> executable side-effect proof.
5. Oracle diff metadata is a target shape, not proof that the current worktree already contains the implementation. Do not write "oracle changes already present", "implementation already present", or "tests should pass with proper setup" unless you cite a current-worktree source line that implements the exact missing source-chain assignment and `git diff`/source inspection proves no production diff is needed.
6. For source-chain / rebuild-path requirements, terminal setters or payload readers are not enough. Existing code such as `taskData.setPolicyNum(request.getPolicyNum())`, `taskData.setInsureNum(request.getInsureNum())`, or `input_data` key mapping only proves the downstream copy exists. The plan must inspect and bind the upstream source assignment into the request object. If the upstream assignment from build context/source into the request is missing, `expected_production_diff` and `green_minimum_implementation` must add that assignment in the selected production carriers.
7. If `ORACLE_DIFF_ANALYSIS.json` reports production additions, do not claim `NO_CHANGE`, `VERIFIED_PRESENT`, `Total Production Changes: 0`, `baseline already contains the complete implementation`, `Production Code: No changes`, or test-only completion for those oracle production files. For policyNum/insureNum rebuild, the first slice must be a `core_entry` production LOGIC_FIX in both oracle HIGH-weight TaskProcessor files, not a DTO/contract/test-only slice.
8. Even when no Golden Delivery Slice sample file exists, do not write `NONE`, `TBD`, `unknown`, `placeholder`, `none_with_reason`, or "no golden delivery slice files exist". Use a concrete verifier fingerprint binding such as `exact_contract_gap -> ... -> stateful_side_effect`. If no honest binding exists, set `plan_status: BLOCKED` and write a concrete blocker.

【EXACT Oracle Signatures (Phase 2 Pre-Binding, MANDATORY)】

**Step 1: Read Oracle Contracts**

如果 `{{REPLAY_ROOT}}\ORACLE_CONTRACTS.json` 存在，你 MUST 在生成候选计划前读取它。

该文件包含 oracle commit 中所有实际方法的精确签名（class_name, method_name, parameter_types, return_type）。

**Step 2: Use EXACT Signatures**

对于候选计划中的每个 production carrier（Service/Facade/Controller）：

1. ✅ 必须: 使用 `ORACLE_CONTRACTS.json` 中的 EXACT method name
2. ✅ 必须: 使用 EXACT parameter types
3. ✅ 必须: 使用 EXACT return type
4. ❌ 禁止: 从需求推断签名
5. ❌ 禁止: 创建与 oracle 签名不同的新方法
6. ❌ 禁止: 创建在 `forbidden_carriers` 列表中的 carrier

**Step 3: Document Oracle Alignment**

在 `PLAN_RESULT.md` 和 `IMPLEMENTATION_CONTRACT.md` 中必须包含：

```markdown
- oracle_contract_pre_binding: performed | skipped_no_contracts | blocked
- oracle_signature_alignment: exact_match | parameter_mismatch | synthetic_carrier
- synthetic_carrier_count: <number>
- oracle_forbidden_carriers_avoided: <comma-separated list or none>
```

**Example:**

如果 `ORACLE_CONTRACTS.json` 包含：
```json
{
  "AiAutoClaimFlowService": {
    "method": "handle",
    "signature": "public void handle(Long caseId, AiApplyClaimApiTask task)",
    "parameter_types": ["Long", "AiApplyClaimApiTask"],
    "return_type": "void"
  }
}
```

你的计划 MUST 使用：
- ✅ `AiAutoClaimFlowService.handle(Long caseId, AiApplyClaimApiTask task)`
- ❌ NOT `AiAutoClaimFlowService.executeAutoFlow(Long caseId)`
- ❌ NOT `AiAutoClaimFlowService.processAiResult(Long caseId, AiResult result)`

**Verification:**

verifier 将检查：
1. 计划中的 carrier 是否在 oracle 中存在
2. 签名是否完全匹配（method name, parameters, return type）
3. 是否创建了 synthetic carrier（不在 oracle 中的新 carrier）

如果 synthetic carrier rate > 40%，计划将被拒绝。

如果 `ORACLE_CONTRACTS.json` 不存在，写 `oracle_contract_pre_binding: skipped_no_contracts` 并继续。

【Pattern Matching Enforcement (MANDATORY for integration/callback features)】
如果需求涉及外部集成、回调、推送、通知、RPC 接口、API callback 等与外部系统交互的场景：

1. **搜索相似实现**：对项目中已有同方向 Facade 入口（如相同接口上的其他方法），用 `rg` 搜索候选方法签名、返回类型和错误处理模式。必须记录搜索命令、候选签名。
2. **Pattern to Follow 文档**：在 FIRST_SLICE_PROOF_PLAN.md 的 `key: value` 字段中增加：
   - `pattern_to_follow:` — 相似方法的完整签名（如 `ClassName.methodName(ParamType) -> ReturnType`）或 `NEW_PATTERN`（如果确实找不到相似实现）
   - `pattern_return_type:` — 相似实现的返回类型
   - `pattern_error_handling:` — 相似实现的错误处理模式（`response_codes` 或 `exception_propagation`）
   - `pattern_evidence_source:` — 搜索命令和代码文件路径
3. 如果 `pattern_to_follow:` 不是 `NEW_PATTERN`，`pattern_return_type:` 和 `pattern_error_handling:` 必须有具体值，禁止占位词。

禁止用叙述性描述替代具体搜索证据。`pattern_evidence_source:` 必须包含可复现的搜索命令。

---

## EXPERIMENT 1: Carrier Existence Verification (MANDATORY v358)

**CRITICAL CARRIER VERIFICATION REQUIREMENT:**

在完成规划并选定 `selected_carrier` 后，你必须验证所选 carrier 确实存在于代码库中。

### Verification Steps

**STEP 1: Search for carrier class**
```bash
rg "class YourSelectedCarrier" --type java
```

**STEP 2: Verify entry method exists**
```bash
rg "public.*yourMethodName\(" --type java
```

**STEP 3: If either search returns no results:**
- **DO NOT** proceed with this carrier
- Either select a different carrier that exists
- Or mark plan as `BLOCKED` with reason `"carrier_not_found"`

### Allowed Actions

✅ **ALLOWED**: 选择确实存在的 carrier（搜索返回结果）
✅ **ALLOWED**: 如果 carrier 不存在，写 `plan_status=BLOCKED` 和 `blocker: carrier_not_found`

❌ **FORBIDDEN**: 提交一个 carrier 不存在的计划
❌ **FORBIDDEN**: 假设 carrier 存在而不验证

### Example

**WRONG** (carrier doesn't exist):
```
Selected Carrier: AiNonExistentService.handle
Evidence: None (assumed to exist)
Status: PROCEED  # ❌ FORBIDDEN
```

**CORRECT** (carrier verified):
```
Selected Carrier: AiAutoClaimFlowService.handle
Verification: rg "class AiAutoClaimFlowService" --type java
Result: Found in claim-core/src/main/java/.../AiAutoClaimFlowService.java
Status: PROCEED  # ✅ ALLOWED
```

### Blocker Format

如果 carrier 不存在，在 `PLAN_RESULT.md` 中设置：
```markdown
- plan_status: BLOCKED
- blocker: carrier_not_found
- carrier_searched: <attempted carrier name>
- search_query: rg "class <CarrierName>" --type java
- search_result: No matches found
```

---

【候选计划要求】
生成 `{{PLAN_CANDIDATE_COUNT}}` 个候选计划文件：
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_1.md`
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_2.md`
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_3.md`

每个候选计划必须包含：
- strategy summary
- core path first slice
- deploy-facing surface allocation
- requirement family allocation：core_entry / stateful_side_effect / deploy_export_page / wire_payload_api_contract / config_policy_threshold / generated_artifact_template_upload / external_integration / automation_test_interface / lifecycle_cleanup_retention
- FAMILY_CONTRACT.json alignment：每个 detected family 的 planned slice、proof_required、forbidden_proof 和 coverage cap 是否被候选计划保留或更严格化
- production carrier alignment：每个 required family 必须优先绑定 `SURFACE_CARRIER_SCAN.md` 中的已有生产承载点；如果要新建承载文件，必须说明它由哪个已有入口调用、同 slice 修改哪个已有承载点、如何测试真实输出/副作用
- no substitute carrier：高权重 core/stateful/artifact family 的计划不得以 `Noop` / `Stub` / `Fake` / `Dummy` / `Placeholder` / `Mock` / `InMemory` / `TestOnly` / `Scaffold` 等占位或替代类作为主要承载点。新类只能是领域真实能力类，并且必须由已有生产入口调用。
- slice budget reservation table
- exact contract strategy
- side-effect ledger strategy
- test charter
- expected diff matrix
- sibling surface ownership：每个 sibling 必须归属到具体 `family_id`，后续 slice 结果必须用 `family_id: sibling` 格式报告，禁止把 deploy/export sibling 传播到 stateful/config/artifact family
- risk/cap rule
- why this plan could fail

候选计划必须有差异：
- 一个偏 core-transaction-first
- 一个偏 deploy-facing-surface-balanced
- 一个偏 exact-contract-and-test-first
如果你认为某个策略明显不可行，仍要写出并说明淘汰理由。

【择优规则】
用 100 分 rubric 评分：
- core path closure: 25
- side-effect/transaction evidence: 20
- exact contract fidelity: 15
- deploy-facing surface coverage: 15
- executable tests: 15
- token/cost discipline: 5
- rollback/blocker clarity: 5

不得选择只做入口钩子、helper/service 骨架、DTO/entity/config 支撑面的计划。
不得选择主要依赖新建 synthetic service/helper/substitute carrier 的计划；新文件只能作为既有生产承载点的被调用实现，不能单独关闭 family。
不得选择把所有 Phase 1 slice 都分配到同一概念族的计划；当 core/stateful 基线已能形成可执行证据后，后续预算必须转入至少一个 deploy-facing executable surface。
不得选择让 detected requirement family 在 Phase 1 中完全 untouched 的计划；如果 slice 数不足，必须明确 `family_budget_gap`、cap 和下一轮首片。
如果所有候选都无法安全进入编码，`PLAN_RESULT.md` 写 `plan_status=BLOCKED`。

【Production Carrier Search（MANDATORY, v270）】

在选择第一刀和生成 `IMPLEMENTATION_CONTRACT.md` 之前，你必须先证明“没有选错生产入口”。禁止先创建新 service 再让测试追随新 service。

必须完成并记录：
1. `carrier_search_queries:` 至少 3 条可复现源码搜索命令或搜索式，覆盖现有 task/processor/handler/facade/controller/route/consumer/listener、现有 `handle*` / `process*` / `execute*` / `callback*` / `notify*` 方法，以及与需求关键词相近的既有实现或 sibling surface。
2. `existing_production_carriers:` 搜索命中的真实生产承载点列表；如果为空，写 `NONE_FOUND_AFTER_SEARCH`，不能留空。
3. `selected_carrier_from_search:` 最终选择的生产承载点，必须来自 `existing_production_carriers`，除非 `new_service_proposed: true` 且有合格理由。
4. `new_service_proposed: true | false`。
5. `new_service_justification:` 仅当新 service 必须创建时填写；只允许跨项目成立的理由，例如 `orphan_feature_no_existing_domain`、`new_external_boundary`、`incompatible_existing_carriers`、`oracle_new_service_no_existing_orchestration`。不能写“为了方便测试”“先占位”“后续再接入口”。

如果 `selected_carrier_from_search` 不在搜索结果中，或 `new_service_proposed: true` 但没有合格理由，`PLAN_RESULT.md` 必须写 `plan_status=BLOCKED` 和 `blocker: carrier_search_unproven`，不得进入 Phase 1。

机器校验格式要求：
- `carrier_search:` 必须在 `PLAN_RESULT.md` 中独立成行，值只能是 `performed` 或 `blocked`。
- `carrier_search_queries:` 必须在 `PLAN_RESULT.md` 中独立成行，值必须包含至少 3 条以分号、逗号或 `|` 分隔的搜索式，且至少出现 3 次 `rg` / `grep` / `findstr` / `Select-String` / `search` / `query` 之一。
- `existing_production_carriers:` 必须在 `PLAN_RESULT.md` 中独立成行，值必须和 key 在同一行；多项用 `;` 分隔，不能写成空 key 后接 bullet/list。字段名必须是 `existing_production_carriers`，不能写 `carrier_search_existing_carriers` 等别名。
- Alias names such as `carrier_search_existing_carriers` are forbidden. Empty key followed by bullet/list is forbidden.
- `selected_carrier_from_search:` 必须在 `PLAN_RESULT.md` 中独立成行，且必须能从 `existing_production_carriers:` 同一行值中匹配到；除非 `new_service_proposed: true` 且理由合格。
- `oracle_production_file_overlap:` 必须在 `PLAN_RESULT.md` 中独立成行，值必须是数字百分比，例如 `83%`。不能只写在 `ORACLE_OVERLAP_GATE.json`、候选计划、解释段落或后验报告里。
- 如果 verifier 报 `carrier_search_queries_too_few`、`plan_result_missing:oracle_production_file_overlap` 或 `oracle_overlap_below_threshold`，Plan stage 会触发一次 contract repair pass；repair 后仍失败则本轮必须 BLOCKED。

【必须产出最终规划文件】
1. `{{REPLAY_ROOT}}\PLAN_SELECTION.md`
   - 候选计划评分表
   - 选择理由
   - 淘汰理由
   - 关键取舍

2. `{{REPLAY_ROOT}}\REPLAY_PLAN.md`
   - 按 slice 排序的最终计划
   - 每个 slice: requirement rows / surfaces / files / tests / DoD / blocker / coverage cap
   - 每个 slice 必须写 `existing production carrier(s)`；若为空，必须写 `carrier_search_terms` 与 `BLOCKED/coverage_cap`
   - 每个 detected requirement family 至少对应一个 slice 或 blocker/cap
   - 明确哪个 slice 首次覆盖 deploy-facing surface；若没有，必须写 `surface_budget_gap` 与 coverage cap
   - 明确 `STOP_AND_REPORT` 条件

3. `{{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md`
   - Phase 1 必须遵守的执行合同
   - 必须包含独立机器可读行：`selected_real_entry: <Phase0 selected_real_entry>`；如果无法绑定真实入口，写 `selected_real_entry: PLAN_BLOCKED_SELECTED_REAL_ENTRY`，并在 `PLAN_RESULT.md` 写 `plan_status=BLOCKED`
   - 必须包含独立机器可读行：`first_slice: <PLAN_RESULT first_slice>` 与 `first_red_test: <PLAN_RESULT first_red_test>`
   - 不允许重开大范围探索
   - 不允许替换 selected real entry，除非写 `BLOCKED_PLAN_MISMATCH`
   - 不允许以浅层 GREEN 宣称 core DONE
   - 不允许用新建 replay-local service/helper/test-only surface 关闭 family；必须经过已有生产入口/承载点
   - 不允许连续两个以上 slice 只扩展同一 core/service/log test 家族，除非所有高权重 deploy-facing surface 已有 executable slice 或明确 blocker/cap

4. `{{REPLAY_ROOT}}\EXPECTED_DIFF_MATRIX.md`
   - requirement -> module -> expected file families -> change type -> validation -> closure condition

5. `{{REPLAY_ROOT}}\SIDE_EFFECT_LEDGER.md`
   - selected real entry -> orchestration -> persistence/query/write -> state/task/progress/log -> transaction/failure isolation -> executable proof

6. `{{REPLAY_ROOT}}\TEST_CHARTER.md`
   - RED/GREEN 顺序
   - 真实入口测试
   - DB/事务或替代验证
   - deploy-facing surface tests
   - static-only/blocker 时的 cap
   - **格式硬要求（v426）**：TEST_CHARTER 必须包含独立的 `## RED Phase` 和 `## GREEN Phase` 标题段落。验证器会搜索 "RED" 和 "GREEN" 关键词，如果缺少这些关键词将触发 `test_charter_missing:RED` 或 `test_charter_missing:GREEN` 错误。你可以添加其他内容，但必须显式包含这两个标题段落。

7. `{{REPLAY_ROOT}}\FIRST_SLICE_PROOF_PLAN.md`
   - 只写 Phase 1 第一刀，不写全量计划
   - 必须绑定 `PLAN_RESULT.md` 的 `first_slice`、`first_red_test` 和 Phase 0 的 `selected_real_entry`
   - **格式硬要求（机器校验 v452）**：FIRST_SLICE_PROOF_PLAN 必须包含以下所有字段作为独立的 `key: value` 行。runner dry-run 脚本会逐行解析这些字段，不会解析叙述段落、Markdown 表格或嵌套列表。如果某个字段没有以 `key: value` 格式出现在独立行上，dry-run gate 会直接 BLOCKED_PLAN_MISMATCH。
   - **v452 最高优先级字段**：以下字段是最容易被遗漏的关键字段，必须优先检查：
     - `highest_weight_open_gate:` - **必须填写**。从 ROUND_CONTRACT.md 的 Requirement Family Ledger 中找出 weight 最高且需要在第一刀"打开"（新建服务或修改核心路径）的 family。例如：`stateful_side_effect`、`core_entry`、`wire_payload_api_contract`。不能省略，不能写成 "TBD"、"待确认" 等占位词。
     - `selected_real_entry:` - **必须填写**。必须与 Phase 0 的 selected_real_entry 完全一致。
     - `proof_kind:` - **必须填写**。必须是以下枚举值之一：`real_entry_behavior`、`stateful_side_effect`、`route_export_behavior`、`payload_shape_behavior`、`generated_artifact_behavior`。
     - `real_carrier_kind:` - **必须填写**。必须是以下枚举值之一：`production_entry_or_service`、`production_controller_or_route`、`production_mapper_or_query`、`production_payload_builder`、`production_template_or_artifact_renderer`、`production_lifecycle_cleanup`、`production_service_method`、`production_service`、`production_enum`、`production_dto`。
   - 禁止用叙述性段落、Markdown 表格、`##` 标题段落或嵌套列表替代 `key: value` 格式。你可以在 `key: value` 行之前或之后添加解释性内容，但每个必填字段本身必须以 `key: value` 独立行出现，值非空、非占位词。
   - 每个字段值禁止写占位词：`TBD`、`unknown`、`N/A`、`placeholder`、`待确认`、`未确认`、`后续确认`。如果某字段确实无法填写，必须写 `PLAN_BLOCKED_<FIELD>` 并在 `PLAN_RESULT.md` 写 `plan_status=BLOCKED`。
   - 必须逐字使用以下字段名，供 runner dry-run 校验；不得只写近义词：
     - `first_slice:`
     - `golden_slice_binding:`
     - `highest_weight_open_gate:` ← **v452 CRITICAL：这是最常被遗漏的字段，必须填写** 
     - `first_red_test:`
     - `selected_real_entry:`
     - `public_entry_contract_coverage:`
     - `selected_carrier:`
     - `target_subsurface_or_carrier:`
     - `real_carrier_kind:`
     - `minimum_side_effect_or_blocker:`
     - `forbidden_substitute_check:`
     - `required_sibling_surfaces:`
     - `production_boundary:`
     - `expected_production_diff:`
     - `red_expectation:`
     - `green_minimum_implementation:`
      - `proof_kind:`
      - `forbidden_substitute_proof:`
      - `fail_closed_condition:`
      - `coverage_cap_if_not_closed:`
      - `coverage_cap_if_missing:`
     - `pattern_to_follow:`
     - `pattern_return_type:`
     - `pattern_error_handling:`
     - `pattern_evidence_source:`
   - 推荐直接复制下面的单行 schema，不要改字段名；每一行冒号后必须直接写非空值，不能先空着再用下一行 bullet/list 补值：
```text
first_slice: <slice id>
golden_slice_binding: <rule fingerprint -> selected production carrier -> first RED -> minimum GREEN -> executable side effect>
highest_weight_open_gate: <MANDATORY: family name like stateful_side_effect/core_entry/wire_payload_api_contract. This field CANNOT be omitted. Read ROUND_CONTRACT.md Requirement Family Ledger, find the highest-weight family that needs to be opened in S1, and write its id here. Do NOT write TBD/unknown/placeholder.>
first_red_test: <test class or command>
selected_real_entry: <real production entry from Phase0>
public_entry_contract_coverage: <specific assertion or not_public_entry_with_reason>
selected_carrier: <production carrier>
target_subsurface_or_carrier: <concrete subsurface/carrier>
real_carrier_kind: <allowed enum value>
minimum_side_effect_or_blocker: <minimum side effect proof or blocker>
forbidden_substitute_check: passed
required_sibling_surfaces: <comma-separated surfaces or none_with_reason>
production_boundary: <comma-separated production files/methods; same line, no bullet list>
expected_production_diff: <comma-separated file families>
red_expectation: <why RED fails before implementation>
green_minimum_implementation: <minimum code/test change to pass>
proof_kind: <allowed enum value>
forbidden_substitute_proof: <why not helper/test-only/static>
fail_closed_condition: <condition that stops Phase1>
coverage_cap_if_not_closed: <integer>
coverage_cap_if_missing: <integer>
pattern_to_follow: <existing signature or NEW_PATTERN>
pattern_return_type: <return type>
pattern_error_handling: <response_codes or exception_propagation>
pattern_evidence_source: <rg command + file path>
```
   - **测试 harness 选择规则（v289/v473/v475/v476）**：`first_red_test` 必须指向已有测试依赖的模块。当前 claim replay 默认使用 `claim-server/src/test/...` + `-pl claim-server -am` 作为测试 harness，但测试目标可以是 `claim-core` 中的真实 Service/TaskProcessor carrier。`claim-core` 若无 JUnit/Mockito/Spring Test 依赖，不得规划 `claim-core/src/test/...` 测试；必须规划 `claim-server/src/test/...` 测试并通过依赖调用 `claim-core` 生产 carrier。所有 Maven RED/GREEN 命令必须包含 `-am`，PowerShell 下带 `-Dtest`/`#` 时使用 `mvn --% ...` 形态。禁止通过修改任何 `pom.xml` 或新增测试依赖来满足 RED。若无法在已有 harness 中证明，写 `PLAN_BLOCKED_TEST_HARNESS` 并把 `plan_status` 降为 `BLOCKED`。
     - **测试模块策略预检（v478/v479）**：在最终确定 plan 前，必须完成并记录 test infrastructure check：
       1. 识别生产目标模块与实际测试 harness 模块，例如 `claim-core` 生产 carrier 可由 `claim-server/src/test/...` 覆盖。
       2. 读取候选测试模块 `pom.xml` 与已有 `src/test` 文件，确认 JUnit/TestNG、Mockito/Spring Test 等依赖和 import 风格真实存在。
       3. 确认测试模块能 import 目标生产类，不能靠修改任何 `pom.xml` 或新增测试依赖解决。
       4. **Do not execute Maven in Plan.** Plan 只能声明 intended isolated dry-run command：`mvn {{MAVEN_SETTINGS_ARG}} -f {{WORKTREE}}\pom.xml -pl <test-module> -am test-compile`，其中 `{{MAVEN_SETTINGS_ARG}}` 仅在 replay config 定义 `maven_settings` 时填入 `-s <settings.xml>`；并把 `compilation_dry_run_evidence_file` 设为 replay root 下的 `TEST_INFRASTRUCTURE_DRY_RUN.json`。runner 会在 Plan 返回后、schema gate 前 materialize `TEST_INFRASTRUCTURE_DRY_RUN.json`，并只允许使用隔离 worktree root POM。
       5. `PLAN_RESULT.json.test_infrastructure_check.compilation_dry_run_evidence_file` 必须引用该 replay-root 内证据文件；不得要求 Plan agent 自行运行 Maven 或写 stdout/stderr 摘要。所选 `<test-module>` 必须存在 `src/test` 且已有测试源；`claim-core` 没有 `src/test` 时不能作为测试 harness。
       6. 如果静态检查已经确认测试模块不可导入生产类、harness 不存在、或只能依赖 protected project root dry-run，`plan_status=BLOCKED`，`blocker=PLAN_BLOCKED_TEST_INFRASTRUCTURE`，不得进入 Phase 1。
     - **policyNum/insureNum rebuild 专用测试 harness 硬规则（v480/v481）**：如果需求、Phase0 事实、source-chain 合同、候选 carrier 或 oracle 文件涉及 `policyNum`、`insureNum`、`rebuildTaskData`、`AiApplyClaimApiTaskProcessor`、`AiCalculateLossApiTaskProcessor` 任一关键词，则 `PLAN_RESULT.json.test_infrastructure_check.test_module_for_target` 必须是 `claim-server`，`compilation_dry_run_command` 必须包含 `-pl claim-server -am test-compile`，`expected_test_class` 必须规划在 `claim-server/src/test/...` 的现有测试 harness 下。此类需求中 `claim-core` 只能作为生产 carrier 模块，不能作为测试 harness；如果只能选择 `claim-core` 或 dry-run 输出 `No sources to compile`，必须写 `plan_status=BLOCKED`、`blocker=PLAN_BLOCKED_TEST_INFRASTRUCTURE`，禁止输出 `PROCEED`。不得把 `claim-core/src/main` 生产类、DTO getter/setter 或 terminal payload reader 当作测试 harness 证据。`manual verification`、`manual check`、`manual inspection`、`none_with_manual_verification` 只能作为 BLOCKED 原因，绝不能出现在 `PROCEED` 的 `first_red_test`、`blocker_reason`、`next_action` 或 test infrastructure 字段中。
   - **TaskProcessor rebuild no-Spring 规则（v476/v477）**：当第一刀是 `TaskProcessor` / `rebuildTaskData` / source-chain，计划必须指定 no-Spring JUnit + Mockito/反射测试形态；不得规划继承 `AbstractTestClass`、`@SpringBootTest`、`@RunWith(SpringJUnit4ClassRunner.class)`、`@ContextConfiguration` 或 `@Resource` 注入 processor 的测试。对 policyNum/insureNum rebuild，计划必须要求 mock `AiClaimDataAssemblyHelper.buildRequestCommon(...)` 并在 `thenAnswer` 中调用真实 `AiClaimDataAssemblyHelper.RequestBuildFunction`，用 `RequestBuildContext` 注入 `policyNum`/`insureNum`，断言 `rebuildTaskData` 输出 taskData 字段等于 context 值。禁止依赖固定数据库 `caseId`、外部测试数据、完整 Spring ApplicationContext、`taskData == null` 后打印 WARN 继续通过、只测 terminal DTO getter/setter、只测 mock verify，或在 `thenAnswer` 中直接返回手工构造/手工 set 字段的 request。第一刀必须同时覆盖 `AiApplyClaimApiTaskProcessor.rebuildTaskData(Long caseId)` 与 `AiCalculateLossApiTaskProcessor.rebuildTaskData(Long caseId)` 两个 sibling carrier；否则 `plan_status=BLOCKED` 或 `coverage_delta=0`。
   - **公共入口证明规则（机器校验）**：如果 `selected_real_entry` 是 facade/controller/API/endpoint/route 等公共入口，则以下全部必须满足，否则 runner 拒绝 FIRST_SLICE_PROOF_PLAN 并 early stop：
     1. `selected_carrier` 必须是该公共入口本身，或包含该公共入口全名的响应契约测试 carrier。禁止只写 Mapper/Entity/DTO/internal service。例如：entry 是 `AiClaimModuleConfigController` → carrier 必须包含 `AiClaimModuleConfigController` 或 `AiClaimModuleConfigFacade`，不能只写 `TAiClaimModuleConfig entity` 或 `AiClaimModuleConfigMapper`。
     2. `first_red_test` 必须通过该公共入口或其直接调用链发起，不能只测 Mapper/DAO 层。
     3. `public_entry_contract_coverage:` 必须写明请求参数、响应字段、状态码或错误分支中至少一个的可执行证明。仅写 "Full" 或 "existing contract accepts DTO" 不够，必须写具体断言内容（如 "assert ResultModel.success contains exemptReviewAmount field"、"assert POST /ai/claim/config/add returns 200 with updated config JSON"、"assert invalid param returns ResultModel.error with message"）。
     4. `real_carrier_kind` 必须写 `production_entry_or_service` 或 `production_controller_or_route`，不能写 `production_mapper_or_query`、`production_dto`、`production_enum`。
   - `proof_kind` 是机器校验字段，只允许以下值（逐字照写）：`real_entry_behavior`、`stateful_side_effect`、`route_export_behavior`、`payload_shape_behavior`、`generated_artifact_behavior`。禁止写 `static_presence`、`helper_only`、`compile_only`、`dto_only` 或自造词如 `entity_behavior`。违反格式的 FIRST_SLICE_PROOF_PLAN 将被 runner 拒绝。
   - `real_carrier_kind` 是机器校验字段，只允许以下值（逐字照写）：`production_entry_or_service`、`production_controller_or_route`、`production_mapper_or_query`、`production_payload_builder`、`production_template_or_artifact_renderer`、`production_lifecycle_cleanup`、`production_service_method`、`production_service`、`production_enum`、`production_dto`。禁止写 `production_entity`、`protected_hook`、`test_subclass`、`helper_only`、`dto_only`、`static_presence`、`mock_only` 或任何自造词。违反格式的 FIRST_SLICE_PROOF_PLAN 将被 runner 拒绝。
   - `minimum_side_effect_or_blocker` 必须写出第一刀最少要证明的真实生产调用、状态/落库/输出/payload/导出/template 副作用；如果找不到，写 `PLAN_BLOCKED_REAL_CARRIER`。
   - **v295_executable_first_slice_gate / v295 可执行第一刀硬门禁**：当 `plan_status: PROCEED` 时，第一刀不得是 `Contract & RED Tests`、`CONTRACT_ONLY`、`RED-only`、`test-only`、`production_boundary: NONE` 或 `expected_production_diff: NONE`。第一刀必须在同一 slice 内包含：一个 RED 测试、最小 GREEN 生产实现、以及 `minimum_side_effect_or_blocker` 中写明的真实生产副作用/payload/输出/导出/template 证明。禁止把 GREEN 或生产副作用延后到 S2/S3；如果第一刀只能写合同或 RED 测试，必须把 `plan_status` 改为 `BLOCKED`。
   - **source-chain GREEN 最小实现规则（v474）**：如果 `SOURCE_CHAIN_CONTRACT.json.required_source_chain=true`，第一刀 GREEN 必须闭合 `next_required_slice.entry` 中的 source -> request/task -> payload 链路。禁止把当前源码里已有的 downstream setter、DTO getter、payload key、或 taskData copy 当成“已实现”。若缺的是 request/buildContext 赋值，必须把该赋值列入 `expected_production_diff`；否则写 `PLAN_BLOCKED_SOURCE_CHAIN_UNPROVEN`。
   - **v296_core_executable_tracer_selection**：如果 Phase 0 已发现 `selected_real_entry`，且最高权重 family 是 `core_entry`，候选计划必须至少包含一个以该真实入口为第一刀的 executable tracer bullet。最终 `selected_candidate` 不得选择只改 Constant/DTO/Entity/Mapper 的 exact-contract/static slice。`highest_weight_open_gate: core_entry` 时，`selected_carrier` 必须是真实入口/服务/方法，`proof_kind` 必须是 `real_entry_behavior` 或 `stateful_side_effect`，`real_carrier_kind` 必须是 `production_entry_or_service`、`production_service_method` 或 `production_service`。禁止用 `plan_status: BLOCKED` 逃避该选择，除非 Phase0 没有真实入口、测试 harness 不可用或 oracle overlap 在扩展后仍低于阈值。
   - `minimum_side_effect_or_blocker` 的值禁止写 `NONE`、`N/A`、`NOT_APPLICABLE`、`none_with_reason`、`no production code`、`contract definition only`、`to be implemented in Slice 2` 等绕过语。它必须是可执行证明，例如“service method writes state through mapper and test asserts mapper call + status value”，或写 `PLAN_BLOCKED_REAL_CARRIER` 并停止。
   - `production_boundary` 和 `expected_production_diff` 在 `plan_status: PROCEED` 时必须指向真实生产文件/方法/文件族，禁止写 `NONE` 或 “Slice 1 does not touch production code”。
   - `forbidden_substitute_check` 是机器校验字段，只允许以下两种值（逐字照写，不加点号、不加空格、不加描述）：
     - `forbidden_substitute_check: passed` （检查通过）
     - `forbidden_substitute_check: failed:<reason>` （检查不通过，必须同时写 `plan_status=BLOCKED`）
     禁止写描述性文本如 "Must verify..."、"No substitute..."、"Check that..."。违反格式的 FIRST_SLICE_PROOF_PLAN 将被 runner 拒绝并 early stop。
   - 如果需求写明字段来源、来源表、来源字段或“后端自动填充”，第一刀或第二刀必须是 source-chain slice：`source carrier -> build context/request -> task data -> wire payload`。只验证终端 DTO/taskData/payload 写入不能关闭 core。
   - 字段默认写成单行 `field: value`；如必须换行，下一行只能使用 Markdown definition-list 的 `: value`，不能把值散落到普通段落里。`production_boundary:`、`selected_carrier:`、`target_subsurface_or_carrier:`、`expected_production_diff:` 这四个字段必须优先写成同一行逗号分隔值；禁止写成空冒号后接 bullet/list，否则 verifier 会判定 `first_slice_proof_schema_empty`。
   - 若第一刀无法用真实入口和 RED 测试证明，`PLAN_RESULT.md` 必须写 `plan_status=BLOCKED`，不得进入 Phase 1
	   - **v457 first_slice_proof schema 硬要求（Executable Evidence Gate）**：
	     FIRST_SLICE_PROOF_PLAN 必须包含以下 V457 字段，且格式必须符合机器校验：
	     - `target_carrier_file_path:` - 精确文件路径，不能是 TBD/unknown/占位词
	     - `target_carrier_line_number:` - 精确行号（整数），不能是 TBD_facade_save_method
	     - `expected_test_class:` - 完整测试类名
	     - `expected_test_method:` - 测试方法名
	     - `expected_assertions:` - JSON 数组格式，至少 3 个断言，例如：
	       ```text
	       expected_assertions: ["assertEquals(35, caseStatus)", "verify(compensateDetailMapper).insert()", "assertNotNull(result)"]
	       ```
	     - `expected_side_effects:` - JSON 数组格式，至少 1 个副作用，例如：
	       ```text
	       expected_side_effects: [{"table": "t_compensate_detail", "operation": "insert"}, {"table": "t_case_route", "operation": "update", "field": "status", "value": "35"}]
	       ```
	     禁止使用占位词（TBD、unknown、placeholder），禁止写成叙述性段落，禁止缺少 required 字段。
	     如果 target_carrier_line_number 无法从 baseline 确认，必须写 `PLAN_BLOCKED_LINE_NUMBER` 并把 `plan_status` 改为 `BLOCKED`。
	   - **v457 layer validation 硬要求（Surface Coverage Gate）**：
	     在选择 carrier 之前，必须执行 layer validation pre-check：
	     1. 对于 `core_entry` family：默认 carrier.layer 必须是 Facade 或 Controller；但当归档 oracle 的 HIGH 生产文件全部位于后台 TaskProcessor/Service，且需求是 rebuild/async/backend-only 路径、没有 Controller/Facade/deploy surface 时，必须绑定这些 oracle TaskProcessor/Service 方法作为真实可执行入口，不得为了满足 Facade 规则扩散到无 oracle 证明的 helper/service/DTO 链。
	     2. 对于 `stateful_side_effect` family：carrier.layer 可以是 Service 或 Facade
	     3. 对于 `deploy_export_page` family：carrier.layer 可以是 Controller 或 Service
	     4. 如果选定的 carrier 是 Service 层但目标 family 是 `core_entry`，且不满足“oracle 后台 TaskProcessor/Service 例外”：
	        - 必须拒绝该 carrier
	        - 必须搜索对应的 Facade 层入口
	        - 如果没有 Facade，必须写 `PLAN_BLOCKED_LAYER_VALIDATION` 并把 `plan_status` 改为 `BLOCKED`
	     5. 执行 layer validation 的证据：
	        - `rg "class.*Facade" --type java` 在相关模块搜索 Facade
	        - 记录搜索结果和选择的理由
	        - 如果 Service 层 carrier 是唯一的真实入口，必须在 FIRST_SLICE_PROOF_PLAN 中说明为何没有 Facade 层等价入口

8. `{{REPLAY_ROOT}}\PLAN_RESULT.md`

【PLAN_RESULT.md 格式】

```markdown
# Plan Result

**注意**：以下所有字段必须以 `key: value` 格式独立成行，禁止空 key 后接 bullet/list。每个 key 必须有非空值（除了 `blocker:` 和 `invalid_reason:` 在无问题时可以为空）。

- plan_status: PROCEED | INVALID_PLAN | BLOCKED
- selected_candidate: <从 PLAN_SELECTION.md 复制，如 "3 - Exact-Contract-and-Test-First">
- selected_strategy: <从 PLAN_SELECTION.md 复制策略摘要，如 "exact-contract-and-test-first" | "core-transaction-first" | "deploy-facing-surface-balanced">
- implementation_model_recommendation: gpt-5.3-codex
- required_files:
- oracle_production_file_overlap:
- oracle_high_weight_coverage:
- oracle_missing_high_weight_files:
- oracle_expansion_plan:
- oracle_out_of_scope_files:
- golden_slice_binding:
- oracle_primary_domain: <功能域名称>
- requirement_primary_domain: <功能域名称>
- domain_compatibility: COMPATIBLE | MISMATCH | UNCERTAIN
- foreign_domain_ratio: <百分比>
- carrier_search: performed | blocked
- carrier_search_queries: <query1>; <query2>; <query3>
- existing_production_carriers: <carrier1>; <carrier2> | NONE_FOUND_AFTER_SEARCH
- selected_carrier_from_search: <carrier from existing_production_carriers> | NONE_FOUND
- new_service_proposed: true | false
- new_service_justification:
- first_slice:
- first_red_test:
- core_closure_required: true | false
- deploy_surface_required: true | false
- invalid_reason:
- blocker:
- next_action:
```

`PLAN_RESULT.md` 必须声明 `oracle_production_file_overlap` 和 `oracle_high_weight_coverage`（基于**域过滤后**的 oracle 文件集）。如果 oracle-assisted planning 模式下 overlap 低于 50%，必须先扩大/修正 selected plan 覆盖的高权重生产文件族；仍无法达到 50% 时，写 `plan_status=BLOCKED` 和 `blocker: oracle_overlap_below_threshold`，不得输出 PROCEED。

当 overlap < 50% 或存在 HIGH-weight uncovered 时，`PLAN_RESULT.md` 还必须包含以下机器可读字段：
- `oracle_missing_high_weight_files:` 用分号列出未覆盖的 HIGH-weight oracle production files。
- `oracle_expansion_plan:` 写成 `oracle file -> existing production carrier -> slice/test` 的映射；如果无法扩展，写 `BLOCKED:<reason>`。
- `oracle_out_of_scope_files:` 只允许列出在 blind 条件下不可安全判断的文件，并逐项给出 blocker；没有则写 `none`。

判定规则：
- `PROCEED`：最终计划可直接交给 Phase 1 执行，且 required planning artifacts 全部存在。
- `INVALID_PLAN`：计划仍以 supporting/helper/static/DTO/config 为第一刀，或缺真实入口 RED。
- `BLOCKED`：需求/代码事实不足以冻结计划，或关键 exact contract 无法在 blind 条件下安全判断。

【必须全部写出以下文件，无论 plan_status 是 PROCEED 还是 BLOCKED】

以下 9 个文件是 Plan stage 的必产物。即使 plan_status=BLOCKED 或 plan_status=INVALID_PLAN，也必须全部写出。缺少任何一个都将触发 artifact repair pass 或 early stop。

1. `{{REPLAY_ROOT}}\PLAN_RESULT.md` — plan_status + selected strategy
2. `{{REPLAY_ROOT}}\PLAN_RESULT.json` — machine-readable plan contract. Markdown is for humans; this JSON is the authority for unattended gates.
3. `{{REPLAY_ROOT}}\PLAN_SELECTION.md` — 候选评分与选择理由
4. `{{REPLAY_ROOT}}\REPLAY_PLAN.md` — slice 排序最终计划
5. `{{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md` — Phase 1 执行合同
6. `{{REPLAY_ROOT}}\EXPECTED_DIFF_MATRIX.md` — requirement → file → change type → validation → closure

   **格式硬要求（v449）**：EXPECTED_DIFF_MATRIX 必须使用 Markdown 表格格式，且必须包含 "Closure" 或 "Closure Condition" 列头。验证器会搜索 "closure" 关键词，如果缺少该列头将触发 `expected_diff_missing:closure` 错误。表格格式示例：

   ```markdown
   ## Slice 1: Contract Definition

   | Oracle File | Diff Type | Lines Added | Lines Deleted | Validation | Closure |
   |-------------|-----------|-------------|---------------|------------|---------|
   | claim-domain/.../TAiClaimModuleConfig.java | FIELD_ADD | 3 | 0 | type_match | S1 |
   | claim-core/.../AiAutoClaimFlowService.java | NEW_STUB | 20 | 0 | signature_only | S1 |
   ```

   - "Closure" 列必须说明该 diff 在哪个 slice 闭合（如 S1, S2, S3）或为何无法闭合（如 BLOCKED:reason）
   - 禁止使用 "Status: TODO" 或其他占位格式，必须明确 slice 或 blocker
   - 验证器会检查 "closure" 关键词存在性
7. `{{REPLAY_ROOT}}\SIDE_EFFECT_LEDGER.md` — entry → side effect → state/task/transaction → proof
8. `{{REPLAY_ROOT}}\TEST_CHARTER.md` — RED/GREEN order + real entry tests + DB/transaction
9. `{{REPLAY_ROOT}}\FIRST_SLICE_PROOF_PLAN.md` — first slice proof schema (见上方字段清单)

`PLAN_RESULT.json` 最低格式：

```json
{
  "plan_status": "PROCEED | BLOCKED | INVALID_PLAN",
  "target_carrier_file_path": "relative/path/ToCarrier.java",
  "target_carrier_line_number": 123,
  "expected_test_class": "SomeBehaviorTest",
  "expected_test_method": "methodName",
  "side_effects": ["DB/state/file/API/log side effect"],
  "expected_assertions": ["assertion 1", "assertion 2"],
  "test_infrastructure_check": {
    "test_module_for_target": "<module_name>",
    "test_module_has_dependencies": true,
    "test_harness_available": true,
    "can_import_production_classes": true,
    "compilation_dry_run_exit_code": 0,
    "compilation_dry_run_command": "mvn -s D:\\maven\\settings\\settings.xml -f {{WORKTREE}}\\pom.xml -pl <test-module> -am test-compile",
    "compilation_dry_run_evidence_file": "TEST_INFRASTRUCTURE_DRY_RUN.json",
    "blocker_reason": "none"
  },
  "blocker": "required only when plan_status is BLOCKED",
  "invalid_reason": "required only when plan_status is INVALID_PLAN"
}
```

当 `plan_status=PROCEED` 时，`target_carrier_file_path`、`target_carrier_line_number`、`expected_test_class`、`expected_test_method`、`side_effects` 必须非空。`target_carrier_line_number` 必须是从 baseline/worktree 源码读取到的精确整数行号，不能是 `null`、`TBD`、`unknown` 或占位符；如果无法确认，必须写 `plan_status=BLOCKED` 和 `blocker=PLAN_BLOCKED_LINE_NUMBER`。`test_infrastructure_check` 必须存在并满足：`test_module_has_dependencies=true`、`test_harness_available=true`、`can_import_production_classes=true`、`compilation_dry_run_exit_code=0`、`compilation_dry_run_command` 指向同一个测试模块且包含 `-pl`/`-am`/`test-compile`，并且必须指向 `{{WORKTREE}}\pom.xml` 或等价隔离 worktree root POM、绝不能指向 protected project root；`compilation_dry_run_evidence_file` 指向 replay root 内真实存在的 dry-run 证据（由 runner materialize），`blocker_reason=none` 或空值。当 `plan_status=BLOCKED` 时必须写 `blocker`；当 `plan_status=INVALID_PLAN` 时必须写 `invalid_reason`。

如果 plan_status=BLOCKED，IMPLEMENTATION_CONTRACT 和 FIRST_SLICE_PROOF_PLAN 可以写简短 blocker 说明，但文件必须存在。

开始执行 Phase 0.5。只写上述规划产物。

---

【Pre-S1 Plan Check Integration (v348)】

在完成 Phase 0.5 规划后，Phase 1 开始前，必须执行以下检查：

### 1. Carrier Verification (v348)

参考 `PRE_S1_PLAN_CHECK.md`:
- 验证 selected_carrier 与 requirement keywords 的匹配度
- 运行 `verify-carrier.ps1` 验证载体选择
- 如果 WARN 且无正当理由，plan_status 必须改为 BLOCKED

### 2. Horizontal Slicing Verification (v348)

参考 `TRACER_BULLET_GUIDANCE.md`:
- S1 (tracer_bullet) 必须触摸至少 3 个 family
- 运行 `verify-horizontal-slice.ps1` 验证水平切片覆盖
- 如果 families_touched < 3，slice 不得进入 GREEN 阶段

### 3. Behavioral Test Charter (v348)

参考 `TEST_CHARTER_GUIDANCE.md`:
- RED 测试必须包含业务断言，禁止 fail()/assertTrue(true)/TODO
- 运行 `verify-test-charter.ps1` 验证测试质量
- 如果包含 blocked_patterns，不得进入 GREEN 阶段

这些检查确保规划产生的 carrier 选择、切片设计和测试契约符合 TDD 最佳实践。

---
