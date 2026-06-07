---
name: quality-check
description: "Compute weighted 0-10 code quality score with auto-detected tools and trend tracking. Use when user says 质量检查, 代码质量, quality check, health check, 质量评分"
allowed-tools: Bash,Read,Glob
---

# 质量检查

Compute weighted 0-10 code quality score with auto-detected tooling and historical trend tracking.

**专家角色：** 质量守门员 — 不依赖主观感受，用数据说话。

**上游技能：** 无
**下游技能：** `restore-context` (reads health history), `dev-workflow` (pre-ship check)

---

## 何时使用

用户说 "质量检查" / "代码质量" / "quality check" / "health check" / "质量评分"。

## 何时不使用

- 项目无任何检测工具配置（无 tsconfig / eslint / test scripts）
- 用户明确说"跳过检查"

---

## 常见陷阱

| 失败 | 预防 |
|------|------|
| 首次运行无基线 | 正常 — 本次结果即为基线 |
| 分数低但测试通过 | 检查覆盖范围，可能只跑部分测试 |
| 局部测试被当成整体 Tests 分数 | 过滤参数/子集运行只能算局部验证，不能直接计满分 |
| 工具检测失败 | 手动指定工具到 CLAUDE.md `## Health Stack` |
| 每次都重新检测工具 | 首次检测后持久化到 CLAUDE.md |
| 忽略 dead code 检测 | 未使用导出 = 隐性维护负担 |

---

## 红旗警告

| 想法 | 为什么错 |
|------|----------|
| "分数=10=完美" | 总有改进空间，10 是理论极限 |
| "一次检查够了" | 代码会退化，持续追踪才有意义 |
| "测试通过就没事" | 类型错误和 dead code 也是债务 |
| "只看总分" | 单项退化被总分掩盖 |

---

## Iron Law

1. **不跳过任何检测到的工具。** 每个工具必须执行并计分。
2. **分数下降必须解释原因。** 标注哪个类别退化及可能 commit。
3. **局部验证不能冒充整体质量。** 过滤后的测试结果不得直接作为 Tests 综合分依据。

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：Tests 类别硬规则就是本技能的 Hard Gate，未满足不得把结果当正式健康结论
- **PARTIAL**：只表示测试验证范围未覆盖全量
- **完成标准（DoD）**：本技能的完成标准是完成所有已检测工具的执行、评分与趋势对比
- **验证范围**：统一使用 `文件 / 模块 / workspace / 全仓库`

---

## 工具自动检测 (Tool Auto-Detection)

| 工具类别 | 检测信号 | 执行命令 |
|----------|----------|----------|
| Type Check | `tsconfig.json` | `tsc --noEmit` |
| Lint | `biome.json` / `.eslintrc*` / `ruff.toml` | `biome check` / `npx eslint .` / `ruff check .` |
| Tests | `package.json` scripts.test / `pytest.ini` | `npm test` / `bun test` / `pytest` |
| Dead Code | `knip` in devDeps | `npx knip` |
| Shell Lint | `*.sh` files exist | `shellcheck **/*.sh` |

首次检测后写入 CLAUDE.md `## Health Stack` 段落以持久化。

**Tests 类别硬规则：**

- 只有项目约定的全量测试命令成功，Tests 分项才可按正常评分表打分
- 若命令包含类/方法/文件过滤，或无法证明覆盖全量范围，Tests 必须标记为 `PARTIAL`
- 典型局部命令包括：`mvn -Dtest=... test`、`pytest path::case`、`npm test -- path/to/test`
- `PARTIAL` 不得记为 10 分；最高按 4 分封顶，或在无法量化时记为 `N/A`
- `PARTIAL` 时综合分只能标记为“参考值”，不得当成正式健康结论

---

## 评分体系 (Scoring System)

加权 0-10 综合评分：

| 类别 | 权重 | 10 | 7 | 4 | 0 |
|------|------|----|---|---|---|
| Type Check | 25% | clean | <10 errors | <50 errors | ≥50 errors |
| Lint | 20% | clean | <5 warnings | <20 warnings | ≥20 warnings |
| Tests | 30% | all pass | >95% pass | >80% pass | ≤80% pass |
| Dead Code | 15% | clean | <5 unused | <20 unused | ≥20 unused |
| Shell Lint | 10% | clean | <5 issues | ≥5 issues | N/A |

**综合分 = Σ(类别分 × 权重)**

---

## 工作流程

```
[1] Auto-detect tools
    ├── 扫描项目根目录检测信号文件
    ├── 如 CLAUDE.md 有 ## Health Stack → 复用
    └── 否则检测并写入 CLAUDE.md
    ↓
[2] Run each detected tool (sequential)
    ├── 记录 stdout/stderr 和 exit code
    └── 解析错误数 / 警告数 / 失败测试数 + 是否全量执行
    ↓
[3] Score each category → lookup 评分表
    ↓
[4] Compute weighted composite score
    ↓
[5] Persist to .memory/health-history.jsonl
    ├── {"date":"...","score":7.8,"categories":{...},"commit":"abc123"}
    └── append 模式，不覆盖历史
    ↓
[6] Compare with previous scores
    ├── 读取最近 5 条记录
    └── 分数下降 ≥1 → flag regression
    ↓
[7] Output dashboard
```

---

## 趋势追踪 (Trend Tracking)

**存储格式：** `.memory/health-history.jsonl`

每行一条记录：`{"date":"YYYY-MM-DD","score":7.8,"categories":{"type":10,"lint":7,"tests":7,"dead":10,"shell":10},"commit":"abc123"}`

**趋势显示（最近 5 次）：**

| 日期 | 综合分 | Type | Lint | Tests | Dead | Shell | 趋势 |
|------|--------|------|------|-------|------|-------|------|
| 04-05 | 7.8 | 10↑ | 7→ | 7↓ | 10→ | 10→ | → |

**退化检测：** 任何类别分数下降 ≥1 点 → 标注该类别及可能关联的 commit。

---

## 仪表盘输出 (Dashboard Output)

```markdown
## 质量仪表盘

综合评分: 7.8/10 → (上次 8.0 ↓0.2)

| 类别 | 分数 | 趋势 | 详情 |
|------|------|------|------|
| Type Check (25%) | 10 | ↑ | 0 errors |
| Lint (20%) | 7 | → | 3 warnings |
| Tests (30%) | 7 | ↓ | 96% pass (2 failed) |
| Dead Code (15%) | 10 | → | 0 unused exports |
| Shell Lint (10%) | N/A | — | 无 .sh 文件 |

⚠️ 退化警告: Tests 从 10→7，检查最近 commit 是否引入测试失败
⚠️ 验证范围: {FULL / PARTIAL}；若 PARTIAL，综合分需降级解读
⚠️ 结论等级: {正式 / 参考}；PARTIAL 时只能是“参考”

### 改进建议
1. 修复 2 个失败测试（优先级高，权重 30%）
2. 修复 3 个 lint warnings（优先级中）
```

---

## 常见借口

| 借口 | 反击 | 行动 |
|------|------|------|
| "分数只是数字" | 数字驱动决策，主观不可靠 | 所有判断基于分数和趋势 |
| "测试通过就够了" | 类型错误和 dead code 也是债务 | 执行全部分类检查 |
| "退化0.5分不算什么" | 小退化是趋势起点 | 标注退化 + 可能 commit |
| "跳过 dead code 检测" | 未使用导出 = 隐性维护成本 | 每个检测到的工具必执行 |
| "没装工具就跳过" | 首次检测后写入 CLAUDE.md | 检测 + 持久化 + 执行 |
| "上次检查过，不用再查" | 代码会退化，单次检查无意义 | 持续追踪 + 趋势对比 |
| "只看总分" | 单项退化被总分掩盖 | 逐类别报告 + 趋势箭头 |
| "分数下降了但功能正常" | 功能正常 ≠ 健康良好 | 退化警告 + 建议修复 |
| "Shell 脚本不重要" | Shell bug = 生产事故 | 检测到 .sh 就必检 |
| "一次检查够了" | 代码库持续演化 | 每次提交前运行 |

**Spirit-over-Letter 声明：** Iron Law "不跳过任何工具" 的精神是：完整可见性。如果跳过一个工具能让你"感觉好"但遗漏问题，违反精神。宁可多跑一个工具，不可遗漏一类缺陷。

---

## 跨技能集成

| 技能 | 集成方式 |
|------|----------|
| `restore-context` | 读取 health-history.jsonl 显示质量趋势 |
| `dev-workflow` | 发布前 quality gate，分数 <6 → 阻止发布 |
| `retro` | 复盘报告包含健康分数趋势 |
| `compound-learning` | 重复出现的错误记录为知识 |
