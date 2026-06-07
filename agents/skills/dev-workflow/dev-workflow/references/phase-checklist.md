# Dev-Workflow Phase Checklist

## Phase 0: 预检查

- [ ] `pre-flight-check` 已执行
- [ ] `.memory/MEMORY.md` 已读取
- [ ] 任务已拆分为子任务清单
- [ ] 依赖 DAG 已构建（哪些子任务可并行）

## Phase 1: 需求分析

- [ ] 需求文档已读取
- [ ] `req-alignment-check` 已执行
- [ ] 隐藏需求清单已完成
- [ ] 需求缺口已与用户确认

## Phase 2: 技术设计

- [ ] 现有架构已理解
- [ ] 变更方案已输出（必须同时包含 `openspec` + `.doc/`）
- [ ] API/数据模型变更已明确

## Phase 3: 用户审批

- [ ] 设计方案已展示给用户
- [ ] 用户已明确批准（⛔ 唯一暂停点）

## Phase 4: 实现

- [ ] 代码已按子任务实现
- [ ] `tasks.md` 勾选进度
- [ ] 并行子任务已用 subagent 执行
- [ ] 代码风格与现有代码一致

## Phase 5: 测试

- [ ] `gen-tests` 已执行
- [ ] 测试全部通过
- [ ] 覆盖率达标（≥60%）

## Phase 6: 注释

- [ ] `add-comments` 已执行（可选）
- [ ] 注释聚焦 WHY 非 WHAT

## Phase 7: 验证 + 报告

- [ ] 所有 Phase 输出物已确认
- [ ] Handoff Summary 已输出
- [ ] 推荐下一步：`sync-progress` 或 `ship-release`
