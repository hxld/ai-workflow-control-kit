---
name: replay-test-charter-validator
description: "Test charter validator - Require side-effect proof (DB/state/file/API) in tests, reject helper-only validations"
allowed-tools: Read,Glob,Grep
---

# Test Charter Validator

确保测试契约包含副作用证明，而非仅验证 helper 逻辑。

**专家角色：** 测试有效性验证员。

**上游技能：** gen-tests
**下游技能：** deep-review, sync-progress

## 何时使用

- 测试契约验证
- Slice 测试授权检查
- 测试 surface 评估

## 何时不使用

- 纯单元测试工具类 (明确边界)
- 用户明确跳过副作用要求

## Iron Law

**Helper-only tests are INSUFFICIENT for slice authorization.** 每个测试必须证明至少一个副作用。

## 可接受的副作用证据

### 有效副作用

- **DB write**: INSERT/UPDATE/DELETE 带 @Transactional rollback
- **State change**: 状态转换、任务创建、进度日志
- **File generation**: PNG/PDF 创建、上传
- **External API**: RPC 调用、HTTP 请求、消息队列
- **Async behavior**: @EventListener、@Scheduled 执行

### 无效测试 (不充分)

- 纯函数验证 (仅 validator 逻辑)
- 静态方法测试 (无状态变化)
- Helper 类测试 (无副作用)
- DTO 序列化测试 (无行为)

## 验证规则

### Rule 1: 副作用断言必需

测试必须断言以下之一:
- Database state: `assertThat(mapper.select(...)).isNotNull()`
- State change: `assertThat(entity.getStatus()).isEqualTo(newStatus)`
- File generation: `assertThat(file).exists()`
- API call: `verify(facade).method(...)`

### Rule 2: 禁止的测试模式

仅断言以下内容的测试不充分:
- 返回值: `assertThat(calculate(x)).isEqualTo(y)`
- Validator 逻辑: `assertThat(validator.validate(x)).isRejected()`
- 字符串序列化: `assertThat(json).contains("field")`

这些对于 carrier 闭包是不充分的。

### Rule 3: DB 测试必需 Transactional

如果测试证明 DB 状态:
- 必须 `@Transactional`
- 应该 `@Rollback`
- 必须不留下测试数据

## Verifier 集成

测试文件创建后:
1. 解析测试方法
2. 检查副作用断言
3. 如无: 标记 `wrong_test_surface`，BLOCK
4. 如有: 允许切片继续

## 示例分析

### 有效测试 (有副作用)

```java
@Test
@Transactional
public void testHandle_InsertsCompensateDetail() {
    // Given
    Long caseId = givenCaseWithAiResult();

    // When
    aiAutoClaimFlowService.handle(caseId, task);

    // Then: 副作用断言
    CompensateDetail detail = compensateDetailMapper.selectByCaseId(caseId);
    assertThat(detail).isNotNull(); // Side-effect assertion
}
```

### 无效测试 (仅 helper)

```java
@Test
public void testValidate_RejectsNegative() {
    ValidationResult result = validator.validate("-100");
    assertThat(result.isRejected()).isTrue(); // 无副作用
}
```

## 测试契约模板

```markdown
### Slice S1: <Slice Title>

**Target Carrier**: <Service.method()>

**Side-Effect to Prove**: [选择: DB write | State change | File gen | API call]

**Test Name**: test<Scenario>_<ExpectedSideEffect>()

**Given**: <Setup including test data>
**When**: <Call target carrier>
**Then**: <Verify side effect occurs>

**Example**:
```java
@Test
@Transactional
public void testAutoFlow_InsertsCompensateDetail() {
    // Given: Case with AI result
    Long caseId = givenCaseWithAiResult();

    // When: Process auto flow
    aiAutoClaimFlowService.handle(caseId, task);

    // Then: Compensate detail inserted
    CompensateDetail detail = compensateDetailMapper.selectByCaseId(caseId);
    assertThat(detail).isNotNull();
    assertThat(detail.getAmount()).isEqualTo(aiResult.getAmount());
}
```
```

## Agent Prompt 添加

在 Test Creation Agent 提示词中添加:

```
## Test Side-Effect Requirement (MANDATORY)

你写的每个测试必须证明副作用:

### 什么算副作用证明

- DB write: `assertThat(mapper.select(...)).isNotNull()`
- State change: `assertThat(entity.getStatus()).isEqualTo(newStatus)`
- File generation: `assertThat(generatedFile).exists()`
- API call: `verify(facade).push(...).times(1)`

### 什么不算

- Return value: `assertThat(calculate(x)).isEqualTo(y)`
- Validator logic: `assertThat(validator.validate(x)).isRejected()`
- String format: `assertThat(json).contains("field")`

### 测试模板

```java
@Test
@Transactional // DB 测试必需
public void test<Method>_<SideEffect>() {
    // Given: 用测试数据 setup
    // When: 调用目标方法
    // Then: 验证副作用 (DB/state/file/API)
}
```

警告: 无副作用证明的测试将被标记为 `wrong_test_surface` 并阻塞。
```

## 强制执行

如果测试文件未通过验证:
- 添加 `wrong_test_surface` 标记到 SLICE_RESULT
- 添加 `side_effect_evidence_missing` 阻塞
- 设置 authorized_for_next_slice = false
- 要求重写测试带副作用证明

## 验证命令

```bash
# 运行 3 轮带副作用验证器的 replay
for i in {1..3}; do
  ./run-replay.sh --feature=aiClaimV2 --side-effect-validator
  # 检查测试文件的副作用断言
  # 检查 side_effect_ledger 的闭包 > 0%
done

# 成功标准: >= 2/3 轮有带副作用断言的测试
# 回滚标准: >= 2/3 轮仍是 helper-only 测试
```

## 回滚条件

如果 3 轮中有 2 轮仍产生 helper-only 测试:
- 调查为什么 agent 避免副作用测试
- 可能转向: 在 context 中提供副作用测试示例
- 可能转向: 简化 DB setup (H2 in-memory 配置)

## 预期指标改善

- **当前**: 0% 轮次有副作用测试 (0/11)
- **目标**: 80% 轮次有副作用测试
- **预期改善**: +20-40% 覆盖率

---

**演化来源**: aiClaimV2 replay v278-v293 deep review, RC5: Tests prove helper logic only, not executable behavior (side effects)
