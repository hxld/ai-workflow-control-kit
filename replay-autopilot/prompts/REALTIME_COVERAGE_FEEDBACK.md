# REAL-TIME COVERAGE FEEDBACK (EXPERIMENT 3)

**v358 Enforcement**: Coverage 现在基于**行为证据**实时计算，而非文件创建数量。

---

## Coverage Delta Calculation

你的 `coverage_delta` 不再基于"创建了多少文件"，而是基于**你证明了什么行为**。

### What Counts Toward Coverage

✅ **Counts**: 有行为证据的实现
- 真实入口调用 + 业务断言 (e.g., `assertEquals(expected, actual)`)
- DB 写入 + 验证 (e.g., `verify(mapper).insert(...)`)
- 副作用验证 (e.g., status changed, task created)
- 外部输出验证 (e.g., export file generated, API response correct)

❌ **Does NOT Count**: 仅结构性的实现
- 文件创建但无测试
- TODO 注释
- Getter/setter 测试
- assertNotNull / isNotNull 断言
- 类/方法存在性检查
- 编译通过但无业务断言

---

## Real-Time Estimation

验证器现在会在每个 slice 完成后实时估算覆盖率：

| Evidence Type | Coverage Contribution |
|--------------|---------------------|
| core_entry with behavioral test | +30% |
| stateful_side_effect verified | +20% |
| deploy_export_page with test | +10% |
| wire_payload_api_contract verified | +10% |
| external_integration verified | +15% |
| generated_artifact with output test | +10% |
| config_policy_threshold with validation | +5% |

**关键**: 如果你创建了文件但**没有行为证据**，`coverage_delta = 0`。

---

## Feedback Messages

你可能看到以下反馈消息：

### "Files created but no behavioral evidence - coverage delta is 0"

**原因**: 你修改了生产代码或创建了测试文件，但测试没有包含业务断言。

**修复**:
- 添加业务断言: `assertEquals(expected, actual)`
- 验证副作用: `verify(mapper).insert(...)`
- 检查输出: `assertThat(result.getField()).isEqualTo(expected)`

### "coverage_delta corrected from self-assessed X to 0"

**原因**: 你自评覆盖率为 X%，但验证器发现没有行为证据。

**修复**: 确保测试包含至少一个业务断言，而不是结构性检查。

---

## Example

**WRONG** (creates files, no coverage credit):
```json
{
  "implemented_files": ["ExampleService.java", "ExampleServiceTest.java"],
  "tests": [
    {"phase": "GREEN", "result": "pass"}
  ],
  "coverage_delta": 0,  // No behavioral assertion in test
  "gap_flags": ["no_behavioral_evidence"]
}
```

Test file:
```java
@Test
public void test() {
    // WRONG: Only checks non-null
    assertNotNull(service.getConfig());
}
```

**CORRECT** (creates files with behavioral assertion):
```json
{
  "implemented_files": ["ExampleService.java", "ExampleServiceTest.java"],
  "tests": [
    {"phase": "RED", "result": "fail"},
    {"phase": "GREEN", "result": "pass"}
  ],
  "coverage_delta": 30,  // Behavioral assertion exists
  "side_effect_evidence": {
    "status": "CLOSED",
    "entry_call": "exampleService.handleFlow",
    "test_name": "ExampleServiceTest.testAutoFlow"
  }
}
```

Test file:
```java
@Test
public void testAutoFlow() {
    // CORRECT: Checks business outcome
    AutoFlowResult result = service.handleFlow(caseId, task);
    assertEquals(AutoFlowStatus.READY, result.getStatus());
}
```

---

## Stop-Loss Rule

如果连续 3 个 slice 的 `coverage_delta = 0`（尽管有文件创建）：
- 回合将被标记为 `BLOCKED_NO_PROGRESS`
- 需要重新规划测试策略

**解决**: 在下一个 slice 中确保至少包含一个业务断言。

---

**核心原则**: Coverage is **evidence**, not **effort**. 创建 100 个文件但没有行为证据 = 0% 覆盖。
