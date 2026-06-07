---
name: restore-context
description: "Restore project state to continue where you left off. Use when user says 恢复上下文, 继续之前的工作, restore context, 新会话, 我做到哪了, checkpoint, resume, or at new session start"
allowed-tools: Bash,Read,Glob,Skill
---

# 恢复上下文

恢复项目状态，让你能从离开的地方继续。采用**三层加载**策略，按需读取，避免上下文浪费。

**专家角色：** 团队负责人 — 快速恢复项目状态让你能继续。

**下游技能：** 所有下游技能（提供项目状态）
**联动技能：** `compound-learning`（读取 docs/solutions/ 知识摘要）

---

## 何时使用

- "恢复上下文" / "继续之前的工作" / "restore context"
- 新会话开始
- 忘记当前任务

## 何时不使用

- 已经有完整上下文
- 刚开始一个全新项目

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 加载所有 .memory/ 文件 | 只加载 Layer 1 + Layer 2，Layer 3 按需 |
| 读取不存在的文件 | 先用 Glob 检查文件是否存在，不存在则跳过 |
| `.memory/MEMORY.md` 过期（>7 天）| 检查最后修改，过期则警告 |
| 太冗长 → 过载 | 摘要，不要倾倒文件内容 |
| 只恢复任务进度，不恢复验证风险 | 单独提取失败阶段、验证范围、残留风险 |
| 工作区有 `.memory/` 但缺 `skill-feedback.md` | 非阻断提醒：建议从 `templates/skill-feedback.md.tpl` 初始化 |

---

## 三层加载策略（核心优化）

### Layer 1 — 始终加载（必读，~120行）

| # | 来源 | 行动 |
|---|------|------|
| 1 | Git 状态 | `git status --short` + `git branch --show-current` |
| 2 | Git 日志 | `git log --oneline -5`（从10改为5） |
| 3 | `.memory/MEMORY.md` | 错误教训摘要（核心） |
| 4 | `openspec/changes/*/tasks.md` | 如 openspec/ 存在，读活跃变更进度 |

### Layer 2 — 按最近时间加载（轻量）

| # | 来源 | 行动 |
|---|------|------|
| 5 | `.memory/progress.md` | 只读最后 3 条记录 |
| 6 | `.memory/findings.md` | 只读最后 3 条记录 |
| 7 | `.doc/*/tech-design.md` | 如 `.doc/` 存在，只读概述部分（非全文） |
| 7.5 | `.memory/progress.md` / `.memory/findings.md` | 若出现 compile/testCompile/test/package/局部测试 关键词，扩大窗口读取相关片段 |

### Layer 3 — 按需加载（不默认读取）

| # | 来源 | 触发条件 |
|---|------|---------|
| 8 | `.memory/error-lessons.md` | pre-flight-check、用户问"之前有什么错误"、或检测到 build/test/局部验证风险关键词 |
| 9 | `.memory/skill-feedback.md` | skill-audit 使用；缺失时在恢复结果中给初始化提醒 |
| 10 | `.memory/instincts.md` | 仅摘要（3行表格）|
| 11 | `.memory/knowledge-gaps.md` | 仅 dialogue-learning 使用 |
| 12 | `.memory/solution-patterns.md` | 仅 compound-learning 使用 |
| 13 | `openspec/specs/*/spec.md` | 用户询问特定规格时 |
| 14 | `CLAUDE.md` | 已在系统提示中加载，跳过重复读取 |

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：本技能中“验证风险恢复硬规则”属于 Hard Gate，未满足不得把上下文恢复成“可直接继续开发”
- **PARTIAL**：在本技能中只表示“上次验证范围未覆盖全量”，不能表示“恢复了一部分上下文”
- **完成标准（DoD）**：本技能的完成标准是“当前状态 + 风险 + 推荐下一步”三者都恢复出来
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

---

## 文件存在性检查（铁律）

读取任何 .memory/ 文件前，**必须先用 Glob 检查是否存在**：
```
Glob(".memory/MEMORY.md") → 存在 → 读取
Glob(".memory/progress.md") → 不存在 → 跳过，不报错
```
不存在的文件直接跳过，不浪费工具调用次数。

## 反馈模板提醒

如果工作区已存在 `.memory/`，但缺少 `.memory/skill-feedback.md`：

- 不阻断恢复上下文
- 在输出末尾追加一条轻提醒
- 提醒内容：可从 `templates/skill-feedback.md.tpl` 初始化到 `<workspace>/.memory/skill-feedback.md`

## 风险关键词预扫描

在读取 Layer 2 摘要前，必须先用**全文搜索工具**对以下文件做关键词扫描：

- `.memory/progress.md`
- `.memory/findings.md`
- `.memory/error-lessons.md`
- `openspec/changes/*/tasks.md`

关键词包括但不限于：

- `compile`
- `testCompile`
- `package`
- `编译失败`
- `构建失败`
- `局部测试`
- `PARTIAL`
- `只跑`
- `mvn -Dtest`
- `过滤测试`
- `失败阶段`
- `验证范围`
- `未复验`
- `仅目标测试`

若命中任一关键词，则必须扩大读取窗口并在恢复结果中优先展示验证风险，而不是只展示普通任务进度。

---

## 过期检测

恢复时检查 MEMORY.md 年龄: ≤3天 🟢 / >3天 🟡 Aging / >7天 🔴 Stale → 警告

---

## 5问重启

| 问题 | 主要来源 | 备选 |
|------|----------|------|
| 我在哪？ | Git 分支/状态 | — |
| 我要去哪？ | `openspec/changes/*/tasks.md` | `.doc/*/requirements.md` |
| 目标是什么？ | `openspec/changes/*/proposal.md` | `.doc/*/tech-design.md` 概述 |
| 学到了什么？ | `.memory/MEMORY.md` | — |
| 做了什么？ | `openspec/changes/*/tasks.md` `- [x]` 项 | `.memory/progress.md` + git log |
| 风险还剩什么？ | progress/findings/error-lessons 中的失败阶段与验证范围 | `.doc/*/tech-design.md` 的验证章节 |

---

## Token 预算控制

最多 500 行上下文输出（从2000降低）。输出: `上下文: {N}/500 行`
优先级: P0 Git状态 > P1 tasks.md > P2 MEMORY.md > P3 progress+findings

超限时裁剪：宁输出"上下文已裁剪"也不倾倒全文。

---

## 推荐下一步

恢复上下文后，基于恢复结果推荐：
- **有活跃 openspec 变更** → 推荐继续该变更
- **有 `.doc/` 需求但无 openspec** → 推荐立即补建 openspec 变更，再继续技术设计
- **发现构建/测试红灯或仅局部验证** → 优先推荐 `pre-flight-check` → `gen-tests` FIX；若是生产日志/事故则转 `log-investigator`
- **工作区已有 `.memory/` 但缺 `skill-feedback.md`** → 追加“建议初始化反馈模板”的轻提醒，不替代主推荐链
- **首次恢复/新项目** → 不推荐，等待用户指示

## 验证风险恢复硬规则

若在以下任一来源中检测到 `compile`、`testCompile`、`package`、`局部测试`、`PARTIAL`、`仅跑目标测试` 等信号：

- `.memory/progress.md`
- `.memory/findings.md`
- `.memory/error-lessons.md`
- `openspec/changes/*/tasks.md`

则必须：

1. 读取相关片段而不是只读最后 3 条摘要
2. 在输出中显式给出：
   - 上次失败阶段
   - 上次验证范围（FULL / PARTIAL / UNKNOWN）
   - 当前残留风险
3. 下一步优先推荐排障/复验链路，而不是直接推荐继续开发

---

## 输出格式

```markdown
## 上下文已恢复
| 问题 | 答案 |
|------|------|
| 我在哪？ | 分支 `feature/payment-export`，0 未提交 |
| 我要去哪？| 支付导出能力（`.doc/payment-export/`，示意占位） |
| 学到了什么？| {MEMORY.md 摘要前3条} |
| 验证状态 | 上次失败阶段: {compile/testCompile/test/none} | 范围: {FULL/PARTIAL/UNKNOWN} |
| 上下文预算 | 120/500 行 (24%) · MEMORY 🟢 |

### 下一步
→ `requirement-assessment`（需求评估）
```

## 参数

| 参数 | 范围 |
|------|------|
| `all` | 全部三层（谨慎使用） |
| `git` | 仅 Layer 1 的 Git 部分 |
| `project` | Layer 1 + Layer 2 |
| `work` | 仅 openspec/ + `.doc/` |
