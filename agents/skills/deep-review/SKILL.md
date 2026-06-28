---
name: deep-review
description: "Multi-specialist review with adaptive gating, structured findings, confidence scoring, review-first workflow, inline comments format, large diff batching, and clean Review declaration. Use when user says 深度审查, 代码审查, deep review, code review, optimize code, 优化代码, review this PR, check this code, fix review comments, 审查代码, 检查代码质量, 十轮深度审查, 第二视角审校, or Claude Code/Codex will review the result"
allowed-tools: Bash,Read,Edit,Glob,Grep,Skill,Task
---
# 深度审查 (Deep Review)
多专家代码审查：specialist 派遣 + 置信度门控 + 结构化发现 + Fix-First。
**专家角色：** 代码审查官 — 多专家派遣 + 自适应门控 + 审查-修复分离。
**上游技能：** `dev-workflow`, `auto-complete`
**下游技能：** `gen-tests`, `quality-check`
---
## 何时使用

- "深度审查" / "代码审查" / "deep review" / "review this PR"
- "检查代码质量" / "优化代码" / "fix review comments"
- "十轮深度审查" / "第二视角审校" / "Claude Code/Codex 会审查结果"
- 代码完成后、提交前、PR 审查时
## 何时不使用

- 只需语法检查 | 快速 lint | 无代码变更
---
## References（按需加载）

审查时按需读取 `references/` 下的参考文件，不预加载：

| 文件 | 内容 | 加载条件 |
|------|------|----------|
| `references/anti-patterns.md` | Anti-Patterns 表 + 代码异味 + 安全检查 + mock/testing 反模式 | 发现反模式、安全问题或测试质量风险时 |
| `references/review-lens-templates.md` | 按任务类型选择审查视角：后端、前端、提示词/Agent、技术方案、技能、知识库 | 用户要求多轮/十轮审查、第二视角审校，或显式提到 Claude Code/Codex/外部 reviewer 会复核时 |
| `references/codex-only-cross-review.md` | 只用 Codex 做单上下文多镜头或 Codex 线程隔离审查的协议 | 用户要求只用 Codex 实现交叉审查、第二视角、多 reviewer 或模拟跨工具复核时 |
| `references/subagent-review-contracts.md` | 可选只读子 agent 审查契约、结果合并门禁和禁止事项 | 大 diff、多 surface、review pressure 或需要独立审查镜头时 |

---

## Clean Review 声明

**本审查为只读审查（Review-Only）。** 审查阶段不修改任何代码。所有发现以结构化评论形式输出，修复在审查完成后由用户确认。

---

## Review-First 工作流

```
[1] ⚠️ REQUIRED 检测变更范围 + 大diff分批
    ↓
[2] ⚠️ REQUIRED 派遣专家 + 独立审查
    ↓
[3] ⚠️ REQUIRED 输出结构化发现（不修复）
    ↓
[4] ⛔ BLOCKING 用户确认 Next Steps
    ↓
[5] (conditional) 执行修复（用户确认后）
    ↓
[6] ⚠️ REQUIRED 输出最终审查报告
```

---

## 审查顺序

每批审查按固定顺序执行，避免只看实现细节：

1. 先读需求/合同和变更意图。
2. 再看测试：是否验证行为、边界、错误路径和 must-not。
3. 再看实现：正确性、可读性/简单性、架构边界、安全、性能五轴。
4. 最后核对验证故事：命令、范围、失败阶段复验、手工/运行态证据。

若非平凡决策缺少可反驳证据，输出 `decision_doubt_gap`，不要用“看起来合理”放行。

需求驱动的非平凡实现还必须审查 Planning Brainstorm Matrix：是否有稳定 `PB-xx`、是否真的比较了方案，是否写清 `chosen / rejected because / risk / validation assertion`，以及验证断言是否落到测试、静态检查或明确 blocker。缺失时输出 `planning_brainstorm_gap`；只有矩阵但没有真实被拒方案或验证证据时输出 `brainstorm_formalism_gap`；PB-ID 无法贯穿计划、测试、实现证据和收口时输出 `brainstorm_trace_gap`；`skip_reason` 不在白名单或理由是 `prd_exists / looks_simple / time_pressure / tests_pass / model_confident` 时输出 `invalid_brainstorm_skip`。

若审查对象经历过用户纠错、返工、重复追问“是否完成”或曾提前宣称完成，Stage 1 必须先执行 Completion Claim Review：核对需求冻结矩阵、同类问题扫描、Expected Diff Matrix、Proof Ledger、Final Completeness Gate 和真实 surface 证据。缺少同类扫描或更新合同，输出 `correction_closure_gap`；缺少完成证据却使用完成态表述，输出 `premature_done_gap`；只有 helper/mock/局部测试而没有真实入口证据，输出 `visible_surface_gap`。

架构审查额外执行 Depth Check：新增模块、抽象、接口或 adapter 要问“删除它后复杂度是消失还是分散到调用方”。若只是 pass-through、只有一个真实 adapter、测试面绕过 public interface，输出 `shallow_module` / `hypothetical_seam` / `wrong_test_surface`。

## Review Lens Selection

当用户要求十轮/多轮深度审查、第二视角审校，或说 Claude Code/Codex/外部 reviewer 会复核时，先选择审查镜头，而不是机械重复同一轮审查。

规则：
- 按目标类型读取 `references/review-lens-templates.md` 中最小匹配模板。
- 每轮必须使用不同视角；如果找不到足够证据，输出 `verification_gap`，不要补幻想结论。
- 每个非平凡发现必须标注证据来源、严重级别、确定性、验证方式；无法验证的内容只能标为假设。
- 同一模型同一上下文的多轮审查不等于独立外部审查；必须披露 `independence_level=same_context_lens`。
- 路由层传入 `review_mode=codex_only_cross_review`，或用户要求只用 Codex / 第二视角 / 多轮交叉审查时，读取 `references/codex-only-cross-review.md`，在 `single_context_lens` 与 `codex_thread_isolated` 中选择；不要声称使用了外部模型。

## Codex-Only Cross-Review Mode

当路由层自动设置 `review_mode=codex_only_cross_review`，或用户想要“只用 Codex”模拟多方审查、交叉审查或第二视角时，读取 `references/codex-only-cross-review.md`。默认 `single_context_lens`；只有宿主支持只读 Codex 线程/分叉且风险足够时，才使用 `codex_thread_isolated`。

最低门禁：报告必须写明 review mode、independence level、是否使用外部模型、审查镜头和主会话复核范围；可选隔离线程只能输出证据、候选发现、置信度和未覆盖范围，最终裁决仍由主会话完成。

## Optional Subagent Dispatch Mode

当任务命中大 diff、多 surface、review pressure、技能/知识库/技术方案审查，且当前宿主支持并允许并行代理时，可派只读子 agent 做独立审查镜头。详细契约见 `references/subagent-review-contracts.md`。

子 agent 只能输出证据、候选发现、置信度和未覆盖范围；主会话必须去重、复核 P0/P1 与核心事实、裁决冲突，并保留唯一审查报告。Next Steps 确认前仍保持 Review-Only，不得由子 agent 直接修复或宣布通过。

---

## Route Table（路由表）

| 用户意图 | 路由 | 执行路径 |
|----------|------|----------|
| "快速检查" | `SCAN` | 仅 Always-on 专家，高层扫描 |
| "代码审查"（默认）| `REVIEW` | 全维度专家审查 |
| "修复问题" | `FIX` | 审查 + 自动修复 |
| "性能检查" | `PERF` | 专注性能审查 |
| "后验对比" / "replay报告" | `ORACLE-REVIEW` | 先分类 oracle diff，再判断技能或实现缺口 |

---

## 大 Diff 分批处理

当 `git diff` 输出超过 200 行时，必须分批审查：

| Diff 规模 | 策略 |
|-----------|------|
| ≤ 200 行 | 单批全量审查 |
| 200-500 行 | 按文件分 2-3 批 |
| > 500 行 | 按模块分批 + 每批汇总后合并去重 |

**分批规则：** 每批独立审查 → 汇总所有发现 → 指纹去重（同文件同行号）→ 统一输出。

---

## 专家派遣机制

**Always-on 专家：**

| 专家 | 职责 | 指标 |
|------|------|------|
| Security | 安全漏洞、注入、密钥泄露 | P0 必须报告 |
| Logic | 业务逻辑正确性、边界条件 | P1+ |
| Performance | 性能瓶颈、N+1、内存泄漏 | P2+ |

**Conditional 专家（自动检测）：**

| 专家 | 触发条件 |
|------|----------|
| API Design | 有接口变更（新增/修改 endpoint）|
| Database | 有 SQL/ORM 变更 |
| Frontend | 有 UI/组件变更 |
| External Integration | 有外部系统调用、API 集成、重试机制、异步通知变更 |

**Adaptive Gating：** 低置信度发现（< 0.6）自动降级为建议，不阻塞。

**External Integration 专家重点：**
- 信任边界是否清晰（签名/来源/鉴权）
- 重复请求是否具备幂等
- 状态机是否存在回退、重复推进或脏写
- 配置是否把特定系统硬编码成通用逻辑
- 日志是否能串起完整请求处理链路

---

## 结构化发现格式

每个发现输出为结构化 JSON：

```json
{"file":"src/auth.ts","line":42,"severity":"P0","category":"Security",
 "finding":"SQL injection via string concatenation",
 "suggestion":"Use parameterized query","confidence":0.95}
```

**内联评论格式：** `::review-comment file:line [P0] finding → suggestion`

---

## Fix Eligibility Triage

Fix-First 只表示先判断可修复性，不绕过 Review-First。每条发现先分流：

| 分流 | 条件 | 动作 |
|------|------|------|
| `AUTO-FIX` | 低歧义、局部、可验证，不改变业务语义：typo、import、显式空指针、明显资源泄漏、测试 mock 误用等 | 用户选择修复后可直接改，并复跑对应验证 |
| `ASK` | 需要业务取舍、架构方向、scope 扩张、数据迁移、兼容性或 owner 判断 | 把问题集中放入 Next Steps，不做 trivial confirmation |
| `PUSH-BACK` | 发现基于错误假设、会破坏现有契约、与需求/ADR 冲突或超出本轮范围 | 给证据、替代建议和风险说明 |

**Hard Gate：** 不得把 `ASK` 项伪装成自动修复；也不得为了礼貌接受技术上错误的 reviewer 建议。

---

## Next Steps 确认门控

审查完成后，必须向用户展示 Next Steps 并等待确认：

| 选项 | 描述 |
|------|------|
| **Fix All P0** | 自动修复所有 P0 问题 |
| **Fix All** | 修复所有 P0 + P1 |
| **Manual** | 仅报告，用户手动修复 |
| **Approve** | 审查通过，无需修复 |

用户选择后才能进入修复阶段。

---

## 置信度门控

| 置信度 | 行动 |
|:------:|------|
| ≥ 0.8 | 报告 + 建议修复 |
| 0.6-0.8 | 报告为建议，不阻塞 |
| < 0.6 | 自动过滤，不输出 |

---

## 双阶段审查

| 阶段 | 职责 | 专家 |
|------|------|------|
| Stage 1: Spec 合规 | 检查是否满足需求/规格 | Logic + API Design |
| Stage 2: Code 质量 | 检查代码质量、安全、性能 | Security + Performance + Logic |

Stage 1 FAIL → 直接报告，不进 Stage 2。Stage 1 PASS → Stage 2 审查。

## Oracle / Replay 审查

当审查目标提交、历史最终态、上一轮 replay 或 oracle diff 时，先分类再比较：

| 分类 | 是否作为需求漏做依据 |
|------|----------------------|
| `EFFECTIVE_REQUIREMENT_DIFF` | 是 |
| `SUPPORTING_TEST_OR_TOOLING` | 只作为支撑证据 |
| `TEMP_DEBUG_OR_HISTORY_DRIFT` | 否，记录为历史噪音 |
| `FRONTEND_ONLY` | 否，除非本轮 scope 包含前端 |
| `UNRELATED_DRIFT` | 否，记录 scope 风险 |

禁止把整个目标 diff 当成标准答案；只有需求内有效 diff 可用于判断实现或技能缺陷。

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 审查时修改代码 | Clean Review 声明：审查阶段不修改 |
| 大 diff 遗漏问题 | >200 行必须分批 |
| 发现不分优先级 | 严格 P0/P1/P2 分级 |
| 修复不验证 | Fix-First：修复后必须运行测试 |
| 只跑局部测试就宣布验证通过 | 必须对齐原失败阶段或完整验证范围 |
| 用户纠错后只看被指出的一行 | Stage 1 先做 Completion Claim Review，扫同类字段、入口、错误提示、数据源、文案和真实 surface |
| 同一问题多次报告 | 指纹去重（文件:行号）|
| 后验 diff 全部算漏做 | 先做 Oracle / Replay 分类，只审需求内有效 diff |
| reviewer 提了就改 | 先做 `AUTO-FIX / ASK / PUSH-BACK` 分流 |
| 测试绿就行 | mock 可能只验证了 mock，不验证真实行为 |
| helper/constant 存在就算 surface 完成 | 没有真实入口引用就是 false coverage |
| 多一层接口就算架构更好 | 用 deletion test、adapter count 和 interface-as-test-surface 判断是否真有 leverage |
| 有 Planning Brainstorm Matrix 就算规划充分 | 必须审查 chosen/rejected/risk/validation 是否真实落地 |
| 写了 skip_reason 就能跳过 planning brainstorm | 只接受白名单内机械/无决策理由，已有 PRD 或看起来简单不是合法跳过 |

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：`Next Steps` 门控与修复阶段验证门都属于 Hard Gate，未通过不得宣称审查/修复完成
- **PARTIAL**：只表示部分验证，不能表示“审查做了一部分”
- **完成标准（DoD）**：统一表示“审查结论或修复结论达到可交付”的条件
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

---

## 红旗警告

| 想法 | 为什么错 |
|------|----------|
| "这行看起来没问题" | 需要证据，不是感觉 |
| "先修复再报告" | 必须先报告后修复（Clean Review）|
| "小项目不需要审查" | 小项目 bug 影响更大 |

---

## 安全护栏

- ⛔ 审查阶段禁止修改代码（Clean Review）
- 修复限制 3 次（超限 → 暂停 + 报告）
- 修改关键行为代码前验证测试存在
- 作用域锁定（仅审查指定范围）
- 若修复前存在 `compile` / `testCompile` / `package` 失败，修复后必须复跑同一失败阶段或项目约定的完整验证命令，才能写“验证通过”
- Surface 审查必须追真实入口：新增 helper、builder、constant、SQL 片段或 DTO 字段若未被 controller/service/exporter/worker/mapper select/filter 引用，标记 `P1 false coverage` 或 `P2 verification gap`，不得按 DONE 通过。
- Core path 审查必须区分 static proof 与 behavior proof；状态、持久化、消息、导出、外部 payload、事务回滚或 must-not 边界只有源码存在而无行为证据时，结论最多 `PARTIAL`。
- Planning brainstorm 审查必须追到最终证据：矩阵里的 PB-ID、关键选择、被拒方案和风险必须能映射到实现 diff、测试断言、静态验证或 blocker；不能用“规划阶段已讨论”替代最终 proof。

---

## 输出格式

```
## 审查报告
- 模式: {SCAN/REVIEW/FIX/PERF} | 批次: {N} | 发现: {P0:N} {P1:N} {P2:N}
- Stage 1 Spec: {PASS/FAIL} | Stage 2 Quality: {score}/10
- Completion Claim Review: {PASS/FAIL/NOT_APPLICABLE}
- Codex Review Mode: {single_context_lens/codex_thread_isolated/not_applicable} | Independence: {same_context_lens/codex_thread_isolated/not_applicable} | External Model Used: {yes/no}
- Review Lenses: {lens list} | Main Verification: {what was rechecked / gaps}

### P0 Critical（必须修复）
| # | file:line | 问题 | 建议 |
### P1 High（建议修复）
| # | file:line | 问题 | 建议 |
### P2 Medium（可选优化）
| # | file:line | 问题 | 建议 |

### Next Steps
→ [ ] Fix All P0 / Fix All / Manual / Approve
```

**修复完成后：** 输出修复报告（修复了哪些、跳过了哪些、验证结果）。

**修复阶段验证门：**

- 验证结果必须写明命令、范围、原失败阶段是否已复验
- 仅局部测试通过时，只能写 `PARTIAL`
- 未复跑原失败阶段时，禁止写“修复完成，验证通过”
- 修复报告必须列出 `AUTO-FIX / ASK / PUSH-BACK` 数量；`ASK` 未决时最终状态不能是完全通过
