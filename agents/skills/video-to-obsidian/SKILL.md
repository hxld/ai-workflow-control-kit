---
name: video-to-obsidian
description: "Use when the user provides a YouTube or Bilibili URL and asks to summarize, save, transcribe, convert to Markdown, or create an Obsidian video note"
allowed-tools: Bash,Read,Write
---

# Video → Obsidian Note

## Overview

Get transcript from video subtitles (preferred), then write a structured Obsidian note directly via Write tool.

**Supported platforms:** YouTube, Bilibili

**Output directory:**
- YouTube → `AI/YouTube/`
- Bilibili → `AI/Bilibili/`

---

## 何时使用

- 用户提供 YouTube、Bilibili 或 b23.tv 链接。
- 用户要求总结、转写、保存为 Markdown 或生成 Obsidian 笔记。

## 何时不使用

- 普通网页文章，使用 `article-to-obsidian`。
- 语雀文档，使用 `yuque-to-markdown`。
- 没有字幕且用户不允许 ASR fallback。

---

## Prerequisites

- `yt-dlp` — subtitle download & metadata extraction (supports YouTube & Bilibili)
- `python3` — subtitle parsing script execution
- `ffmpeg` — audio conversion (ASR fallback only, optional)
- Bilibili cookies (optional) — for member-only or age-restricted videos, use `--cookies-from-browser chrome`

> **Note:** No `obsidian` CLI needed. Notes are written directly via Write tool. Obsidian auto-detects file changes.

---

## Step-by-Step Workflow

### 0. Detect platform

```python
import re
url = "URL"
if re.match(r'https?://(www\.)?(bilibili\.com|b23\.tv)', url):
    platform = "bilibili"
    output_dir = "AI/Bilibili"
elif re.match(r'https?://(www\.)?(youtube\.com|youtu\.be)', url):
    platform = "youtube"
    output_dir = "AI/YouTube"
else:
    print("Unsupported platform")
    exit(1)
```

> Use `platform` and `output_dir` throughout the workflow.

### 1. Get video metadata + detect subtitles

```bash
yt-dlp --dump-json --skip-download "URL" 2>&1 | python3 -c "
import json, sys
for line in sys.stdin.read().strip().split('\n'):
    try:
        d = json.loads(line)
        print('TITLE:', d.get('title',''))
        print('CHANNEL:', d.get('channel','') or d.get('uploader',''))
        print('UPLOAD_DATE:', d.get('upload_date',''))
        print('DURATION:', d.get('duration_string',''))
        print('VIEW_COUNT:', d.get('view_count',''))
        print('DESCRIPTION:', d.get('description','')[:500])
        auto_subs = d.get('automatic_captions', {})
        manual_subs = d.get('subtitles', {})
        if auto_subs:
            langs = list(auto_subs.keys())
            print('AUTO_SUBS_AVAILABLE:', ','.join(langs))
        if manual_subs:
            langs = list(manual_subs.keys())
            print('MANUAL_SUBS_AVAILABLE:', ','.join(langs))
        if not auto_subs and not manual_subs:
            print('NO_SUBS_AVAILABLE')
        break
    except: continue
"
```

> **Bilibili note:** If download fails (member-only / age-restricted), retry with `--cookies-from-browser chrome`.

**Subtitle decision logic:**

| Condition | Action |
|-----------|--------|
| `AUTO_SUBS_AVAILABLE` contains `en` or `zh-Hans` or `zh` | Download subtitle → go to Step 2A |
| `MANUAL_SUBS_AVAILABLE` contains `en` or `zh-Hans` or `zh` | Download subtitle → go to Step 2A |
| Any auto/manual subs available | Download the first available language → go to Step 2A |
| `NO_SUBS_AVAILABLE` | **Stop and inform user** — no subtitles available, transcription not possible without ASR setup |

> **Priority:** Prefer `zh-Hans` > `zh` > `en` > first available language.

### 2A. Download subtitle (preferred path)

```bash
# Use best subtitle format (srv3/vtt/srt), yt-dlp auto-selects best
yt-dlp --write-auto-sub --sub-lang LANG --sub-format srv3/vtt/srt \
  --skip-download -o "./.yt_sub_%(id)s" "URL" 2>&1 | tail -3
```

Then parse the subtitle file to extract clean text with **logical paragraph segmentation** (based on timestamp gaps > 3s):

```python
import re

def _parse_timestamp(ts_str):
    ts_str = ts_str.strip().replace(',', '.')
    parts = ts_str.split(':')
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    return 0.0

def _segment_by_gaps(cues, gap_threshold=3.0):
    if not cues:
        return ""
    paragraphs = []
    current_lines = [cues[0][1]]
    for i in range(1, len(cues)):
        gap = cues[i][0] - cues[i-1][0]
        if gap > gap_threshold:
            paragraphs.append(" ".join(current_lines))
            current_lines = [cues[i][1]]
        else:
            current_lines.append(cues[i][1])
    if current_lines:
        paragraphs.append(" ".join(current_lines))
    return "\n\n".join(paragraphs)

def parse_srt(srt_path):
    with open(srt_path, 'r', encoding='utf-8') as f:
        content = f.read()
    blocks = re.split(r'\n\n+', content.strip())
    cues = []
    for block in blocks:
        parts = block.strip().split('\n')
        if len(parts) < 2:
            continue
        ts_line = None
        text_start = 0
        for i, line in enumerate(parts):
            if '-->' in line:
                ts_line = line
                text_start = i + 1
                break
        if ts_line is None:
            continue
        end_ts = ts_line.split('-->')[1].strip()
        end_time = _parse_timestamp(end_ts)
        text_lines = [l.strip() for l in parts[text_start:] if l.strip()]
        if text_lines:
            cues.append((end_time, " ".join(text_lines)))
    return _segment_by_gaps(cues)

def parse_vtt(vtt_path):
    with open(vtt_path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = re.sub(r'^WEBVTT.*\n\n', '', content, flags=re.DOTALL)
    blocks = re.split(r'\n\n+', content.strip())
    cues = []
    prev_text = None
    for block in blocks:
        parts = block.strip().split('\n')
        ts_line = None
        text_start = 0
        for i, line in enumerate(parts):
            if '-->' in line:
                ts_line = line
                text_start = i + 1
                break
        if ts_line is None:
            continue
        end_ts = ts_line.split('-->')[1].strip()
        end_time = _parse_timestamp(end_ts)
        text_lines = [l.strip() for l in parts[text_start:] if l.strip()]
        text = " ".join(text_lines)
        if text == prev_text:
            continue
        if text:
            cues.append((end_time, text))
            prev_text = text
    return _segment_by_gaps(cues)

import glob
sub_files = glob.glob('./.yt_sub_VIDEOID.*')
transcript = ''
for f in sub_files:
    if f.endswith('.vtt'):
        transcript = parse_vtt(f)
        break
    elif f.endswith('.srt'):
        transcript = parse_srt(f)
        break
```

### 3. Create Obsidian note

**Note structure template:**

```markdown
---
title: <video title>
tags: [<inferred topics>]
source: <original url>
author: <channel/uploader name>
date: <YYYY-MM-DD>
duration: <HH:MM>
type: 视频笔记
platform: <youtube|bilibili>
transcript_source: <subtitle>
---

# <title>

> [!info] 视频信息
> author / duration / date / [link](URL)

## 核心观点
[1-3 sentence summary]

## [Section headers inferred from transcript content]
[Structured summary with callouts, tables, lists]

## 个人思考
- [ ] Action items

## 原始转录

> [!note]-
> 第一段转录内容……
>
> 第二段转录内容……
>
> 第三段转录内容……
```

> **Transcript storage rule:** If transcript exceeds **20000 characters**, do NOT save it — just leave a note like `> 转录内容过长（N 字符），未保存。可从 [原视频](URL) 获取。`. Under 20000 chars, embed in a collapsible callout with **logical paragraph breaks** (each paragraph separated by `>` lines).
>
> **Transcript segmentation:** 转录必须按照**内容逻辑**分段，而非按照时间或字数机械切割。
> - 字幕路径：时间戳间隔分段（>3s）是初步分段。写入笔记前需要检查，确保段落边界与话题转换对齐，必要时合并过短的段落或拆分过长的话题混合段。
> - **分段粒度**：一般 20-30 分钟视频分成 15-25 段。每段应是一个完整的论点、叙述单元或话题。

**Write strategy:** Use Write tool to write `<output_dir>/<title>.md`. File name: replace `/` with `_`.

### 4. Cleanup

```python
import os, glob
video_id = "VIDEOID"
for f in glob.glob(f'.yt_sub_{video_id}*'):
    os.remove(f)
```

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `yt-dlp: command not found` | Not installed | `winget install yt-dlp.yt-dlp` |
| Subtitle parse empty | Bad format | Try `--sub-format` with different value (srv3 > vtt > srt) |
| Bilibili download fails | Member-only / age-restricted | Retry with `--cookies-from-browser chrome` |
| NO_SUBS_AVAILABLE | No subtitles on video | Inform user, suggest checking video page manually |

---

## Quick Reference

```
URL → detect platform (YouTube / Bilibili)
    → yt-dlp (metadata + subtitle detection)
        ├─ Has subtitles → download & parse subtitle → transcript
        └─ No subtitles  → inform user (ASR not configured)
    → summarize → write to <output_dir>/<title>.md → cleanup
```
