---
name: ship-release
description: "Ship code to production with 8-step pipeline: detect base, test, review, bump version, changelog, commit, push, create PR. Use when user says 发布, ship, deploy, 发布代码, create PR, push to production"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep,Task
---

# 发布一键流 (Ship Release)

8步发布流水线：检测→测试→审查→版本提升→变更日志→提交→推送→创建PR。

**专家角色：** 发布工程师 — 从代码到生产的一站式完成。

**上游技能：** `deep-review` (review), `gen-tests` (coverage), `sync-progress` (sync)
**下游技能：** `retro` (metrics)

**迭代位置：** 发布阶段（最终出口）

## 何时使用 / 何时不使用

| 适用 ✅ | 不适用 ❌ |
|---------|----------|
| 用户说"发布/ship/deploy/推送到生产" | 仅本地调试 |
| 代码已完成，准备上线 | 探索性实验 |
| 需要 PR + 版本管理 | 临时hotfix无审查 |
| 多文件变更需要完整审查 | 单文件小修无审查需求 |

## 铁律 (Iron Laws)

1. **没有测试通过就没有发布** — 测试失败 → 停止
2. **没有审查通过就没有发布** — review FAIL → 停止
3. **每个声明必须有新鲜证据** — 禁止假设，必须验证
4. **全量验证前不进入版本提升/提交/PR** — 子集测试不能冒充发布门

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：测试、审查、计划完成度与红旗门控都属于 Hard Gate，未通过不得进入后续发布步骤
- **PARTIAL**：只表示计划完成度或验证证据不完整时的“部分验证/部分落地”，不能冒充可发布状态
- **完成标准（DoD）**：统一表示“达到可提交/可推送/可创建 PR 的发布条件集合”
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

## 常见借口与反击

| 借口 | 反击 |
|------|------|
| "测试在CI里通过" | CI ≠ 本地，本地先 |
| "只是一个PR" | 每个PR都值得审查 |
| "先发布，hotfix再说" | hotfix也需要正确流程 |
| "覆盖率80%就够了" | 80%是下限不是目标 |
| "审查发现都是小问题" | 小问题累积成大事故 |
| "跳过版本提升" | 版本号是最重要的文档 |
| "变更日志没用" | 变更日志是团队沟通工具 |
| "先推送，等会再创建PR" | 推送后代码在无人审查状态 |
| "Metrics不重要" | 无Metrics无法追踪趋势 |

**Spirit-over-Letter 声明：** 铁律"没有测试通过就没有发布"的精神是：不发布未验证的代码。如果测试通过但审查发现 P0 问题，等于未验证。流水线每步失败必须停止 — 这不是官僚，是安全网。

---

## 8步发布流水线

### [1] ⚠️ REQUIRED DETECT BASE — 检测基线分支

```
git branch -r → find main/master/develop
git merge-base HEAD {base} → commit range for diff
```

### [2] ⚠️ REQUIRED RUN TESTS — 运行测试套件

运行全量测试。处理既有失败：

| 场景 | 行动 |
|------|------|
| 独立仓库 | 建议立即修复 |
| 协作仓库 | 归因 + 创建 GitHub Issue |
| 未知 | 报告并询问用户 |

**全量验证定义（不可曲解）：**

- 必须运行项目约定的完整验证命令，而不是 `-Dtest`、指定模块、指定测试类等子集命令
- 若本轮或近期曾失败于 `compile` / `testCompile` / `package`，必须先复跑并通过同一失败阶段
- 只有在“原失败阶段已恢复 + 全量验证通过”时，步骤 [2] 才算完成
- 子集测试结果只能作为诊断证据，不能作为发布证据

### [2.5] ⚠️ REQUIRED QUALITY GATE — 质量门控

调用 `quality-check` 计算综合评分。**门控规则：**

| 分数 | 行动 |
|------|------|
| ≥ 7.0 | ✅ 继续 |
| 6.0-6.9 | 🟡 警告，列出退化项，用户确认后继续 |
| < 6.0 | 🔴 阻止发布，修复后重新检测 |

### [3] ⛔ BLOCKING REVIEW DIFF — 审查差异

调用 `deep-review` 对 `git diff {base}...HEAD` 审查。
结果：PASS（继续）| FAIL（列出 P0/P1 阻塞项，停止）。

### [4] ⚠️ REQUIRED BUMP VERSION — 版本提升

| 变更规模 | Semver 动作 |
|---------|------------|
| Breaking/API变更 | MAJOR (x.0.0) |
| 新功能 | MINOR (0.x.0) |
| Bug修复/重构 | PATCH (0.0.x) |
| 仅文档 | 无提升 |

读取当前版本 → 提升 → 写回文件。

### [5] ⚠️ REQUIRED CHANGELOG — 变更日志

从 `git log {base}...HEAD` + `git diff` 生成：

```markdown
## [vX.Y.Z] - YYYY-MM-DD
### Added / Fixed / Changed / Breaking
- scope: description (#PR)
```

追加到 CHANGELOG.md 顶部。

### [6] ⚠️ REQUIRED COMMIT + PUSH — 提交并推送

```
conventional commit: type(scope)!: description
body: key changes (≤5 bullets)
```

`git push -u origin {branch}`

### [7] ⚠️ REQUIRED CREATE PR — 创建PR (自适应描述)

| Diff规模 | 描述风格 |
|---------|---------|
| <10行 | 一句话总结 |
| 10-50行 | 2-3要点 + 文件列表 |
| 50-200行 | 多章节详细描述 |
| >200行 | 完整章节 + 示例 |

PR模板：

```
## Summary
- bullet points

## Test Plan
- [ ] unit tests pass
- [ ] manual verification: {steps}
- [ ] coverage ≥ {threshold}%

## Screenshots (if UI)
```

使用 `gh pr create` 创建。

### [8] (conditional) METRICS — 记录指标

追加到 `.memory/ship-metrics.jsonl`：

```jsonl
{"date":"YYYY-MM-DD","coverage":85.2,"quality_score":7.8,"plan_completion":"DONE:8/PLAN_PARTIAL:2/NOT_DONE:1","tests":"pass","review":"PASS","version":"1.2.0","branch":"feat-x"}
```

### [8.5] (conditional) RETRO TRIGGER — 复盘触发

PR 创建后推荐运行 `retro`。条件：本次 diff > 200行 OR 跨 ≥ 3 个模块 → **自动建议复盘**。

---

## 计划完成度审计 (Plan Completion Audit)

发现计划文件（从上下文或 `**/*plan*` 搜索）。提取可执行项，交叉比对 diff：

| 条目 | 分类 |
|------|------|
| 在diff中且在计划中 | ✅ DONE |
| 部分在diff中 | ⚠️ PLAN_PARTIAL |
| 在计划中但不在diff中 | ❌ NOT DONE |
| 在diff中但不在计划中 | 🔄 CHANGED |

**门控：** 核心项 NOT DONE → 阻止发布，询问用户。

---

## 覆盖率门控 (Coverage Gate)

| 阈值 | 来源 | 行动 |
|------|------|------|
| 最低 60% | CLAUDE.md 或默认 | 低于 → 触发 `gen-tests` |
| 目标 80% | CLAUDE.md 或默认 | 报告差距 |
| 自定义 | 项目配置 | 使用自定义值 |

最多2轮 `gen-tests`。在 CLAUDE.md 中配置：

```yaml
## Health Stack
coverage_minimum: 60
coverage_target: 80
```

---

## 完成选项 (Structured Options)

管道完成后提供4个选项：

| 选项 | 描述 | 行动 |
|------|------|------|
| **Merge** | 合并到基线 | 本地 merge + push |
| **Push+PR** | 推送并创建PR | `push -u` + `gh pr create` |
| **Keep** | 保留当前状态 | 不推送，保留分支 |
| **Discard** | 丢弃变更 | 删除分支（需确认） |

**Discard 确认：** 用户必须输入 `discard`。显示将被删除的内容。

---

## 红旗 (Red Flags)

| 🚩 信号 | 严重性 | 行动 |
|---------|--------|------|
| 测试覆盖率 < 40% | P0 Critical | 阻止发布 |
| 原失败阶段未复验 | P0 Critical | 阻止发布 |
| 只存在子集测试通过证据 | P0 Critical | 阻止发布 |
| diff > 500行无计划文件 | P1 High | 警告，要求确认 |
| P0 审查发现未解决 | P0 Critical | 阻止发布 |
| CHANGELOG 未更新 | P2 Low | 自动生成 |
| 版本未提升 | P1 High | 自动提升 |
| 存在 `console.log` / `debugger` | P1 High | 清理后发布 |
| 存在 `TODO` / `FIXME` | P2 Low | 报告但不阻止 |
| secrets 硬编码 | P0 Critical | 立即阻止，删除 |
| 未追踪的大文件 | P1 High | 检查 .gitignore |
| 分支与基线差距 > 50 commits | P1 High | 建议 rebase |

---

## 输出格式 (Ship Report)

```
╔══════════════════════════════════════╗
║         SHIP REPORT                  ║
╠══════════════════════════════════════╣
║ Base: {branch} → Target: {branch}   ║
║ Tests: ✅/❌  |  Coverage: {n}%      ║
║ Review: {PASS/FAIL} | P0/P1/P2: {n} ║
║ Version: {old} → {new}              ║
║ Changelog: ✅ Generated              ║
║ PR: #{url}                          ║
║ Plan: DONE {n} | PLAN_PARTIAL {n} | MISS {n}║
╚══════════════════════════════════════╝
```

**执行顺序严格：** DETECT → TEST → REVIEW → BUMP → CHANGELOG → COMMIT → PUSH → PR → METRICS
每步失败停止流水线，报告原因。
