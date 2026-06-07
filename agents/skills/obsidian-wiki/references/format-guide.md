# 非 Markdown 文件处理策略

## 策略：原文件放入 vault（方案 A）

非 md/pdf 文件（xlsx/ppt/doc/docx 等）**直接放入 vault 的 raw/sources/ 或 assets/ 目录**，不转换为 markdown。

**原因**：Obsidian 原生不支持渲染这些格式，转换会丢失格式（表格、布局等），得不偿失。

## 各格式处理方式

| 格式 | 处理方式 | Obsidian 中 |
|------|---------|-------------|
| .xlsx | 直接放入 raw/sources/ | 资源管理器可见，点击可用 Excel 打开 |
| .pptx | 直接放入 raw/sources/ | 资源管理器可见，点击可用 PowerPoint 打开 |
| .docx | 直接放入 raw/sources/ 或转为 md 后 ingest | 取决于是否需要全文搜索 |
| .doc | 同 docx | 同上 |
| .pdf | 直接放入 raw/sources/ | Obsidian 原生支持预览 |
| 图片 | 直接放入 raw/sources/ 或 assets/ | Obsidian 原生渲染 |

## 特殊情况：需要全文搜索时

如果某个 xlsx/ppt 的**内容**需要在 wiki 中可搜索，可以：
1. 原文件照常放入 vault（保持格式完整）
2. 手动或用工具提取关键内容写入一个 md 文件
3. 对 md 文件执行 ingest，frontmatter 中标注原文件链接

### 可选转换工具（按需使用）

```powershell
# docx/pptx → md（pandoc）
winget install pandoc
pandoc "<输入文件>.docx" -t markdown -o "<vault>/inbox/<输出文件>.md"

# xlsx → md 表格（Python）
pip install pandas tabulate openpyxl
python -c "
import pandas as pd, sys
df = pd.read_excel(sys.argv[1])
print(df.to_markdown(index=False))
" "<输入文件>.xlsx" > "<vault>/inbox/<输出文件>.md"
```

## 注意事项

1. **原文件保持不动**：从外部复制到 vault 时，原文件不变
2. **vault 内用 wikilink 引用**：`![[raw/sources/work/xxx.xlsx]]` 可内嵌链接
3. **大文件考虑**：单个附件 >50MB 时建议用外部链接而非直接放入 vault
4. **功能性文件**（如技能模板）放在 `vault/templates/`，不是 raw/sources/
