---
name: retro
description: "Run engineering retrospective with git analytics, hotspot analysis, and trend tracking. Use when user says 复盘, 回顾, 总结, retro, retrospective, weekly review"
allowed-tools: Bash,Read,Glob
---

# 复盘 (Engineering Retrospective)

基于 git 数据的工程复盘，包含热点分析和趋势追踪。

**专家角色：** 复盘分析师 — 用数据讲故事，不用主观印象。

**上游技能：** 无
**下游技能：** `restore-context` (reads retro history)

---

## 何时使用
用户说 "复盘" / "回顾" / "总结" / "retro" / "retrospective" / "weekly review"。

## 何时不使用
- 工作正在进行中（等完成后再复盘）| 项目刚启动（<5 commits）

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 无数据复盘 | 总是先跑 git stats，数据优先 |
| 只看最近一周 | 对比历史趋势，看变化方向 |
| 忽略热点文件 | 热点 = 风险指标，必须分析 |
| 只数 commit 数量 | 质量 > 数量，看 LOC 和 PR 大小 |
| 不保存历史 | 每次复盘结果持久化到 .memory/retros/ |
| 大量时间花在修 compile/testCompile 红灯却没被识别 | 必须单列构建健康风险与行动项 |

---

## 红旗警告

| 想法 | 为什么错 |
|------|----------|
| "这周没什么变化" | 变化可能隐蔽，用数据验证 |
| "commit 数 = 生产力" | 1 个好 commit > 20 个小 fixup |
| "复盘浪费时间" | 不复盘 = 重复犯错 |
| "只看自己的提交" | 团队视角才能发现协作问题 |

---

## Iron Law

1. **必须基于 git 数据而非主观印象。** 每个结论必须有数据支撑。
2. **热点文件需要行动建议。** 不能只列出名单，必须说明风险和行动。
3. **后期救火式交付必须被识别。** 若大量工作集中在修构建/编译红灯，不能被产出指标掩盖。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：构建健康硬规则属于 Hard Gate，命中时不得在复盘中轻描淡写带过
- **PARTIAL**：本技能不使用 `PARTIAL` 表示复盘状态
- **完成标准（DoD）**：统一表示“指标、热点、风险、行动项都已形成可执行复盘结论”
- **验证范围**：在本技能中主要指复盘证据覆盖到的提交/周期范围，不表示测试执行状态

---

## 学习聚合 (Learnings Aggregation)

复盘后自动扫描 commit 消息和 diff，捕获非显而易见的洞察。

| 学习类型 | 说明 | 示例 |
|----------|------|------|
| `pattern` | 可复用的方法模式 | "热点文件 >5 次变更 → 需要拆分" |
| `pitfall` | 应避免的陷阱 | "fix ratio >50% → 审查流程有缺口" |
| `architecture` | 架构决策洞察 | "测试集中在 service 层，UI 层缺失" |
| `operational` | 项目环境/工具知识 | "build 需要 --no-optional 标志" |

存储路径：`.memory/learnings.jsonl`，每条含 confidence (1-10) + 关联文件列表。仅记录 confidence ≥ 7 的洞察。

---

## 行动项追踪 (Action Item Tracking)

从热点分析和修复链中生成具体行动项。

| 字段 | 说明 | 示例 |
|------|------|------|
| 标题 | 具体可执行的行动描述 | "拆分 authService.ts 为 3 个模块" |
| 优先级 | P0 (紧急) / P1 (重要) / P2 (改善) | P1 |
| 负责人 | 建议的责任人 | "@alice" |
| 截止建议 | 建议完成时间 | "下次复盘前" |

存储路径：`.memory/retros/action-items.md`，追加式写入，不覆盖历史项。完成项标记 `✅`。

---

## 速度趋势 (Velocity Trends)

追踪团队和个人速度指标，对比历史均值。

| 指标 | 计算方式 | 意义 |
|------|----------|------|
| 团队连续天数 | 所有贡献者合并，每日 ≥1 commit | 团队节奏健康度 |
| 个人连续天数 | 仅当前用户，每日 ≥1 commit | 个人节奏稳定性 |
| commits/天 | 本期日均 vs 历史日均 | 产出效率变化 |
| LOC/天 | 本期日均 vs 历史日均 | 代码产出速率 |

连续天数：从今天往前逐日计数，含 `origin/<default>` 上至少 1 个 commit 的连续日。无上限。

---

## 参数 (Arguments)

| 命令 | 时间范围 | 说明 |
|------|----------|------|
| `/retro` | 7d | 默认一周复盘 |
| `/retro 24h` | 1 day | 日报式快速复盘 |
| `/retro 14d` | 14 days | 双周复盘 |
| `/retro 30d` | 30 days | 月度复盘 |
| `/retro compare` | — | 对比最近两个等长周期 |

---

## 工作流程

```
[1] 收集原始数据 (12 parallel git commands)
    ├── git log --stat, --oneline, --format with timestamps
    ├── per-commit LOC breakdown (+/-)
    ├── file hotspot analysis (most-changed files)
    ├── shortlog by author
    └── test file changes detection
    ↓
[2] 计算指标
    ├── Total commits, PRs, LOC added/removed
    ├── Test ratio (test file changes / total changes)
    └── Version range (tags between period)
    ↓
[3] 工作会话检测
    ├── 45-min gap threshold between commits
    ├── Deep session: >50 min continuous work
    ├── Medium session: 20-50 min
    └── Micro session: <20 min
    ↓
[4] 提交类型分析 (conventional commit prefixes)
    ├── feat / fix / refactor / docs / test / chore
    └── ⚠️ fix ratio >50% → flag as quality concern
    ↓
[4.5] 构建健康风险分析
    ├── 检测 compile / testCompile / dependency / config / ci 等关键词
    ├── 检测周期末集中修红灯的提交簇
    └── 构建救火占比高 → flag as delivery risk
    ↓
[5] 热点分析
    ├── Top 10 most-changed files (by commit count + LOC)
    ├── Churn detection: file changed >5x → risk
    └── 每个热点文件附带行动建议
    ↓
[6] PR 大小分布
    ├── Small: <100 LOC | Medium: 100-500 | Large: 500-1000 | XL: >1000
    └── Large/XL >30% → flag as review bottleneck
    ↓
[7] 专注分数 + Ship of the Week
    ├── Focus Score: % of commits touching single most-changed directory
    └── Ship of the Week: 最高影响力单次提交
    ↓
[8] 周对比趋势 (14d+ windows only)
    ├── 对比前一个等长周期的指标
    └── 标注变化方向 (↑↓→) 和幅度
    ↓
[9] 保存历史
    ├── .memory/retros/YYYY-MM-DD-retro.json
    └── 包含完整指标快照
    ↓
[9.1] 学习聚合
    ├── 扫描 commit 消息和 diff 中的模式关键词
    ├── 识别非显而易见洞察 (confidence ≥ 7)
    └── 追加写入 .memory/learnings.jsonl
    ↓
[9.2] 行动项生成
    ├── 热点文件 → 重构/拆分建议
    ├── 修复链 (同文件连续 fix) → 流程改进建议
    └── 追加写入 .memory/retros/action-items.md
    ↓
[10] 输出复盘报告
```

---

## 输出格式

```markdown
## 复盘报告 (YYYY-MM-DD ~ YYYY-MM-DD)

### 可推文摘要
> 本周 {N} commits, {LOC} LOC, 专注分数 {X}%
> Top: {Ship of the Week 一句话}

### 指标概览

| 指标 | 本期 | 上期 | 趋势 |
|------|------|------|------|
| Commits | {n} | {n} | ↑↓→ |
| LOC (+/-) | {n}/{n} | — | — |
| PRs | {n} | {n} | ↑↓→ |
| Test Ratio | {x}% | {x}% | ↑↓→ |
| Focus Score | {x}% | — | — |
| Sessions (D/M/μ) | {n}/{n}/{n} | — | — |

### 提交类型分布
{feat/fix/refactor/docs/test/chore 的百分比条形图}

### 热点文件 Top 10
| # | File | Commits | LOC | 风险 | 建议行动 |
|---|------|---------|-----|------|----------|

### Ship of the Week
{最高影响力提交的详细说明}

### 学习聚合

| # | 类型 | 洞察 | Confidence | 关联文件 |
|---|------|------|------------|----------|
| 1 | pattern | {洞察} | {n}/10 | {file} |

### 构建健康风险

| 指标 | 数值 | 风险 |
|------|------|------|
| Build-Fix Ratio | {x}% | {Low/Medium/High} |
| Late Build Rescue | {Yes/No} | {说明} |

### 行动项

| # | 行动 | 优先级 | 负责人 | 截止 |
|---|------|--------|--------|------|
| 1 | {行动描述} | P{0-2} | {who} | {when} |

### 速度趋势

| 指标 | 本期 | 历史均值 | 趋势 |
|------|------|----------|------|
| 团队连续天数 | {n} | — | — |
| 个人连续天数 | {n} | — | — |
| commits/天 | {n} | {n} | ↑↓→ |
| LOC/天 | {n} | {n} | ↑↓→ |

### 下周建议
1. {基于数据的建议}
2. ...
```

**构建健康硬规则：**

- 若与 `compile/testCompile/dependency/config/ci` 相关的修复提交占比过高，必须在报告中单列风险
- 若交付前最后阶段集中出现修红灯提交，必须生成至少 1 条流程行动项
- 不得因为 commits/LOC 看起来不错就忽略该类风险

---

## 跨技能集成

| 技能 | 集成方式 |
|------|----------|
| `restore-context` | 恢复会话时显示上次复盘摘要 |
| `quality-check` | 复盘报告包含健康分数趋势 |
| `compound-learning` | 复盘中发现的模式写入 `.memory` / `skill-feedback.md` |
| `restore-context` | 读取 `.memory/learnings.jsonl` 跨会话复用洞察 |
| `sync-progress` | 行动项需要进入当前交付状态时同步记录 |

---

## 跨项目模式
检测到多个 git 仓库时：扫描所有仓库 git stats → 聚合全局指标 → 全局 streak = 所有仓库连续天数 → 按仓库分组展示热点。

---

## Ship Metrics 集成
读取 `.memory/ship-metrics.jsonl` 趋势数据：| 日期 | 覆盖率 | 计划完成 | 审查结果 |。覆盖率趋势 = 最近 N 次 ship 的覆盖率变化方向。
