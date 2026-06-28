---
name: replay-pre-flight-check
description: "Replay pre-flight test environment validation - Validate JUnit/TestNG, compilation, and smoke test before Phase 1 execution"
allowed-tools: Bash,Read,Glob
---

# Replay Pre-Flight Check

在 Replay Phase 1 执行前验证测试环境。快速失败而非在执行中遇到环境阻塞。

**专家角色：** 环境验证员。

**上游技能：** workflow-router
**下游技能：** dev-workflow, ideate

## 何时使用

- Replay / eval 执行前
- 需要运行测试的自动化工作流启动前

## 何时不使用

- 纯只读分析不涉及执行
- 用户明确跳过环境检查

## 检查项 (全部必须)

### 1. JUnit/TestNG 可用性

```bash
mvn dependency:tree -pl <target_module> | grep -E "junit|testng"
```

**期望**: 至少找到一个测试框架依赖。
**失败**: BLOCK replay，报告缺少测试框架。

### 2. 测试编译冒烟测试

```bash
cd <worktree>
mvn test-compile -pl <target_module>
```

**期望**: BUILD SUCCESS
**失败**: BLOCK replay，报告编译错误。

### 3. 最小测试文件创建

```bash
# 在目标模块创建最小测试
cat > <worktree>/<target_module>/src/test/java/SmokeTest.java <<'EOF'
import org.junit.Test;
import static org.junit.Assert.assertTrue;

public class SmokeTest {
    @Test
    public void testEnv() {
        assertTrue(true);
    }
}
EOF

# 运行冒烟测试
mvn test -pl <target_module> -Dtest=SmokeTest
```

**期望**: BUILD SUCCESS, 1 test passed
**失败**: BLOCK replay，报告测试框架问题。

## Phase 0 门禁添加

将 **Gate 9: Test Environment Validation** 添加到 8-Gate 合规检查。

**状态**: ✅ PASS (以上所有检查通过)
**阻塞**: ❌ BLOCK (任一检查失败)

## 强制执行

如果预检查失败：
1. 设置 phase0_status = BLOCKED
2. 设置 stop_stage = PreFlight
3. 不要进入 Plan 或 Phase 1
4. 报告具体失败原因 (JUnit 缺失、编译失败等)

## 集成

在 replay runner 中 Phase 1 前添加:

```python
def run_pre_flight_check(worktree, target_module):
    check_junit_available(worktree, target_module)
    check_test_compilation(worktree, target_module)
    check_smoke_test(worktree, target_module)
    return PreFlightResult(status="PROCEED"|"BLOCKED", details={...})
```

## Agent 提示词添加

在 Phase 0 Agent 提示词中添加:

```
## Pre-Flight Validation (MANDATORY)

在开始 Plan 或 Phase 1 前，你必须运行预检查:

1. 验证 JUnit/TestNG 在 <target_module> 中可用
2. 验证测试编译可以工作
3. 创建并运行最小冒烟测试

如果任一检查失败:
- 不要进入 Plan 阶段
- 报告具体失败原因
- 建议修复方案 (如 "在 claim-core/pom.xml 添加 JUnit 依赖")

预检查不是可选的。损坏的测试环境无法通过写更多测试来修复。
```

## 验证命令

```bash
# 运行 3 轮带预检查的 replay
for i in {1..3}; do
  ./run-replay.sh --feature=aiClaimV2 --pre-flight-check
  # 检查 phase0_status == BLOCKED at PreFlight stage
  # 检查 Phase 1 是否到达 GREEN phase
done

# 成功标准: >= 2/3 轮到达 GREEN phase
# 回滚标准: >= 2/3 轮仍在 RED 因环境错误失败
```

## 回滚条件

如果 3 轮中有 2 轮仍在 RED 因以下原因失败:
- "找不到符号: 类 Test"
- "JUnit dependencies missing"
- 任何编译/测试框架错误

则回滚预检查并调查替代方案 (如全局修复项目 POM)。

---

**演化来源**: aiClaimV2 replay v278-v293 deep review, RC6: Test environment failures (JUnit, compilation) not detected pre-flight
