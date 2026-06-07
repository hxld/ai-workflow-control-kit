# 目录说明 — Vault 中每个目录和文件的作用

## 根目录文件

| 文件 | 作用 |
|------|------|
| `CLAUDE.md` | LLM 的工作规则文件。每次 ingest/ask/maintain 时 LLM 会读它来了解 vault 的结构和规则 |
| `index.md` | 知识库内容目录。列出所有 wiki 页面的链接和一句话摘要，LLM 用它定位相关页面 |
| `log.md` | 操作日志。记录每次 ingest/ask/maintain 的时间、内容、结果，append-only |
| `.gitignore` | git 忽略规则（忽略 .obsidian/、.idea/ 等） |

## 根目录文件夹

| 目录 | 作用 |
|------|------|
| `inbox/` | **全局收件箱**。Web Clipper 保存的网页、你手动放入的待处理文件都放这里。ingest 后文件会被移走 |
| `assets/` | **全局附件**。图片、文件等 Obsidian 附件存放处 |
| `templates/` | **页面模板**。各类 wiki 页面的模板参考（LLM 创建页面时使用） |

## 每个领域目录的内部结构

以 `work/` 为例，其他领域（tech/learning/travel/life）结构相同：

```
work/
├── raw/                        ← 原始资料层（只读，你不写，LLM 也不改）
│   └── sources/                ← 已归档的原始文件
│       ├── order-system/       ← 按业务系统分类（仅 work 有）
│       ├── integration-system/
│       ├── 发版管理/
│       └── 工时评估/
│
└── wiki/                       ← 知识页面层（LLM 写，你读）
    ├── sources/                ← 来源摘要页：每篇 raw 文件的 LLM 提炼摘要
    ├── concepts/               ← 概念页：术语、技术概念、方法论（如 OCR识别、微服务）
    ├── entities/               ← 实体页：具体的人/团队/系统/产品（如 订单系统、支付平台）
    ├── themes/                 ← 主题综述页：跨文档的综合分析（如"Q1项目全景"）
    └── explorations/           ← 探索页：你问问题时 LLM 产生的高价值回答
```

### raw/ vs wiki/ 的区别

| | raw/ | wiki/ |
|--|------|-------|
| **内容** | 你的原始文件（原封不动） | LLM 编译生成的页面 |
| **谁写** | 你（手动放入或 inbox 移入） | LLM（自动生成和维护） |
| **谁读** | LLM（提取信息时读取） | 你（在 Obsidian 中浏览） |
| **可修改** | 不可修改（硬规则） | LLM 可以更新、重建 |
| **命名** | 中文/英文都可以 | 必须是 kebab-case（英文小写+连字符） |

### wiki/ 下 5 个子目录的区别

| 目录 | 存什么 | 举例 |
|------|--------|------|
| `sources/` | 每篇原始文档的**摘要** | `OCR接口文档.md` → `2026-04-10-ocr-api.md` |
| `concepts/` | 文档中提取的**概念/术语** | `ocr-recognition.md`（OCR识别是什么、怎么用的） |
| `entities/` | 文档中出现的**实体** | `order-system.md`（订单系统简介、特点、关联） |
| `themes/` | 跨多篇文档的**综合主题** | `order-architecture.md`（订单系统整体架构综述） |
| `explorations/` | 你问问题后保存的**好回答** | `how-ocr-works-in-documents.md`（OCR在文档处理中如何工作） |

## 文件流转过程

```
1. 你在浏览器看到好文章
   → Web Clipper 保存到 inbox/

2. 你说"wiki ingest --batch"
   → LLM 读文件，判断领域
   → 从 inbox/ 移动到 {area}/raw/sources/（原文件不动）
   → 生成 source 摘要页 → {area}/wiki/sources/
   → 提取概念 → 创建/更新 {area}/wiki/concepts/
   → 提取实体 → 创建/更新 {area}/wiki/entities/
   → 更新 index.md + log.md

3. 你在 Obsidian 里
   → Graph View 看页面之间的连接
   → 读 wiki/ 下的页面
   → 发现错误告诉 LLM 修正
```

## 5 个领域的区别

| 领域 | 放什么 | wiki/ 子目录 |
|------|--------|-------------|
| `work/` | 工作文档、会议、需求、接口、发版 | 全部 5 个（sources/concepts/entities/themes/explorations） |
| `tech/` | 技术文章、论文、框架、工具评测 | 全部 5 个 |
| `learning/` | 书籍笔记、课程笔记、教程 | 全部 5 个 |
| `travel/` | 旅行攻略、行程、目的地 | 3 个（sources/entities/themes） |
| `life/` | 健康、理财、家居 | 3 个（sources/entities/themes） |
