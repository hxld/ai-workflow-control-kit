# yuque-to-markdown

## 目的
- 将语雀文档转换为 Markdown
- 保留图片链接
- 避免表格表头错位、比较表达式丢失、零宽字符残留

## 日常使用
- 正常转换：按 `SKILL.md` 流程执行
- 改过 `scripts/convert.js` 后：必须先跑回归测试

## 一键回归测试

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\run-regression.ps1"
```

或直接运行 Node 脚本：

```bash
node .\scripts\test-convert.js
```

## 当前回归覆盖
- 合并表头表格转四列表头
- 五列表头假象归一化
- 正文中的 `<`、`>`、`<=` 比较表达式保留
- 零宽字符不会残留到输出

## 什么时候必须跑
- 修改了 `scripts/convert.js`
- 修改了表格转换逻辑
- 修改了标签清洗逻辑
- 修改了正文抽取逻辑

## Hard Gate
- 如果改过 `scripts/convert.js` 却没有跑回归测试，不得宣称“脚本已修复”
- 如果回归测试未通过，不得宣称“以后不会再犯”
