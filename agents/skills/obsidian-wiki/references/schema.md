# Schema — 目录规范 + Frontmatter + 命名约定

## 目录结构

```
<vault-path>/
├── CLAUDE.md                       ← LLM 工作规则（schema）
├── index.md                        ← 全局内容目录
├── log.md                          ← append-only 操作日志
├── assets/                         ← 全局附件（图片等）
├── inbox/                          ← 全局收件箱（Web Clipper + 手动放入）
├── templates/                      ← 页面模板
│
├── work/                           ← 工作文档
│   ├── raw/
│   │   └── sources/                ← 按你自己的方式组织子目录（动态，不写死）
│   └── wiki/
│       ├── sources/                ← 来源摘要页
│       ├── concepts/               ← 概念页
│       ├── entities/               ← 实体页（人/团队/系统/产品）
│       ├── themes/                 ← 主题综述页
│       └── explorations/           ← 问答/探索产生的高价值页面
│
├── tech/                           ← 技术研究
│   ├── raw/sources/
│   └── wiki/ (同上)
│       └── purpose.md             ← 该领域的研究方向和关注主题（可选）
│
├── learning/                       ← 学习（书籍/课程/教程）
│   ├── raw/sources/
│   └── wiki/ (同上)
│
├── travel/                         ← 旅行
│   ├── raw/sources/
│   └── wiki/
│       ├── sources/
│       ├── entities/               ← 城市/景点/餐厅
│       └── themes/                 ← 旅行计划/攻略
│
├── life/                           ← 生活（健康/理财/家居）
│   ├── raw/sources/
│   └── wiki/
│       ├── sources/
│       ├── entities/
│       └── themes/
│
└── (未来新领域直接加顶层目录)
```

## 核心规则

1. **raw/ = 权威层（只读）**：LLM 不创建、不修改、不删除 raw/ 下的任何文件（ingest 时从 inbox/ 移入除外）
2. **wiki/ = 派生层（LLM 写入）**：可创建、更新、重建
3. **inbox/ = 临时暂存**：文件到此为止，ingest 后移到对应 raw/sources/
4. **每个领域独立**：但通过 wikilink 跨领域连接
5. **raw/sources/ 子目录由用户管理**：LLM 不创建、不修改、不删除 raw/sources/ 下的子目录结构。用户可以按公司/业务/系统等任意方式组织，LLM 在 ingest 时动态扫描发现实际目录

## 领域定义

| 领域 | 目录名 | 内容范围 |
|------|--------|---------|
| 工作 | work | 项目文档、会议记录、需求、接口文档、发版记录、工时评估 |
| 技术 | tech | 技术文章、论文、框架文档、架构模式、工具评测 |
| 学习 | learning | 书籍笔记、课程笔记、教程、学习计划 |
| 旅行 | travel | 旅行攻略、行程、目的地信息、经验总结 |
| 生活 | life | 健康、理财、家居、个人成长 |

新增领域：直接在 vault 根目录创建新的一级目录，内部结构参照 `raw/sources/` + `wiki/`。

## raw/sources/ 目录组织

raw/sources/ 下的子目录**完全由你决定**，不写死。你可以：
- 按公司分：`hz/`、`tb/`
- 按业务分：`orders/`、`payments/`、`others/`
- 按系统分：`order-system/`、`integration-system/`
- 任意组合：`company-a/orders/`、`company-a/integrations/`
- 随时改名、增删子目录，不影响 Skill 工作

LLM 在 ingest 时会：
1. 扫描 `{area}/raw/sources/` 发现实际的目录结构
2. 在 source 摘要页的 `source_path` 字段记录实际路径
3. 在 entity 页的 `systems` 字段记录来源所属的系统/项目（从目录路径推断）

## Frontmatter 规范

### 通用字段（所有 wiki 页面必须有）

```yaml
---
type: source|concept|entity|theme|exploration
area: work|tech|learning|travel|life
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [tag1, tag2]
---
```

### 各类型额外字段

**source 摘要页：**
```yaml
source_type: technical|meeting|requirement|paper|book|travel|article
source_path: "{area}/raw/sources/实际路径/xxx.md"
date_published: YYYY-MM-DD（如有）
---
```

**concept 概念页：**
```yaml
aliases: [别名1, 别名2]
sources: [source-a, source-b]
related: [[other-concept]]
confidence: extracted|inferred|unverified
---
```

**entity 实体页：**
```yaml
entity_type: person|team|system|product|organization|place
systems: [从raw/sources/目录路径自动推断]   # 仅 work 领域
aliases: [别名1, 别名2]
sources: [source-a]
confidence: extracted|inferred|unverified
---
```

### confidence 置信度定义

| 值 | 含义 | 赋值条件 |
|------|------|---------|
| `extracted` | 信息直接来自原始来源，原文可找到 | 原文中有明确表述 |
| `inferred` | 从多处来源推断得出，原文无直接表述 | 综合 ≥2 个 source 的信息推导 |
| `unverified` | 缺少原始来源佐证，来自 LLM 背景知识或单一不确定来源 | 无原文证据或来源模糊 |

**赋值规则：**
- 新建 concept/entity 页时，根据信息来源确定置信度
- 跨 ≥2 个 source 且原文有明确表述 → `extracted`
- 需要推理才能得出、原文未直接说明 → `inferred`
- 仅来自 LLM 知识或来源不明确 → `unverified`
- 规范性断言（完成标准/验收标准等）不使用此字段，走规范性断言 Hard Gate

**theme 主题综述页：**
```yaml
sources: [source-a, source-b, source-c]
related_concepts: [[concept-a], [concept-b]]
---
```

**exploration 探索页：**
```yaml
question: "原始问题"
sources: [source-a, wiki-page-b]
---
```

## 文件命名约定

| 规则 | 示例 |
|------|------|
| kebab-case | `ocr-recognition.md` 而非 `OCR识别.md` |
| source 摘要加日期前缀 | `2026-04-09-ocr-api-doc.md` |
| 无空格无中文 | `order-system.md` 而非 `订单 系统.md` |
| raw/sources/ 子目录随意 | `raw/sources/company-a/orders/` 或 `raw/sources/order-system/` 都行 |

## index.md 格式

```markdown
# 知识库索引

> 最后更新：YYYY-MM-DD | 总页面数：N

## work
### sources
- [[work/wiki/sources/2026-04-09-ocr-api-doc|OCR接口文档]] — 文档处理系统OCR接口定义与调用规范
### concepts
- [[work/wiki/concepts/ocr-recognition|OCR识别]] — 光学字符识别在文档处理中的应用
### entities
- [[work/wiki/entities/order-system|订单系统]] — 核心订单业务系统

## tech
...（同上格式）
```

## log.md 格式

```markdown
# 操作日志

## [2026-04-09] init | 知识库初始化
- 创建 vault 目录结构（5 个领域）
- 初始化 git repo

## [2026-04-09] ingest | OCR接口文档.md
- 领域：work | 类型：technical | 路径：work/raw/sources/company-a/orders/
- 新增：1 source, 2 concepts, 1 entity
- 更新：index.md

## [2026-04-09] ingest-batch | 5 个文件
- work: 3 files (2 technical, 1 meeting)
- tech: 1 file (paper)
- travel: 1 file (travel)
- 新增：5 sources, 8 concepts, 3 entities
```

## 规模策略

| 阶段 | 页面数 | index 策略 |
|------|--------|-----------|
| 初期 | <200 页 | 单一 index.md，按领域分 section |
| 中期 | 200-500 页 | 根 index.md + 每个领域一个 `_index.md` |
| 后期 | >500 页 | Dataview 动态查询为主，index.md 只做领域概览 |

maintain 命令（Phase 2）会在巡检时检测当前规模并建议是否需要升级索引策略。
