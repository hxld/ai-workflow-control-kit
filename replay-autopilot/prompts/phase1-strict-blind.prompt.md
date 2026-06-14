你现在要执行 {{FEATURE_NAME}} strict blind replay，目标是验证当前工作流是否能在只读需求文档、禁止 oracle 污染的条件下，独立做到可信 90% 覆盖。

【固定上下文】
- 主仓库: {{PROJECT_ROOT}}
- feature_name: {{FEATURE_NAME}}
- requirement_source: {{REQUIREMENT_SOURCE}}
- oracle identity: redacted in Phase 1; direct oracle refs are forbidden
- base commit: {{BASE_COMMIT}}
- replay root: {{REPLAY_ROOT}}
- isolated worktree: {{WORKTREE}}
- neutral baseline index: {{BASELINE_INDEX}}
- context manifest: {{CONTEXT_MANIFEST}}
- system context dir: {{SYSTEM_CONTEXT_DIR}}
- run label: {{RUN_LABEL}}
- round: {{ROUND_ID}}

【Phase 1 目标】
只做 strict blind implementation replay。
禁止读取 oracle branch/commit/diff/历史实现/旧 replay 报告。
禁止读取任何 ROUND_RESULT、FINAL_REPLAY_REPORT、历史会话总结、oracle 后验报告。

只允许使用：
1. requirement_source
2. repo rules: AGENTS.md, CLAUDE.md, .memory/build-test-profile.yaml
3. isolated worktree 当前代码
4. 当前已安装技能/工作流规则
5. 本轮 Phase 0 产物：`{{REPLAY_ROOT}}\ROUND_CONTRACT.md`、`{{REPLAY_ROOT}}\PHASE0_RESULT.md`
6. 本轮 Phase 0.5 规划产物：`{{REPLAY_ROOT}}\EXPLORATION_REPORT.md`、`{{REPLAY_ROOT}}\PLAN_RESULT.md`、`{{REPLAY_ROOT}}\REPLAY_PLAN.md`、`{{REPLAY_ROOT}}\IMPLEMENTATION_CONTRACT.md`、`{{REPLAY_ROOT}}\EXPECTED_DIFF_MATRIX.md`、`{{REPLAY_ROOT}}\SIDE_EFFECT_LEDGER.md`、`{{REPLAY_ROOT}}\TEST_CHARTER.md`
7. `{{BASELINE_INDEX}}`，但只能作为中性结构索引，不能作为结论来源
8. `{{CONTEXT_MANIFEST}}` 以及其中列出的 `{{SYSTEM_CONTEXT_DIR}}` 只读上下文文件；只能作为通用系统背景，不能替代本轮计划和代码事实

【BASELINE_INDEX 使用纪律】
- 允许用它减少重复读取：需求标题、规则文件存在性、模块/文件族数量、可复现搜索命令。
- 禁止从它继承 selected real entry、core path、上一轮 gap、oracle 后验、旧 replay 分数或实现建议。
- 如果发现 `BASELINE_INDEX.md` 含有上述结论性内容，必须在 `ROUND_RESULT.md` 标记 `context_contamination_risk`，并忽略该文件。
- strict blind 分数只认本轮 Phase 0/Phase 1 独立判断和本轮实现证据。

【上下文预算纪律】
- 优先用 `rg` / `rg --files` / `Select-String` 定位文件和行号。
- 当前执行环境会通过 `RIPGREP_CONFIG_PATH` 默认排除 `.git`、`target`、生产 SQL、min/map 文件和 `example-web/src/main/webapp/**`；只有需求明确要求前端或 SQL 证据时，才用精确路径和小窗口临时解除。
- PowerShell 下不要把 `claim-*` 这类裸通配作为路径参数传给 `rg`；用 `rg PATTERN . --glob 'example-core/**'`，或传精确目录列表。
- 禁止把大型源码文件、日志、XML、JS、需求文档或搜索结果整文件输出到对话；任何单次读取控制在约 80 行以内。
- 读取文件时先用 `Select-String -Context` 或按行窗口读取，只打开与当前 slice 直接相关的片段。
- 不要用 `Get-Content -Raw` 或无窗口 `Get-Content` 读取 `requirement_source`、`SKILL.md`、大型 Java/XML/SQL/JS 文件；先用标题/关键词定位，再读必要窗口。
- 当前已安装技能/工作流规则只作为执行约束；除非某个技能被当前步骤直接触发，否则不要读取整篇技能正文或参考文档。
- 不要把 `rg --files`、`Get-ChildItem -Recurse`、大范围 `git diff` 的完整输出贴入上下文；需要时只统计、过滤或取前后小窗口。
- 如果上下文接近上限或需要读超大文件，先写 `ROUND_RESULT.md` 标记 `workflow gate / context_budget_blocker`，不要继续扩散读取。
- 最终回答只总结产物路径和状态，不粘贴大段 diff 或源码。

【必须先做】
1. 确认 cwd 是 isolated worktree。
2. 读取 `{{REPLAY_ROOT}}\PHASE0_RESULT.md` 和 `{{REPLAY_ROOT}}\ROUND_CONTRACT.md`。
3. 如果 Phase 0 不存在或 `phase0_status` 不是 `PROCEED`，不得实现；直接写 `ROUND_RESULT.md`，`final status=INVALID_REPLAY`。
4. 读取 `{{REPLAY_ROOT}}\PLAN_RESULT.md`。如果不存在或 `plan_status` 不是 `PROCEED`，不得实现；直接写 `ROUND_RESULT.md`，`final status=INVALID_REPLAY`。
5. 读取并遵守 `REPLAY_PLAN.md`、`IMPLEMENTATION_CONTRACT.md`、`EXPECTED_DIFF_MATRIX.md`、`SIDE_EFFECT_LEDGER.md`、`TEST_CHARTER.md`。任一缺失时不得实现；直接写 `ROUND_RESULT.md`，`final status=INVALID_REPLAY`。
6. Phase 1 不允许重新大范围探索或临场替换主线。若计划中的真实入口、字段契约或测试策略被当前代码事实推翻，停止编码并写 `final status=BLOCKED_PLAN_MISMATCH`，不要改成低风险 helper/DTO/静态 guard 继续。
7. 若需要补写或修正 ROUND_CONTRACT.md，必须先完成；ROUND_CONTRACT.md 写完前不得开始生产代码实现。
8. ROUND_CONTRACT.md 必须包含：
   - source_of_truth 分类
   - forbidden_sources
   - requirement coverage ledger
   - 8-Gate Compliance Ledger
   - Expected Diff Matrix
   - Behavior Test Charter
   - Real Entry Discovery Matrix
   - Critical Surface Allocation Plan
   - core_path first executable slice
   - supporting_surface executable slices
   - exact contract ledger
   - side-effect ledger
   - feedback loop plan
   - tracer bullet sequence
   - coverage cap rules

【收敛后的 8 个产品化门禁】
后续所有判断都围绕这 8 个门禁输出。不要再发明新的 gate 名称；若发现新风险，先归入最接近的主门禁，并在 ROUND_RESULT.md 里说明是否需要后续收敛。

1. Source-of-Truth Gate
   - 冻结 requirement_source、repo rules、code surface、forbidden sources。
   - ROUND_CONTRACT.md 写完前不得实现。
   - 任何需求项必须能追溯到 requirement coverage ledger。

2. Oracle Isolation Gate
   - Phase 1 禁止读取 oracle branch/commit/diff、历史实现、旧 replay 产物、历史会话总结。
   - ROUND_RESULT.md 必须写 oracle_used=false 和 forbidden_source_check。

3. Requirement Contract Gate
   - 冻结业务术语、同词多义和固定字面量。
   - 字段、列名、flag、type、enum、payload shape、展示列必须写成：
     literal -> code symbol -> DB/API/wire name -> exact value/shape -> owner -> test assertion
   - 只“大致命中语义”不得计入 DONE。

4. Surface Coverage Gate
   - 对需求显式点名的入口、报表、导出、前端展示、模板、图片生成/上传、OCR payload、自动化测试接口、日志删除等 surface，逐个列：
     surface -> entry -> carrier/query/write -> output/display -> executable proof
   - 同类 surface 不能互相代表。
   - 缺真实承载文件族或可执行最小切片时，标 executable_surface_slice_gap。

5. Core-First Budget Gate
   - 先完成最高权重 core_path 的真实生产入口和最小可执行闭环，再做 DTO/entity/mapper/helper 支撑面。
   - core_path 必须接入真实入口，例如 processor/controller/facade/worker/exporter/mapper/scheduler。
   - 开始实现前必须写 Real Entry Discovery Matrix：
     requirement event/literal -> candidate production entries -> evidence from code -> rejected entries with reason -> selected real entry -> first RED test.
   - 至少比较 2 个候选真实入口；如果只找到 1 个，必须记录搜索关键词、路径范围和为什么没有第二候选。
   - 首个 executable slice 必须从选定真实入口触发业务行为；不能先实现孤立 service/helper，再回头找入口。
   - supporting slice first 是硬失败：如果第一刀落在 DTO/entity/mapper/config/log/OCR/report/export/helper/static guard，而不是 core_path 真实入口，必须停止实现并写 `final status=INVALID_REPLAY`。
   - 如果真实入口选择证据不足，先停止扩展支撑面，标 real_entry_gap，并把 verification_capped_coverage 封顶到 40%。
   - 只新增 service/helper/mock-only GREEN 不得算 core DONE；未闭环标 core_entry_unclosed 或 real_entry_gap。
   - “失败不阻断主链”只表示失败隔离，不代表功能可跳过；必须同时覆盖成功路径和失败隔离。

6. Executable Evidence Gate
   - 严格按 RED -> 最小 GREEN -> 下一行为推进。
   - 每个 slice 记录 changed files -> tests/build -> remaining risk -> rollback boundary。
   - 反馈信号优先是真实入口测试、DB/事务测试、集成测试或可运行 contract guard；static-only guard 只能支撑低权重证据。
   - 首个 RED 必须优先打在真实入口或其最近的可执行边界；如果因为测试设施限制只能打 helper/static guard，必须写明限制，并把该 slice 记为 support evidence 而不是 core evidence。
   - 最终验证只有 compile、无任何行为测试时，verification_capped_coverage 最高 45%；有行为测试但未覆盖真实入口时，最高 55%；真实入口覆盖但状态/落库/事务副作用未验证时，最高 70%。
   - 状态流转、任务状态、进度、日志、落库、事务/回滚、失败隔离必须列 side-effect ledger。
   - 缺 DB/事务级验证时标 needs_transaction_test 或 side_effect_ledger_gap。
   - 测试打到错误 seam、mock-only 或浅层 pass-through 时标 wrong_test_surface / shallow_module / mock_behavior_gap。
   - 出现非预期编译/测试/运行失败，停止新增功能，记录命令、首个错误、根因分类和修复/阻塞结论。

【Minimum Deliverable Slice 追加硬门禁】
Phase 1 不能以“入口接线 + helper/service + 终端日志/flag 测试”作为 core_path 完成证据。只要 Phase 0 选中的 core path 涉及状态、落库、任务、进度、日志、事务、生成物、导出或外部 payload，第一批实现和测试必须至少闭合以下链路中的核心副作用：

`selected real entry -> orchestration -> persistence/query/write -> state/task/progress/log side effects -> failure isolation -> executable proof`

如果受本地环境限制无法做 DB/事务或真实输出验证，必须在 ROUND_RESULT.md 写 `side_effect_ledger_gap` / `needs_transaction_test` / `executable_surface_slice_gap`，并且 verification_capped_coverage 不得超过 45%。不能用 terminal artifact（成功日志、最终 flag、导出列名、页面标签）替代产生该 artifact 的入口/编排/副作用链。

【Exact Naming 追加硬门禁】
字段、列名、flag、enum、payload type、展示列必须优先来自 requirement_source 和当前代码命名证据。禁止仅凭中文语义自由翻译。若只能推断命名，必须在 exact contract ledger 标记 `exact_contract_gap`，并把相关需求项从 DONE 降为 PARTIAL。

【Deploy-Facing Budget 追加硬门禁】
达到或接近 90% 前，显式 deploy-facing surface 必须至少有一个可执行最小切片：report/export/page/template/generated artifact/OCR/API/external payload/task。只有 static guard、文件存在检查、blocker 行或 helper-only 实现时，必须标 `executable_surface_slice_gap` 并降 cap；不能把这些 surface 记为已完成。

7. Coverage Cap Gate
   - 高权重 core_path、deploy-facing surface、exact contract、状态副作用或可执行证据未闭环时，不得报 90%。
   - static-only、helper-only、blocker-only、mock-only 只能降权或封顶，不能算 DONE。
   - ROUND_RESULT.md 必须写 verification_capped_coverage 和 coverage cap reason。

8. Evolution Abstraction Gate
   - gap root cause 必须映射到上述 8 个主门禁之一。
   - 只能把跨项目成立的门禁、路由、验证纪律或报告格式作为后续技能进化候选。
   - 项目路径、类名、表名、commit、replay root、业务需求编号只能留在 replay 报告或项目记忆，禁止写进通用技能。

【实现要求】
- 严格 TDD：新行为先 RED，再 GREEN。
- Phase 1 的职责是执行已冻结规划，不是重新规划。优先按 `REPLAY_PLAN.md` 的 slice 顺序推进；若预算不足，先闭合最高权重 core side-effect slice，并在 ROUND_RESULT.md 记录未执行 slice 和 cap。
- 使用 Maven 必须带：
  - -s D:\maven\settings\settings.xml
  - -f {{WORKTREE}}\pom.xml
- PowerShell 必要时使用 mvn --%。
- 测试优先覆盖真实入口、状态副作用、exact contract、must-not 行为。
- 实现预算优先级：真实入口 RED/GREEN -> 状态/落库/副作用 ledger -> deploy-facing surface -> DTO/mapper/config 支撑面。支撑面不得消耗第一优先级预算。
- 不得修改主工作区 {{PROJECT_ROOT}}。
- 不得读取 oracle 或旧 replay 产物。
- 不得清理 worktree 或日志证据。
- 不得因为计划复杂就降级为入口钩子、service 骨架、DTO/config 支撑面；如无法按计划执行，输出 BLOCKED_PLAN_MISMATCH。

【评分要求】
Phase 1 只能输出：
- blind_self_assessed_coverage
- verification_capped_coverage
- final status: PASS / PARTIAL / BLOCKED / INVALID_REPLAY

严禁输出 oracle_adjusted_coverage。
严禁读取 oracle 后验材料。
如果高权重 core_path 或 deploy-facing surface 未闭环，不能报 90%。
如果 first executable slice 不是 core_path，必须输出 `blind_self_assessed_coverage=0`、`verification_capped_coverage=0`、`final status=INVALID_REPLAY`，并且不得继续实现 supporting slice。

【产物】
在 replay root 写：
1. ROUND_CONTRACT.md
2. ROUND_RESULT.md

ROUND_RESULT.md 必须包含：
- replay root
- isolated worktree
- base commit
- oracle_used=false
- forbidden_source_check
- implemented slices
- plan_files_used
- plan_deviation_or_blocker
- tracer bullet log
- 8-Gate Compliance Ledger 结果
- Expected Diff Closure Ledger
- exact contract ledger
- side-effect ledger
- executable surface slice ledger
- tests run with commands and results
- blind_self_assessed_coverage
- verification_capped_coverage
- coverage cap reason
- final status
- gap root cause 分类：requirement / design / implementation / test / verification / workflow gate

开始执行 Phase 1。
