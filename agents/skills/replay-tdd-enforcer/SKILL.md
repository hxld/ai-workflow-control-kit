---
name: replay-tdd-enforcer
description: "TDD cycle enforcement - Require RED AND GREEN phases with production code changes for valid slice completion"
allowed-tools: Read,Glob
---

# TDD Cycle Enforcer

强制完整 TDD 周期：RED-only 是无效进度，必须完成 GREEN 阶段并产生生产代码变更。

**专家角色：** TDD 执行监督员。

**上游技能：** dev-workflow, ideate
**下游技能：** gen-tests, deep-review

## 何时使用

- Replay slice 执行验证
- TDD 周期完整性检查
- 切片授权判断

## 何时不使用

- 非实现类任务 (纯文档、配置)
- 用户明确跳过 TDD 要求

## Iron Law

**RED-only is NOT progress.** 有效切片必须:
1. RED Phase: 测试因业务断言失败 (非编译错误)
2. GREEN Phase: 添加生产代码，测试通过
3. Evidence: SLICE_RESULT 显示 red_phase 和 green_phase

## GREEN Phase 必需条件

- `production_changes.files_added OR production_changes.files_modified` 必须非空
- `production_changes.lines_added` 必须 >= 10 (非琐碎修改)
- `green_phase.test_result` 必须是 "BUILD SUCCESS"
- `green_phase.tests_must_pass` 必须为 true

## 强制阻塞条件

### 1. RED-only 无 GREEN

如果 SLICE_RESULT 有 red_phase 但无 green_phase:
- Blocker: `tdd_red_only_no_green`
- Authorization: authorized_for_next_slice = false
- Action: 在下一切片前停止

### 2. GREEN 无生产代码

如果 GREEN phase 无生产代码变更:
- Blocker: `green_no_production_changes`
- Authorization: authorized_for_next_slice = false
- Action: 停止并要求生产实现

## SLICE_RESULT Schema 增强

```json
{
  "slice_id": "S1",
  "status": "DONE|BLOCKED",
  "red_phase": {
    "required": true,
    "evidence": "test_command_output",
    "expected_failure": "business_assertion",
    "actual_failure": "compilation|business_assertion|none"
  },
  "green_phase": {
    "required": true,
    "evidence": "BUILD SUCCESS output",
    "production_changes": {
      "files_added": ["path/to/File.java"],
      "files_modified": ["path/to/Other.java"],
      "lines_added": 123,
      "lines_deleted": 0
    },
    "test_command": "mvn test ...",
    "test_result": "BUILD SUCCESS, X tests passed"
  },
  "green_completion_check": {
    "must_have_production_changes": true,
    "min_production_lines": 10,
    "tests_must_pass": true
  }
}
```

## Agent Prompt 添加

在 Slice Execution Agent 提示词中添加:

```
## TDD Cycle Requirement (MANDATORY)

每个切片必须完成完整 TDD 周期:

### RED Phase
- 写测试，预期失败 (因为生产代码不存在)
- 运行测试: 预期失败 (ClassNotFoundException 或断言失败)
- 这证明测试有效

### GREEN Phase (必需)
- 写最小生产代码使测试通过
- 运行测试: 预期 PASS
- 这证明实现有效

### REFACTOR Phase (可选)
- 在保持测试 green 的同时清理代码

### SLICE_RESULT 提交

提交 SLICE_RESULT 时:
- red_phase.evidence: 测试失败输出
- green_phase.evidence: 测试通过输出
- production_changes: 修改/添加的文件列表

警告: 如果提交 RED-only，切片将被阻塞。GREEN phase 不是可选的。
```

## 验证命令

```bash
# 运行 3 轮带 TDD enforcer 的 replay
for i in {1..3}; do
  ./run-replay.sh --feature=example-feature --tdd-enforcer
  # 检查 SLICE_RESULT.json 是否包含 green_phase
  # 检查 production_changes 是否非空
done

# 成功标准: >= 2/3 轮有 green_phase 和 production_changes
# 回滚标准: >= 2/3 轮仍为 RED-only
```

## 回滚条件

如果 3 轮中有 2 轮仍产生 RED-only SLICE_RESULT:
- 调查为什么 agent 停在 RED
- 可能转向: 延长超时 (如果 agent 时间不够)
- 可能转向: 简化需求 (如果任务太复杂)

## 预期指标改善

- **当前**: 0% 轮次有 GREEN 完成 (0/11)
- **目标**: 80% 轮次有 GREEN 完成
- **预期改善**: +10-30% 覆盖率

---

**演化来源**: example-feature replay v278-v293 deep review, RC4: TDD cycle incomplete - RED-only execution, no GREEN phase
