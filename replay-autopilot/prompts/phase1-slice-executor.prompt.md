You are now executing Phase 1 strict blind “single slice coding execution”. Only execute one slice, do not perform oracle post-hoc, do not write final ROUND_RESULT.

【Fixed Context】
- 主仓库: {{PROJECT_ROOT}}
- feature_name: {{FEATURE_NAME}}
- requirement_source: {{REQUIREMENT_SOURCE}}
- oracle identity: redacted in Phase 1; direct oracle refs are forbidden
- base commit: {{BASE_COMMIT}}
- replay root: {{REPLAY_ROOT}}
- isolated worktree: {{WORKTREE}}
- neutral baseline index: {{BASELINE_INDEX}}
- context manifest: {{CONTEXT_MANIFEST}}
- surface carrier scan: {{SURFACE_CARRIER_SCAN}}
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}
- slice index: {{SLICE_INDEX}} / {{MAX_SLICES}}
- slice result path: {{SLICE_RESULT}}
- slice verify path: {{SLICE_VERIFY}}
- carrier authorization: {{CARRIER_AUTHORIZATION}}
- carrier rank map: {{CARRIER_RANK}}
- exact contract assertion matrix: {{EXACT_CONTRACT_ASSERTION_MATRIX}}
- next slice exact contract subset: {{NEXT_SLICE_EXACT_CONTRACT}}
- side-effect evidence harness: {{SIDE_EFFECT_EVIDENCE}}
- pre-slice cap display: {{PRE_SLICE_CAP_DISPLAY}}
- slice progress json: {{SLICE_PROGRESS}}
- slice progress md: {{SLICE_PROGRESS_MD}}
- requirement family ledger: {{REQUIREMENT_FAMILY_LEDGER}}
- forced requirement family: {{FORCED_REQUIREMENT_FAMILY}}
- forced slice type: {{FORCED_SLICE_TYPE}}
- forced sibling surface: {{FORCED_SIBLING_SURFACE}}
- open-family backpressure: {{OPEN_FAMILY_BACKPRESSURE}}
- open requirement families: {{OPEN_REQUIREMENT_FAMILIES}}

【Allowed to Read】
1. requirement_source.
2. repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml.
3. isolated worktree current code.
4. Current round Phase 0/0.5 outputs: ROUND_CONTRACT.md, PHASE0_RESULT.md, EXPLORATION_REPORT.md, PLAN_RESULT.md, REPLAY_PLAN.md, IMPLEMENTATION_CONTRACT.md, EXPECTED_DIFF_MATRIX.md, SIDE_EFFECT_LEDGER.md, TEST_CHARTER.md, FIRST_SLICE_PROOF_PLAN.md.
5. Current round slice progress files: SLICE_PROGRESS.json, SLICE_RESULT_*.json, SLICE_VERIFY_*.json.
6. Current round family contract and requirement family ledger: FAMILY_CONTRACT.json, REQUIREMENT_FAMILY_LEDGER.json.
7. Current round slice evidence contracts: CARRIER_AUTHORIZATION_*.json, CARRIER_RANK_*.json, EXACT_CONTRACT_ASSERTION_MATRIX_*.json, NEXT_SLICE_EXACT_CONTRACT_*.json, SIDE_EFFECT_EVIDENCE_*.json, PRE_SLICE_CAP_DISPLAY_*.json.
8. BASELINE_INDEX.md can only be used as a neutral structural index.
9. SURFACE_CARRIER_SCAN.md can only be used as a neutral list of production carrier candidates; must confirm by reading source code before use.
10. CONTEXT_MANIFEST.md listed system context files, can only be used as general project background.

Forbidden to read feature documentation directories outside the snapshot where requirement_source is located; do not run `rg` / `Get-ChildItem` / batch reads on `.doc\<feature>` or original requirement parent directories. If requirement facts are needed, only read the `requirement_source` single-file snapshot given in this prompt.

【Forbidden】
- Forbidden to read oracle branch/commit/diff, historical implementations, old replays, historical session summaries, FINAL_REPLAY_REPORT.
- Forbidden to read other replay roots.
- Forbidden to replace Phase 0.5 selected real entry or main route; if the plan is overturned by code facts, write BLOCKED_PLAN_MISMATCH.
- Forbidden to claim core DONE after only doing helper/DTO/static guard.
- Forbidden to write `oracle_adjusted_coverage`.
- Forbidden to use online search; only local `rg`, `Get-Content`, `git`, Maven and other in-repo commands allowed.
- Forbidden to ask the user questions, wait for manual confirmation, or end early due to isolated worktree dirty state. In auto replay, must either advance this slice or write BLOCKED JSON.
- For slice 2+, when `git status` shows modifications/untracked files from previous slices, default to “Option 1: these changes are expected, continue executing on top of them”. Forbidden to output multiple-choice questions, wait for user confirmation, or treat expected dirty worktree as a blocker; only write BLOCKED JSON when the main workspace is written to, oracle is contaminated, or previous outputs logically conflict with this round's plan.
- When searching for test style, prefer searching class names, `@Test`, `SpringBootTest`, `Mockito`, `@Mock`, `@InjectMocks`, or specific file paths; avoid combining common English verb-call syntax into regex queries. If confirmation of call details is needed, locate the file first then read the source code.

【P0: Pre-Implementation Carrier Validation (CRITICAL BLOCKER)】

**BEFORE writing the RED test or GREEN implementation, you MUST validate the carrier:**

## Validation Steps

1. **Verify Carrier Exists in Baseline**
   - Run: `python scripts/verify_carrier_signature.py --input '{"plan_carrier": "YourCarrier.method", "worktree_path": "{{WORKTREE}}"}'`
   - Exit code 0 = PASS, Exit code 1 = FAIL
   - If FAIL: DO NOT proceed with implementation. Write BLOCKED JSON.

2. **Verify Exact Signature**
   - Extract the EXACT signature from your target carrier:
     - Method name: MUST match exactly
     - Parameters: MUST match in type and order
     - Return type: MUST match
     - Annotations: Check for @Transactional (required for stateful methods)

3. **Document Carrier Caller**
   - Who calls this method? (Controller, Facade, or another Service)
   - When is it called? (Request lifecycle, event handler, scheduled task)
   - What are the preconditions? (Case exists, user authenticated, etc.)

4. **Run Quality Gate**
   - Run: `.\scripts\v348_slice_quality_gate.ps1 -SliceDir {{REPLAY_ROOT}} -Worktree {{WORKTREE}} -WarnOnly`
   - Check for blocking issues before proceeding

## P0 Violation Consequences

If you proceed WITHOUT carrier validation:
- `gap_flags`: [`wrong_carrier`, `carrier_signature_mismatch`, `exact_contract_gap`]
- `slice_status`: "BLOCKED"
- `blocker`: "carrier_not_validated"
- `coverage_delta`: 0

## Allowed Flow

1. Extract exact carrier signature → 2. Write RED test with that signature → 3. Run Maven test → 4. Implement GREEN → 5. Run quality gate → 6. Verify side effects

**DO NOT invent signatures. DO NOT proceed without validation.**

---

## Test Hard Constraints — Must follow, otherwise slice will be rejected by verifier
1. Test files must be placed in `example-server/src/test/` directory, cannot be placed in `example-core/src/test/`. `example-core` has no test dependencies (JUnit, Mockito, Spring Test), only `example-server` does.
2. Package path example: `example-server/src/test/java/com/example/project/core/caseinfo/service/YourTest.java`
3. Correct import paths (confirm with `rg` or `Get-Content` before writing):
   - `com.example.project.domain.insurance.ExampleData` / `ExampleQuery` / `ExampleResult`
   - `com.example.project.domain.open.OpenExampleQuery`
   - `com.example.project.domain.ResultModel`
   - `com.example.project.core.exampleData.ExampleDataFacadeImpl`
   - `com.example.project.common.constant.Constant`
   - `com.example.project.domain.Pagination`
4. Mockito version is 1.10.19 (legacy version):
   - Use `org.mockito.Matchers` (not `ArgumentMatchers`)
   - Use `org.mockito.Matchers.any(ExampleQuery.class)` (not `any()`)
   - Use `org.mockito.Matchers.anySet()` (not `any()`)
   - `thenAnswer` lambda parameter is `invocation -> { ... }`
5. JUnit uses `org.junit.Assert` (not assertj): `assertEquals`, `assertTrue`, `assertNotNull`, `assertFalse`
6. Use `ReflectionTestUtils.setField(service, "fieldName", mock)` for dependency injection (not `@InjectMocks`)
7. After writing the test, must actually run `mvn -s {{MAVEN_SETTINGS}} -f {{WORKTREE}}\pom.xml test -pl example-server -am -Dtest=YourTest -Dsurefire.failIfNoSpecifiedTests=false` and confirm `BUILD SUCCESS`. If compilation fails, must fix to pass before continuing.
8. Forbidden to modify any `pom.xml`, forbidden to add new JUnit/Mockito/Spring Test dependencies. If `example-core` is missing test dependencies, this is not a fixable business diff; must place the RED test in `example-server`'s existing test harness.
9. If `FIRST_SLICE_PROOF_PLAN.md` only gives the test class name without path or module, default to creating the test in `example-server/src/test/java/...` and run with `-pl example-server -am`. Forbidden to change to `example-core/src/test` or `-pl example-core`.

## Test Contract Verification (MANDATORY)
Before writing tests, must verify the interface contracts in FIRST_SLICE_PROOF_PLAN and IMPLEMENTATION_CONTRACT:

1. **Return Type Alignment**: If the return type of `selected_real_entry` or `selected_carrier` is non-void (e.g., `SomeResponse`), the test must declare and assert the return value. Forbidden to write `void` tests for non-void entries (only asserting "no exception thrown" or "called a mock").

2. **Error Handling Alignment**:
   - If `pattern_error_handling:` or `interface_contract_error_handling:` specifies `response_codes`, test error scenarios must assert response code (e.g., `assertEquals("500", result.getCode())`), cannot use `catch (Exception e)` + `fail()` pattern.
   - If it specifies `exception_propagation`, tests must use exception-catching pattern.
   - Violating any of the above means the test receives no coverage credit, `gap_flags` must include `test_contract_mismatch`.

3. **Assertion Surface Alignment**: The test's assertion target must match the production entry's contract boundary. For public entries (Facade/Controller/API), assertions must land on response payload fields, not just on internal service mock verifies.

Any slice violating the above will be marked by the verifier with `test_contract_mismatch`, `return_value_vs_exception_mismatch`, or `assertion_surface_mismatch`, `coverage_delta=0`.

## Behavioral Test Requirements (EXPERIMENT_1)

Your RED phase tests must assert **expected business behavior**, not structural deficiencies. Tests will be classified as BEHAVIORAL or STRUCTURAL.

### BEHAVIORAL Tests (Required)

BEHAVIORAL tests assert expected business results: side effects, state changes, output.

**Keywords**: assert, verify, equals, populate, insert, update, generate, create, status, progress, compensate, select, mapper, dao, repository, transaction, rollback, persist, save, delete

**有效示例**:
- ✅ "When executeAutoFlow is called with valid flash case, 理算表 is populated with AI settlement_details"
- ✅ "When amount threshold is met, case status changes to 35"
- ✅ "When beneficiary data is complete, task is created with 1-day timeout"
- ✅ "When flow completes, 理算明细.png is generated at expected path"

## STRUCTURAL 测试（禁止作为 RED）

STRUCTURAL 测试只验证代码结构存在性，不足以驱动生产实现。

**关键词**: exists、notexist、ClassNotFoundException、NoSuchMethodException、file、not、file、missing

**禁止示例**:
- ❌ "Class ExampleFlowService does not exist yet"
- ❌ "Method executeAutoFlow throws ClassNotFoundException"
- ❌ "File example-server/src/main/java/.../ExampleFlowService.java is missing"

## 测试分类规则

每个测试方法将被分类。如果**所有**测试方法都是 STRUCTURAL，slice 将被拒绝：
- 设置 `gap_flags`: [`wrong_test_surface`, `behavior_test_charter_gap`]
- 设置 `slice_status`: "BLOCKED"
- 设置 `coverage_delta`: 0
- 设置 `blocker`: "no_behavioral_tests_found"

至少需要一个 BEHAVIORAL 测试才能继续 GREEN 阶段。

## RED 阶段要求

- 测试必须命名业务场景，而不是结构性缺失
- 测试方法名应以 `test<Scenario>_<ExpectedBehavior>()` 格式命名
- 测试内容必须包含断言期望的业务结果（副作用、状态变化、输出）
- 禁止使用 `@Test(expected = ClassNotFoundException.class)` 等结构性断言

## 验证命令

测试创建后，verifier 将检查：
1. 测试方法是否包含 BEHAVIORAL 关键词
2. 断言是否针对业务结果而非结构
3. 是否至少有一个测试方法断言副作用

如果验证失败，slice 将阻塞，不允许继续。

【No-Mock Gate For Stateful Families (EXPERIMENT_1)】

**CRITICAL: For stateful_side_effect family, mock-only implementations are STRICTLY FORBIDDEN.**

## 禁止的占位符模式

1. **TODO 注释** - 禁止在实现中使用 TODO：
   - ❌ `// TODO: 实际插入数据库`
   - ❌ `// TODO: 实现上传逻辑`

2. **占位符返回** - 禁止返回占位值：
   - ❌ `return null; // TODO`
   - ❌ `return ""; // placeholder`
   - ❌ `return new SomeResponse(); // 占位`

3. **抛出未实现异常** - 禁止抛出：
   - ❌ `throw new NotImplementedException()`
   - ❌ `throw new UnsupportedOperationException()`

4. **Mock DAO 响应** - 禁止使用 Mock DAO：
   - ❌ 在生产代码中使用 mock mapper 返回假数据

## stateful_side_effect family 必须包含

1. **真实 DB 操作**：
   - ✅ `mapper.insert(entity)`
   - ✅ `mapper.updateByExample(record)`
   - ✅ `mapper.deleteByPrimaryKey(id)`

2. **真实事务处理**：
   - ✅ `@Transactional` 注解
   - ✅ 真实的 rollback/commit 行为

3. **验证断言**：
   - ✅ 测试中用 `mapper.select()` 验证插入结果
   - ✅ 测试中用 `assertEquals()` 验证状态值

## 在声明 GREEN 前必须验证

1. 所有 DB 写入操作已实现
2. 没有 TODO 注释残留
3. 真实的 mapper 调用存在
4. 测试能验证 DB 状态变化

---

【EXPERIMENT 2: TODO Penalty and Coverage Credit (NEXT_EXPERIMENT_PLAN.md)】

**v373 Coverage Penalty 规则**：在 slice 完成时，runner 将自动计算并应用 coverage penalty。

### Penalty 计算

runner 执行以下检查（通过 `calculate-coverage-penalty.py`）：
1. **TODO 注释**：每个 TODO 扣 10% credit
2. **Placeholder 方法**：每个空方法/占位方法扣 20% credit
3. **总 penalty 上限**：100%

### Penalty 后果

| Penalty | Consequence |
|---------|-------------|
| ≤ 50% | Slice 授权继续，coverage 按比例下调 |
| > 50% | ❌ **BLOCKED** - slice 不被授权，必须修复 |

### 示例

假设 TODO=3，placeholder 方法=1：
- TODO penalty = 3 × 10% = 30%
- Placeholder penalty = 1 × 20% = 20%
- Total penalty = 50%
- Implementation credit = 50%
- 如果原始 `coverage_delta=60`，调整后 = 60 × 50% = **30**

### 避免 Penalty 的方法

使用**增量 TDD**（Test-Driven Development）代替 TODOs：

1. **先写测试**：指定期望的行为
2. **实现最小代码**：仅通过测试
3. **验证断言**：检查 DB 状态、副作用
4. **继续下一个行为**：重复以上步骤

❌ **错误**：用 TODO 标记未实现功能
```java
public void handle(Long caseId, ExampleApplyApiTask task) {
    // TODO: 验证参数
    // TODO: 写入补偿信息
    // TODO: 更新状态
    return true;  // placeholder
}
```

✅ **正确**：增量实现，每个步骤对应测试断言
```java
public void handle(Long caseId, ExampleApplyApiTask task) {
    // Test 1 验证：参数校验
    if (!isSupportedScope(task)) {
        return;  // 测试验证提前返回
    }
    // Test 2 验证：DB 写入
    CompensateInfo info = buildCompensateInfo(task);
    compensateInfoMapper.insert(info);  // 测试验证行存在
    // Test 3 验证：状态更新
    caseFlowStatusService.updateStatus(caseId, STATUS_READY);
}
```

---

## 如果无法在一个 slice 内实现真实 DB 操作

- 使用 `continue_s1_implementation` slice 类型
- 不要在没有真实实现时声明 GREEN
- 写 `PARTIAL` 而非 `DONE`，`next_recommended_slice_type` 指向继续实现

## 验证器检查

verifier 将在 GREEN 阶段前运行 `verify_green_phase.py`：
- 检测 TODO、placeholder、not implemented 等占位符
- 检测 mock-only 返回语句
- 验证 stateful family 是否有 DB 操作证据

如果检测到 mock-only 实现：
- `gap_flags`: `mock_only_implementation_gap`, `side_effect_ledger_gap`
- `slice_status`: "BLOCKED"
- `coverage_delta`: 0
- `blocker`: "mock_only_implementation_not_allowed"

【执行纪律】
1. 先确认 cwd 是 isolated worktree。
2. 读取 PHASE0_RESULT.md，必须是 `PROCEED`。
3. 读取 PLAN_RESULT.md，必须是 `PROCEED`。
4. 读取 REPLAY_PLAN.md、IMPLEMENTATION_CONTRACT.md、EXPECTED_DIFF_MATRIX.md、SIDE_EFFECT_LEDGER.md、TEST_CHARTER.md、FIRST_SLICE_PROOF_PLAN.md。
5. 读取 SURFACE_CARRIER_SCAN.md，并优先选择已有生产承载点；如果 forced family 在 scan 中没有合适承载点，必须记录 `carrier_search_terms`、源码搜索证据和 blocker/cap。
   - v270 carrier-search enforcement：在写任何新 service/helper 前，必须核对 `PLAN_RESULT.md` 的 `carrier_search_queries`、`existing_production_carriers`、`selected_carrier_from_search`、`new_service_proposed`、`new_service_justification`。如果 `selected_carrier_from_search` 没有来自搜索结果，或计划新建 service 但 justification 不是 orphan/new-boundary/incompatible-existing-carriers 级别理由，不得编码，直接写 `BLOCKED_PLAN_MISMATCH`，`gap_flags` 包含 `carrier_search_unproven`、`wrong_test_surface`、`tooling_enforcement_stop`。
6. 根据 FAMILY_CONTRACT.json、SLICE_PROGRESS、REQUIREMENT_FAMILY_LEDGER 与已有 SLICE_RESULT/VERIFY，选择下一个最高权重未完成 slice。
7. 如果 `forced requirement family` 非空，本 slice 必须优先执行该 family 和 `forced slice type`；如果 `forced sibling surface` 非空且不是 `none`，本 slice 必须优先关闭这个具体 sibling surface。`machine_command_forced_family`：forced family 是 runner 的机器指令，不是建议；禁止因为更容易而改做较低权重 helper、DTO、validator、常量、字段校验或静态 guard。只有代码事实证明不可执行时，才能写 BLOCKED，并在 `gap_flags` 加 `gate_present_but_not_enforced` 与具体 blocker。
   - forced family 偏离处理：若你已经开始实现了非 forced family，必须立刻停止并改回 forced family；不能把非 forced family 当作本 slice 的 DONE/PARTIAL 证据。确实无法改回时，写 `BLOCKED`，`coverage_delta=0`，`gap_flags` 包含 `tooling_enforcement_stop`、`no_progress_slice`，并解释为什么 forced family 不可执行。
8. replay worktree 在 slice 2+ 中会包含前序 slice 的已修改/未跟踪文件，这是本轮上下文的一部分；你已被授权在保留这些改动的前提下继续执行。必须读取已有 `SLICE_RESULT/VERIFY/PROGRESS` 后在其基础上继续，不得因为前序 slice diff、未跟踪文件、测试文件或新增生产文件而停下向用户确认。只有发现主工作区被写入、oracle 污染、或前序 slice 与本轮计划发生不可调和冲突时，才写 BLOCKED。
9. 编码前必须读取 `{{CARRIER_AUTHORIZATION}}`、`{{CARRIER_RANK}}`、`{{EXACT_CONTRACT_ASSERTION_MATRIX}}`、`{{NEXT_SLICE_EXACT_CONTRACT}}`、`{{SIDE_EFFECT_EVIDENCE}}`：
    - 如果 carrier authorization 不是 `ALLOW`，不得编码，直接写 `BLOCKED`，`gap_flags` 包含 `carrier_authorization_stop`。
    - `{{CARRIER_RANK}}` 中 rank 1 的 required OPEN/PARTIAL family 是本 slice 的最高优先级生产承载点。若 forced family/sibling 与 rank 1 冲突，必须以 runner 给出的 forced sibling 为准；禁止自行降级到 helper、DTO、常量、静态枚举或非边界 sibling。
    - 必须重新核对 `FIRST_SLICE_PROOF_PLAN.md` 中的 `real_carrier_kind`、`minimum_side_effect_or_blocker`、`forbidden_substitute_check`。`real_carrier_kind` 不是生产入口/服务/controller/mapper/payload/template/lifecycle 承载点，或 `forbidden_substitute_check` 不是 `passed` 时，不得写生产 diff。
    - 第一片必须从 `FIRST_SLICE_PROOF_PLAN.md` / `IMPLEMENTATION_CONTRACT.md` 原样复制 `selected_real_entry`、`selected_carrier`、`first_red_test`。如果计划写明 `TaskServiceTransformCaseTaskPolicyTest`，就必须创建/运行这个测试；测试文件不存在时创建 RED 测试或写 `BLOCKED_PLAN_MISMATCH`，禁止替换成另一个需求/另一个 family 的测试类。
    - 如果 `SOURCE_CHAIN_CONTRACT.json.required_source_chain=false`，禁止选择 `ExampleDataAssemblyHelper`、`InputData.policy_num`、`InputData.insure_num`、`AiPolicyNumSourceChainTest` 之类 source-chain carrier；这些只能在 source-chain contract 明确为 true 时使用。
    - `selected_carrier -> production_boundary -> expected failing assertion -> command -> fail_closed_condition` 五项必须能连起来；如果只能新增日志型、委托型、占位型或 helper-only carrier，直接写 `PARTIAL/BLOCKED`，`coverage_delta=0`。
   - exact-contract 只允许业务可断言项：页码/窗口数、请求字段、响应字段、payload shape、展示值、状态写入、顺序、must-not side effect。规划文件名、路径、模块名、phase/status、branch/commit/hash、generic gap flag 都不是 literal。
   - 如果本 slice 触碰 exact-contract family，必须在 `SLICE_RESULT` 写 `exact_contract_assertions`，每项包含 `literal`、`symbol_or_field`、`db_or_wire_or_display`、`boundary_type`、`production_boundary`、`closure_proof`、`production_predicate`、`forbidden_extra_predicate`、`test_assertion`、`source_type=requirement|code_fact`、`status=CLOSED|BLOCKED`。`production_predicate` 只能包含需求字面量要求的判断；若新增状态、渠道、类型、环境、旧链路等额外谓词，必须在 `forbidden_extra_predicate` 写出并提供“该谓词由生产入口逻辑必然推出”的可执行证明，否则本 slice 只能 `PARTIAL/BLOCKED`，不得关闭 family。
   - v270 exact-contract threshold：如果 `{{EXACT_CONTRACT_ASSERTION_MATRIX}}` 中 `required_for_this_slice=true` 或 rows 中存在 `touched=true`，本 slice 必须关闭至少一半 touched/required exact rows；低于 50% 时 `coverage_delta=0`，`gap_flags` 包含 `exact_contract_minimum_coverage_gap`。
   - 如果 `{{NEXT_SLICE_EXACT_CONTRACT}}` 的 `decision` 不是 `ALLOW`，不得编码，直接写 `BLOCKED`，`gap_flags` 包含 `next_slice_exact_contract_not_ready` 和 `tooling_enforcement_stop`。
   - `{{NEXT_SLICE_EXACT_CONTRACT}}` 中的每一行都是本 slice RED 前必须执行的最小契约子集；不得用 broad rows（git diff/show、文件路径、phase/status、coverage、gap flag）替代业务断言。
   - 对 payload、DB、callback、exchange、queue、display、导出/页面契约，`closure_proof` 必须是 wire/db/display/output 边界断言；enum-only、DTO-only、helper-only、static-only、mock-only 只能算 supporting evidence，不能写 CLOSED。
   - 如果本 slice 触碰 core/stateful family，必须更新 `{{SIDE_EFFECT_EVIDENCE}}`，写入 `status=READY|CLOSED|BLOCKED`、`entry_call`、`expected_writes_or_outputs`、`must_not_writes`、`test_name`、`red_result`、`green_result`。`red_result` 只有业务断言失败才写 `BUSINESS_ASSERTION_FAILED`；编译、参数、0 tests、环境问题都不能伪装成业务 RED。
   - v270 stateful side-effect evidence：凡 `expected_writes_or_outputs` 涉及 DB/state/task/progress/log/transaction/update/insert/delete/save/persist，`closed_assertions` 或 `side_effect_evidence` 必须包含可执行 DB/state 查询或真实输出断言；只写 mock verify、日志、返回字符串或“not implemented”失败，一律不能关闭 family。
   - 对 stateful suppression / skip / guard 类需求，`must_not_writes` 不只包括目标 insert/timeout，还必须覆盖 guard 之前会发生的状态、任务、进度、日志、清理、过期、update/delete/save 等写入；如果 `SIDE_EFFECT_EVIDENCE` 已列出 pre-guard write（例如某个 update/expired/cleanup 调用），本 slice 必须用 RED/GREEN 证明该写入被抑制或写明为什么 preserve/out_of_scope。
10. 编码前必须读取 `{{PRE_SLICE_CAP_DISPLAY}}`。如果本 slice 无法用可执行证据关闭 forced family，则 `coverage_delta` 必须为 0，且不得把相关 family 写入 `closed_requirement_families`。不要把“类/方法存在、TODO、空实现、只是不抛异常”当成突破 cap 的证据。
11. 如果上一 slice 是 `tracer_bullet_only`，本 slice 必须优先选择：
   - `stateful_success_slice`，或
   - `deploy_surface_first_slice`。
   不能继续扩 helper/DTO/常量/static guard。
11. 如果已有 slice 已覆盖真实入口与最小 stateful success，而 `SLICE_RESULT/VERIFY` 中仍有 `deploy_surface_contract_gap`、`executable_surface_slice_gap`，或 `next_recommended_slice_type=deploy_surface_first_slice`，本 slice 必须选择 `deploy_surface_first_slice`，除非写明 blocker。
    - deploy/export/page slice 必须以 `{{CARRIER_AUTHORIZATION}}` 的 `selected_carrier` 为准闭合 route/output 证据。若授权 carrier 写明 controller、route、endpoint、export、download、workbook、Excel 等输出边界，只测 facade/service/mapper/source-row projection 不能授权；必须写 `PARTIAL/BLOCKED`，`gap_flags` 包含 `wrong_test_surface` 与 `deploy_surface_contract_gap`。
12. 不允许连续三个 slice 都只修改同一 core/service/log test 家族。达到该条件时，必须切到报表/导出/模板/图片/OCR/外部 payload/API/controller/mapper 等 deploy-facing 承载点之一，或把该 surface 标为 BLOCKED 并降 coverage。
13. 如果 forced family 是 core_entry/stateful_side_effect 且仍有 open sibling surfaces，本 slice 必须先补其中一个具体副作用 sibling；不能只新增日志、常量、DTO 或 mock-only 断言。
14. 如果本 slice 没有关闭或推进 REQUIREMENT_FAMILY_LEDGER 中任何 OPEN/PARTIAL family，`coverage_delta` 必须为 0，`gap_flags` 必须包含 `no_progress_slice`。
15. 严格 TDD：先写/调整 RED，运行并记录失败，再最小 GREEN。`DONE` 必须至少有一条 `phase=RED,result=fail` 的测试证据；如果 RED 命令因 PowerShell 参数解析、`-Dtest`、`-Dsurefire...` 或 wrapper 参数问题被阻断，必须立刻用 `mvn --% -s ... -f {{WORKTREE}}\pom.xml ...` 重放同一个 RED，再决定是否编码。不能把“RED 命令 blocked”当成可接受 RED，也不能在没有 RED fail 的情况下进入 GREEN；若重放仍非业务断言失败，写 BLOCKED 或 PARTIAL，并在 `gap_flags` 写 `tdd_red_not_replayed`、`feedback_loop_blocker`。
16. Maven 必须带 `-s {{MAVEN_SETTINGS}}` 和 `-f {{WORKTREE}}\pom.xml`。
17. 不允许修改主工作区 {{PROJECT_ROOT}}。

【生产承载点规则】
- `target_subsurface_or_carrier` 必须是已有生产入口/承载点，或清楚说明由哪个已有生产入口调用的新实现边界。
- 对 core/stateful/artifact 等高权重 family，禁止用 `Noop`、`Stub`、`Fake`、`Dummy`、`Placeholder`、`Mock`、`InMemory`、`TestOnly`、`Scaffold` 等替代/占位生产类作为关闭证据。若确实需要新建生产承载类，类名和职责必须是领域真实能力，不得是临时适配或空实现；同 slice 还必须改到既有生产入口并验证真实副作用/输出。
- 第一片或高权重 slice 不得用空方法、只有注释的方法、protected override seam、测试子类计数器、`get*Count()`、`invokeCount`、helper-only 调用或 subclass-only proof 作为行为证据。若真实入口只能新增一个空 hook 或测试 override 才能变绿，必须写 `BLOCKED_PLAN_MISMATCH` 或 `PARTIAL`，`gap_flags` 写 `tooling_enforcement_stop`、`wrong_test_surface`、`synthetic_carrier_gap`，`coverage_delta=0`，不要继续实现同类浅层 hook。

【行为承载点 vs 数据承载点门禁 (v263)】
当需求涉及行为（MQ/push/send/callback/notify/event/queue/消息/推送/通知/发送/回调）时，以下规则强制生效：

1. **禁止数据型承载点**：`target_subsurface_or_carrier` 不能是 enum、DTO、constant、字段映射类。即使这些类被需求引用，它们只能是辅助证据，不能作为 `core_entry` 或行为 family 的关闭证明。

2. **Facade 方向验证**：如果 `selected_carrier` 包含 `Receive`/`Push`/`Send`/`Callback`/`Notify` 方向词，必须在 `SLICE_RESULT` 中写明搜索了反方向的 Facade 并说明排除理由。格式：`searched_opposite_direction: rg -i "XXXFacade" -> found YYY, excluded because ...`。

3. **行为入口点证据**：`downstream_side_effect_or_output` 或 `SIDE_EFFECT_EVIDENCE` 中提到的行为（如 "MQ push"、"send message"、"notify event"）必须有对应的行为入口点（Service/Handler/Listener/Consumer/Producer）作为 carrier，不能只由数据定义触发。

4. **side_effect entry_call 验证**：`SIDE_EFFECT_EVIDENCE.entry_call` 必须指向行为执行者（Service/Handler/Listener），不能指向 enum/DTO/constant。

违反以上任何一条的 slice 将被 `BEHAVIOR_CARRIER_FACADE_VALIDATION` 门禁标记 `behavior_carrier_gap` 或 `facade_direction_gap`，`coverage_delta=0`，family 不能关闭。
- 对第一片 core-entry proof，`target_subsurface_or_carrier` 必须绑定真实生产 carrier，并在 `production_boundary` 或 `closed_assertions` 中写明至少一个下游生产服务调用、状态/落库副作用、外部输出、真实 payload shape、导出/模板输出之一。仅证明“入口调用了一个可被测试子类覆盖的方法”不能关闭 family。
- 如果本轮存在 `SOURCE_CHAIN_CONTRACT.json` 且 `required_source_chain=true`，只能实现其中 `next_required_slice` 指定的 source-chain。测试必须从真实 source/service/request 构造链路产生值；用 reflection、手工 set taskData、手工构造 downstream DTO 只能标记 `synthetic_carrier`，不得关闭 source-chain/core family。
- `implemented_files` 若只有 `src/test`、新 helper、新 DTO、常量或静态文件存在断言，不得把 family 写入 `closed_requirement_families`。
- 如果仍有 `required_sibling_surfaces`，本 slice 最多 `PARTIAL`；不要写 `DONE`。
- `required_sibling_surfaces` 必须按 family 归属写成 `family_id: sibling surface`，例如 `deploy_export_page: /case/export controller workbook assertion`。禁止把一个 deploy/export sibling 写到 stateful/config/artifact family 上。
- 对 stateful family，`closed_assertions` 至少覆盖状态/任务/进度/日志/落库/事务或失败隔离中的 4 类；否则必须保留 `side_effect_ledger_gap`。

【slice 完成定义】
每个 slice 必须尝试闭合：
`真实入口/承载点 -> 编排 -> 读写/状态/任务/进度/日志/输出副作用 -> must-not -> 可执行验证`

【覆盖率诚实门禁】
- 如果 `gap_flags` 包含 `wrong_test_surface`、`core_entry_unclosed`、`side_effect_ledger_gap`、`non_authorizing_evidence`、`proof_type_mismatch`、`tooling_enforcement_stop`、`mock_behavior_gap`、`synthetic_carrier_gap`、`shallow_module`、`exact_contract_gap` 或 `deploy_surface_contract_gap`，本 slice 不能写 `slice_status=DONE`，不能把相关 family 写入 `closed_requirement_families`，`coverage_delta` 必须为 0。
- 只有 `SLICE_VERIFY` 预期可授权 synthesis 的证据，才允许在 `coverage_delta` 中贡献正向覆盖。静态断言、helper-only、mock-only、DTO/常量/字段存在、测试子类计数器、只证明入口调用新方法，都只能写 supporting evidence。
- 自评覆盖率必须跟随生产边界证据。若本 slice 没有真实生产入口、真实副作用/输出、RED/GREEN、proof type 匹配四项同时成立，必须把 `remaining_gaps` 写清楚，并主动降为 `PARTIAL/BLOCKED`。

如果只能完成入口 hook、负向隔离、placeholder service 或 mock-only 断言，必须标记：
- `tracer_bullet_only`
- `side_effect_ledger_gap` 或 `executable_surface_slice_gap`
- `next_recommended_slice_type`

【必须写入】
1. `{{SLICE_RESULT}}`，必须是纯 JSON，不要 Markdown fence。
2. 更新 `{{SLICE_PROGRESS}}`。
3. 追加 `{{SLICE_PROGRESS_MD}}`。
4. 禁止直接写 `REQUIREMENT_FAMILY_LEDGER.json` 或 `{{SLICE_VERIFY}}`；这两个文件由 runner/verifier 统一生成。

【SLICE_RESULT JSON schema】
```json
{
  "slice_index": {{SLICE_INDEX}},
  "slice_id": "S1",
  "slice_title": "",
  "slice_type": "tracer_bullet | stateful_success_slice | deploy_surface_first_slice | exact_contract_slice | blocker",
  "slice_status": "DONE | PARTIAL | BLOCKED | INVALID_REPLAY",
  "coverage_delta": 0,
  "target_subsurface_or_carrier": "",
  "required_sibling_surfaces": [],
  "production_boundary": "",
  "proof_kind": "real_entry_behavior | stateful_side_effect | route_export_behavior | payload_shape_behavior | generated_artifact_behavior | lifecycle_cleanup_behavior",
  "real_carrier_kind": "production_entry_or_service | production_controller_or_route | production_mapper_or_query | production_payload_builder | production_template_or_artifact_renderer | production_lifecycle_cleanup",
  "forbidden_substitute_check": "passed | failed:<reason>",
  "red_expectation": "",
  "implemented_files": [],
  "current_slice_changed_files": [],
  "round_changed_files_snapshot": [],
  "tests": [
    {"command": "", "phase": "RED|GREEN|VERIFY", "result": "pass|fail|blocked", "evidence": ""}
  ],
  "exact_contract_assertions": [
    {"literal": "", "symbol_or_field": "", "db_or_wire_or_display": "", "boundary_type": "wire|db|display|payload|callback|behavior", "production_boundary": "", "closure_proof": "", "production_predicate": "", "forbidden_extra_predicate": "", "test_assertion": "", "source_type": "requirement|code_fact", "status": "CLOSED|BLOCKED"}
  ],
  "side_effect_evidence": {
    "status": "CLOSED|BLOCKED",
    "entry_call": "",
    "expected_writes_or_outputs": [],
    "must_not_writes": [],
    "test_name": "",
    "red_result": "BUSINESS_ASSERTION_FAILED|BLOCKED|NOT_RUN",
    "green_result": "PASS|BLOCKED|NOT_RUN"
  },
  "behavior_test_charter": {
    "proof_kind": "transaction_side_effect|db_persistence|status_progress_log|export_page_output|wire_payload|generated_artifact_upload|external_integration|async_lifecycle_cleanup|real_entry_behavior",
    "production_entry": "",
    "state_or_output": "",
    "must_not": "",
    "RED_command": "",
    "expected_RED_failure": "",
    "GREEN_command": "",
    "evidence_file": ""
  },
  "closed_assertions": [],
  "must_not_assertions": [],
  "remaining_gaps": [],
  "gap_flags": [],
  "touched_requirement_families": [],
  "closed_requirement_families": [],
  "blocker": "",
  "next_recommended_slice_type": "stateful_success_slice | deploy_surface_first_slice | exact_contract_slice |"
}
```

`DONE` 额外要求：
- `target_subsurface_or_carrier` 必须是具体 endpoint / service method / mapper query / template-render boundary / task processor / request builder，而不是粗粒度 family 名。
- `production_boundary` 必须说明真实生产边界；仅 helper/static_contract 不能关闭 family。
- `red_expectation` 必须说明 RED 应该失败在哪个行为断言；RED 未失败或 0 tests run 时不得写 DONE。
- `proof_kind` 必须能匹配当前 family 在 `FAMILY_CONTRACT.json.proof_required` 中要求的 proof type；弱于 family contract 的 proof 只能写 PARTIAL/BLOCKED，不能写入 `closed_requirement_families`。
- 如果同一 family 有 sibling surfaces，必须在 `required_sibling_surfaces` 列出剩余项，未全部闭合时 family 只能 PARTIAL。

【退出】
只完成一个 slice 后停止。不要继续做下一 slice，不要写 FINAL_REPLAY_REPORT，不要读 oracle。
## v275 RED Business Assertion Gate

Before editing any production file or test file, you must run the planned RED command for the selected production carrier.

Authorizing RED means all of the following are true:
- the command executed, not just attempted;
- the test result is `fail`;
- the failure is a business assertion failure against the selected production carrier or observable output;
- the failure is not caused by PowerShell parsing, Maven argument parsing, zero tests, missing dependency, compilation failure, environment setup, or a wrapper/tooling error.

If a RED command is blocked by PowerShell/Maven parsing, retry the same RED with `mvn --% -s {{MAVEN_SETTINGS}} -f {{WORKTREE}}\pom.xml ...` before any edit. If the retry is still not a business assertion failure, stop the slice.

When RED is blocked, passes, runs zero tests, or fails for non-business tooling reasons:
- do not edit production files;
- do not edit test files;
- write `{{SLICE_RESULT}}` immediately with `slice_status: "BLOCKED"` or `"PARTIAL"`, `coverage_delta: 0`, `implemented_files: []`, `current_slice_changed_files: []`, `round_changed_files_snapshot: []`;
- include `gap_flags`: `tdd_red_not_replayed`, `feedback_loop_blocker`, `tooling_enforcement_stop`;
- set `side_effect_evidence.red_result` to `BLOCKED`;
- set `blocker` to `red_business_assertion_not_observed`.

If any file is edited after a blocked RED, the verifier will set `implementation_after_blocked_red`, `implementation_allowed=false`, `coverage_cap=0`, and `adjusted_coverage_delta=0`.

## v276 RED Repair and Behavior Test Charter Gate

This section supersedes the v275 "do not edit test files" rule only for test-only RED repair. It does not authorize production edits.

If the planned RED command is blocked by shell/Maven parsing:
- retry the same RED command with the project PowerShell form first;
- if the retry is still blocked, stop with `slice_status: "BLOCKED"` and no file edits;
- if the retry runs but passes, you may perform test-only RED repair.

If the planned RED command runs but passes before production code changes:
- do not edit production files yet;
- you may create or adjust only the focused test file named by `first_red_test` / `side_effect_evidence.test_name`;
- the repaired test must assert the selected real carrier's observable behavior, state, output, payload, or side effect;
- rerun the repaired RED command and record a later `{"phase":"RED","result":"fail"}` entry before any production edit;
- if you cannot create a business RED without changing production code, stop with `blocker: "red_business_assertion_not_observed"`.

Every high-weight family touch must write `behavior_test_charter` in `{{SLICE_RESULT}}`. Required fields:
- `proof_kind`
- `production_entry`
- `state_or_output`
- `must_not`
- `RED_command`
- `expected_RED_failure`
- `GREEN_command`
- `evidence_file`

The charter must not be mock-only, helper-only, static-only, file-presence-only, mapper-presence-only, or placeholder proof. Missing or non-authorizing charters force `behavior_test_charter_gap`, `wrong_test_surface`, zero adjusted coverage, and no family closure.

---

## v379 Test Charter Pre-Validation Gate (MANDATORY BEFORE RED)

**CRITICAL: Your TEST_CHARTER.md must pass validation BEFORE you write any test code.**

### Required Charter Sections

Your TEST_CHARTER.md must contain ALL of the following sections:

1. **Entry Point**: Exact Facade/Controller method to test
   - Format: `Entry Point: YourFacade.yourMethod(paramTypes)`
   - Example: `Entry Point: ExampleAutoClaimFlowFacade.executeAutoFlow(ExampleApplyApiTask)`

2. **Test Surface**: Test class at Facade/Controller layer, NOT Service layer
   - ✅ Correct: `ExampleAutoClaimFlowFacadeTest` or `ExampleAutoClaimFlowControllerTest`
   - ❌ Wrong: `ExampleFlowServiceTest` (Service layer - cannot verify full request/response flow)

3. **DB Verification**: SELECT queries for each side effect
   - Example: `SELECT * FROM t_compensate_detail WHERE case_id = ?`
   - Or: `AtomicReference<CompensateInfo> infoRef = new AtomicReference<>();`

4. **Transaction Test**: Rollback scenario for stateful operations
   - Required for operations with DB side effects
   - Example: `@Transactional test with expected rollback`

5. **Side Effects**: List with verification method
   - Each side effect must have verification (assert, verify, SELECT query, or AtomicReference)

### Validation Gate

Before starting RED phase, the `test_charter_prevalidator.py` script will validate your TEST_CHARTER.md:

```bash
python3 test_charter_prevalidator.py TEST_CHARTER.md --output json
```

If validation FAILS, you MUST:
1. Read the failure report
2. Fix your TEST_CHARTER.md
3. Re-run validation
4. Only proceed to RED phase after validation passes

### Example Validation Failures

#### WRONG_TEST_SURFACE (common)
```
❌ [WRONG_TEST_SURFACE]: Testing Service layer instead of Facade/Controller layer
   Required: Move test to Facade or Controller layer matching planned entry
```

#### MISSING_ENTRY_POINT
```
❌ [MISSING_ENTRY_POINT]: Entry point not specified in test charter
   Required: Add "Entry Point: YourFacade.yourMethod()" section
```

#### SIDE_EFFECTS_NOT_VERIFIED
```
❌ [SIDE_EFFECTS_NOT_VERIFIED]: Side effects listed but no verification method specified
   Required: Each side effect must have verification (assert, verify, SELECT query, or AtomicReference)
```

### Do NOT Proceed Without VALID Test Charter

If the validator fails with any FAIL code:
- **STOP** - Do not write RED test
- **FIX** - Update TEST_CHARTER.md to address failures
- **REVALIDATE** - Run validation again
- Only continue when status is `PASS`

This gate prevents the anti-pattern where RED tests are written at the wrong layer or without proper side effect verification, leading to `wrong_test_surface` and `side_effect_ledger_gap` flags.

---

## Phase 1 Implementation Gates (STRICT ENFORCEMENT)

These gates are MANDATORY workflow constraints. Violations will cause automatic rejection.

### Pre-Implementation Contract Verification Gate (CRITICAL)

**BEFORE writing any test or implementation code, you MUST verify exact service method signatures.**

For each service method you plan to reference:
1. Read the actual service file using the Read tool with full path
2. Verify the method exists with exact signature
3. Note the exact parameter types and return type

#### Example wrong pattern (DO NOT DO THIS):
```java
// You assume this exists
compensateService.batchInsertCompensateDetail(list);
```

#### Example correct pattern:
```java
// Step 1: Read example-core/.../CompensateService.java
// Step 2: Find: public void rewriteCompensateData(Long caseId, List<DetailBundle> bundles)
// Step 3: Use verified signature
compensateService.rewriteCompensateData(caseId, bundles);
```

#### Rule:
If you cannot find the exact method signature, **declare BLOCKED** and do not proceed with assumption.

---

### TODO Placeholder Ban (CRITICAL)

**TODO placeholders are FORBIDDEN in implementation code.**

#### If you don't know how to implement a feature:

1. Declare the slice **BLOCKED**
2. Explain EXACTLY what information you need
3. **Do NOT write TODO comments**

#### Examples of FORBIDDEN patterns:
```java
// ❌ FORBIDDEN
// TODO: 实现完整的自动流程逻辑

// ❌ FORBIDDEN
// TODO: 验证受益人数据

// ❌ FORBIDDEN
// TODO: 写入理算明细

// ❌ FORBIDDEN
public void process() {
    // TODO: implement this
}
```

#### Correct pattern when implementation unknown:
```
BLOCKED: Cannot implement compensate write without verifying CompensateService.rewriteCompensateData() method signature.
Required: Read CompensateService.java to confirm signature.
```

#### Verification:
The `todo_detector.py` script will automatically reject any code containing TODO placeholders.

---

### Carrier Search Requirement

**Before creating new service classes:**

1. Search for existing carriers with: `rg "class.*{Feature}Service"`
2. Read the found file to verify it cannot serve the use case
3. Only create new carrier if existing carriers are genuinely insufficient

#### Rule:
- First preference: Use existing service
- Second preference: Extend existing service
- Last resort: Create new service (with justification)

#### Penalty:
-50% coverage for unverified new carriers (no carrier search performed)

---

### Test Surface Verification

**When writing RED phase tests:**

1. Test methods must match the planned entry from TEST_CHARTER.md
2. Use descriptive test method names (min 8 characters, excluding "test" prefix)
3. Generic names like `test()`, `testMethod()` are **FORBIDDEN**

#### Example:
```
# If planned entry is "rewriteCompensateData"
✅ GOOD: testRewriteCompensateData_success()
✅ GOOD: testRewriteCompensateData_withEmptyList()
❌ BAD: test()
❌ BAD: testMethod()
```

---

### Side Effect Verification

**Before completing GREEN phase:**

Ensure all side effects have executable proof:

1. **Database operations** (insert/update/delete) → Test verifies row count/field values
2. **External service calls** → Test uses mock and verifies call parameters
3. **State changes** → Test asserts before/after state
4. **Exception handling** → Test covers exception branch

#### Rule:
If a side effect cannot be verified with executable test, mark slice as BLOCKED.

---

### Summary Checklist (MANDATORY)

Before completing any slice:

- [ ] All service method signatures verified by reading actual files
- [ ] No TODO placeholders in implementation
- [ ] Existing carriers searched before creating new service
- [ ] Test methods have descriptive names matching planned entry
- [ ] All side effects have executable test assertions
- [ ] Implementation is complete (no placeholder methods)

**Violations will result in automatic rejection by verification scripts.**
