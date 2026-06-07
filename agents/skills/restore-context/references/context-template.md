# Context Loading Template

三层加载的期望输出模板。

## Layer 1: Project Context

```
## 项目上下文已加载
- **项目：** {项目名}
- **技术栈：** {语言}/{框架}/{数据库}
- **目录结构：** {关键目录}
- **最近活动：** {git log 最后3条}
```

## Layer 2: Session History

```
## 会话历史已加载
- **会话数：** {N} 个历史会话
- **最近工作：** {最后一次工作的摘要}
- **未完成项：** {tasks.md 中未勾选项}
- **上次暂停原因：** {stop_reason}
```

## Layer 3: Knowledge Base

```
## 知识库已加载
- **错误教训：** {N} 条 (🟡{n} 警告 / 🔴{n} 严重)
- **最佳实践：** {N} 条
- **相关风险：** {与当前任务相关的教训列表}
- **Instincts：** {N} 条活跃 instinct
```

## Combined Output Example

```
## 上下文已恢复
**项目：** example-service | **技术栈：** Java 17 / Spring Boot 3 / MySQL
**最近工作：** 完成订单状态机重构 (2026-04-07)
**未完成：** 订单导出功能 (tasks.md #5 未完成)
**知识库：** 12条教训 | 3条相关风险: [JPA N+1, 事务边界, 幂等性]
**上次暂停：** DONE_WITH_CONCERNS (导出CSV编码问题)
**推荐下一步：** 继续完成导出功能 → 修复CSV编码
```
