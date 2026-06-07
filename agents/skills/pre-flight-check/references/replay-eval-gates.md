# Replay / Eval Gates

仅在用户明确要求历史重跑、oracle 对比、技能实测、分支/提交复现、或从旧实现吸收补丁时读取。普通开发、hotfix、debug-only、static review 不默认展开本文件。

## Mode Boundary

Replay/eval 是评估和打磨工作流的实验室，不是默认交付流水线。

| mode | 允许事项 | 禁止事项 |
|------|----------|----------|
| `delivery` | 按需求、方案、OpenSpec、TDD、验证和同步交付代码 | 默认三轮 replay、默认 oracle 对比、默认 coverage scoring |
| `replay-eval` | 隔离 worktree、blind replay、ROUND 文档、oracle post-hoc、评分报告 | 把 replay 产物直接写入主交付 `code-change.md` 或直接升级为生产 scope |

未显式命中 replay / eval / oracle / 历史重跑 / 技能实测 / 工作流打磨实验时，保持普通 `delivery` 或只读模式。

## Productized 8-Gate Mapping

replay/eval 报告、oracle 后验和 evolution proposal 必须先映射到以下 8 个产品化 gate，再决定是否修改技能。不得新增同义 gate；重复 gap 优先演进执行路由和可执行证据，而不是只新增评分 cap。

| productized gate | owns | typical flags | absorption rule |
|------------------|------|---------------|-----------------|
| Source-of-Truth Gate | 需求源、当前方案、历史材料、oracle 分类 | `source_contamination`、`missing_requirement_source` | 缺分类时补 source boundary；项目路径和业务细节不进通用技能 |
| Oracle Isolation Gate | blind replay 与 oracle post-hoc 隔离 | `oracle_used`、`context_contamination_risk` | 只进 replay/eval 规则，不进入普通 delivery |
| Requirement Contract Gate | literal、字段来源、顺序、must-not、exact contract | `exact_contract_gap` | 进入需求/设计/测试冻结表；固定值必须可断言 |
| Surface Coverage Gate | surface mining、Expected Diff、deploy-facing family | `surface_budget_gap`、`executable_surface_slice_gap` | 演进为 surface allocation 或 first executable slice，不靠文件清单评分 |
| Core-First Budget Gate | 核心入口、编排和最高权重 slice 顺序 | `core_entry_unclosed`、`core_path_unclosed`、`tracer_bullet_only` | 下一片必须直击核心入口、stateful success path 或其直接前置承载点 |
| Executable Evidence Gate | RED/GREEN、真实入口、side-effect ledger、测试面 | `feedback_loop_blocker`、`side_effect_ledger_gap`、`wrong_test_surface`、`shallow_module`、`tracer_bullet_only` | 演进为可运行反馈回路、真实入口测试、stateful success path、终态信号链路证明 |
| Coverage Cap Gate | replay/eval 评分上限和披露 | `small_green_false_positive`、`mock_behavior_gap` | 只调整评分/披露；不是普通执行替代品 |
| Evolution Abstraction Gate | 技能吸收层级、污染扫描、最小 eval | `project_identity_pollution`、`needs_more_replay_evidence` | 只吸收跨项目模式；证据不足则归档候选，不改正文 |

分类结果必须使用：`already-covered-by-existing-gate`、`already-covered-but-not-enforced`、`workflow-gate-needs-evolution`、`tooling-evolution-needed`、`scoring-only-not-execution`、`project-specific-do-not-absorb`、`needs-more-replay-evidence`。

吸收边界：

- `workflow-gate-needs-evolution`：现有 8 gate 无法承载，才允许修改 canonical 技能正文或 gate 定义。
- `already-covered-but-not-enforced`：现有 gate 已覆盖但 replay 仍重复命中时，不得直接 no-op；优先转为 `tooling-evolution-needed`，补 runner / prompt / verifier 的强制执行逻辑。
- `tooling-evolution-needed`：只改执行器、轮次 prompt、验证器、报告模板或本 replay/eval reference 的执行约束；不得新增同义 gate。
- `already-covered-by-existing-gate`：必须有证据证明 runner / prompt / verifier 已经执行该 gate，才允许 no-source-change。

## Source Of Truth

当输入是目录、历史需求包、replay 材料或包含多个文档时，先分类：

| source | 含义 |
|--------|------|
| `requirement_source` | 需求原文、PRD、用户确认口径 |
| `current_plan_source` | 本轮生成并被接受的技术方案 |
| `historical_source` | 旧设计、旧 code-change、旧报告、历史审查 |
| `oracle_source` | 目标 commit、最终态补丁、上一轮 replay 结果 |

实现前不得读取或套用 `historical_source` / `oracle_source`，除非用户明确要求做 diff port。违反 = `NO-GO`。

## Branch / Commit Reconstruction

当输入只有分支、commit range、patch、目标 diff 或别人已实现分支，且没有 PRD / 用户验收口径时，默认进入 `branch-derived` / `commit-derived`：

- 先声明 mode、oracle 用法和隔离路径。
- 输出 `Inferred Requirement Matrix`：`inferred requirement -> confidence -> evidence -> missing source -> verification gap -> next step`。
- 输出 `Diff Role Matrix`：`file family -> role -> expected/surprising -> shared impact -> validation`。
- diff 只能作为证据或后验 oracle；未确认前不得升级为 PRD 契约。
- bugfix 没有日志、堆栈、失败测试或复现输入时，结论最多是 `compile_pass + static_inference + verification_gap`。

缺失上述声明或矩阵 = `NO-GO`。

## Existing Implementation Slice

当从历史提交、旧分支、示例实现、上一轮 replay 或外部补丁复用内容时，必须先拆分：

- `intended_change_slice`：本需求需要吸收的有效文件族与行为。
- `out_of_scope_drift`：来源中存在但本需求不应带入的文件族、重构、格式化、生成物或无关修复。

无法区分切片与漂移 = `NO-GO`；禁止整分支、整目录或整补丁无筛选导入。

## Isolation

replay、eval、技能实测、独立重跑、历史提交重跑或分支对比时：

1. 先创建或确认隔离 worktree / sandbox。
2. 写 `.doc`、`openspec`、测试或代码前，确认目标路径位于隔离目录。
3. 禁止在主工作区写 ignored 轮次产物。
4. 构建/测试命令的 repo root 必须指向当前隔离目录；项目 profile 里的原始 root 只能作为模板。
5. 输出主工作区、隔离路径、当前 cwd、目标写入路径、实际 root pom / workspace root。

目标路径不在隔离目录 = `NO-GO`。

## Two-Phase Blind Replay Protocol

标准 replay/eval 分两阶段执行：

### Phase 1: Blind Replay

1. 不读取 oracle commit、oracle diff、旧 replay 报告、旧 ROUND 文档、历史会话或宿主恢复会话。
2. 从 baseline 创建隔离 worktree 或 sandbox。
3. 每轮生产代码编辑前必须先写 `ROUND_CONTRACT.md`。
4. 每轮初始 `ROUND_RESULT.md` 必须在 oracle 后验前写出，且包含 `oracle_used=false`。
5. 初始评分只能基于需求、当前 worktree 代码、验证命令和自查门禁。

### Phase 2: Oracle Post-Hoc

1. 只有当 `ROUND_RESULT.md` 已存在后，才允许读取 oracle。
2. 不改写 blind 自评结论；只追加 `Oracle Post-Hoc` section。
3. 先执行 `oracle_scope_filter`：用 `requirement_source` / 用户确认范围过滤 oracle diff。oracle 分支里的额外重构、未来阶段、其他业务文件族或无关修复只能标 `oracle_extra_out_of_scope`，不得进入 coverage denominator、gap 扣分或技能进化依据。
4. oracle 后验必须区分：
   - `blind_self_assessed_coverage`
   - `verification_capped_coverage`
   - `oracle_adjusted_coverage`
5. oracle gaps 不能自动进入生产实现；必须经 promotion gate 转入 delivery。

## ROUND_CONTRACT Minimum

`ROUND_CONTRACT.md` 至少包含：

- `mode / scope / deliverable / verification / exit_condition`
- `source_of_truth`
- `forbidden_source_check`
- `requirement_literal_checklist`
- `exact_contract_matrix`
- `surface_matrix`
- `expected_diff_matrix`
- `core_entry_closure_gate`
- `stateful_side_effect_ledger`
- `critical_surface_allocation_plan`
- `real_entry_gate`
- `nonblocking_feature_gate`
- `deploy_facing_checklist`
- `coverage_cap_rules`

缺少合同即进入生产代码编辑 = `NO-GO`。

## ROUND_RESULT Minimum

`ROUND_RESULT.md` 至少包含：

- changed files
- changed files 必须同时来自 `git diff --name-status` 和 `git status --short --untracked-files=all`
- verification commands and exits
- requirement coverage ledger
- expected diff closure ledger
- exact contract closure ledger
- critical surface allocation ledger
- weighted coverage
- flags:
  - `oracle_used`
  - `context_contamination_risk`
  - `small_green_false_positive`
  - `helper_only_surface_gap`
  - `static_only_core_path`
  - `mock_behavior_gap`
  - `expected_diff_unclosed`
  - `exact_contract_gap`
  - `real_entry_gap`
  - `core_entry_unclosed`
  - `side_effect_ledger_gap`
  - `surface_budget_gap`
  - `executable_surface_slice_gap`
  - `nonblocking_feature_gap`
  - `deploy_surface_lock_gap`
  - `transaction_depth_gap`
  - `behavior_test_blocker`
  - `test_runtime_blocker`
- final status: `PASS / PARTIAL / BLOCKED`

## Diff Accounting Gate

replay/eval 的 diff 统计必须覆盖 tracked 与 untracked：

```bash
git diff --name-status
git status --short --untracked-files=all
```

未跟踪的生产代码、测试、SQL、模板、前端、文档或脚本都必须进入 changed files、Expected Diff Closure 和 coverage 计算。把 untracked 文件排除在 oracle 对比之外 = `untracked_diff_gap`，最终状态最高 `PARTIAL`。

## Coverage Cap Rules

这些 cap 是 replay/eval 评分纪律，不自动进入普通 delivery：

| 情况 | 最高可信覆盖 |
|------|-------------:|
| 核心运行入口 / 编排链路未实现或未接入 | 50% |
| 已识别核心入口但实际 diff 未闭环真实入口文件族 | 45% |
| 没有真实入口测试 | 不得报 90% |
| stateful core path 缺 side-effect ledger | 60% |
| deploy-facing 字段、列、flag、payload shape 或展示列未精确冻结/断言 | 65% |
| 核心状态流转 / 事务链路无 DB 或事务级测试 | 70% |
| 明确要求的图片、附件、报表、导出、异步、通知或外部协议未实现 | 75% |
| 高权重 deploy-facing family 未获得任何 RED/guard/实现切片 | 70% |
| 高权重 deploy-facing family 只有 static-only 或 blocker-only allocation，没有可执行最小切片 | 60% |
| 外部 request / response / payload 结构未由测试锁定 | 80% |
| 报表、导出、前端或浏览器联动未验证 | 85% |
| 只有 helper test 或 compile 覆盖核心行为 | 核心项只能 `PARTIAL` |
| static-only 证据 | 只能 `PARTIAL`，不能标 `DONE` |

## Oracle Calibration Rubric

oracle 后验评分必须分开记录三项，不得只给单一主观分：

| dimension | scoring question |
|-----------|------------------|
| exact file-family overlap | blind 是否命中 oracle 的关键文件族，tracked 与 untracked 都要计入 |
| conceptual role overlap | blind 是否实现同一业务角色、入口、状态、副作用和外部 payload 语义 |
| missing deploy-facing family penalty | report/export/frontend/template/generated artifact/OCR/external payload/test family 缺失如何扣分和触发 cap |
| exact contract penalty | 字段名、DB/API/wire name、flag/type/enum、payload shape、展示列偏差如何扣分和触发 cap |

`oracle_adjusted_coverage` 必须由上述三项和 coverage cap 合成；概念命中核心入口不能抵消明确缺失的 deploy-facing 文件族。若 oracle branch 含有不属于需求范围的文件族，先列 `oracle_extra_out_of_scope -> excluded_reason`，再计算覆盖；不得用整分支文件命中率代表需求覆盖率。

## Two-Stage Workflow Deliverability Eval

两阶段验证用于判断“工作流是否可交付”，不是普通需求交付的默认流程。未显式进入 replay/eval 时，不得要求普通 delivery 连续多轮重跑。

### Stage 1: Baseline Requirement Stability

选择一个代表性复杂需求，至少执行 3 轮互相独立的 strict blind replay。每轮必须满足：

- 新会话或等价隔离上下文；独立 worktree / sandbox。
- blind 阶段只允许读取 `requirement_source`、repo rules 和当前隔离 worktree 代码。
- 禁止读取 oracle、旧 replay 报告、旧 ROUND 文档、历史会话总结或上一轮缺口摘要。
- 先写 `ROUND_CONTRACT.md`，实现和验证后写 `ROUND_RESULT.md`，再进入 oracle post-hoc。

Stage 1 通过条件：

- 连续 3 轮 `verification_capped_coverage >= 90`。
- 连续 3 轮 `oracle_adjusted_coverage >= 90`。
- 连续 3 轮最终状态为 `PASS`。
- hard gaps 必须为 false：`expected_diff_unclosed`、`exact_contract_gap`、`real_entry_gap`、`core_entry_unclosed`、`side_effect_ledger_gap`、`surface_budget_gap`、`executable_surface_slice_gap`、`mock_behavior_gap`、`nonblocking_feature_gap`、`behavior_test_blocker`、`deploy_surface_lock_gap`、`transaction_depth_gap`。

### Stage 2: Generalization Validation

Stage 1 通过后，必须换到至少 1 个不同类型的需求，优先 2 个，按同样 strict blind replay 与 oracle post-hoc 执行。新需求也必须达到 Stage 1 的 coverage 与 hard gap 标准，才可称为“可交付工作流”。

只完成 Stage 1 只能说明工作流在该类需求上稳定，不证明通用性；只完成单轮高分只能说明候选改进有效，不证明稳定。

### Scoring And Learning Loop

- 覆盖率只能按 `Requirement Coverage Ledger + behavior tests` 计算；文件命中率、代码行命中率或 helper 存在不能代表 90%。
- 失败轮次必须分类根因：`requirement`、`design`、`implementation`、`test`、`verification`。
- 只有可跨项目复用的模式才能 promotion 到通用技能；项目路径、业务类名、commit、历史分数和具体缺口不得写入通用技能正文。
- 每次技能改进后必须用新的独立 replay 验证，不得把旧轮次补分当作通过。

## Final Replay Report Minimum

父层 `FINAL_REPLAY_REPORT.md` 至少包含：

- replay root / worktree list / baseline
- 每轮 exit / contract / result 状态
- blind capped coverage
- oracle-adjusted coverage
- Oracle Calibration Rubric 结果
- 是否达到 90%
- 关键缺口
- workflow 改进建议
- 是否清理 worktree；默认保留证据

## Parent Intervention Rule

多轮 replay/eval 中，父层可以在轮次 checkpoint 审查 `ROUND_CONTRACT` / 中间 diff / changed files。若发现最高权重核心链路仍未动工，而实现继续投入 DTO、constant、helper、日志、静态 guard 等低价值 slice，应标记 `core_miss_checkpoint` 并要求该轮停止或改为报告 blocker。该规则只防止继续浪费实验预算，不允许父层把 oracle 内容写回 blind 轮次。

## Repeated Gap Enforcement Loop

当 evolution proposal 把 gap 标为 `already-covered-but-not-enforced` 时，下一轮 runner / prompt / verifier 必须把该 gap 转成可执行停线条件：

1. runner：在每个 slice 前读取上一轮 open high-weight gaps，若下一个 slice 没有映射到最高权重 open gate，停止并报告 `tooling_enforcement_stop`。
2. prompt：要求本 slice 写出 `target gate -> target file family/surface -> executable proof -> exit condition`，缺失时禁止继续实现。
3. verifier：若 gap 仍 open，不得把 slice 标 `DONE`；必须输出 `PARTIAL/BLOCKED`、coverage cap 和下一片强制目标。

自动化 replay prompt 必须默认禁止 GUI/IDE/桌面应用介入；只能使用 shell、git、构建/测试命令和直接文件编辑。若 runner/prompt 需要人工图形界面才能继续，必须标记 `tooling_enforcement_stop` 或环境 blocker，不能把 GUI 操作当作可复现执行证据。

新增一轮 replay 前必须有执行器闭环证据，可嵌入 `ROUND_CONTRACT` 或独立的 runner contract：`previous_open_high_weight_gaps -> highest_weight_gate -> next_slice_target -> fail_closed_condition -> verifier_assertion`。缺失该证据时不得启动或继续消耗 slice，应立即输出 `tooling_enforcement_stop`，而不是等到 `max_slices_reached` 后再记账。

runner contract 不能只证明 slice 命中了一个粗粒度 family。对高权重 family，执行器闭环证据还必须细化到：

- `target_subsurface_or_carrier`：本片要闭合的具体 endpoint、页面/导出、payload builder、模板/渲染/上传链路、状态化生产入口或其他真实承载点。
- `required_sibling_surfaces`：同一需求明确点名多个 endpoint、导出、页面、payload、模板或外部协议时，逐个列出兄弟 surface；只闭合其中一个时，family 只能是 `PARTIAL`，其余项必须有 defer/blocker/cap。
- `production_boundary`：证明发生在生产边界或其直接承载点；replay-local harness、synthetic bytes、常量存在、静态文件扫描或 helper-only assertion 不能单独关闭 deploy-facing 或 stateful family。
- `proof_kind`：RED/GREEN、真实输出验证、payload shape assertion、side-effect ledger assertion、template/render/upload/metadata proof、DB/transaction proof 或明确 blocker。
- `red_expectation`：RED 期望失败点。若 RED 未失败、0 tests run、只验证静态存在或被测试基础设施阻塞，verifier 必须阻止 `DONE` 并输出 cap / 下一片强制目标。
- `fail_closed_condition`：本片缺少 carrier、proof、RED 或 sibling closure 时的停线动作；不得只写“人工判断”或“后续补充”。

runner contract schema validation 必须发生在第一片 slice 之前。若 runner contract 只包含 broad family、touched family、fail-closed 文案或 verifier assertion，但缺少上述 `target_subsurface_or_carrier`、`required_sibling_surfaces`、`production_boundary`、`proof_kind`、`red_expectation`、`fail_closed_condition` 任一字段，则不得开始或继续 replay；必须立即输出 `tooling_enforcement_stop`，并把缺失字段列成下一轮 runner/prompt/verifier 修复项。

Carrier 语义校验必须发生在第一片实现前，而不是等实现后靠覆盖率扣分。高权重 core / deploy-facing slice 的 prompt 必须输出：`selected_carrier`、`production_boundary`、`downstream_side_effect_or_output`、`forbidden_substitute_check`、`why_this_is_not_a_test_only_seam`。runner / verifier 若发现 carrier 是空实现、仅供 override 的保护 seam、Noop/Stub/Fake/Dummy/Placeholder/Scaffold 类替代物、只被测试子类计数证明、或没有下游生产服务调用 / 状态写入 / 外部输出，必须输出 `tooling_enforcement_stop`，并标记 `wrong_test_surface` 或 `synthetic_carrier_gap`；该 slice 不得算 core entry closure。

RED / proof verifier 必须 fail closed。对 core-entry、stateful 或 deploy-facing slice，若出现 `red_phase_did_not_fail`、`tdd_red_not_replayed`、0 tests run、RED 被测试基础设施阻塞且没有明确环境 blocker、subclass-only proof、static/no-op proof 或 synthetic carrier proof，则设置 `has_behavior_evidence=false`、`executable_delta=0`，并给出 `wrong_test_surface` / `feedback_loop_blocker` / `synthetic_carrier_gap`。高权重 core-entry slice 在这种情况下的 coverage cap 默认不得高于 10，除非报告明确把阻断归类为环境或基线 blocker；GREEN proof 必须命名被调用的生产方法，以及一个外部可见输出或 stateful side-effect 断言。

Fresh replay 前先运行 cost-bounded dry-run gate。dry-run 只读取 first-slice proof plan、runner enforcement contract、slice result / verifier output、round result 和当前 diff metadata，输出 `STOP`、`ALLOW` 或 `BLOCKED_PLAN_MISMATCH`。若 dry-run 命中 no-op carrier、wrong-surface proof、缺 RED、缺 runner schema 或 artifact mismatch，runner 不得加载宽泛项目上下文、不得运行 Maven、不得请求实现；必须先报告停线原因和下一项 runner / prompt / verifier 修复。

多阶段规划器还必须在下游 tournament、selection 或 implementation contract 运行前校验阶段输入产物：

- `required_stage_artifacts`：列出下一阶段必须读取的候选计划、选择结果、contract、matrix、ledger、test charter 或 verifier 输入文件。
- `artifact_owner`：说明由 runner 生成、由 prompt 产出、由人工提供，还是允许从现有 contract 合成。
- `synthesis_authorization`：缺少候选产物但允许合成时，必须有显式授权和合成来源；没有授权时不得静默合成。
- `fail_closed_condition`：任一 required artifact 缺失、为空、不可解析或未经授权合成时，必须在进入下一阶段前输出 `tooling_enforcement_stop` 或 `BLOCKED_PLAN_MISMATCH`。
- `verifier_assertion`：验证器必须检查 required artifact 清单与实际文件一致；不能在缺少候选计划或 selected candidate 时授权第一片 RED/GREEN。

若上游探索已给出 first slice，但候选计划 tournament 没有完整输入或没有 selected candidate，该 first slice 只能作为 non-authorizing ledger 保留；Phase 1 必须 `STOP_AND_REPORT`，不得把探索建议当作已授权实现计划。

额外停线规则：

- 同一 deploy-facing family 有多个显式 sibling endpoint/carrier 时，不得用“一个 endpoint 已闭合”代表整个 family；未闭合 sibling 保持 `executable_surface_slice_gap`。
- `core_entry` hook 与 `stateful_core_path` closure 分开记账。入口可达、负向隔离或浅层 orchestration 只能证明 tracer bullet；状态写入、日志/进度/任务、事务/rollback、成功链路和 must-not 副作用必须有独立 side-effect proof。
- Exact contract slice 必须在生产请求构造、DB/wire/display 字段、payload shape、模板元数据或外部协议边界断言；相似语义字段、包装层级不同、大小写不同或只在 DTO/helper 中断言，都保持 `exact_contract_gap`。
- Generated artifact slice 必须证明 template/render/upload/metadata 或等价真实链路；仅生成文件名、常量、synthetic bytes 或 mock 上传成功不能关闭 artifact family。
- OCR/外部 payload slice 必须有 request-shape assertion；只有 DTO 字段存在、mock 响应或静态 JSON 片段时，保持 `exact_contract_gap` 或 `wrong_test_surface`。
- `red_phase_did_not_fail`、`tdd_red_not_replayed`、0 tests run 或 RED 被测试基础设施阻塞时，该 slice 的 executable delta 记为 0，不得 `DONE`，并按证据面设置 coverage cap；高权重核心/入口类 slice 默认 cap 不得高于 45，且 runner 应设置 `should_continue=false` 直到下一片补出可运行 RED。
- 新增 fresh replay 前，若上一轮已经暴露最高权重 open carrier，必须先生成一页以内的 `FIRST_SLICE_PROOF_PLAN` 或等价 runner contract：`highest_weight_open_gate -> carrier candidates -> selected carrier -> must-not siblings -> first RED command -> expected diff families -> stop condition`。缺失时先停线，不加载宽泛上下文或实现 supporting DTO/helper/config。
- 若允许 `FIRST_SLICE_PROOF_PLAN` 的等价 runner contract，runner / prompt / verifier 必须共享同一份 artifact acceptance registry。存在等价 contract 时，不得只因固定文件名缺失而停线；必须改为校验等价 contract 的 schema，并把缺失字段报告为 `tooling_enforcement_stop`。若 runner 决定固定文件名是唯一授权产物，则 prompt 必须产出该文件，规则文本也不得继续写“等价”。
- 复用已经生成的 slice artifacts 做 replay/深审时，runner 在遇到停线条件前必须继续登记后续已存在的 slice 文件和 verifier 输入，避免 deep review 丢失证据；登记不等于授权继续实现。

若本轮无法修改真实 runner / prompt / verifier，必须在 evolution history 中写明替代落点与剩余缺口；不得把重复 gap 记录成普通 no-op，也不得把 reference 文本存在当作执行器已落实的证据。

### Stop-Loss Enforcement Experiment Contract

当 stop-loss 或 evolution proposal 明确要求 `STOP_AND_EVOLVE`，且重复 gap 全部映射到既有 8 gate 的 `already-covered-but-not-enforced` 时，fresh replay 仍不得直接开始。下一轮 runner / prompt / verifier 至少先闭合 dry-run 与四项可证伪 enforcement experiment；缺一项即输出 `tooling_enforcement_stop`：

1. **first-slice dry-run**：在加载宽泛上下文、运行 Maven 或发出实现 prompt 前，只读取上一轮 stop-loss 摘要、family ledger、runner contract、first-slice proof plan 或等价 contract、当前 diff metadata；输出 `STOP`、`ALLOW` 或 `BLOCKED_PLAN_MISMATCH`，并列出最高权重 open gate、selected carrier、proof kind 和 fail-closed condition。
2. **runner invocation smoke**：在发出任何实现 slice 前，runner 必须用同一 command registry 校验实际执行命令和脚本参数契约；dry-run/no-op、参数 introspection 或等价静态校验均可。若 wrapper 或 prompt invoker 使用目标脚本不支持的参数、shell quoting 不可复现、或命令无法在当前 host 非交互执行，立即写 `tooling_enforcement_stop`、`runner_invocation_error`，且该 slice 的 `implemented_files=[]`、`has_behavior_evidence=false`、`authorized_for_synthesis=false`。
3. **fail-closed evidence authorization**：verifier 必须把 `red_phase_did_not_fail`、`tdd_red_not_replayed`、0 tests run、executor-blocked slice、synthetic carrier、static-only proof、shallow service proof、helper-only assertion、mock-only proof 归为 non-authorizing evidence；对高权重 core / stateful / deploy-facing slice 设置 `executable_delta=0`、`authorized_for_next_slice=false`、`authorized_for_synthesis=false`，除非已明确分类为环境或基线 blocker。synthesis runner 只有在 required families 全部 closed，或输出显式 STOP / EVOLVE 时，才能继续写最终报告。
4. **highest-weight open family router**：每个 slice 后从 requirement family ledger 选择仍为 `OPEN/PARTIAL` 的最高权重 required family；下一片必须映射到该 gate、具体 subsurface/carrier、production boundary、proof command 和 stop condition。若 proposed slice 继续落在已触达的 helper/config/core-only support，而 deploy-facing/generated/external/stateful family 仍 open，runner 必须停线。若该 family 有 blocker，blocker 必须包含证据；否则不能绕路到更容易的 slice。
5. **proof-type registry and ledger cap for family closure**：`FAMILY_CONTRACT` 或等价 ledger 必须声明每个 required family 的 `required_proof_type`，verifier 必须从 slice result 写出 `actual_proof_type` 并比较。`stateful_side_effect`、`wire_payload`、`rendered_artifact`、`export_output`、`lifecycle_cleanup` 等行为 family 不能被 DTO/entity/constant/file-presence/mock-only proof 关闭；不匹配时保持 `OPEN/PARTIAL`，并标记 `wrong_test_surface`、`shallow_module`、`exact_contract_gap` 或 `executable_surface_slice_gap`。coverage cap 必须从 required family ledger 状态计算：任一 required family 仍为 `OPEN/PARTIAL`、任一 touched family 缺 `required_proof_type/actual_proof_type`、或存在 executor-blocked/no-production-boundary slice 时，`coverage_cap_from_ledger` 不得为 100，并必须登记 `no_progress_slices` 或等价 blocker。

history / changelog 只能把这类变更记为 `tooling-evolution-needed` 或 `source-change-with-runner-gap`；不能因为本 reference 已写入规则就声明真实执行器已经完成。新 replay 只有在 dry-run、runner invocation smoke、evidence authorization、highest-weight router、proof-type registry 和 ledger cap 都能对当前证据 fail closed 后，才允许至多进入一轮 fresh replay，并在该轮结束后重新做 stop-loss check。

### Stop-Loss Experiment Validation Contract

当 deep replay review 已输出 `STOP_AND_EVOLVE`，且 `NEXT_EXPERIMENT_PLAN` 把修复收敛为 <=3 个 falsifiable experiments 时，本 reference 只能吸收跨项目执行约束，不能吸收 replay root、oracle commit、项目类名或文件名。进入下一轮 fresh replay 前，runner / prompt / verifier 必须留下三类 validation evidence；缺任一类时保持 `tooling_enforcement_stop`：

1. **dry-run stop validation**：dry-run 必须在加载宽泛上下文、运行构建或发出实现 prompt 前读取 stop-loss、family ledger、runner contract、first-slice proof plan 或等价 contract、diff metadata，并输出 `STOP` / `ALLOW` / `BLOCKED_PLAN_MISMATCH`。输出至少包含 `highest_weight_open_gate`、`selected_carrier`、`target_subsurface_or_carrier`、`production_boundary`、`proof_kind`、`red_expectation`、`fail_closed_condition`；缺字段时只能 STOP，不能授权实现。
2. **carrier/evidence authorization validation**：slice verifier 必须把 `selected_carrier`、`production_boundary`、`downstream_side_effect_or_output`、`forbidden_substitute_check`、`why_this_is_not_a_test_only_seam` 作为高权重 core / stateful / deploy-facing slice 的授权字段。RED 未失败、未重放、0 tests、helper/static/mock/subclass-only proof、replay-local carrier 或缺生产边界时，必须设置 `authorized_for_next_slice=false`、`authorized_for_synthesis=false`、`executable_delta=0`，并保持 family `OPEN/PARTIAL`。
3. **highest-weight router and ledger-cap validation**：每片后 runner 必须从 required family ledger 选择最高权重 `OPEN/PARTIAL` family，并要求下一片写出 `target gate -> family -> sibling surface -> production carrier -> proof command -> stop condition`。若 proposed slice 不命中 router 目标且无 verifier-approved blocker，输出 `BLOCKED_PLAN_MISMATCH`；只要任一 required family 仍 `OPEN/PARTIAL`、proof type 不匹配或存在 no-progress slice，最终状态不得是 `PASS`，`coverage_cap_from_ledger` 不得为 100。

这些 validation evidence 可以来自真实脚本、dry-run/no-op 模式、参数 introspection 或等价静态校验，但必须可复跑、能 fail closed，并把拒绝原因绑定到具体 schema 字段。若本轮只能修改 reference / prompt 文本而不能修改真实 runner / verifier，history 必须标为 `source-change-with-runner-gap`，并列出仍需脚本化验证的命令形态。

#### Stop-Loss Falsifiable Artifact Schemas

当 stop-loss review 已把下一步收敛为三个实验时，runner / prompt / verifier 不得再用泛化描述代替可检查产物。fresh replay 前至少生成或等价静态校验以下 schema；字段缺失、空值或无法证明生产边界时，输出 `tooling_enforcement_stop`，不得发出实现 slice：

1. `CARRIER_AUTHORIZATION`：读取 requirement family ledger，输出 `real_entry`、`selected_carrier`、`production_boundary`、`downstream_side_effect_or_output`、`forbidden_synthetic_carrier`、`authorization=ALLOW|STOP`。若 carrier 只是新 helper/service、只打日志、只委托、没有真实入口可达性或缺下游状态写入/外部输出，必须 `STOP`。
2. `EXACT_CONTRACT_ASSERTION_MATRIX`：对每个固定字段、取值、文案、来源或顺序输出 `literal`、`symbol_or_field`、`db_or_wire_or_display`、`test_assertion`、`status`、`touched`。被触达的 exact-contract family 若仍为 `OPEN` 且没有断言或 blocker，verifier 必须保持 family open，并标记 `exact_contract_gap`。
3. `SIDE_EFFECT_EVIDENCE`：对 core/stateful family 输出 `entry_call`、`state_before`、`expected_writes_or_outputs`、`must_not_writes`、`test_name`、`red_result`、`green_result`。除非 `red_result=BUSINESS_ASSERTION_FAILED` 且 `green_result=PASS`，或存在已分类的环境/基线 blocker，否则 executable delta 为 0；static-only、mock-only、helper-only、compile-only 或 subclass-only proof 一律 non-authorizing。

这些 artifact 名称是 schema anchor，不是项目路径或唯一文件名要求；runner 可以使用等价文件名，但必须保留同等字段、fail-closed 条件和可复跑验证命令。

### Stop-Loss Fail-Closed Refinements

fresh replay 前的验证器和合成器还必须处理三类常见假进步：

1. **planned carrier is not authorization**：`selected_carrier`、`target_subsurface_or_carrier`、`production_boundary` 或 `downstream_side_effect_or_output` 只写 planned、candidate、TBD、pending、helper-only、static-only、DTO/entity/constant carrier、无下游生产输出时，必须 `STOP`。这些内容最多是计划或支持证据，不能授权实现 slice，也不能进入 synthesis。
2. **exact contract gaps fail closed**：被触达的 fixed field、fixed value、payload shape、wire/display name、ordering、must-not 或 literal family 若仍带 `exact_contract_gap`，verifier 必须设置 `has_behavior_evidence=false`、`executable_delta=0`、`authorized_for_next_slice=false`、`authorized_for_synthesis=false`，并保持 family `OPEN/PARTIAL`，直到生产边界断言或明确 blocker 存在。
3. **ledger cap overrides round synthesis**：round-level `verification_capped_coverage` 必须服从 required family ledger 的 `coverage_cap_from_ledger`。若任一 required family 仍为 `OPEN/PARTIAL`、proof type 不匹配、存在 no-progress slice、或 `final_pass_allowed=false`，合成器必须下调 coverage 并禁止最终 `PASS`；最后一个 slice 的局部 cap 不能覆盖全局 ledger cap。

## Trace Distillation / Harness Tuning

从 replay、历史会话、论文笔记或外部方法论提炼规则时，先做蒸馏审查，再决定是否改技能或执行器：

1. **Raw evidence first**：优先读取完整执行轨迹、diff、日志、验证输出、ROUND 文档和 verifier 输入；只有摘要、分数或二手结论时，不得直接生成新 gate。
2. **Verified root cause**：失败分析必须能用最小修复、最小 proof、真值对比或可复跑命令解释；找不到可验证根因的建议丢弃或标 `needs_more_trace_evidence`。
3. **Anti sequential drift**：不要边跑边把每一轮偶然结论写进技能。先把多轮补丁放入候选池，按重复频次、高权重 family、可迁移性和冲突情况合并。
4. **Control signal over document dump**：可吸收内容必须压缩成触发条件、停线条件、artifact schema、runner/prompt/verifier assertion 或 coverage cap；长篇解释只进 wiki 或 history。
5. **Question/delete/simplify before automation**：自动化 replay 或 runner 前，先质疑该步骤是否必要、删除冗余上下文和低价值 slice、简化停线条件，再加速或自动化。

蒸馏结果分类：

| result | meaning | action |
|--------|---------|--------|
| `new_cross_project_failure_class` | 现有 8 gate 不能承载，且有可验证多例证据 | 修改 owner skill 或本 reference |
| `covered_but_not_enforced` | 现有 gate 已覆盖但 runner/prompt/verifier 未执行 | 改执行约束，不新增同义 gate |
| `candidate_only` | 有启发但缺 raw evidence、根因 proof 或重复证据 | 只写 wiki/history，不进入运行链 |
| `project_specific_memory` | 依赖项目路径、类名、表名、业务事故或公司命令 | 写项目规则或项目记忆 |
| `discarded_unverified_patch` | 根因无法复现或最小 proof 不能解释失败 | 不吸收 |

## Finding Promotion Gate

replay/eval 发现不是生产需求。进入 `delivery` 前必须转成：

1. 人工确认的需求项或已接受的 `tech-design.md` 决策；
2. 对齐后的 OpenSpec change；
3. expected code surface / ownership boundary；
4. test assertion 或本地不可测原因；
5. `sync-progress` 目标。

未完成 promotion 时，只能保留在 replay 报告、审计报告或项目记忆中。

## Minimal Eval Anchors

用于验证本 reference 是否被正确触发：

- should-trigger: 用户说“做一次 blind replay / oracle 后验 / 技能实测 / 历史重跑”。
- should-trigger: 用户给 baseline 和需求源，并要求多轮隔离验证。
- should-not-trigger: 用户只是要求实现一个正常需求、修 bug、写技术方案或只读排查。
- pressure scenario: 用户在同一会话已经看过 oracle，仍要求“重新 blind replay”；正确行为是建议新会话或外部隔离子进程，并披露污染风险。
