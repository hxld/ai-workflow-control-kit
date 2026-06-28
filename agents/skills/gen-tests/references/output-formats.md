# gen-tests 输出格式

## CREATE / FILL

```markdown
## 测试已生成/补充 | 新增 X | 通过 X | 失败 0
### 框架: [框架名] | 测试文件: [路径] | 场景: 正常/空/Null/无效/边界
### 测试设计控制映射
| 行 | 目标/surface | 测试文件/方法 | 状态 | 缺口/行动 |
|----|----------------|----------------|------|-----------|
### 自动化验证: [已覆盖场景]
### 集成验证: [需外部确认场景]
```

## FIX

```markdown
## 测试修复报告
| 轮次 | 测试 | 已修复 | 剩余 | 状态 |
### 失败阶段: [resolve / compile / testCompile / test / runtime]
### 验证范围: [文件 / 模块 / workspace / 全仓库]
### 修复详情: [每个修复的说明]
### 遗留: [未解决的问题] (如有)
```

## TRIAGE

```markdown
## Bugfix 采证报告
### 现有证据: [失败测试 / 日志trace / 复现步骤 / 外部contract / 明确堆栈 / 只有口头描述]
### 当前结论: [NEEDS_REPRO / NEEDS_LOGS / NEEDS_CONTRACT / NEEDS_STACK_INPUT / STATIC_INFERENCE]
### 异步状态链: [父任务 / 子任务 / 状态流转 / 调度 / 完成日志 / 下游触发 / 不适用]
### 信息缺口: [缺什么]
### 下一步采证: [最小可执行步骤]
```

## AUDIT

```markdown
## 覆盖率报告
### 代码覆盖率: X% (行) / Y% (分支)
### 场景覆盖: [已覆盖/总数]
### 测试设计控制覆盖矩阵: [covered / partial / blocked / not_applicable 摘要]
### 缺口文件: [未覆盖的源文件列表]
### 建议下一步: FILL (补缺口) / CREATE (新建)
```
