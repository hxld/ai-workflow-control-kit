# Obsidian Vault Schema

> 此文件由 obsidian-wiki init 命令自动生成。LLM 每次操作 vault 前必须读取此文件。

## Vault 信息

- **vault_path**: {{VAULT_PATH}}
- **创建日期**: {{DATE}}
- **领域列表**: work, tech, learning, travel, life

## 目录结构

```
{{VAULT_PATH}}/
├── CLAUDE.md          ← 你正在读的文件
├── index.md           ← 内容目录
├── log.md             ← 操作日志
├── inbox/             ← 全局收件箱（Web Clipper 默认保存位置）
├── assets/            ← 全局附件
├── templates/         ← 页面模板
├── work/              ← 工作（raw/ + wiki/）
├── tech/              ← 技术研究
├── learning/          ← 学习
├── travel/            ← 旅行
└── life/              ← 生活
```

## 核心规则

1. **raw/ 只读** — LLM 不修改 raw/ 下的任何文件
2. **raw/sources/ 子目录由用户管理** — LLM 不创建、不修改、不删除子目录，只动态扫描发现
3. **wiki/ 可写** — LLM 创建、更新、重建
4. **inbox/ → raw/sources/** — ingest 时从 inbox 移动到对应领域
5. **断言可回链** — 所有 wiki 断言通过 frontmatter `sources` 字段追溯到 raw/
6. **log.md append-only** — 只追加
7. **kebab-case 命名** — wiki 文件名禁止空格和中文
8. **单次 ingest 必须完整** — source 页 + concept/entity 页 + index.md + log.md

## 领域说明

| 领域 | 内容 | wiki 子目录 |
|------|------|------------|
| work | 项目文档、会议、需求、接口、发版 | sources/concepts/entities/themes/explorations |
| tech | 技术文章、论文、框架、工具评测 | sources/concepts/entities/themes/explorations |
| learning | 书籍、课程、教程 | sources/concepts/entities/themes/explorations |
| travel | 攻略、行程、目的地 | sources/entities/themes |
| life | 健康、理财、家居 | sources/entities/themes |

## Frontmatter 字段

所有 wiki 页面必须有：
- `type`: source | concept | entity | theme | exploration
- `area`: work | tech | learning | travel | life
- `created`: YYYY-MM-DD
- `updated`: YYYY-MM-DD
- `tags`: [tag1, tag2]

work 领域额外字段：`systems: [从 raw/sources/ 目录路径自动推断]`

## ingest 三种来源

| 来源 | 说明 | 文件移动 |
|------|------|---------|
| inbox/ | 暂存文件 | 移动到 {area}/raw/sources/ |
| 外部路径 | vault 外的任意位置 | 复制到 {area}/raw/sources/（原文件不动） |
| raw/sources/ 已有 | 你已放好的文件 | 不动，直接编译 wiki |

## 操作 Checklist

### ingest 单文件
- [ ] 确定来源文件和目标领域
- [ ] 从 inbox/ 移动到 {area}/raw/sources/（如适用）
- [ ] 按来源类型选择提取模板
- [ ] 写 source 摘要页 → {area}/wiki/sources/
- [ ] 创建/更新 concept 页 → {area}/wiki/concepts/
- [ ] 创建/更新 entity 页 → {area}/wiki/entities/
- [ ] 更新 index.md
- [ ] 追加 log.md

### ingest --batch
- [ ] inbox 模式：运行 scan_inbox.py；raw/sources 模式：扫描未编译文件
- [ ] 输出分类计划让用户确认
- [ ] 每批 3-5 个文件执行 ingest
- [ ] 全部完成后输出汇总
- [ ] 追加汇总到 log.md

## index.md 格式

按领域分 section，每个 wiki 页面一行：`- [[链接|标题]] — 一句话摘要`

## log.md 格式

每条：`## [YYYY-MM-DD] command | title`

## 跨领域链接

使用 Obsidian wikilink：`[[area/wiki/type/page-name]]`
