---
name: skill-evolution
description: "Use when user says 进化技能, 技能进化, 融合优点, 吸取百家之长, evolve skill, skill evolution, 改进技能, improve skill, or asks to absorb better skill practices"
allowed-tools: Read,Edit,Write,Glob,WebFetch,Skill
---

# 技能进化

通过吸收参考来源的最佳实践来进化你的自定义技能，然后审计至 P0/P1 归零。

**专家角色：** 技能进化者 — 吸收最佳实践并合并到目标技能。

**下游技能：** `skill-audit`, `compound-learning` (if issues found)

---

## 何时使用

- "进化技能" / "技能进化" / "融合优点" / "吸取百家之长"
- "evolve skill" / "skill evolution" / "improve skill"
- 收集到技能反馈后
- 向社区发布技能前

## 何时不使用

- 技能已经是 A 级无需改进
- 用户想从头写新技能（先按本技能的 Skill Shape 规则创建最小草稿，再进入审计）
- 不做社区分析的快速修复

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 盲目复制 | 分析模式为什么有效 |
| 过度工程 | 限制最多3个参考来源 |
| 破坏功能 | 变更后总是运行审计 |
| 丢失身份 | 保持核心目的不变 |
| 缺少参考来源 | 询问用户路径/URL 或历史报告 |
| 只做静态改文案 | 技能行为可能没变好；补最小 trigger/output eval |

---

## Iron Law（铁律）

**核心约束:** 进化后必须通过 `skill-audit` 检查 P0/P1 归零，否则技能会退化。不改变核心目的或主要触发器。目标技能默认预算 120-250 行；复杂执行技能可到 300 行，但必须说明不拆分原因并把案例/模板/长清单移入 `references/`。
**完成态规则:** 未通过 `skill-audit` 前，禁止使用“进化完成”“可发布”“已收敛”之类完成表述。
**源头规则:** 修改前必须读取 `.agents/AGENTS.md`（若存在）和 `skills-manifest.md`，只编辑 canonical source；镜像和知识库备份只由 source 同步生成。
**Eval 规则:** 修改 `SKILL.md` 正文行为时，至少保留一组最小 trigger/output eval；纯错字、备份同步、changelog 或路径说明可跳过，但必须写明原因。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：`完成前 Hard Gate` 未通过时，不得进入完成态
- **PARTIAL**：本技能不使用 `PARTIAL` 表示进化程度；若未满足完成条件，只能写“候选修改”或“阻塞”
- **完成标准（DoD）**：统一表示“已完成进化且通过审计”的条件集合
- **验证范围**：在本技能中指验证纪律覆盖范围，而非测试执行范围

---

## 常见借口

| 借口 | 反击 | 行动 |
|------|------|------|
| "热门技能一定更好" | 适合他们的场景 | 选择性吸收 |
| "P1 可以先跳过" | P1 必须修复 | 立即修复 |
| "保持原样更安全" | 不进化 = 停滞 | 持续改进 |

---

## 工作流程

```
[0] 读取源头治理 → 确认 source / mirror / backup / changelog
    ↓
[1] 解析输入 → 确定模式
    ├── 模式 A：用户指定了参考来源
    │   ├── 本地文件 → 直接读取
    │   ├── GitHub URL → 通过 web/Read 获取
    │   └── skills.sh 名称 → 尝试获取
    └── 模式 B：未指定参考 → 询问用户
    ↓
[2] 分析目标技能（核心目的、触发器、缺口）
    ↓
[3] 分析参考来源，提取模式
    ↓
[4] AutoResearch Loop：将模式合并到目标
    ├── 基线测量（当前 P0/P1 + Yes/No Checklist 得分）
    ├── 原子变更（每次只改一处）
    ├── 最小 eval（trigger / output / pressure scenario / 跳过原因）
    ├── 证据字段（old_skill/without_skill vs with_skill、assertions、transcript、人类反馈、成本）
    ├── 重新评估（比基线好→保留，变差→回滚）
    └── 重复直到所有模式处理完
    ↓
[5] 审计循环 → skill-audit 直到 P0=0, P1=0
    ↓
[6] 输出进化报告 + Change Log
```

## 模式分层

进化前先判断规则属于哪一层：

| 层级 | 进入位置 | 判断 |
|------|----------|------|
| 普通开发主链 | `pre-flight-check` / `req-alignment-check` / `deep-plan` / `dev-workflow` / `gen-tests` / `sync-progress` | 跨项目日常需求也会遇到 |
| 高风险加深 | 主链 Hard Gate 或 references | 只在复杂需求、异步、多 surface、外部集成时触发 |
| replay/eval 专用 | `skill-audit` / `deep-review` oracle 分支 / `sync-progress` disclosure | 只在历史重跑、oracle 对比、技能评估时触发 |
| 项目规则 | 仓库 `AGENTS.md` / `.memory` | 包含项目路径、命令、类名、表名、业务事故 |

禁止把 replay/eval 专用规则全部塞进普通开发主链；禁止把项目规则写进通用技能正文。

## Foundation Alignment Gate

吸收任何外部方法、公司技能或历史复盘前，先判断它是否服务当前基座的 North Star：把真实需求源稳定转成可验证交付物，并降低假完成、返工和项目污染。

逐条回答：

1. 是否提升 requirement-to-code 的真实可交付覆盖率，而不是只增加流程感？
2. 是否减少漏 surface、错 contract、小 GREEN、mock 绿、旁路 slice 或收口误判？
3. 是否跨项目成立，且不依赖特定仓库、公司命令、业务类名、表名或事故原文？
4. 应进入普通开发主链、高风险加深、replay/eval、项目规则，还是只进入知识库说明？
5. 这是缺少新 gate，还是已有 gate 未被 runner / prompt / verifier 强制执行？
6. 是否依赖特定 agent、CLI、session 格式、目录结构、云服务或宿主 hook？若依赖，只能作为 adapter/plugin 候选，不得进入 core base。

不服务 North Star 的模式不得进入主工作流；已被覆盖但反复失效的模式，优先补执行约束，而不是新增同义规则。

**吸收判定门：** 从报告、复盘或外部方法论吸收规则前，逐条归入上述四层；只有日常跨项目会遇到的规则可轻量进入普通主链，replay/eval 专用规则只进入审计或 disclosure，项目细节只进仓库规则或项目记忆。不能因为规则来自真实失败报告，就默认写入普通开发主链。
replay evolution proposal 中若 gap 已有 gate 覆盖但重复出现，默认分类为 `already-covered-but-not-enforced`；优先补 runner / prompt / verifier 强制执行，只有 gate 本身缺失时才改技能正文。

## General Base Portability Gate

当参考来源是某个 agent、IDE、会话桥、自动记忆、专有平台或公司流程时，先读取 `references/general-base-portability.md`，并把候选模式分类为：

| 分类 | 含义 | 动作 |
|------|------|------|
| `core_base` | 不依赖宿主，能提升通用交付控制面 | 进入 owner skill 或 manifest |
| `optional_adapter` | 有价值但依赖特定宿主/格式/API | 只进入插件、adapter 或 reference，不进主链 |
| `reference_only` | 只有启发，缺证据或重复性 | 留在知识库/历史报告 |
| `reject_vendor_lockin` | 会把基座绑定到单一工具、路径或服务 | 不吸收 |

Hard Gate：通用基座默认宿主中立。外部工具可以作为营养或插件进入，但不能成为运行时依赖；会话/自动记忆只能先作为候选证据，经过验证和抽象后才可晋升为长期规则。

## Trace / Harness Distillation Gate
当参考来源是论文摘要、知识库收录、历史会话、replay 轨迹、跨宿主 session、自动记忆或外部方法论时，先读取 `references/trace-harness-distillation.md`，把它当作调优证据而不是直接当作新规则。
最低判定：是否有 raw evidence、verified root cause、重复/高权重模式、compact control signal、正确落点层级。只有摘要或单轮未验证经验时标 `candidate_only`；已有 gate 覆盖但执行失效时改 runner / prompt / verifier，不新增同义正文。

## 最小技能 Eval 门禁

修改会影响技能触发、执行流程、Hard Gate、输出格式或下游路由时，完成前必须留下最小 eval 证据：

| 类型 | 最小要求 | 用途 |
|------|----------|------|
| `trigger_eval_minimal` | 2 条 should-trigger + 1 条 should-not-trigger | 防误触发/漏触发 |
| `pressure_scenario_minimal` | 1 条真实压力场景，说明旧规则会怎样偏离 | 防静态好看但实战无效 |
| `golden_output_minimal` | 1 条输入与期望输出要点 | 防输出格式漂移 |
| `no_eval_reason` | 仅限错字、备份同步、changelog、路径说明 | 防无理由跳过 |

证据可写入审计报告、changelog 或 `skill-audit` 的 eval 文件；不要求每次都做多轮 replay。若没有任何 eval 或跳过原因，只能报告“候选修改”，不得报告“进化完成”。

## Eval 证据结构

吸收外部模式后，审计报告至少记录 `reference_pattern / target_change / baseline / with_skill / assertions / evidence / cost`。没有 `baseline + assertions + evidence` 的吸收项只能标记为 `candidate_absorbed`，不能标记为 `verified_absorbed`。

---

## 输入模式

### 模式 A：用户指定参考

| 输入格式 | 如何处理 |
|----------|----------|
| `进化 gen-tests 参考 ~/skills/test.md` | 读取本地文件 |
| `进化 gen-tests 参考 https://github.com/xxx/skill.md` | 通过 web-reader 获取 |
| `进化 gen-tests 参考 playwright-generate-test` | 搜索 skills.sh 或询问用户 |
| `进化 gen-tests 参考 test1.md, test2.md` | 处理多个（最多3个）|

### 模式 B：未指定参考

**询问用户：**

```
请指定参考来源（3选1）：

1. 本地文件路径：~/skills/reference-skill.md
2. GitHub URL：https://github.com/xxx/skills/blob/main/skill.md
3. skills.sh 技能名：playwright-generate-test

可指定多个（最多3个），用逗号分隔。
```

---

## 模式提取检查清单

分析参考来源时，提取：

| 类别 | 找什么 |
|------|--------|
| 结构 | 工作流阶段、输出格式、章节 |
| 纪律 | Iron Law, HARD-GATE, Red Flags, Guardrails |
| 验证纪律 | 失败阶段复验、验证范围、完成标准/DoD |
| 预防 | Gotchas, Common Rationalizations |
| 集成 | Consumes from, Feeds into, When to PAUSE |
| 最佳实践 | 命名、模式、检查清单 |

---

## 外部参考源治理（v22）

进化技能时，可以读取外部方法论作为参考，但不得把外部技能名写成 `.agents/skills` 下的本地 downstream 依赖：

| 来源 | 路径/URL | 搜索内容 |
|------|---------|----------|
| 外部参考来源 | 用户指定路径/URL | 可迁移的方法论、门禁、输出格式 |
| 本地自定义技能 | `.agents/skills/<skill>/SKILL.md` | 真实可触发入口和下游依赖 |
| 历史 replay/eval 报告 | 用户指定报告路径 | 失败模式、门禁缺口、验证证据 |

**规则：** 只吸收模式，不复制外部技能身份。若参考来源不是本地自定义技能，输出中必须写成“已吸收模式”，而不是“下游技能”。

---

## 模式吸收检查

| 检查项 | 是否吸收 | 理由 |
|--------|:--------:|------|
| 有 Red Flags / Common Rationalizations？ | ✅/❌ | |
| 有 HARD-GATE / Iron Law？ | ✅/❌ | |
| 有证据分级要求？ | ✅/❌ | |
| 有失败阶段复验 / 验证范围 / 完成标准？ | ✅/❌ | |
| 有增量验证点？ | ✅/❌ | |
| 有 Graceful Exit？ | ✅/❌ | |
| 保持核心目的不变？ | ✅/❌ | |

---

## 合并规则

| 规则 | 描述 |
|------|------|
| **保持身份** | 不改变核心目的或主要触发器 |
| **限制来源** | 每次进化最多3个参考来源 |
| **行数预算** | 默认 120-250 行；复杂执行技能可到 300 行但需理由和 `references/` 承接 |
| **选择性吸收** | 取适合的模式，跳过冲突的 |
| **必须审计** | 必须通过 skill-audit 且 P0=0, P1=0 |
| **同步/提交** | 源头修改后必须同步知识库备份并更新 changelog；若用户要求远程提交，只提交备份仓库并推送远程 |
| **去项目化** | 通用技能正文不得出现项目名、仓库绝对路径、类名、表名或事故案例原文 |

---

## 完成前 Hard Gate

在宣称“进化成功”前，必须同时满足：

1. 已逐项核对参考来源中的**验证纪律模式**是否被吸收或明确说明为何不适用：至少包含 `失败阶段复验`、`验证范围`、`完成标准/DoD`
2. 已完成 `skill-audit`，且结果为 `P0=0`、`P1=0`
3. 若存在 replay/eval/真实失败报告，已逐项把失败模式映射到目标技能 Hard Gate，或明确记录不吸收理由
4. 输出中明确区分：
   - `已吸收的模式`
   - `刻意不吸收的模式及理由`
   - `仍待后续处理的 P2/P3`
5. 已提供最小 trigger/output eval 证据，或明确 `no_eval_reason`
6. 已完成 source -> backup 同步和 changelog 更新；若要求远程提交，已推送备份仓库，或明确标记阻塞。
7. 已扫描修改后的 `SKILL.md`，确认没有项目特定污染。
8. 若吸收来源依赖特定宿主或会话格式，已输出 portability 分类；`optional_adapter` / `reference_only` / `reject_vendor_lockin` 不得表述成 core base 完成项。

若第 1 条未完成，则最多只能报告“已完成一轮演进候选修改”，**不得**报告“进化完成”。
若参考来源本身缺少这三类验证纪律模式，不能直接写“不适用”了事；必须从用户指定参考来源或历史 replay/eval 报告补齐，或明确标记为**阻塞项**并禁止进入完成态。

---

## 可吸收模式（优先级）

| 优先级 | 模式 | 示例 |
|:------:|------|------|
| **高** | Common Rationalizations / Iron Law / Graceful Exit | 借口表/铁律/失败报告 |
| **高** | 失败阶段复验 / 验证范围 / 完成标准 | 防止表面完成与局部验证误导 |
| **高** | Owner 意识四问 / 能动性等级表 | 根因影响预防数据/被动vs主动 |
| **高** | AutoResearch Loop（基线→原子变更→评估→保留/回滚）| 每次只改一处，变差就回滚 |
| **中** | Phase Detection / Output Format / 环境异常处理 | 自动检测/标准化/异常识别 |
| **中** | Yes/No Checklist（3-6 题评估输出质量）| 客观是非题，替代主观评分 |

---

## Skillify 模式（操作→技能提取）

当操作序列成功且可复用时，提示提取为技能模板：

**触发：** 同类操作成功 ≥2 次 且 用户未拒绝记录

**规则：** 从成功操作提取固定步骤→可变参数→边界条件→失败处理；粒度 3-5 行 instinct→计数≥3→提醒进化为技能；零上下文假设。

**禁止：** 不自动创建技能文件 — 只记录到 instincts.md 并提醒。

---

## 参考来源质量验证

外部来源需检查安装量、来源声誉、stars、更新频率和文档完整度；低声誉或久未更新的来源只能作为启发，不能直接照搬。

---

## 输出

输出模板见 `references/evolution-report-template.md`。报告必须包含目标分析、参考来源、吸收/不吸收模式、验证纪律覆盖矩阵、eval 证据、审计结果和 changelog 摘要。

若未提供“验证纪律覆盖矩阵”，则“已核对验证纪律”的说法视为**无证据**，不得进入完成态。

---

## 集成

`skill-audit` Phase 5 审计循环（必须，且必须核对“验证纪律覆盖矩阵”与目标技能正文一致）| `compound-learning` 进化失败时记录教训
