---
argument-hint: [planning|openspec|docs|all]
description: 恢复上下文 - 从需求文档路径推断并读取所有相关文件
---

# Claude Command: Restore Context

这个命令帮助你从所有相关文件中恢复完整上下文，回答5个关键问题。

---

## ⚠️ 前置条件：检查历史错误（必须执行）

> **这个错误已经犯了 N+1 次！每次执行任何技能前必须先检查！**

**执行步骤**:
1. **识别当前项目并读取 MEMORY.md 中的错误速查表**
   - 根据当前工作目录确定项目标识符（如 `d:\\projects\\my-project` → `d--projects--my-project`）
   - 文件路径: `~/.claude/projects/{项目标识符}/memory/MEMORY.md`
   - 重点关注 "常见错误速查" 章节

2. **检查是否有相关技能的错误记录**
   - 找出与当前要执行的技能相关的历史错误

3. **确认不会重复犯错**
   - 如果有相关错误记录，必须明确说"已检查错误 X，本次不会重复"

**输出示例**:
```
📋 错误检查（前置条件）
- [x] 已读取 MEMORY.md 错误速查表
- [x] 相关错误：无（restore-context 是读取操作，风险较低）
- [x] 确认：本次将正确执行上下文恢复
```

---

## ⚠️ 会话开始时的路径约定（推荐）

**建议用户在会话开始时指定需求文档路径**：

```
"需求文档在 D:\\docs\\requirements.md"
```

**系统将自动推断并读取以下文件**：

| 文件类型 | 推断规则 | 用途 |
|---------|---------|------|
| 技术文档 | 同目录 + "技术文档.md" | 了解当前技术方案 |
| 改动说明 | 同目录 + "改动说明.md" | 了解代码变更范围 |
| OpenSpec变更 | 根据"一期迭代"或需求关键词匹配 | 了解任务进度 |

---

## Usage

```
/restore-context            # 完整恢复（推荐）
/restore-context planning   # 只恢复 planning-with-files
/restore-context openspec   # 只恢复 openspec
/restore-context docs       # 只恢复项目文档
/restore-context all        # 恢复所有（同默认）
```

## Command Options

- 无参数 (默认): 从需求文档路径推断并恢复所有相关文件
- `planning`: 只读取 planning-with-files 文件
- `openspec`: 只读取 openspec 相关文件
- `docs`: 只读取项目文档（技术文档、改动说明）
- `all`: 读取所有上下文文件

---

## The 5-Question Reboot Test

恢复上下文时，回答以下5个问题：

| 问题 | 答案来源 | 增强来源 |
|------|----------|----------|
| 1. 我在哪？ | task_plan.md → Current Phase | 技术文档 → 当前版本 |
| 2. 我要去哪？ | task_plan.md → Phases | OpenSpec → 任务进度 |
| 3. 目标是什么？ | task_plan.md → Goal | 需求文档 → 功能范围 |
| 4. 我学到了什么？ | findings.md → Research Findings | 技术文档 → 设计决策 |
| 5. 我做了什么？ | progress.md → 最近几条 Session | 改动说明 → 文件清单 |

---

## Workflow

### 阶段 0: 路径确认

**检查会话上下文是否有需求文档路径**：

```
场景A: 有需求文档路径
    ↓
推断技术文档、改动说明、OpenSpec路径
    ↓
输出路径确认信息

场景B: 无需求文档路径
    ↓
提示用户（可选）
    ↓
继续从项目根目录恢复基本上下文
```

**输出**：
```
📋 路径确认
- 需求文档: D:\...\requirements.md ✓
- 技术文档: D:\...\technical-doc.md ✓
- 改动说明: D:\...\changelog.md ✓
- OpenSpec: openspec/changes/my-feature-v101/ ✓
- Planning: d:\projects\my-project\ (项目根目录) ✓
```

**如果无路径**：
```
⚠️ 未找到需求文档路径，将从项目根目录恢复基本上下文

提示: 在会话开始时指定需求文档路径可恢复更完整的上下文
例如: "需求文档在 D:\docs\requirements.md"

继续恢复基本上下文...
```

---

### 阶段 1: 读取 Planning-with-files

**task_plan.md（路线图）**:
- **Goal**: 当前目标
- **Current Phase**: 当前在哪个阶段
- **Phases**: 阶段状态（pending/in_progress/complete）
- **Decisions Made**: 已做出的决策
- **Errors Encountered**: 遇到的错误

**progress.md（会话日志）**:
- **读取最近2-3条 Session**
- 了解最近做了什么工作
- 知道修改了哪些文件

**findings.md（知识库）**:
- **Research Findings**: 技术发现
- **Technical Decisions**: 技术决策
- **Error Lessons**: 错误教训

---

### 阶段 2: 读取项目文档（如有路径）

**技术文档**:
- **当前版本**: 文档修订版本
- **最近修订**: 最新修订记录
- **功能模块**: 已完成的功能模块
- **待开发功能**: 计划开发的功能

**改动说明**:
- **改动文件清单**: 已修改的文件列表
- **接口变更**: 新增/修改的接口
- **配置变更**: Redis、数据库等配置

---

### 阶段 3: 读取 OpenSpec（如有）

**tasks.md**:
- **任务列表**: 所有任务及完成状态
- **待完成任务**: 未完成的任务

**spec.md**（如存在）:
- **功能规格**: 接口规格描述

---

## Output Example

```markdown
📋 Context Restored

## 路径确认
- 需求文档: D:\...\requirements.md ✓
- 技术文档: D:\...\technical-doc.md ✓ (V2.15)
- 改动说明: D:\...\changelog.md ✓
- OpenSpec: openspec/changes/my-feature-v101/ ✓
- Planning: d:\projects\my-project\ ✓

## 5-Question Reboot Test

| Question | Answer |
|----------|--------|
| 我在哪？ | Phase 4: Delivery |
| 我要去哪？ | 运维部署和测试验证 |
| 目标是什么？ | 完成项目迭代 |
| 我学到了什么？ | 敏感字段复用数据库加密值；AI OCR API 支持批量处理 |
| 我做了什么？ | 敏感字段修改、工单自动完结逻辑修正 |

## 当前状态
- **Git**: master-fix20260319 (clean)
- **Phase**: 4 of 5 (Delivery)
- **Status**: ✅ 代码完成，待运维
- **技术文档版本**: V2.15 (最后修订: 2026-03-18)

## 最近工作 (progress.md)

### 2026-03-18
- 敏感字段 insured_certificate_no → insured_certificate_no_encrypt
- Commit: 8f4c3611b

### 2026-03-17
- 工单自动完结逻辑修正
- 删除定时任务，改为实时触发

## 待完成任务
### 运维
- [ ] Redis限流配置
- [ ] 测试验证

### OpenSpec (my-feature-v101)
- [x] 任务1-5: 已完成
- [ ] 任务6: Redis限流配置（部署时添加）

## 改动文件清单 (改动说明.md)
- 新增文件: 2 个
- 修改文件: 5 个
- 详情见: D:\...\changelog.md

## 关键技术发现 (findings.md)
1. 敏感字段复用数据库加密值，无需重复加密
2. AI OCR API 支持批量处理
3. 工单创建在任务发起时（无论成功失败都有记录）

## 关键教训 (MEMORY.md)
1. sync-progress 必须更新所有文件
2. 执行技能前必须阅读技能说明
3. 文档代码示例必须是实际代码的复制粘贴

---
Ready to continue. What would you like to do?
```

---

## When to Use

- 新会话开始时（推荐配合需求文档路径）
- 忘记当前进度时
- 需要了解之前决策时
- 切换到新任务前

## Quick Triggers

你也可以直接说：
- "恢复上下文"
- "读取上下文"
- "继续之前的工作"
- "当前进度是什么"
- "我在做什么"

## Notes

- **推荐指定路径**: 指定需求文档路径可恢复更完整的上下文
- **按顺序读取**: task_plan.md → progress.md → findings.md → 项目文档 → OpenSpec
- **不需要读完整个文件**: progress.md 只读最近2-3条
- **快速恢复**: 基本上下文30秒内恢复，完整上下文1分钟内恢复
- **兼容无路径**: 即使没有指定路径，也能从项目根目录恢复基本上下文
