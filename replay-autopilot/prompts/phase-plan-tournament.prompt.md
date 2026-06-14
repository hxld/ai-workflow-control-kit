你现在执行 Phase 0.5 Plan Tournament。只做规划，不写生产代码、不写测试代码、不跑 Maven。

【Evolution Version Verification (Experiment 1 from NEXT_EXPERIMENT_PLAN.md)】
- EVOLUTION_VERSION: Check the evolution version loaded by the runner
- If you are using surface validation or new service authorization rules, verify that evolution version is >= v427
- If version is < v427, those rules are NOT available and you must NOT apply them
- Current loaded evolution version should be available in environment or runner metadata

【Fixed Context】
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
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- plan candidate count: {{PLAN_CANDIDATE_COUNT}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}

【Goal】
Based on the exploration facts from Phase 0, generate multiple candidate implementation plans, evaluate by unified rules, and finally freeze an executable implementation contract for Phase 1. Strong planning, low exploration coding.

【Allowed to Read】
1. requirement_source.
2. repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml.
3. isolated worktree current code.
4. Current replay root at `EXPLORATION_REPORT.md`, `ROUND_CONTRACT.md`, `PHASE0_RESULT.md`, `FAMILY_CONTRACT.json`, `CONTEXT_MANIFEST.md`.
5. `{{BASELINE_INDEX}}`, but only as a neutral structural index.
6. `{{SURFACE_CARRIER_SCAN}}`, but only as a neutral list of production carrier candidates; each candidate must still be confirmed by reading source code.
7. `{{CONTEXT_MANIFEST}}` listed read-only system context files; only as general project background.
8. `{{ORACLE_DIFF_ANALYSIS}}`, structured analysis of oracle commit diff (file list, layer classification, weight), used to constrain plan alignment with actual oracle changes.

It is forbidden to read feature documentation directories outside the snapshot where requirement_source is located; do not run `rg` / `Get-ChildItem` / batch reads on `.doc\<feature>` or original requirement parent directories. If requirement facts are needed, only read the `requirement_source` single-file snapshot given in this prompt.

【Forbidden】
- Forbidden to directly read oracle branch/commit or run `git diff`/`git log`/`git show` to access oracle commit (only allowed to read the preprocessed structured analysis in `{{ORACLE_DIFF_ANALYSIS}}`). Forbidden to read historical implementations, old replays, historical session summaries, FINAL_REPLAY_REPORT.
- Forbidden to modify production code, test code, configuration, SQL, frontend files.
- Forbidden to run Maven/tests/builds.
- Forbidden to write candidate plans as generic task lists; each high-weight slice must land on real entry points, file families, verification points, and stop conditions.

【Must Do First】
1. Read `{{REPLAY_ROOT}}\PHASE0_RESULT.md`.
2. If `phase0_status` is not `PROCEED`, do not plan implementation, write `PLAN_RESULT.md`, `plan_status=INVALID_PLAN`.
3. Read `{{REPLAY_ROOT}}\EXPLORATION_REPORT.md` and `{{REPLAY_ROOT}}\ROUND_CONTRACT.md`.
4. Read `{{REPLAY_ROOT}}\FAMILY_CONTRACT.json`.
5. Read `{{SURFACE_CARRIER_SCAN}}`, include the required family's candidate production carriers in the candidate plan.
6. If any of the above files are missing, write `PLAN_RESULT.md`, `plan_status=BLOCKED`.

【Oracle Feature Domain Compatibility Check (MANDATORY v347)】

在执行 "Oracle-Constrained Planning" 之前，必须先检查 oracle 与需求的功能域是否兼容。

1. Read `{{ORACLE_DIFF_ANALYSIS}}`, extract functional domain keywords from oracle file paths:
   - `ai/` / `Example` / `ExampleAuto` / `AiReview` → workflow domain
   - `push/` / `ExamplePush` / `PushService` → external push domain
   - `compensate/` / `CompensateTable` → settlement domain
   - `route/` / `CaseRoute` → case routing domain
   - `refund/` / `RefundTicket` / `ExampleTicket` → callback domain

2. Read `{{REQUIREMENT_SOURCE}}`, extract functional description keywords from the requirement:
   - Feature name in the title (e.g., "workflow", "callback processing")
   - Core domain terminology (e.g., "exempt review amount", "callback reason")

3. **Domain Compatibility Judgment**:
   - Count the number of files in each functional domain in oracle files
   - Determine primary domain: the domain with the most files
   - Calculate non-primary domain file ratio: `foreign_ratio = non_primary_count / total_oracle_files`
   - If `foreign_ratio > 30%` → `domain_compatibility: MISMATCH`
   - If oracle primary domain differs from requirement primary domain → `domain_compatibility: MISMATCH`
   - Otherwise → `domain_compatibility: COMPATIBLE`

4. **Must include in `PLAN_RESULT.md`**:
   - `oracle_primary_domain:` <extracted oracle primary domain>
   - `requirement_primary_domain:` <extracted requirement primary domain>
   - `domain_compatibility:` COMPATIBLE | MISMATCH | UNCERTAIN
   - `foreign_domain_ratio:` <non-primary domain file percentage>

5. If `domain_compatibility: MISMATCH`, forbidden to generate candidate plans, directly write `PLAN_RESULT.md` and set:
   - `plan_status=BLOCKED`
   - `blocker: oracle_feature_domain_mismatch`
   - Explain conflicting file list and conflict reason in `PLAN_RESULT.md`

【Oracle-Constrained Planning (MANDATORY)】

在生成候选计划之前，你 MUST 先完成以下 oracle 对齐步骤：

1. Read `{{ORACLE_DIFF_ANALYSIS}}` to understand which files were actually modified in the oracle commit.
2. List all oracle production files (non-test files), and determine the layer (DTO/Enum/Service/Mapper/Controller/Resource) for each file.
3. Sort oracle production files by weight: HIGH (Service/Controller) > MEDIUM (Enum/Mapper/Resource) > LOW (DTO/Test).
4. **Hard constraint**: Each candidate plan's `required_files` and `expected_diff_matrix` MUST include all oracle HIGH-weight production files. Candidate plans missing oracle HIGH-weight files will be eliminated.
5. **First Slice Rule**: The first slice MUST target the highest weight production file in the oracle. If oracle has Service layer changes, do not use DTO/Enum as the first slice.
6. **Domain-Aware Oracle Overlap Calculation (v423)**: Before calculating oracle overlap, domain filtering must be applied first.
   - First determine `oracle_primary_domain` (extracted from ORACLE_DIFF_ANALYSIS.json)
   - Apply domain filtering: only retain oracle files whose path contains directories related to `oracle_primary_domain` (e.g., workflow → ai/claim/calculation/auto-flow)
   - Calculate overlap on domain-filtered file set: `overlap = |plan_files ∩ domain_filtered_oracle_files| / |domain_filtered_oracle_files|`
   - Requirement: overlap MUST >= 50%, HIGH-weight overlap MUST >= 70%
   - Report `oracle_primary_domain` and the number of domain-filtered files in `PLAN_RESULT.md`

7. **Oracle overlap validation**: The overlap rate between planned production files and **domain-filtered** oracle production files MUST >= 50%. Plans below 50% will be rejected by the runner. HIGH-weight oracle file overlap rate MUST >= 70%.

8. **Oracle Coverage Repair Ledger**: If overlap < 50% or not all HIGH-weight oracle production files are included in the plan, write a machine-readable repair ledger in `PLAN_RESULT.md`. The ledger must explain the missing oracle high-weight files, which existing production carrier / slice / executable test to extend to, or why the file must be blocked in blind replay. Do not write placeholders like “to be added later”, “needs confirmation”, “decide after referencing oracle”.

If `{{ORACLE_DIFF_ANALYSIS}}` does not exist or is empty, skip oracle constraints but must write `oracle_analysis_skipped` in `PLAN_RESULT.md`.

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
5. Do not write `NONE`, `TBD`, `unknown`, `placeholder`, `none_with_reason`, or narrative-only prose. If no honest binding exists, set `plan_status: BLOCKED` and write a concrete blocker.

【EXACT Oracle Signatures (Phase 2 Pre-Binding, MANDATORY)】

**Step 1: Read Oracle Contracts**

If `{{REPLAY_ROOT}}\ORACLE_CONTRACTS.json` exists, you MUST read it before generating candidate plans.

This file contains the exact signatures (class_name, method_name, parameter_types, return_type) of all actual methods in the oracle commit.

**Step 2: Use EXACT Signatures**

For each production carrier (Service/Facade/Controller) in candidate plans:

1. ✅ MUST: Use EXACT method name from `ORACLE_CONTRACTS.json`
2. ✅ MUST: Use EXACT parameter types
3. ✅ MUST: Use EXACT return type
4. ❌ Forbidden: Infer signatures from requirements
5. ❌ Forbidden: Create new methods different from oracle signatures
6. ❌ Forbidden: Create carriers listed in `forbidden_carriers`

**Step 3: Document Oracle Alignment**

Must include in `PLAN_RESULT.md` and `IMPLEMENTATION_CONTRACT.md`:

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
  "ExampleFlowService": {
    "method": "handle",
    "signature": "public void handle(Long caseId, ExampleApplyApiTask task)",
    "parameter_types": ["Long", "ExampleApplyApiTask"],
    "return_type": "void"
  }
}
```

你的计划 MUST 使用：
- ✅ `ExampleFlowService.handle(Long caseId, ExampleApplyApiTask task)`
- ❌ NOT `ExampleFlowService.executeAutoFlow(Long caseId)`
- ❌ NOT `ExampleFlowService.processAiResult(Long caseId, AiResult result)`

**Verification:**

The verifier will check:
1. Whether the carrier in the plan exists in the oracle
2. Whether the signature matches exactly (method name, parameters, return type)
3. Whether a synthetic carrier was created (new carrier not in the oracle)

If synthetic carrier rate > 40%, the plan will be rejected.

If `ORACLE_CONTRACTS.json` does not exist, write `oracle_contract_pre_binding: skipped_no_contracts` and continue.

【Pattern Matching Enforcement (MANDATORY for integration/callback features)】
If the requirement involves external integration, callback, push, notification, RPC interface, API callback, or other scenarios interacting with external systems:

1. **Search for similar implementations**: For existing Facade entries in the same direction in the project (e.g., other methods on the same interface), use `rg` to search for candidate method signatures, return types, and error handling patterns. Must record the search commands and candidate signatures.
2. **Pattern to Follow Documentation**: Add the following to the `key: value` fields in FIRST_SLICE_PROOF_PLAN.md:
   - `pattern_to_follow:` — Complete signature of similar method (e.g., `ClassName.methodName(ParamType) -> ReturnType`) or `NEW_PATTERN` (if no similar implementation found)
   - `pattern_return_type:` — Return type of the similar implementation
   - `pattern_error_handling:` — Error handling pattern of the similar implementation (`response_codes` or `exception_propagation`)
   - `pattern_evidence_source:` — Search command and code file path
3. If `pattern_to_follow:` is not `NEW_PATTERN`, `pattern_return_type:` and `pattern_error_handling:` must have concrete values, no placeholders allowed.

Do not use narrative descriptions to replace specific search evidence. `pattern_evidence_source:` must contain reproducible search commands.

---

## EXPERIMENT 1: Carrier Existence Verification (MANDATORY v358)

**CRITICAL CARRIER VERIFICATION REQUIREMENT:**

After completing the plan and selecting `selected_carrier`, you must verify that the selected carrier actually exists in the codebase.

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

✅ **ALLOWED**: Select a carrier that actually exists (search returned results)
✅ **ALLOWED**: If the carrier does not exist, write `plan_status=BLOCKED` and `blocker: carrier_not_found`

❌ **FORBIDDEN**: Submit a plan with a non-existent carrier
❌ **FORBIDDEN**: Assume a carrier exists without verification

### Example

**WRONG** (carrier doesn't exist):
```
Selected Carrier: AiNonExistentService.handle
Evidence: None (assumed to exist)
Status: PROCEED  # ❌ FORBIDDEN
```

**CORRECT** (carrier verified):
```
Selected Carrier: ExampleFlowService.handle
Verification: rg "class ExampleFlowService" --type java
Result: Found in example-core/src/main/java/.../ExampleFlowService.java
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

【Candidate Plan Requirements】
Generate `{{PLAN_CANDIDATE_COUNT}}` candidate plan files:
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_1.md`
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_2.md`
- `{{REPLAY_ROOT}}\PLAN_CANDIDATE_3.md`

每个候选计划必须包含：
- strategy summary
- core path first slice
- deploy-facing surface allocation
- requirement family allocation：core_entry / stateful_side_effect / deploy_export_page / wire_payload_api_contract / config_policy_threshold / generated_artifact_template_upload / external_integration / automation_test_interface / lifecycle_cleanup_retention
- FAMILY_CONTRACT.json alignment: planned slice, proof_required, forbidden_proof, and coverage cap for each detected family -- whether retained or made more strict by the candidate plan
- production carrier alignment: each required family must preferentially bind to existing production carriers from `SURFACE_CARRIER_SCAN.md`; if creating a new carrier file, must explain which existing entry calls it, which existing carrier is modified in the same slice, and how to test real output/side effects
- no substitute carrier: plans for high-weight core/stateful/artifact families must not use `Noop` / `Stub` / `Fake` / `Dummy` / `Placeholder` / `Mock` / `InMemory` / `TestOnly` / `Scaffold` placeholder or substitute classes as primary carriers. New classes must be real domain capability classes and must be called by existing production entries.
- slice budget reservation table
- exact contract strategy
- side-effect ledger strategy
- test charter
- expected diff matrix
- sibling surface ownership: each sibling must belong to a specific `family_id`, subsequent slice results must use `family_id: sibling` format, deploying/export siblings must not be propagated to stateful/config/artifact family
- risk/cap rule
- why this plan could fail

Candidate plans must differ:
- One biased toward core-transaction-first
- One biased toward deploy-facing-surface-balanced
- One biased toward exact-contract-and-test-first
If you believe a strategy is clearly infeasible, still write it out and explain why it's eliminated.

【Evaluation Rules】
Use a 100-point rubric for scoring:
- core path closure: 25
- side-effect/transaction evidence: 20
- exact contract fidelity: 15
- deploy-facing surface coverage: 15
- executable tests: 15
- token/cost discipline: 5
- rollback/blocker clarity: 5

Do not select plans that only do entry hooks, helper/service skeletons, DTO/entity/config supporting surfaces.
Do not select plans that primarily rely on new synthetic service/helper/substitute carriers; new files can only be called implementations of existing production carriers, not close a family on their own.
Do not select plans that allocate all Phase 1 slices to the same conceptual family; once core/stateful baselines can form executable evidence, subsequent budget must shift to at least one deploy-facing executable surface.
Do not select plans that leave detected requirement families completely untouched in Phase 1; if slice count is insufficient, must specify `family_budget_gap`, cap, and the first slice of the next round.
If all candidates cannot safely proceed to coding, write `plan_status=BLOCKED` in `PLAN_RESULT.md`.

【Production Carrier Search (MANDATORY, v270)】

Before selecting the first slice and generating `IMPLEMENTATION_CONTRACT.md`, you must first prove that “the production entry was not chosen incorrectly”. Forbidden to create a new service first and then have tests follow the new service.

Must complete and record:
1. `carrier_search_queries:` At least 3 reproducible source search commands or patterns, covering existing task/processor/handler/facade/controller/route/consumer/listener, existing `handle*` / `process*` / `execute*` / `callback*` / `notify*` methods, and existing implementations or sibling surfaces close to requirement keywords.
2. `existing_production_carriers:` List of real production carriers hit by the search; if empty, write `NONE_FOUND_AFTER_SEARCH`, cannot leave blank.
3. `selected_carrier_from_search:` Final selected production carrier, must be from `existing_production_carriers`, unless `new_service_proposed: true` with valid justification.
4. `new_service_proposed: true | false`.
5. `new_service_justification:` Only fill when a new service must be created; only cross-project valid reasons, such as `orphan_feature_no_existing_domain`, `new_external_boundary`, `incompatible_existing_carriers`, `oracle_new_service_no_existing_orchestration`. Cannot write “for convenience of testing”, “placeholder first”, “will connect later”.

If `selected_carrier_from_search` is not in the search results, or `new_service_proposed: true` without valid justification, `PLAN_RESULT.md` must write `plan_status=BLOCKED` and `blocker: carrier_search_unproven`, and must not enter Phase 1.

Machine-verifiable format requirements:
- `carrier_search:` must be on its own line in `PLAN_RESULT.md`, value can only be `performed` or `blocked`.
- `carrier_search_queries:` must be on its own line in `PLAN_RESULT.md`, value must contain at least 3 search patterns separated by semicolon, comma, or `|`, and must appear at least 3 times with `rg` / `grep` / `findstr` / `Select-String` / `search` / `query`.
- `existing_production_carriers:` must be on its own line in `PLAN_RESULT.md`, value must be on the same line as the key; multiple items separated by `;`, cannot be an empty key followed by bullet/list. Field name must be `existing_production_carriers`, cannot use aliases like `carrier_search_existing_carriers`.
- Alias names such as `carrier_search_existing_carriers` are forbidden. Empty key followed by bullet/list is forbidden.
- `selected_carrier_from_search:` must be on its own line in `PLAN_RESULT.md`, and must be matchable from the same line value of `existing_production_carriers:`; unless `new_service_proposed: true` with valid justification.
- `oracle_production_file_overlap:` must be on its own line in `PLAN_RESULT.md`, value must be a number percentage, e.g., `83%`. Cannot be written only in `ORACLE_OVERLAP_GATE.json`, candidate plans, explanation paragraphs, or post-hoc reports.
- If the verifier reports `carrier_search_queries_too_few`, `plan_result_missing:oracle_production_file_overlap`, or `oracle_overlap_below_threshold`, the Plan stage will trigger one contract repair pass; if repair still fails, this round must be BLOCKED.

【Required Final Plan Output Files】
1. `{{REPLAY_ROOT}}\PLAN_SELECTION.md`
   - Candidate plan scoring table
   - Selection rationale
   - Elimination rationale
   - Key trade-offs

2. `{{REPLAY_ROOT}}\REPLAY_PLAN.md`
   - Final plan sorted by slice
   - Each slice: requirement rows / surfaces / files / tests / DoD / blocker / coverage cap
   - Each slice must write `existing production carrier(s)`; if empty, must write `carrier_search_terms` and `BLOCKED/coverage_cap`
   - Each detected requirement family must correspond to at least one slice or blocker/cap
   - Must specify which slice first covers deploy-facing surface; if none, must write `surface_budget_gap` and coverage cap
   - Must specify `STOP_AND_REPORT` condition

3. `{{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md`
   - Execution contract that Phase 1 must follow
   - Must contain independent machine-readable line: `selected_real_entry: <Phase0 selected_real_entry>`; if cannot bind to real entry, write `selected_real_entry: PLAN_BLOCKED_SELECTED_REAL_ENTRY`, and write `plan_status=BLOCKED` in `PLAN_RESULT.md`
   - Must contain independent machine-readable line: `first_slice: <PLAN_RESULT first_slice>` and `first_red_test: <PLAN_RESULT first_red_test>`
   - Not allowed to reopen large-scale exploration
   - Not allowed to replace selected real entry, unless writing `BLOCKED_PLAN_MISMATCH`
   - Not allowed to claim core DONE with shallow GREEN
   - Not allowed to close family with new replay-local service/helper/test-only surface; must go through existing production entry/carrier
   - Not allowed to extend only the same core/service/log test family for more than two consecutive slices, unless all high-weight deploy-facing surfaces already have executable slice or explicit blocker/cap

4. `{{REPLAY_ROOT}}\EXPECTED_DIFF_MATRIX.md`
   - requirement -> module -> expected file families -> change type -> validation -> closure condition

5. `{{REPLAY_ROOT}}\SIDE_EFFECT_LEDGER.md`
   - selected real entry -> orchestration -> persistence/query/write -> state/task/progress/log -> transaction/failure isolation -> executable proof

6. `{{REPLAY_ROOT}}\TEST_CHARTER.md`
   - RED/GREEN order
   - Real entry tests
   - DB/transaction or alternative verification
   - deploy-facing surface tests
   - cap when static-only/blocker
   - **Format hard requirement (v426)**: TEST_CHARTER must include independent `## RED Phase` and `## GREEN Phase` heading sections. The verifier will search for "RED" and "GREEN" keywords; if these keywords are missing, it will trigger `test_charter_missing:RED` or `test_charter_missing:GREEN` errors. You can add other content, but must explicitly include these two heading sections.

7. `{{REPLAY_ROOT}}\FIRST_SLICE_PROOF_PLAN.md`
   - Only write Phase 1 first slice, not the full plan
   - Must bind `PLAN_RESULT.md` `first_slice`, `first_red_test`, and Phase 0 `selected_real_entry`
   - **Format hard requirement (machine-verified v452)**: FIRST_SLICE_PROOF_PLAN must include all of the following fields as independent `key: value` lines. The runner dry-run script parses these fields line by line, and does not parse narrative paragraphs, Markdown tables, or nested lists. If any field does not appear as `key: value` format on its own line, the dry-run gate will directly BLOCKED_PLAN_MISMATCH.
   - **v452 Highest Priority Fields**: The following fields are most commonly missed and must be checked first:
     - `highest_weight_open_gate:` - **Must fill**. From ROUND_CONTRACT.md's Requirement Family Ledger, find the highest-weight family that needs to be "opened" (create new service or modify core path) in the first slice. For example: `stateful_side_effect`, `core_entry`, `wire_payload_api_contract`. Cannot omit, cannot write "TBD", "pending confirmation" or other placeholders.
     - `selected_real_entry:` - **Must fill**. Must be identical to Phase 0's selected_real_entry.
     - `proof_kind:` - **Must fill**. Must be one of the following enum values: `real_entry_behavior`, `stateful_side_effect`, `route_export_behavior`, `payload_shape_behavior`, `generated_artifact_behavior`.
     - `real_carrier_kind:` - **Must fill**. Must be one of the following enum values: `production_entry_or_service`, `production_controller_or_route`, `production_mapper_or_query`, `production_payload_builder`, `production_template_or_artifact_renderer`, `production_lifecycle_cleanup`, `production_service_method`, `production_service`, `production_enum`, `production_dto`.
   - Forbidden to use narrative paragraphs, Markdown tables, `##` heading sections, or nested lists as substitutes for `key: value` format. You can add explanatory content before or after the `key: value` lines, but each required field itself must appear as a `key: value` independent line, with non-empty, non-placeholder values.
   - Each field value is forbidden to use placeholder words: `TBD`, `unknown`, `N/A`, `placeholder`, `pending confirmation`, `unconfirmed`, `confirm later`. If a field truly cannot be filled, must write `PLAN_BLOCKED_<FIELD>` and write `plan_status=BLOCKED` in `PLAN_RESULT.md`.
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
   - **Test harness selection rule (v289)**: `first_red_test` must point to a module with existing test dependencies. Currently tests must be placed in `example-server/src/test/...`, run command must use `-pl example-server -am`; forbidden to plan `example-core/src/test/...`, `-pl example-core`, or add test dependencies by modifying `pom.xml` to satisfy RED. If unable to prove in existing harness, write `PLAN_BLOCKED_TEST_HARNESS` and downgrade `plan_status` to `BLOCKED`.
   - **Public entry proof rule (machine-verified)**: If `selected_real_entry` is a public entry like facade/controller/API/endpoint/route, then all of the following must be satisfied, otherwise the runner rejects FIRST_SLICE_PROOF_PLAN and early stops:
     1. `selected_carrier` must be the public entry itself, or a response contract test carrier containing the full name of the public entry. Forbidden to only write Mapper/Entity/DTO/internal service. For example: entry is `ExampleModuleConfigController` → carrier must contain `ExampleModuleConfigController` or `ExampleModuleConfigFacade`, cannot only write `TExampleModuleConfig entity` or `ExampleModuleConfigMapper`.
     2. `first_red_test` must be initiated through the public entry or its direct call chain, not only test Mapper/DAO layer.
     3. `public_entry_contract_coverage:` must specify executable proof for at least one of request parameters, response fields, status codes, or error branches. Simply writing "Full" or "existing contract accepts DTO" is insufficient; must write specific assertion content (e.g., "assert ResultModel.success contains exemptReviewAmount field", "assert POST /ai/claim/config/add returns 200 with updated config JSON", "assert invalid param returns ResultModel.error with message").
     4. `real_carrier_kind` must be `production_entry_or_service` or `production_controller_or_route`, cannot be `production_mapper_or_query`, `production_dto`, `production_enum`.
   - `proof_kind` is a machine-verified field, only allows the following values (copy verbatim): `real_entry_behavior`, `stateful_side_effect`, `route_export_behavior`, `payload_shape_behavior`, `generated_artifact_behavior`. Forbidden to write `static_presence`, `helper_only`, `compile_only`, `dto_only`, or invented words like `entity_behavior`. FIRST_SLICE_PROOF_PLAN that violates the format will be rejected by the runner.
   - `real_carrier_kind` is a machine-verified field, only allows the following values (copy verbatim): `production_entry_or_service`, `production_controller_or_route`, `production_mapper_or_query`, `production_payload_builder`, `production_template_or_artifact_renderer`, `production_lifecycle_cleanup`, `production_service_method`, `production_service`, `production_enum`, `production_dto`. Forbidden to write `production_entity`, `protected_hook`, `test_subclass`, `helper_only`, `dto_only`, `static_presence`, `mock_only`, or any invented words. FIRST_SLICE_PROOF_PLAN that violates the format will be rejected by the runner.
   - `minimum_side_effect_or_blocker` must specify the minimum real production call, state/persist/output/payload/export/template side effects the first slice must prove; if not found, write `PLAN_BLOCKED_REAL_CARRIER`.
   - **v295_executable_first_slice_gate / v295 executable first slice hard gate**: When `plan_status: PROCEED`, the first slice must not be `Contract & RED Tests`, `CONTRACT_ONLY`, `RED-only`, `test-only`, `production_boundary: NONE`, or `expected_production_diff: NONE`. The first slice must include within the same slice: one RED test, minimum GREEN production implementation, and the real production side effect/payload/output/export/template proof specified in `minimum_side_effect_or_blocker`. Forbidden to defer GREEN or production side effects to S2/S3; if the first slice can only write contract or RED test, must change `plan_status` to `BLOCKED`.
   - **v296_core_executable_tracer_selection**: If Phase 0 has already discovered `selected_real_entry`, and the highest weight family is `core_entry`, candidate plans must include at least one executable tracer bullet with that real entry as the first slice. The final `selected_candidate` must not choose an exact-contract/static slice that only modifies Constant/DTO/Entity/Mapper. When `highest_weight_open_gate: core_entry`, `selected_carrier` must be a real entry/service/method, `proof_kind` must be `real_entry_behavior` or `stateful_side_effect`, `real_carrier_kind` must be `production_entry_or_service`, `production_service_method`, or `production_service`. Forbidden to use `plan_status: BLOCKED` to avoid this choice, unless Phase0 has no real entry, test harness is unavailable, or oracle overlap remains below threshold after expansion.
   - `minimum_side_effect_or_blocker` value is forbidden to write `NONE`, `N/A`, `NOT_APPLICABLE`, `none_with_reason`, `no production code`, `contract definition only`, `to be implemented in Slice 2`, or similar circumvention phrases. It must be an executable proof, such as “service method writes state through mapper and test asserts mapper call + status value”, or write `PLAN_BLOCKED_REAL_CARRIER` and stop.
   - `production_boundary` and `expected_production_diff` when `plan_status: PROCEED` must point to real production files/methods/file families, forbidden to write `NONE` or “Slice 1 does not touch production code”.
   - `forbidden_substitute_check` is a machine-verified field, only allows the following two values (copy verbatim, without period, space, or description):
     - `forbidden_substitute_check: passed` (check passed)
     - `forbidden_substitute_check: failed:<reason>` (check failed, must also write `plan_status=BLOCKED`)
     Forbidden to write descriptive text like “Must verify...”, “No substitute...”, “Check that...”. FIRST_SLICE_PROOF_PLAN that violates the format will be rejected by the runner and early stopped.
   - If the requirement specifies field sources, source tables, source fields, or “backend auto-fill”, the first or second slice must be a source-chain slice: `source carrier -> build context/request -> task data -> wire payload`. Only verifying terminal DTO/taskData/payload writes cannot close core.
   - Fields should default to single line `field: value`; if a line break is necessary, the next line can only use Markdown definition-list `: value`, cannot scatter values into ordinary paragraphs. The four fields `production_boundary:`, `selected_carrier:`, `target_subsurface_or_carrier:`, `expected_production_diff:` must preferentially be written as comma-separated values on the same line; forbidden to write empty colon followed by bullet/list, otherwise the verifier will determine `first_slice_proof_schema_empty`.
   - If the first slice cannot be proven with real entry and RED test, `PLAN_RESULT.md` must write `plan_status=BLOCKED`, must not enter Phase 1
       - **v457 first_slice_proof schema hard requirement (Executable Evidence Gate)**:
	     FIRST_SLICE_PROOF_PLAN must include the following V457 fields, and format must comply with machine verification:
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
	     1. 对于 `core_entry` family：carrier.layer 必须是 Facade 或 Controller
	     2. 对于 `stateful_side_effect` family：carrier.layer 可以是 Service 或 Facade
	     3. 对于 `deploy_export_page` family：carrier.layer 可以是 Controller 或 Service
	     4. 如果选定的 carrier 是 Service 层但目标 family 是 `core_entry`：
	        - 必须拒绝该 carrier
	        - 必须搜索对应的 Facade 层入口
	        - 如果没有 Facade，必须写 `PLAN_BLOCKED_LAYER_VALIDATION` 并把 `plan_status` 改为 `BLOCKED`
	     5. 执行 layer validation 的证据：
	        - `rg "class.*Facade" --type java` 在相关模块搜索 Facade
	        - 记录搜索结果和选择的理由
	        - 如果 Service 层 carrier 是唯一的真实入口，必须在 FIRST_SLICE_PROOF_PLAN 中说明为何没有 Facade 层等价入口

8. `{{REPLAY_ROOT}}\PLAN_RESULT.md`

## PLAN_RESULT.md Format

```markdown
# Plan Result

**Note**: All of the following fields must be on independent lines in `key: value` format. Empty key followed by bullet/list is forbidden. Each key must have a non-empty value (except `blocker:` and `invalid_reason:` which can be empty when there is no issue).

- plan_status: PROCEED | INVALID_PLAN | BLOCKED
- selected_candidate: <copied from PLAN_SELECTION.md, e.g., "3 - Exact-Contract-and-Test-First">
- selected_strategy: <copied strategy summary from PLAN_SELECTION.md, e.g., "exact-contract-and-test-first" | "core-transaction-first" | "deploy-facing-surface-balanced">
- implementation_model_recommendation: gpt-5.3-codex
- required_files:
- oracle_production_file_overlap:
- oracle_high_weight_coverage:
- oracle_missing_high_weight_files:
- oracle_expansion_plan:
- oracle_out_of_scope_files:
- golden_slice_binding:
- oracle_primary_domain: <domain name>
- requirement_primary_domain: <domain name>
- domain_compatibility: COMPATIBLE | MISMATCH | UNCERTAIN
- foreign_domain_ratio: <percentage>
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

`PLAN_RESULT.md` must declare `oracle_production_file_overlap` and `oracle_high_weight_coverage` (based on **domain-filtered** oracle file set). If overlap is below 50% in oracle-assisted planning mode, must first expand/correct the selected plan's covered high-weight production file families; if still cannot reach 50%, write `plan_status=BLOCKED` and `blocker: oracle_overlap_below_threshold`, must not output PROCEED.

When overlap < 50% or there are HIGH-weight uncovered files, `PLAN_RESULT.md` must also include the following machine-readable fields:
- `oracle_missing_high_weight_files:` List uncovered HIGH-weight oracle production files separated by semicolons.
- `oracle_expansion_plan:` Written as mapping of `oracle file -> existing production carrier -> slice/test`; if cannot expand, write `BLOCKED:<reason>`.
- `oracle_out_of_scope_files:` Only allowed to list files that cannot be safely judged under blind conditions, and give blocker for each; write `none` if none.

Decision rules:
- `PROCEED`: Final plan can be directly handed to Phase 1 execution, and all required planning artifacts exist.
- `INVALID_PLAN`: Plan still uses supporting/helper/static/DTO/config as first slice, or lacks real entry RED.
- `BLOCKED`: Requirement/code facts are insufficient to freeze the plan, or key exact contract cannot be safely determined under blind conditions.

## Must Write All the Following Files, Regardless of plan_status being PROCEED or BLOCKED

The following 9 files are required outputs of the Plan stage. Even if plan_status=BLOCKED or plan_status=INVALID_PLAN, they must all be written. Missing any of them will trigger an artifact repair pass or early stop.

1. `{{REPLAY_ROOT}}\PLAN_RESULT.md` — plan_status + selected strategy
2. `{{REPLAY_ROOT}}\PLAN_RESULT.json` — machine-readable plan contract. Markdown is for humans; this JSON is the authority for unattended gates.
3. `{{REPLAY_ROOT}}\PLAN_SELECTION.md` - Candidate scoring and selection rationale
4. `{{REPLAY_ROOT}}\REPLAY_PLAN.md` - Final plan sorted by slice
5. `{{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md` - Phase 1 execution contract
6. `{{REPLAY_ROOT}}\EXPECTED_DIFF_MATRIX.md` — requirement → file → change type → validation → closure

   **Format hard requirement (v449)**: EXPECTED_DIFF_MATRIX must use Markdown table format, and must include a "Closure" or "Closure Condition" column header. The verifier will search for the "closure" keyword; if the column header is missing, it will trigger `expected_diff_missing:closure` error. Example table format:

   ```markdown
   ## Slice 1: Contract Definition

   | Oracle File | Diff Type | Lines Added | Lines Deleted | Validation | Closure |
   |-------------|-----------|-------------|---------------|------------|---------|
   | example-domain/.../TExampleModuleConfig.java | FIELD_ADD | 3 | 0 | type_match | S1 |
   | example-core/.../ExampleFlowService.java | NEW_STUB | 20 | 0 | signature_only | S1 |
   ```

   - The "Closure" column must explain which slice closes the diff (e.g., S1, S2, S3) or why it cannot be closed (e.g., BLOCKED:reason)
   - Forbidden to use "Status: TODO" or other placeholder formats, must specify slice or blocker
   - The verifier will check for the existence of the "closure" keyword
7. `{{REPLAY_ROOT}}\SIDE_EFFECT_LEDGER.md` — entry → side effect → state/task/transaction → proof
8. `{{REPLAY_ROOT}}\TEST_CHARTER.md` — RED/GREEN order + real entry tests + DB/transaction
9. `{{REPLAY_ROOT}}\FIRST_SLICE_PROOF_PLAN.md` - first slice proof schema (see field list above)

`PLAN_RESULT.json` minimum format:

```json
{
  "plan_status": "PROCEED | BLOCKED | INVALID_PLAN",
  "target_carrier_file_path": "relative/path/ToCarrier.java",
  "target_carrier_line_number": 123,
  "expected_test_class": "SomeBehaviorTest",
  "expected_test_method": "methodName",
  "side_effects": ["DB/state/file/API/log side effect"],
  "expected_assertions": ["assertion 1", "assertion 2"],
  "blocker": "required only when plan_status is BLOCKED",
  "invalid_reason": "required only when plan_status is INVALID_PLAN"
}
```

When `plan_status=PROCEED`, `target_carrier_file_path`, `target_carrier_line_number`, `expected_test_class`, `expected_test_method`, `side_effects` must be non-empty; when `plan_status=BLOCKED` must write `blocker`; when `plan_status=INVALID_PLAN` must write `invalid_reason`.

If plan_status=BLOCKED, IMPLEMENTATION_CONTRACT and FIRST_SLICE_PROOF_PLAN can write a brief blocker explanation, but files must exist.

Start executing Phase 0.5. Only write the above planning artifacts.

---

【Pre-S1 Plan Check Integration (v348)】

After completing Phase 0.5 planning, before Phase 1 begins, the following checks must be performed:

### 1. Carrier Verification (v348)

Refer to `PRE_S1_PLAN_CHECK.md`:
- Verify matching degree of selected_carrier with requirement keywords
- Run `verify-carrier.ps1` to verify carrier selection
- If WARN without valid justification, plan_status must be changed to BLOCKED

### 2. Horizontal Slicing Verification (v348)

Refer to `TRACER_BULLET_GUIDANCE.md`:
- S1 (tracer_bullet) must touch at least 3 families
- Run `verify-horizontal-slice.ps1` to verify horizontal slice coverage
- If families_touched < 3, slice must not enter GREEN phase

### 3. Behavioral Test Charter (v348)

Refer to `TEST_CHARTER_GUIDANCE.md`:
- RED tests must contain business assertions, forbidden to use fail()/assertTrue(true)/TODO
- Run `verify-test-charter.ps1` to verify test quality
- If it contains blocked_patterns, must not enter GREEN phase

These checks ensure that carrier selection, slice design, and test contracts produced by planning conform to TDD best practices.

---
