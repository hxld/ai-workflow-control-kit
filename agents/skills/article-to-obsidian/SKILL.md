---
name: article-to-obsidian
description: "Use when the user provides a public article URL and asks to save, ingest, summarize, convert to Markdown, create an Obsidian note, or archive web content"
allowed-tools: Bash,Read,Write
---

# Article to Obsidian Note

Extract clean content from web articles using Defuddle CLI (preferred) or `web_reader` MCP tool (fallback), then write a structured Obsidian note with images embedded via CDN links.

**Supported platforms:** Any public web article (blog posts, news, technical articles, etc.)

**Output directory:** `AI/Articles/`

---

## 何时使用

- 用户提供公开网页文章 URL。
- 用户要求保存、收录、总结、转换 Markdown 或生成 Obsidian 笔记。

## 何时不使用

- 视频链接，使用 `video-to-obsidian`。
- 语雀链接，使用 `yuque-to-markdown`。
- 私有网页且当前环境没有访问权限。

---

## Prerequisites

- `defuddle` CLI — preferred method for extracting clean content (`npm install -g defuddle`)
- `web_reader` MCP tool — fallback when defuddle fails
- Obsidian vault at working directory — notes written directly via Write tool

---

## Step-by-Step Workflow

### 0. Parse URL and detect source

```
URL = <provided URL>
parsed = parse URL
domain = parsed.netloc.removePrefix('www.')

known_sources = {
  'medium.com': 'Medium',
  'dev.to': 'DEV Community',
  'zhuanlan.zhihu.com': '知乎专栏',
  'www.zhihu.com': '知乎',
  'mp.weixin.qq.com': '微信公众号',
  'juejin.cn': '掘金',
  'segmentfault.com': '思否',
  'sspai.com': '少数派',
  '36kr.com': '36氪',
  'arxiv.org': 'arXiv',
  'blog.csdn.net': 'CSDN',
}

platform = known_sources.get(domain, domain)
output_dir = "AI/Articles"
title_slug = sanitize(article_title, replace '/' with '_')
```

> Use `platform`, `output_dir`, and `title_slug` throughout the workflow.

### 1. Extract article content

**Preferred: Defuddle CLI**

```bash
defuddle parse "URL" --md -o ./.article_content.md 2>&1
defuddle parse "URL" -p title 2>&1
defuddle parse "URL" -p author 2>&1
defuddle parse "URL" -p date 2>&1
defuddle parse "URL" -p description 2>&1
```

**Fallback: web_reader MCP tool**

```
URL: <article URL>
return_format: markdown
retain_images: true
```

### 2. Parse content and metadata

Read extracted content and identify:

- **title**: from defuddle `-p title` or `<h1>` in content
- **author**: from defuddle `-p author` or byline in content
- **date**: from defuddle `-p date` or date pattern `(\d{4}[-/]\d{2}[-/]\d{2})` in first 2000 chars
- **description**: from defuddle `-p description` or first paragraph

Estimate reading time:
- Chinese text: ~400 chars/min
- English text: ~200 words/min

### 3. Process images in content

After extracting content, scan the markdown for all image references and ensure they are properly embedded:

```
Pattern: ![alt](IMAGE_URL)
```

Rules:
- **Keep CDN links as-is** — Obsidian renders external images directly
- **Skip** data URIs or empty URLs
- **Clean up alt text** — replace generic alt like `Image 1`, `Image 2` with descriptive alt text based on surrounding content context
- **Place images in summary sections** — when writing section summaries, embed relevant images inline at appropriate positions using the original CDN URL: `![描述](IMAGE_URL)`

### 4. Create Obsidian note

**Note structure template:**

```markdown
---
title: <article title>
tags: [<inferred topics>]
source: <original url>
author: <author name>
date: <YYYY-MM-DD>
reading_time: <N min>
type: 文章笔记
platform: <platform>
---

# <title>

> [!info] 文章信息
> author / reading time / date / [link](URL)

## 核心观点
[1-3 sentence summary of the article's main argument or thesis]

## [Section headers inferred from article content]
[Structured summary with callouts, tables, lists]
**Images are embedded inline at appropriate positions using original CDN links.**
e.g. `![工作流架构图](https://cdn.example.com/workflow.png)`

## 个人思考
- [ ] Action items

## 原文摘录

> [!note]-
> 摘录内容段落一……
>
> 摘录内容段落二……
>
> 摘录内容段落三……
```

**Content storage rule:** If original content exceeds **20000 characters**, do NOT save it — just leave a note like `> 原文内容过长（N 字符），未保存。可从 [原文链接](URL) 获取。`. Under 20000 chars, embed in a collapsible callout with **logical paragraph breaks** (each paragraph separated by `>` lines).

**Content segmentation:** 原文摘录必须按照**内容逻辑**分段，而非机械切割。
- 通读全文，在话题转换处断段
- 跨段落边界的句子必须合并为完整段落
- 每段 1000-2000 字，应是一个完整的论点或叙述单元
- 过长且价值较低的部分适当省略，用 `[...省略...]` 标注

**Write strategy:** Use Write tool to write `<output_dir>/<title_slug>.md`. Obsidian auto-detects file changes.

### 5. Cleanup

```bash
rm -f ./.article_content.md ./.article_meta.json
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `defuddle: command not found` | Not installed | `npm install -g defuddle` |
| Empty content extracted | Paywall / JS-rendered | Try `web_reader` MCP tool fallback |
| Content is HTML, not markdown | Defuddle parsing failed | Use `web_reader` with `return_format: markdown` |
| Image not rendering in Obsidian | CDN blocked / expired | Replace with working URL or remove |
| Title extraction fails | Unusual page structure | Manually extract from `<h1>` or `<title>` tag |

---

## Quick Reference

```
URL → detect platform (domain-based categorization)
    → defuddle parse URL --md (preferred)
        ├─ Success → read content + metadata
        └─ Fail → web_reader MCP tool (fallback)
    → process images (keep CDN links, clean alt text)
    → infer reading time + metadata
    → summarize with inline images → write to AI/Articles/{title_slug}.md → cleanup
```
