# 语雀 HTML 结构关键知识

语雀使用自定义 HTML 元素（非标准标签），必须按正确顺序处理。

## 元素对照表

| 语雀元素 | 说明 | Markdown 对应 | 处理顺序 |
|----------|------|---------------|----------|
| `<div class="ne-viewer-header">` | 导航栏（"返回文档"按钮） | 必须删除 | 预处理（最先） |
| `<ne-card data-card-name="board">` | 流程图画板（SVG） | 提取SVG保存为本地文件 | 预处理 |
| `<div class="ne-ui-image-ocr-text">` | 图片 OCR 文字层 | 必须删除 | 预处理 |
| `<svg>` | UI 图标/画板内容 | 删除 | 预处理 |
| `<table>` | 表格（rowspan/colspan/多段落单元格） | Markdown 表格 | 1（在段落之前） |
| `<ne-h1>` ~ `<ne-h6>` | 标题 | `##` ~ `######` | 2 |
| `<img>` 在 `<ne-card>` 内 | 图片（CDN） | `![alt](CDN_URL)` | 3 |
| `<ne-uli>` | 无序列表项 | `- ` 列表项 | 4 |
| `<ne-uli-i>` | 列表符号 | 忽略 | 4 |
| `<ne-uli-c>` | 列表项内容 | 提取文本 | 4 |
| `<ne-oli>` | 有序列表项 | `- ` 列表项 | 4 |
| `<ne-oli-i>` | 有序列表编号 | 忽略 | 4 |
| `<ne-oli-c>` | 有序列表项内容 | 提取文本 | 4 |
| `<ne-p>` | 段落 | 文本 | 5（在表格之后） |
| `<ne-text ne-bold="true">` | 加粗 | `**text**` | 辅助函数 |
| `<ne-text>` | 普通文本 | 直接输出 | 辅助函数 |

## 关键注意事项

1. **`<ne-uli>` 和 `<ne-oli>` 都是与 `<ne-p>` 平级的独立元素**，不是嵌套在 `<ne-p>` 内部
2. **`<ne-oli>` 有序列表之前容易被遗漏**，语雀编号项都在 `<ne-oli>` 中
3. **流程图是 `<ne-card data-card-name="board">` 内的 SVG 画板**，可提取保存为 `.svg`
4. **表格必须先于段落处理**，表格单元格内含 `<ne-p>` 元素
5. **表格单元格内多段落用 `%%BR%%` 占位符连接**，最后替换为 `<br>`
6. **`<ne-h1>` 内文本在 `<ne-heading-content>` 子元素中**，而非直接从整体提取
7. **懒加载图片**：大部分 `<img>` 没有 `src` 属性（`class="ne-image-hide"`），URL 在 `ne-card._neRef.attrs.value.src` 中
8. **OCR 文字层** `<div class="ne-ui-image-ocr-text">` 必须删除
9. **图片用 CDN 链接**（`cdn.nlark.com`），无需下载
10. **UI 图标过滤**：`alipayobjects.com` 域名图片是 UI 图标

## HTML 结构示例

```html
<ne-p>普通段落文本</ne-p>
<ne-uli>
  <ne-uli-i><span>●</span></ne-uli-i>
  <ne-uli-c>
    <ne-text>列表项内容</ne-text>
  </ne-uli-c>
</ne-uli>
<ne-oli>
  <ne-oli-i><span>1</span></ne-oli-i>
  <ne-oli-c>
    <ne-text>编号项内容</ne-text>
  </ne-oli-c>
</ne-oli>
```
