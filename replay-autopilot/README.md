# Replay Autopilot

这个目录用于把 AI 编码 replay 任务从“人工复制 prompt”推进到“脚本化循环执行”：准备隔离 worktree、调用本地 agent CLI、收集日志、解析 Phase 1/Phase 2 报告、生成技能进化提案，并在显式授权时触发受控技能进化。

## 路径配置（可移植性）

命令示例中 `.\scripts\...` 假定当前目录是 `replay-autopilot/` 根。指向业务项目和回放产物的路径通过环境变量驱动，不再硬编码到作者机器：

| 环境变量 | 含义 | 命令示例中的形式 |
|----------|------|------------------|
| `AI_WORKFLOW_PROJECT_ROOT` | 业务项目根 | `<PROJECT_ROOT>`（文档）|
| `AI_WORKFLOW_REPLAY_EVIDENCE_ROOT` | 回放产物根 | `$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT` |
| `AI_WORKFLOW_REPLAY_ROOT` | 父目录（少用） | `$env:AI_WORKFLOW_REPLAY_ROOT` |

仓库自身资源（`templates/`、`tools/`、`scripts/`）通过 `$PSScriptRoot` 解析，无需配置。在 `config.yaml` 顶部也有同名说明。

**关于 `scripts/Test-v*.ps1`：** 这些是作者本地回归测试，断言和 fixture 数据引用了作者的历史 replay 产物（如 `changed_files:` evolution 结果、特定 run-id 目录）。它们需要作者本地的 evidence 树才能实际运行；在别的机器上即使设置了上面的环境变量，缺少对应 fixture 仍会 skip 或失败。这是已知的产品化边界，留给后续 Stage 3（可评测演化）处理。

## 文件

- `config.yaml`：项目、base/oracle、replay root、目标覆盖率、executor、分阶段模型、熔断阈值配置。
- `prompts/phase0-contract-gate.prompt.md`：Phase 0 exploration/contract prompt 模板，读取需求、代码和系统上下文，判断第一刀是否命中 core path。
- `prompts/phase-plan-tournament.prompt.md`：Phase 0.5 plan tournament prompt 模板，多方案择优并冻结实施合同。
- `prompts/phase1-strict-blind.prompt.md`：Phase 1 legacy strict blind prompt 模板，保留给人工直跑。
- `prompts/phase1-slice-executor.prompt.md`：Phase 1 单 slice 执行模板，由脚本循环调用。
- `prompts/phase1-round-synthesis.prompt.md`：Phase 1 slice 结果收口模板，生成 `ROUND_RESULT.md`。
- `prompts/phase2-oracle-posthoc.prompt.md`：Phase 2 oracle post-hoc prompt 模板。
- `prompts/skill-evolution.prompt.md`：受控技能进化 prompt 模板。
- `scripts/Start-ReplayRound.ps1`：准备单轮 replay 目录、worktree、context manifest 和 Phase 0/0.5/1/2 prompt。
- `scripts/New-BaselineIndex.ps1`：生成 strict blind 可读取的中性结构索引 `BASELINE_INDEX.md`。
- `scripts/Invoke-AgentPrompt.ps1`：调用 `codex exec` 或 `claude --print`，并保存 stdout/last-message/metadata。
- `scripts/Parse-ReplayReport.ps1`：解析 `ROUND_RESULT.md` / `FINAL_REPLAY_REPORT.md`，输出 `AUTOPILOT_SUMMARY.md`。
- `scripts/Write-ControlPlaneSummary.ps1`：生成文件型控制层输出：`RUN_CONTROL_SUMMARY.md/json`、`BLOCKER_FINGERPRINTS.json`、`STAGNATION_DECISION.json`、`_control/RUN_CONTROL_LATEST.*` 和 `_control/MORNING_BRIEF.md`。
- `scripts/Write-GoldenDeliverySlice.ps1`：把控制层里的重复 blocker 转换成正向第一刀样板，输出 `GOLDEN_DELIVERY_SLICE.md/json`、`GOLDEN_DELIVERY_SLICE_PROMPT.md` 和最新 replay root 内的 `NEXT_GOLDEN_DELIVERY_SLICE.*`。
- `scripts/Write-ReplaySessionSummary.ps1`：从 `$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT` 下的 replay 产物生成可迁移恢复入口 `REPLAY_AUTOPILOT_SESSION_SUMMARY.md`，避免依赖某个 Claude/Codex 会话 memory。
- `scripts/Sync-KnowledgeBackup.ps1`：把 `replay-autopilot` 工具体、`ai-knowledge` 知识版本和轻量证据包同步到个人知识库 Git 仓库，并按白名单提交推送。
- `scripts/New-EvolutionProposal.ps1`：从 replay 报告抽取可迁移 gap，输出 `EVOLUTION_PROPOSAL.md`。
- `scripts/Run-ReplayLoop.ps1`：串联准备、执行、slice loop、解析、进化提案和熔断。
- `scripts/Run-SliceLoop.ps1`：按 Phase 0.5 计划逐个执行 slice，并在每个 slice 后调用 verifier。
- `scripts/Verify-SliceClosure.ps1`：脚本级检查 slice result、测试证据、gap flags 与 coverage cap。
- `scripts/Run-UntilKnowledgeVersion.ps1`：无人值守循环执行 replay + evolution，直到知识库版本达到目标版本或遇到阻塞。
  - 若 evolution 输出 `NO_SOURCE_CHANGE`，脚本会停止为 `STOP_NO_SOURCE_CHANGE`，避免用 no-op 进化刷知识版本。
- `scripts/Start-AgentBridge.ps1`：Claude Code 执行代理与 Codex 审查代理之间的文件协议桥接层，使用 `STATE.json`、`CLAUDE_RESULT.md`、`CODEX_REVIEW.md`、`NEXT_CLAUDE_PROMPT.md` 和 `DECISION.json` 消除人工复制粘贴。
- `scripts/Test-AgentBridgeProtocol.ps1`：Agent Bridge 协议回归测试。

## 先校验

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -ValidateOnly
```

## 可迁移恢复入口

每次 `Run-ReplayLoop.ps1` 或 `Run-CrossFeatureReplay.ps1` 结束时，都会刷新：

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\REPLAY_AUTOPILOT_SESSION_SUMMARY.md
```

这个文件只从 replay evidence、`AUTOPILOT_DECISION.md`、`FINAL_REPLAY_REPORT.md`、`EVOLUTION_RESULT.md` 等脚本产物生成，不读取 Claude/Codex 聊天 JSONL，也不绑定固定会话 ID。新会话恢复上下文时，优先读它，再按最新 replay root 深入查看具体报告。

手动刷新：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Write-ReplaySessionSummary.ps1 -EvidenceRoot $env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT -MaxRoots 80
```

## 控制层摘要

`Run-ReplayLoop.ps1` 收尾时会刷新控制层文件，目标是让无人值守循环少看、少管、少跑：

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_control\RUN_CONTROL_LATEST.md
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_control\RUN_CONTROL_LATEST.json
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_control\BLOCKER_REGISTRY.json
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_control\MORNING_BRIEF.md
```

最新 replay root 内也会写：

```text
RUN_CONTROL_SUMMARY.md
RUN_CONTROL_SUMMARY.json
BLOCKER_FINGERPRINTS.json
STAGNATION_DECISION.json
```

控制层只给一个决策类型：`CONTINUE`、`STOPLINE`、`UPGRADE` 或 `EVOLVE`。它会合并重复 blocker，检查 executor audit，识别长期无实质提升，并给出下一步建议。若判断为长期停滞，收尾阶段还会生成正向第一刀样板：

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_golden-samples\GOLDEN_DELIVERY_SLICE.md
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_golden-samples\GOLDEN_DELIVERY_SLICE.json
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_golden-samples\GOLDEN_DELIVERY_SLICE_PROMPT.md
```

`Start-ReplayRound.ps1` 会在下一轮自动把 `GOLDEN_DELIVERY_SLICE_PROMPT.md` 快照进 replay root，并追加到 Phase0 / Plan / Phase1 prompt。它的定位是正向样板：告诉模型“正确第一刀长什么样”，不是 oracle 事实。

手动刷新：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Write-ControlPlaneSummary.ps1 -EvidenceRoot $env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT -MaxRoots 80
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Write-GoldenDeliverySlice.ps1 -EvidenceRoot $env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT
```

## 知识库备份收口

`Run-ReplayLoop.ps1` 和 `Run-UntilKnowledgeVersion.ps1` 收尾时默认调用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-KnowledgeBackup.ps1 -IncludeAutopilot -IncludeKnowledge -EvidenceMode Milestone -Push
```

默认配置：

```yaml
knowledge_backup_auto_sync: true
knowledge_backup_auto_push: true
knowledge_backup_evidence_mode: Milestone
```

同步范围：

- `<REPLAY_AUTOPILOT_ROOT>` -> `learning/raw/sources/replay-autopilot`
- `<AI_KNOWLEDGE_ROOT>` 原地提交
- `<REPLAY_EVIDENCE_ROOT>` -> `learning/raw/sources/replay-evidence-lite`，只保留报告、汇总、决策、深度审查和 `_reports` 汇报材料

保护边界：

- 只 stage `learning/raw/sources/ai-knowledge`、`learning/raw/sources/replay-autopilot`、`learning/raw/sources/replay-evidence-lite`
- 不使用 `git add -A`
- 禁止把 `worktree/`、`logs/`、`.tmp/`、`.git/`、`*.log`、`*.pyc`、公司源码类文件带入 evidence lite
- 没有变更时输出 `committed=false`，不会制造空提交

## Agent Bridge：Claude 执行 + Codex 审查

Agent Bridge 用文件系统作为两个 Agent 的共享协议层，默认目录：

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_agent-bridge\current
```

核心文件：

```text
STATE.json
CLAUDE_PROMPT.md
CLAUDE_RESULT.md
CLAUDE_DONE.flag
CODEX_REVIEW_PROMPT.md
CODEX_REVIEW.md
NEXT_CLAUDE_PROMPT.md
DECISION.json
CODEX_DONE.flag
LAST_CLAUDE_RESULT.md
LAST_CODEX_REVIEW.md
LAST_NEXT_CLAUDE_PROMPT.md
LAST_DECISION.json
LAST_ARCHIVE_PATH.txt
events.jsonl
```

最小用法：

```powershell
# 初始化当前 bridge
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-AgentBridge.ps1 -Action Init -InitialPromptPath D:\path\to\first-claude-prompt.md -Force

# Claude Code 执行完后写 CLAUDE_RESULT.md 和 CLAUDE_DONE.flag，然后推进给 Codex
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-AgentBridge.ps1 -Action ClaudeDone

# Codex 写 CODEX_REVIEW.md、NEXT_CLAUDE_PROMPT.md、DECISION.json 和 CODEX_DONE.flag 后，推进下一轮
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-AgentBridge.ps1 -Action CodexDone

# 查看状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-AgentBridge.ps1 -Action Status
```

可选全自动循环会调用现有 `Invoke-AgentPrompt.ps1`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-AgentBridge.ps1 -Action RunLoop -ClaudeExecutor claude -CodexExecutor codex -MaxCycles 1
```

保护边界：

- 默认只用 `ProtectedGitRoots` 的 git dirty watchdog 做 fail-closed 检查，不修改受保护仓库 ACL。
- `-UseProtectedRootWriteDeny` 属于危险实验开关；脚本会拒绝直接启用，除非同时传 `-AllowUnsafeProtectedRootWriteDeny`。该组合只应在一次性临时目录/测试仓库中使用，不应用于 `<PROJECT_ROOT>` 主仓库。

`RunLoop` 有界执行，不会无限循环。Codex 必须写 `DECISION.json`；若 decision 为 `STOP` 或 `BLOCKED`，bridge 停止；若为 `CONTINUE` / `EVOLVE` / `DEEP_REVIEW`，`NEXT_CLAUDE_PROMPT.md` 会成为下一轮 `CLAUDE_PROMPT.md`，上一轮证据归档到 `$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_agent-bridge\runs\`。
切换到下一轮前，bridge 还会把上一轮的 Claude 结果、Codex 审查、下一步 prompt、decision 和归档路径复制到 `LAST_*` 文件；下一轮 agent 应优先读这些稳定副本，避免 current-cycle 文件被重置为空造成上下文丢失。

## 收敛口径

当前 replay prompt、post-hoc prompt、summary 和 evolution proposal 统一围绕 8 个产品化门禁输出：

1. Source-of-Truth Gate
2. Oracle Isolation Gate
3. Requirement Contract Gate
4. Surface Coverage Gate
5. Core-First Budget Gate
6. Executable Evidence Gate
7. Coverage Cap Gate
8. Evolution Abstraction Gate

旧 gap flag 仍保留为兼容输入，但提案和总结会映射回上述 8 个门禁，避免规则继续膨胀。

## 分阶段模型

`config.yaml` 支持按阶段配置模型。当前默认策略是 Claude Code 执行、Codex 只在显式授权时使用；避免误耗 Codex 额度：

```yaml
executor: claude
require_executor: claude
allow_codex_executor: false
claude_phase0_model: claude-opus-4-7
claude_plan_model: claude-opus-4-7
claude_phase1_model: claude-sonnet-4-6
claude_phase2_model: claude-opus-4-7
claude_deep_review_model: claude-opus-4-7
claude_evolution_model: claude-opus-4-7
phase1_max_slices: 3
```

`Run-ReplayLoop.ps1` 会在每轮 replay root 写入 `EXECUTOR_AUDIT.json`，记录 Phase0 / Plan / Phase1 / Phase2 / DeepReview / Evolution 的实际 executor 与 model。若实际 executor 与 `require_executor` 不一致，或 Codex 未通过 `-AllowCodexExecutor` / `allow_codex_executor:true` 显式授权，runner 会直接停线。

## Phase 0 / 0.5 Planning Gate

每轮自动执行现在先进入 Phase 0 和 Phase 0.5：

- 每轮准备阶段会先生成 `BASELINE_INDEX.md`，只包含需求标题、规则文件摘要、模块文件族数量和可复现搜索命令。
- 每轮准备阶段还会生成 `CONTEXT_MANIFEST.md`，列出 `system_context_dir` 下允许读取的通用系统上下文文件。
- `BASELINE_INDEX.md` 是 token 优化用的中性索引，不得包含 selected entry、上一轮 gap、oracle 信息、旧 replay 分数或实现建议。
- `CONTEXT_MANIFEST.md` / `.doc/example-system-context` 只能作为通用项目背景，不能替代 requirement_source 和代码事实。
- Phase 0 只允许写 `EXPLORATION_REPORT.md`、`ROUND_CONTRACT.md` 和 `PHASE0_RESULT.md`。
- Phase 0.5 会生成 `PLAN_CANDIDATE_*.md`、`PLAN_SELECTION.md`、`REPLAY_PLAN.md`、`IMPLEMENTATION_CONTRACT.md`、`EXPECTED_DIFF_MATRIX.md`、`SIDE_EFFECT_LEDGER.md`、`TEST_CHARTER.md` 和 `PLAN_RESULT.md`。
- 禁止修改生产代码、测试、配置、SQL、前端文件。
- 禁止跑 Maven/测试/构建。
- 必须输出 `phase0_status: PROCEED | INVALID_PLAN | BLOCKED`。
- Phase 0.5 必须输出 `plan_status: PROCEED | INVALID_PLAN | BLOCKED`。

Phase 0 的核心目的不是评分，而是快速挡掉错误第一刀：

- `PROCEED`：第一刀是 core path，且真实入口、首个 RED 测试、side-effect ledger、deploy-facing follow-up 已明确。
- `INVALID_PLAN`：第一刀是 supporting surface / helper / static-only，或真实入口证据不足，或没有首个真实入口 RED。脚本会停止本轮，不进入 Phase 1/Phase 2。
- `BLOCKED`：需求或代码表面不足以安全判断真实入口。脚本写 `AUTOPILOT_BLOCKER.md` 并停止。

Phase 1 自动模式不再一次性执行完整大 prompt，而是由 `Run-SliceLoop.ps1` 循环执行最多 `phase1_max_slices` 个 slice。每个 slice 必须写 `SLICE_RESULT_XX.json`，随后由 `Verify-SliceClosure.ps1` 做脚本级 cap 检查；最后由 synthesis prompt 生成 `ROUND_RESULT.md`。如果实现阶段绕过 Phase 0/0.5，或第一刀实际落到 DTO/entity/mapper/config/log/OCR/report/export/helper/static guard，则 `ROUND_RESULT.md` 必须写 `final status=INVALID_REPLAY`，脚本不进入 Phase 2。若计划被代码事实推翻，Phase 1 应输出 `BLOCKED_PLAN_MISMATCH`，而不是临场改做低风险支撑面。

校验单个 executor、prompt、worktree 和日志目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-AgentPrompt.ps1 -PromptPath <REPLAY_RUN_ROOT>\PHASE1_PROMPT.md -WorkDir <REPLAY_RUN_ROOT>\worktree -LogDir <REPLAY_RUN_ROOT>\logs\validate -Executor codex -ValidateOnly
```

只准备 prompt 和 worktree，不执行 agent：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -StartRound 1 -Rounds 1 -NoExecute
```

如果 replay root 已存在，必须显式加 `-ReuseExisting`；工具不会自动复用旧目录。

## 无人值守跑一轮

第 1 轮已经准备过时使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -StartRound 1 -Rounds 1 -ReuseExisting
```

从第 2 轮开始新建并执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -StartRound 2 -Rounds 1
```

技能进化后，直接读取知识库最新变更版本并作为新一版 replay root：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -UseLatestKnowledgeVersion -StartRound 1 -Rounds 1
```

`-UseLatestKnowledgeVersion` 会从 `knowledge_repo\custom-skills-history\v*.md` 和 `guide-sections\changelog.md` 里读取最新 `vNNN`。例如知识库最新记录是 `v173` 时，脚本会在运行时生成临时 effective config，把：

```text
v172-autopilot -> v173-autopilot
<REPLAY_RUN_ROOT> -> <REPLAY_RUN_ROOT>
```

原始 `config.yaml` 不会被改写。这样每次完成受控技能进化并写入知识库变更记录后，下一轮 replay 可以直接跟随最新知识库版本启动。

跑最多 3 轮，遇到目标覆盖率或无提升熔断自动停止：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -StartRound 1 -Rounds 3 -ReuseExisting
```

## 自动技能进化

默认只生成 `EVOLUTION_PROPOSAL.md` 和 `EVOLUTION_PROMPT.md`，不会改技能。

显式允许自动执行进化：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-ReplayLoop.ps1 -StartRound 2 -Rounds 1 -RunEvolution
```

也可以在 `config.yaml` 中把 `auto_evolution: true` 打开。建议先用默认模式检查 `EVOLUTION_PROPOSAL.md`，确认 gap 是跨项目 workflow gate，而不是 example-feature 项目细节。

## 跑到指定知识版本

无人值守跑 replay + evolution，直到知识库最新版本达到指定版本，例如目标版本 `v240`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-UntilKnowledgeVersion.ps1 -TargetVersion 240
```

该脚本每轮都会：

1. 用 `-UseLatestKnowledgeVersion` 启动最新版本 replay。
2. 等 replay 结束并读取 `EVOLUTION_PROMPT.md`。
3. 自动执行受控技能进化。
4. 重新读取知识库最新版本。
5. 达到目标版本后停止。

保护规则：

- replay 产生 `AUTOPILOT_BLOCKER.md` 时停止。
- evolution executor 非 0 退出时停止。
- evolution prompt 会收到 `current knowledge version` 和 `expected next knowledge version`；即使判定为 no-source-change，也必须写一个版本化 no-op 审计记录并推送，便于无人值守循环确认本轮已处理。
- evolution 后知识库版本没有提升时停止为 `STOP_NO_VERSION_ADVANCE`，状态文件会写入期望版本和可选 `NO_VERSION_ADVANCE_REASON.md` 路径，避免无限重跑。
- 达到目标版本时停止为 `DONE_TARGET_REACHED`。

状态和日志写在 `run-logs\until-v<目标版本>-<时间>.status.json` 与同名 `.log`。

## 输出位置

每轮会生成：

```text
<REPLAY_RUN_ROOT>
  BASELINE_INDEX.md
  CONTEXT_MANIFEST.md
  PHASE0_PROMPT.md
  PLAN_PROMPT.md
  PHASE1_PROMPT.md
  PHASE2_PROMPT.md
  AUTOPILOT_RUN.json
  EXPLORATION_REPORT.md
  PHASE0_RESULT.md
  ROUND_CONTRACT.md
  PLAN_CANDIDATE_1.md
  PLAN_CANDIDATE_2.md
  PLAN_CANDIDATE_3.md
  PLAN_SELECTION.md
  REPLAY_PLAN.md
  IMPLEMENTATION_CONTRACT.md
  EXPECTED_DIFF_MATRIX.md
  SIDE_EFFECT_LEDGER.md
  TEST_CHARTER.md
  PLAN_RESULT.md
  ROUND_RESULT.md
  FINAL_REPLAY_REPORT.md
  AUTOPILOT_SUMMARY.md
  EVOLUTION_PROPOSAL.md
  EVOLUTION_PROMPT.md
  AUTOPILOT_DECISION.md
  logs\
    phase0\phase0.stdout.log
    phase0\phase0.last-message.md
    plan\plan.stdout.log
    plan\plan.last-message.md
    phase1\phase1.stdout.log
    phase1\phase1.last-message.md
    phase2\phase2.stdout.log
    phase2\phase2.last-message.md
```

如果 Phase 0 没有生成 `PHASE0_RESULT.md`、Phase 0.5 没有生成 `PLAN_RESULT.md` 和规划合同、Phase 1 没有生成 `ROUND_RESULT.md`，或 Phase 2 没有生成 `FINAL_REPLAY_REPORT.md`，脚本会写 `AUTOPILOT_BLOCKER.md` 并停止。

## 熔断规则

- `target_coverage`：默认 90，oracle-adjusted coverage 达到后停止。
- `max_no_improvement_rounds`：默认 2，连续无 oracle 覆盖率提升后停止。
- 缺报告、executor 失败、超时都会阻断本轮，不继续盲跑。

## 安全边界

- 不在 `<PROJECT_ROOT>` 主工作区写生产代码、测试或 replay 产物。
- Phase 1 prompt 禁止读取 oracle、历史 replay、目标 diff。
- Phase 2 prompt 只做 oracle 后验评分，禁止继续实现。
- 技能进化 prompt 禁止把项目路径、类名、表名、commit、replay root 写进通用技能。
- `-RunEvolution` 是显式开关；默认只产出提案，不自动改通用技能。

## 当前加强项

- Parser 优先以 `FINAL_REPLAY_REPORT.md` / Phase 2 指标为准，不再把 Phase 0 的 `PROCEED` 当最终状态。
- 分数解析支持 Markdown 反引号、百分号、表格和 `key: value` 多种写法。
- Phase 0 使用高推理模型做探索，Phase 0.5 做多候选规划择优，Phase 1 使用代码模型按合同逐 slice 执行。
- `.doc/example-system-context` 通过 `CONTEXT_MANIFEST.md` 接入，只作为通用系统背景，减少重复探索。
- Phase 0/Phase 1 强制最小可交付核心闭环：真实入口、编排、持久化/查询/写入、副作用、失败隔离和可执行证据。
- 字段/列名/flag/payload/display 命名必须先锁定当前需求和代码证据；自由翻译会被标记为 `exact_contract_gap`。
- deploy-facing surface 需要可执行最小切片；static-only、blocker-only、helper-only 只能降权或封顶。

## Golden Sample Mining

The runner can mine historical replay evidence into a portable control layer:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-GoldenSampleMining.ps1 -ConfigPath <REPLAY_AUTOPILOT_ROOT>\config.yaml
```

Default output:

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_golden-samples\
  GOLDEN_SAMPLE_LEDGER.json
  GOLDEN_SAMPLE_SOP.md
  GOLDEN_SAMPLE_PROMPT.md
  GOLDEN_SAMPLE_SUMMARY.md
```

When `golden_sample_auto_mine: true`, `Run-ReplayLoop.ps1` refreshes these files after each loop before knowledge backup sync.
When `golden_sample_auto_apply: true`, `Start-ReplayRound.ps1` snapshots `GOLDEN_SAMPLE_PROMPT.md` into the new replay root and appends it to Phase0/Plan/Phase1 prompts as generic workflow control.

This layer must stay generic: it may carry recurring gates such as real-entry first slice, side-effect proof, and coverage honesty, but it must not carry feature-specific oracle facts into blind replay.

## External Practice Search Trigger

Long stagnation should not keep replaying the same local failure. The runner can trigger an external practice search after stop-loss or no-improvement circuit breakers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-ExternalPracticeSearch.ps1 -ConfigPath <REPLAY_AUTOPILOT_ROOT>\config.yaml -RunAgent
```

Default output:

```text
$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\_external-practice\
  EXTERNAL_PRACTICE_RESEARCH_PROMPT.md
  EXTERNAL_PRACTICE_RESEARCH.md
  EXTERNAL_PRACTICE_SOP.md
  EXTERNAL_PRACTICE_DECISION.json
```

When `external_practice_auto_search: true`, `Run-ReplayLoop.ps1` invokes this trigger on stop-loss / no-improvement. When `external_practice_run_agent: true`, the configured executor, normally Claude Code, searches public sources and writes a sourced SOP. When `external_practice_auto_apply: true`, `Start-ReplayRound.ps1` only appends the SOP to new replay prompts if `EXTERNAL_PRACTICE_DECISION.json` marks it safe for auto-apply.

This is the escape hatch for local-loop stagnation: pause blind repetition, inspect external mature practices, extract generic SOP, then resume replay with positive process guidance.

External practice search has a bounded fallback path. The primary executor remains Claude Code, but if it times out, fails, or does not write a valid decision file, the search stage may switch to the configured fallback executor, normally Codex, to produce the sourced conclusion. The decision file records every attempt and `next_replay_executor`; normal replay execution still returns to Claude Code unless the main executor config is explicitly changed.
