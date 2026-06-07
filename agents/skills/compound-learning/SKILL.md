---
name: compound-learning
description: "Use when user says 记住这个错误, 知识沉淀, compound learning, 记录错误, 总结错误, 下次不要再犯, or when recurring mistakes or reusable patterns are detected"
allowed-tools: Bash,Read,Write,Edit,Glob,Grep,Task
---

# 复合学习

把错误、薄弱点和可复用模式沉淀到项目记忆与技能反馈。

**专家角色：** 学习记录员。

## 何时使用

- 用户说记住、总结错误、下次不要再犯。
- 同类纠正出现 2 次以上。
- 出现可复用的工程模式。
- 技能使用失败，需要反馈到 skill-feedback。

## 何时不使用

- 一次性普通说明，无可复用价值。
- 纯代码实现且未暴露新教训。

## Iron Law

用户触发“总结/记住错误”时，先写记忆，再继续解释或实现。

## Tracks

| Track | 触发 | 产物 |
|-------|------|------|
| Bug | 具体错误、返工、事故 | `.memory/MEMORY.md` + `.memory/error-lessons.md` |
| Knowledge | 可复用知识/模式 | `.memory/knowledge*.md` 或项目约定位置 |
| Skill | 技能触发错误、流程缺口 | `.memory/skill-feedback.md` 或技能优化计划 |
| Query | 查看历史教训 | 摘要输出 |
| Prune | 清理过期/重复记忆 | 合并或删除建议 |

历史上的 error-to-memory 说法视为本技能旧入口名。

## Bug Track

记录字段：

```markdown
### {date}: {title}

**Problem:** 发生了什么。
**Root Cause:** 为什么发生。
**Lesson:** 下次必须记住什么。
**Prevention:** 以后如何防止。
**Evidence:** 命令、文件、diff、用户纠正或日志。
```

严重级别：

- Critical：会导致需求错、数据错、发布错、重复返工。
- Warning：影响质量或效率。
- Info：一般经验。

## Skill Track

当错误来自技能流程，记录：

| 字段 | 内容 |
|------|------|
| skill | 哪个技能或技能链 |
| failure | 漏了什么门禁 |
| trigger | 什么用户信号应触发 |
| fix | 应加入哪个 Hard Gate |
| replay evidence | 是否来自真实 replay/eval |

若同类技能问题重复出现，建议 `skill-audit` → `skill-evolution`。

## 重叠检测

记录前检查：

1. 同一技术点是否已有。
2. 同一根因是否已有。
3. 同一预防措施是否已有。
4. 是否应合并到旧条目。
5. 是否需要升级严重级别。

## Stuck Recovery

若同一问题修复失败 3 次：

1. 停止继续补丁式修改。
2. 写入卡点记录。
3. 转 `gen-tests` 的 FIX 模式、`log-investigator`，或回到 `deep-plan`。

## 输出

```markdown
## 学习已记录
- Track:
- 写入位置:
- 严重级别:
- 重叠处理:
- 后续动作:
```
