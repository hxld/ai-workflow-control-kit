# RED TEST BEHAVIORAL ASSERTION REQUIREMENT

**v365 Enforcement**: RED 阶段必须满足两个条件：
1. **P0 (CRITICAL)**: 测试文件必须存在
2. **业务断言**: RED 测试必须失败于**业务断言**，而非结构性缺失

---

## P0: TEST FILE REQUIREMENT (CRITICAL BLOCKER)

RED 阶段开始前，测试文件必须存在。

### 自动生成测试文件（如不存在）

在运行 Maven 测试之前：

1. **检查测试文件是否存在**
   - 如果目标测试文件不存在，先生成测试文件骨架
   - 使用 `ensure_test_file_exists.py` 脚本自动生成

2. **测试文件骨架格式**
   ```java
   package com.example.project.service;

   import org.junit.Test;
   import static org.junit.Assert.*;

   /**
    * Auto-generated test skeleton for ExampleFlowService
    */
   public class ExampleFlowServiceTest {

       @Test
       public void testProcessAutoClaimFlow_ThrowsClassNotFoundException() {
           // RED: This test should fail because ExampleFlowService doesn't exist
           ExampleFlowService service = new ExampleFlowService();
           fail("RED phase: ExampleFlowService.processAutoClaimFlow not implemented");
       }
   }
   ```

3. **Maven 测试要求**
   - 必须运行测试（不是 "Tests run: 0"）
   - 必须得到 FAIL 结果（RED 阶段预期）
   - 失败原因应该是业务断言或 ClassNotFoundException

### P0 违规后果

如果 Maven 报告 "Tests run: 0" 或找不到测试文件：
- `gap_flags`: [`test_file_missing`, `red_business_assertion_not_observed`]
- `slice_status`: "BLOCKED"
- `blocker`: "test_file_not_found"
- `coverage_delta`: 0

---

## REQUIRED Pattern

你的 RED 测试必须包含至少一个**业务断言**，测试才会被验证器接受。

### Business Assertions (REQUIRED)

这些断言验证业务行为、状态变化或副作用：

✅ **Business Outcome Assertions**:
```java
assertEquals(AutoFlowStatus.READY, result.getStatus());
assertThat(compensateInfo.getCaseId()).isEqualTo(caseId);
assertThat(result.getFreeReviewAmount()).isGreaterThan(BigDecimal.ZERO);
```

✅ **Side Effect Verification**:
```java
verify(taskService).create(any());
verify(mapper).insert(argThat(entity -> entity.getCaseId().equals(caseId)));
```

✅ **DB State Verification**:
```java
TExampleModuleConfig saved = mapper.selectByPrimaryKey(configId);
assertThat(saved.getFreeReviewAmount()).isEqualTo(new BigDecimal("1000"));
```

---

## FORBIDDEN Patterns (Will be Rejected)

这些模式只验证结构存在性，不足以驱动生产实现：

❌ **Structural-Only Assertions**:
```java
assertNotNull(result);  // Only checks non-null
assertThat(obj).isNotNull();  // Only checks non-null
assertTrue(service.getClass() != null);  // Only checks class exists
```

❌ **Fail Placeholders**:
```java
@Test
public void test() {
    fail("not implemented");  // TODO placeholder
    fail("TODO: implement");  // TODO placeholder
}
```

❌ **Compilation-Failure-First Tests**:
```java
@Test(expected = ClassNotFoundException.class)  // Structural check only
public void testServiceDoesNotExist() { ... }
```

---

## Verification Rule

验证器将检查：

1. **至少有一个**业务断言模式（`assertEquals`, `assertThat(...).isEqualTo`, `verify`）
2. **不是全部**结构性断言（`assertNotNull`, `isNotNull`）
3. **没有** TODO/fail 占位符

如果违反以上任一规则：
- `gap_flags`: [`wrong_test_surface`, `behavior_test_charter_gap`]
- `slice_status`: "BLOCKED"
- `coverage_delta`: 0
- `blocker`: "no_behavioral_tests_found"

---

## TDD Workflow

1. **Write RED with business assertion**
   - Test must fail because business behavior is missing
   - NOT fail because class doesn't exist

2. **Verify RED fails correctly**
   - Run test: must get `FAIL` status
   - Failure must be assertion error (e.g., "expected X but was Y/null")

3. **Write minimum GREEN**
   - Implement just enough to pass the business assertion

4. **Verify GREEN passes**
   - Test passes with correct business behavior

---

## Examples by Family

| Family | RED Test Pattern | Assertion Example |
|--------|-----------------|-------------------|
| core_entry | Service method fails | assertThat(result).isNull() |
| stateful_side_effect | DB write not called | verify(mapper).insert(...).times(0) |
| wire_payload_api_contract | DTO field missing | assertThat(dto.getField()).isNull() |
| config_policy_threshold | Validation fails | assertThat(result.isValid()).isFalse() |

---

**CRITICAL**: 在继续 GREEN 阶段之前，必须至少有一个业务断言。结构性测试将在验证时被拒绝。

---

## v369 Enforcement Integration (EXPERIMENT 1+3)

**P0 Quality Gate**: 在 RED 测试完成后，GREEN 实现前，必须运行质量门禁：

```bash
.\scripts\v348_slice_quality_gate.ps1 -SliceDir {{REPLAY_ROOT}} -Worktree {{WORKTREE}}
```

### 门禁检查项

1. **Side Effect Ledger**: `side-effect-ledger.md` 必须存在且包含至少 1 个 VERIFIED 条目
2. **DB State Verification**: `db-state-verification.json` 必须存在且包含断言
3. **Test File Existence**: 测试文件必须存在于 `<test-module>/src/test/`
4. **Placeholder Detection**: 不允许 TODO、placeholder、占位符
5. **Behavioral Assertion**: 测试必须包含业务断言（不只是 assertNotNull）

### 如果门禁失败

- Exit code 1 → slice 被阻塞
- 必须修复所有 FAIL 项才能继续
- 修复后重新运行门禁验证

### 如果门禁通过

- Exit code 0 → 可以继续 GREEN 实现
- 质量门禁报告将写入 slice 验证结果

---

## Enforcement Flow

```
1. Write RED test
2. Run Maven test → Must FAIL (业务断言)
3. Run v348 quality gate → Must PASS
4. Implement GREEN
5. Run Maven test → Must PASS
6. Run side effect verification → Must PASS
7. Authorize next slice
```

任何步骤失败都会阻塞 slice 授权。
