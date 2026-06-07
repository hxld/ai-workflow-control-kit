---
name: obsidian-wiki
description: "LLM 编译的综合型个人知识库（Karpathy llm-wiki 方法论）。将原始来源增量编译为结构化 Obsidian wiki，支持多领域（work/tech/learning/travel/life）。Use when user says: wiki init, wiki ingest, wiki ask, wiki maintain, 收录, 知识库, 编译wiki, 知识库初始化, 巡检wiki, 摄入, 收录文档, 批量收录, 重建wiki, 批量重建, 刷新过期wiki"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep,Task,Skill
---

# Obsidian Wiki

LLM 编译的综合型个人知识库。基于 Karpathy llm-wiki 方法论：LLM 持续构建和维护持久化的、相互链接的 markdown wiki，知识只编译一次然后持续更新。

**核心理念**：不是每次查询从原始文档重新检索（RAG），而是 LLM 增量构建 wiki。每新增一个来源，LLM 阅读、提取关键信息、整合到现有 wiki（更新实体页、修正矛盾、强化综合）。wiki 是持久化、持续复利的知识产物。

**专家角色：** 知识管理工程师 — 负责将原始文档编译为结构化、相互链接的 wiki 页面，持续维护知识库的健康和一致性。

**上游技能：** yuque-to-markdown（语雀文档转为来源）
**下游技能：** compound-learning（wiki 发现错误时沉淀）, knowledge-refresh（过期页面刷新）

---

## 何时使用

- "wiki init" / "初始化知识库" / "建知识库"
- "wiki ingest" / "收录" / "摄入" / "收录这篇" / "加到知识库"
- "wiki ingest --batch" / "批量收录" / "整理 inbox"
- "wiki ingest --rebuild" / "重建wiki" / "批量重建" / "刷新过期wiki"
- "wiki ask" / 直接问知识库相关问题
- "wiki maintain" / "巡检" / "检查 wiki"

## 何时不使用

- 纯代码开发任务 → dev-workflow
- 代码审查 → deep-review
- 需求评估 → requirement-assessment

---

## 硬规则

1. **raw/ 只读** — LLM 永远不修改 raw/ 下的任何文件
2. **wiki/ 可写** — LLM 创建、更新、重建 wiki 页面
3. **断言可回链** — 所有非平凡断言必须通过 frontmatter 的 sources 字段可追溯到 raw/ 来源
4. **log.md append-only** — 只追加，不修改或删除历史条目
5. **单次 ingest 必须完整** — 至少更新：source 摘要页 + 相关 concept/entity 页 + index.md + log.md
6. **frontmatter 必须完整** — 新建 wiki 页面必须有 type, area, created, updated, tags；concept/entity 页还必须有 confidence
7. **kebab-case 命名** — 文件名使用 kebab-case，禁止空格和中文字符
8. **不碰外部目录** — 永远不修改 vault 外的任何文件
9. **规范性断言必须标注状态** — 对"完成标准 / 验收标准 / 发布门槛 / 当前流程"这类规范性断言，必须区分"来源历史表述"与"当前有效约定"
10. **未校验不得上升为 wiki 真相** — 若缺少现行实践源或交叉验证，禁止把规范性断言写成 concept/theme 页中的当前结论，只能保留在 source 摘要页并标记待校验
11. **concept/entity 必须标注 confidence** — 新建或更新 concept/entity 页时，必须根据信息来源标注 confidence（extracted/inferred/unverified）

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：`规范性断言 Hard Gate` 未通过时，不得把相关断言提升为 wiki 当前知识
- **PARTIAL**：只表示本次 ingest 对规范性断言的校验未完成，不能表示“知识编译完成一半”
- **完成标准（DoD）**：统一表示“source / concepts / entities / index / log 以及规范性断言状态都处理到位”
- **验证范围**：在本技能中指规范性断言的校验覆盖范围，而非测试执行范围

---

## Decision Tree

| 用户意图 | 路由 |
|---------|------|
| "初始化知识库" / "wiki init" | → init |
| "收录这个" / "wiki ingest" / "加入知识库" | → ingest（单文件） |
| "批量收录" / "ingest --batch" / "整理 inbox" | → ingest --batch |
| "重建wiki" / "ingest --rebuild" / "刷新过期wiki" | → ingest --rebuild |
| 直接问问题 / "wiki ask" | → ask（Phase 2） |
| "检查 wiki" / "巡检" / "wiki maintain" | → maintain（Phase 2） |

---

## 命令详解

### init `[vault-path]`

初始化 Obsidian vault 知识库。

**步骤：**
1. 确定vault路径（优先级：命令参数 > vault CLAUDE.md > 环境变量 OBSIDIAN_VAULT_PATH > 询问用户）
2. 创建全局文件（读 templates/ 模板）：
   - `CLAUDE.md`（vault schema）
   - `index.md`（内容目录）
   - `log.md`（操作日志）
   - `assets/`（全局附件）
   - `templates/`（页面模板）
   - `inbox/`（全局收件箱）
3. 为每个领域创建子目录：`{area}/raw/sources/` + `{area}/wiki/sources/` + `{area}/wiki/concepts/` + `{area}/wiki/entities/` + `{area}/wiki/themes/` + `{area}/wiki/explorations/`
4. 初始化 git repo
5. 写入初始 log 条目

**默认领域**：work, tech, learning, travel, life

**注意**：raw/sources/ 下的子目录由用户自行创建和管理，init 不创建任何子目录。

### ingest `[area] [path]`

收录单个文件到指定领域。支持三种来源：
1. **inbox/ 中的文件**：LLM 移动到 `{area}/raw/sources/`
2. **外部文件路径**：LLM 复制到 `{area}/raw/sources/`（原文件不动）
3. **raw/sources/ 中已有的文件**：LLM 直接读取并编译（文件不动，只生成 wiki 页面）

**步骤：**
0. 如果文件已在 `{area}/raw/sources/` 下，跳过移动步骤
1. 如果文件在 `inbox/`，LLM 将其移动到 `{area}/raw/sources/`（保留用户已有的子目录结构）
2. 如果是外部文件路径，LLM 复制到 `{area}/raw/sources/`（原文件不动）
3. 读取文件内容
3.5. **读取 `{area}/wiki/purpose.md`**（如存在），获取该领域的研究方向、关注主题，用于指导后续概念取舍和标签权重
4. 读取 `references/compile-prompts.md`，按来源类型选择提取模板
5. Per-source pass：提取 concepts / entities / key_claims / tags
5.5. **为每个提取的 concept/entity 确定 confidence**：原文有明确表述 → extracted；需推理得出 → inferred；来源不明确 → unverified
6. 若出现"完成标准 / 验收标准 / 发布门槛 / 当前流程"类规范性断言，先判断它是**历史来源表述**还是**当前有效约定**
7. 写 source 摘要页 → `{area}/wiki/sources/`；未完成交叉验证的规范性断言，只能留在 source 页并标记 `待校验`
8. Cross-source pass：仅将已完成交叉验证的规范性断言写入概念页/主题页；否则只记录"来源间存在差异/待确认"
8.5. **创建/更新 concept/entity 页时必须标注 confidence**，并检查是否需要升级或降级已有 confidence
9. 创建/更新实体页 → `{area}/wiki/entities/`
10. 如涉及跨领域概念，在目标领域也创建/更新页面
11. 更新 `index.md`
12. 追加条目到 `log.md`

**ingest 完成门：**
- 若检测到规范性断言但未完成校验与标注，则本次 ingest 只能标记为 `PARTIAL`
- `PARTIAL` 状态下不得把相关断言写入 `concepts` / `themes` / `index.md` 的当前有效知识描述

**来源类型自动检测：**
- 含"接口"/"API"/"系统" → technical
- 含"会议"/"周报"/"日报" → meeting
- 含"需求"/"PRD"/"设计" → requirement
- .pdf + 含"论文"/"arxiv" → paper
- 含"书"/"章"/"课程" → book
- 含"旅行"/"攻略"/"行程" → travel
- 其他 → article

### ingest --batch

批量处理文件。支持两种模式：
1. **inbox/ 批量**：处理 inbox/ 中所有文件
2. **raw/sources/ 批量**：处理指定领域中尚未编译的文件（LLM 扫描 raw/sources/ 发现无对应 wiki 摘要页的文件）

**步骤：**
1. **inbox 模式**：运行 `python scripts/scan_inbox.py <vault-path>` 获取文件列表
   **raw/sources 模式**：扫描 `{area}/raw/sources/` 下的所有 .md/.pdf 文件，与 `{area}/wiki/sources/` 比对，找出未编译的文件
2. 逐个读取文件，判断领域和来源类型
3. 输出分类计划让用户确认：
   ```
   📥 inbox/ 中发现 N 个文件：

   文件                    → 领域/类型
   OCR接口文档.md          → work/technical
   Transformer论文.pdf     → tech/paper
   如何规划日本旅行.md     → travel/travel
   ...
   
   确认分类？[Y/n/修改]
   ```
4. 用户确认后，每批 3-5 个文件执行 ingest
5. 每批完成后输出进度
6. 全部完成后输出汇总报告
7. 追加汇总条目到 log.md

**分批规则：** 每批最多 5 个文件，避免上下文耗尽。

### ingest --rebuild

批量重建过期的 wiki 页面。适用于用户直接修改了 raw/sources/ 中的源文件，导致 wiki 内容过期的场景。

**与 --batch 的区别：**
- `--batch`：只处理**未编译**的文件（wiki/sources/ 无对应摘要页）
- `--rebuild`：只处理**已编译但过期**的文件（raw 比 wiki 更新）

**步骤：**
1. 扫描 `{area}/raw/sources/` 下所有 .md/.pdf 文件
2. 对每个源文件：
   a. 获取 raw 文件修改时间（`stat` / `ls -la`）
   b. 查找对应 wiki/sources/ 摘要页，读取 frontmatter `updated` 时间
   c. 若 raw 修改时间 > wiki updated 时间，标记为"过期"
3. 输出重建计划让用户确认：
   ```
   🔄 发现 N 个过期 wiki（源文件比 wiki 更新）：

   源文件                                    wiki 更新时间   过期天数
   raw/sources/order-system/refund-api.md       2026-04-05     10天
   raw/sources/integration-system/vendor-api.md 2026-04-01     14天
   ...

   确认重建？[Y/n/选择部分]
   ```
4. 用户确认后，逐个重新 ingest（删除旧 wiki 页面 → 重新编译）
   - ⚠️ 删除旧 wiki 前先读取其 frontmatter `sources` 和内容，保留跨链接引用
   - 重建时遵循与单次 ingest 相同的完成门和规范性断言规则
5. 每批 3-5 个文件，每批完成后输出进度
6. 全部完成后更新 `index.md` + 追加汇总到 `log.md`

**过期检测细节：**
- raw 文件时间取文件系统 mtime（Git 不影响）
- wiki 时间取 frontmatter `updated` 字段（ISO 日期）
- 若 wiki 页面无 `updated` 字段，视为过期（保守策略）

**重建范围：**
- source 摘要页：全量重建
- concept/entity 页：只更新与该源相关的条目（diff 判断）
- index.md：批量重建完成后统一更新一次
- log.md：每个文件一条 + 最终汇总一条

**安全约束：**
- ⛔ 不删除不重建的 wiki 页面（不在过期列表中的不受影响）
- ⛔ 不修改 raw/ 下的任何文件

---

## Vault 路径解析

按以下优先级查找 vault 路径：
1. 用户命令中明确指定的路径
2. vault 根目录下 CLAUDE.md 中的 vault_path 声明
3. 环境变量 `OBSIDIAN_VAULT_PATH`
4. 询问用户

---

## 与其他技能的协作

| 场景 | 协作技能 | 触发条件 |
|------|---------|---------|
| wiki 发现错误教训 | compound-learning | 用户说"记住这个错误" |
| wiki 页面过期 | knowledge-refresh | maintain 发现过期内容 |
| 语雀文档转为来源 | yuque-to-markdown | 用户提供语雀链接 |
| 批量操作预检查 | pre-flight-check | 涉及 2+ 文件修改 |

---

## 文件引用

- **目录规范 + frontmatter**：读 `references/schema.md`
- **来源类型提取 prompt**：读 `references/compile-prompts.md`（仅 ingest 时加载）
- **wiki 页面生成模板**：读 `references/page-templates.md`（仅 ingest 时加载）
- **非 md 格式预处理**：读 `references/format-guide.md`（遇到非 md/pdf 文件时加载）
- **Vault 初始化模板**：读 `templates/CLAUDE.md.tpl`、`templates/index.md.tpl`、`templates/log.md.tpl`

---

## 规范性断言 Hard Gate

当来源中出现以下内容时，视为**规范性断言**：

- 完成标准 / DoD
- 验收标准
- 发布门槛 / 上线条件
- 当前流程、必经审批、固定纪律

处理规则：

1. 必须优先写入 `source` 摘要页，并保留“该来源如此表述”的语气
2. 只有在存在**现行实践源**或用户明确确认“当前仍有效”时，才可写入 `concepts` / `themes`
3. 若与现有 wiki 冲突，不能静默覆盖，必须在相关页面标注“存在冲突/待确认”
4. 未校验时禁止写成“当前团队就是这样执行”的确定性结论
5. 完成校验后，必须在页面或 `log.md` 中留下可追溯记录：`依据了哪个现行源 / 谁确认仍有效 / 校验日期`
6. 对照依据必须可点名到具体材料：`文件路径/页面名 + 章节/段落 + 校验日期`
7. 未校验的规范性断言不得进入 `index.md` 的当前知识导航描述，避免通过索引二次扩散

---

## purpose.md（领域研究方向）

每个领域可在 `{area}/wiki/purpose.md` 中记录研究方向。ingest 时优先读取，用于：
- 决定哪些概念值得建 concept 页 vs 仅在 source 页提及
- 指导标签权重（符合研究方向的概念优先级更高）
- 不需要手动维护，可在 maintain 工作流中根据已有 wiki 内容自动更新

**格式：**
```markdown
---
type: purpose
area: {area}
updated: YYYY-MM-DD
---
# {领域名} 研究方向

## 关注主题
- {主题1}：{为什么关注}
- {主题2}：{为什么关注}

## 核心问题
- {问题1}
- {问题2}
```

**生命周期：**
- init 时不自动创建（避免空模板）
- 首次用户明确说"设定研究方向"时创建
- maintain 工作流可建议更新

---

## Confidence 规则

concept/entity 页必须标注 confidence 字段，表示知识的可靠程度：

| 值 | 含义 | 何时用 |
|------|------|--------|
| `extracted` | 信息直接来自原始来源 | 原文中有明确表述，可回链到具体段落 |
| `inferred` | 从多处来源推断得出 | 综合 ≥2 个 source 的信息推导，原文无直接表述 |
| `unverified` | 缺少原始来源佐证 | 仅来自 LLM 背景知识或来源不明确 |

**升级/降级规则：**
- 新 source 增加佐证 → 可升级（unverified → inferred → extracted）
- 新 source 引入矛盾 → 降级为 inferred
- 规范性断言不使用此字段，走规范性断言 Hard Gate

---

## Phase 状态

- **Phase 1（当前）**：init + ingest（含 --batch）✅
- **Phase 2（计划）**：ask + maintain — 当 wiki 有 20+ 页面时实施
