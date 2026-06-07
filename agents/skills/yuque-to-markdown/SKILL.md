---
name: yuque-to-markdown
description: "Convert Yuque online documents to structured Markdown with CDN image links. Use when user says 语雀转MD, 转Markdown, 保存为markdown, 把这个链接转MD, yuque to markdown, or when URL contains yuque.com and user wants to save/convert"
allowed-tools: Bash,Read,Write
---

# Yuque to Markdown

将语雀在线文档转换为结构清晰的 Markdown 文件，图片直接使用 CDN 在线链接。

## 触发条件

- "语雀转MD" / "转Markdown" / "把这个链接转MD"
- URL 包含 `yuque.com` 且用户要求保存/转换

## 何时不使用

- 普通网页文章，使用 `article-to-obsidian`。
- 视频链接，使用 `video-to-obsidian`。
- 用户只想阅读摘要、不需要保存 Markdown。

## 前置条件

- Chrome 已开启远程调试（`chrome://inspect/#remote-debugging`）
- 语雀页面已在 Chrome 中打开并登录
- Node.js 22+ 可用

## 执行前预检查

在修改脚本、重新生成 Markdown 或批量转换多份文档前，必须先执行一次预检查：

1. 读取项目 `.memory/MEMORY.md`
2. 读取项目 `.memory/error-lessons.md`
3. 特别检查是否已有与以下问题相关的记录：
   - 语雀表格表头错位
   - `colspan/rowspan` 导致的 Markdown 列语义丢失
   - 转换后需要人工修复的固定模式

若命中了相关错误记忆，必须先按记忆中的预防措施调整脚本或校验步骤，再运行转换。

## References（按需加载）

| 文件 | 内容 | 加载条件 |
|------|------|----------|
| `references/html-structure.md` | 语雀 HTML 元素对照表 + 关键注意事项 | 需要理解 HTML 结构时 |

## 预写脚本

| 脚本 | 功能 | 用法 |
|------|------|------|
| `scripts/pre_clean.js` | 预清理（移除导航/SVG/OCR） | `node scripts/pre_clean.js --input xxx --output xxx [--assets-dir xxx]` |
| `scripts/convert.js` | 核心转换（表格→标题→图片→列表→段落） | `node scripts/convert.js --input xxx --output xxx --title "标题"` |
| `scripts/test-convert.js` | 最小回归测试（表格表头 + 比较表达式） | `node scripts/test-convert.js` |
| `scripts/run-regression.ps1` | Windows 一键回归测试入口 | `powershell -ExecutionPolicy Bypass -File ".\\scripts\\run-regression.ps1"` |

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：`交付 Hard Gate` 未通过时，不得宣称“已转换完成”
- **PARTIAL**：只表示转换已完成初步结果，但完整性未完全证明
- **完成标准（DoD）**：统一表示“脚本执行 + 完整性校验 + 交付状态说明”都完成
- **验证范围**：在本技能中指转换完整性校验覆盖到哪些章节/结构

---

## 执行步骤

### Step 1: 定位目标标签页

```bash
node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs list
```

找到目标语雀页面的 targetId 前缀（如 `64740BBC`）。

### Step 2: 修复懒加载图片（关键！）

语雀大部分图片使用懒加载，`<img>` 没有 `src`（`class="ne-image-hide"`）。URL 在 `ne-card._neRef.attrs.value.src` 中。

```bash
node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <target> "var cards=document.querySelectorAll('.yuque-doc-content ne-card[data-card-name=image]');var fixed=0;for(var i=0;i<cards.length;i++){var ref=cards[i]._neRef;if(ref&&ref.attrs&&ref.attrs.value&&ref.attrs.value.src){var img=cards[i].querySelector('img');if(img&&!img.src){img.setAttribute('src',ref.attrs.value.src);img.classList.remove('ne-image-hide');fixed++}}}fixed+' of '+cards.length+' fixed'"
```

验证：
```bash
node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <target> "Array.from(document.querySelectorAll('.yuque-doc-content img')).map(function(i){return i.src||'[EMPTY]'}).join('\n')"
```

### Step 3: 提取 HTML + 文档标题

```bash
# 提取 HTML 内容
node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs html <target> ".yuque-doc-content" > "./yuque_content.html"

# 提取文档标题（在 .yuque-doc-content 之外，需单独获取）
node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <target> "document.title"
```

**记录文档标题，作为 `--title` 参数传给转换脚本。**

### Step 4: 预清理 HTML

```bash
node ~/.agents/skills/yuque-to-markdown/scripts/pre_clean.js --input ./yuque_content.html --output ./yuque_cleaned.html --assets-dir ./OUTPUT_DIR/文档名.assets
```

### Step 5: 转换为 Markdown

```bash
node ~/.agents/skills/yuque-to-markdown/scripts/convert.js --input ./yuque_cleaned.html --output ./OUTPUT_DIR/文档名.md --title "Step3获取的标题"
```

### Step 6: 转换完整性校验（必须）

完成转换后，至少做以下检查：

1. **标题校验**：Markdown 首个 H1 与 Step 3 获取的标题一致
2. **结构校验**：提取源页标题序列/目录，与 Markdown 标题序列逐项对照，确认主要章节未丢失
3. **关键章节校验**：若文档包含“验收 / 上线 / 发布 / 完成标准 / 注意事项 / 风险”等关键词，对应内容必须在 Markdown 中可找到
4. **表格语义校验**：若源页存在“字段名/取值/备注”且第一列表头在语雀中为合并单元格，Markdown 必须保留四列语义，例如 `字段中文名 | 字段标识 | 取值 | 备注`
5. **失败处理**：若任一检查不通过，结论为“转换未完成，需人工复核或补救”，不得直接交付
6. **无法自动校验时降级**：若源页无稳定目录/标题树，或无法确认章节映射，状态必须标记为 `PARTIAL`，并要求人工抽检
7. **校验结果必须回传**：至少回传 `标题校验结果 / 结构校验结果 / 表格语义校验结果 / 关键章节校验结果 / 最终状态`

### Step 7: 清理临时文件

```bash
rm -f ./yuque_content.html ./yuque_cleaned.html
```

---

## 关键注意事项

1. **懒加载图片必须先修复** — URL 在 `ne-card._neRef` 中，必须 CDP eval 注入后再提取 HTML
2. **文档标题需单独提取** — 标题在 `.yuque-doc-content` 之外，用 `document.title` 获取
3. **语雀需要登录** — 必须通过已登录的 Chrome 浏览器提取
4. **图片用 CDN 链接** — `cdn.nlark.com`，直接使用在线链接，无需下载
5. **预清理防止超时** — 画板 SVG 可达 183KB，OCR 文字层上百个，必须先清理再转换
6. **转换成功不等于信息完整** — 必须做标题、章节、表格语义、关键内容完整性校验后才能交付
7. **语雀合并表头需要特殊校验** — Markdown 不支持表头合并；若语雀原表使用 `colspan/rowspan`，必须确认转换结果没有把“字段名”误压成单列

## 回归测试

当你修改过 `scripts/convert.js` 后，必须至少跑一次：

```bash
node scripts/test-convert.js
```

Windows 下也可直接运行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\run-regression.ps1"
```

该测试当前覆盖：
- 合并表头表格转换为四列表头
- 五列表头假象归一化为四列语义
- 正文中 `<`、`>`、`<=` 比较表达式不被误删
- 零宽字符不会残留到输出 Markdown
- 未跑该测试时，不得宣称“脚本已修复”或“以后不会再犯”

---

## 交付 Hard Gate

只有同时满足以下条件，才能宣称“已转换完成”：

- 已完成懒加载图片修复
- 已提取标题并用于转换
- 已完成 Step 6 的完整性校验
- 已完成表格语义校验（如文档含表格）
- 若本次修改过 `scripts/convert.js`，已执行 `node scripts/test-convert.js` 且通过
- 对关键章节缺失风险给出明确结论：`通过 / 需人工复核`
- 若无法完成结构等价校验，已明确标记 `PARTIAL`，且未宣称“完整转换”

默认规则：

- 只要没有完成可复核的结构等价校验，就默认是 `PARTIAL`
- `PARTIAL` 只能表示“初步转换完成，完整性未完全证明”
- 只要改过 `scripts/convert.js` 却没跑回归测试，就默认不能宣称“脚本修复完成”

如果只能证明“脚本跑完了”，不能证明“内容完整保留”，则只能报告**已完成初步转换**，不能报告**转换完成**。
