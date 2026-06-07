# Test Fix Triage

FIX / TRIAGE / AUDIT 模式的长规则放在本文件。主 `SKILL.md` 只保留路由和硬门禁摘要。

## Mode TRIAGE

bugfix 证据不足时先分类：失败测试、日志 trace、复现步骤、外部 contract、只有口头描述。能写断言则先补 RED；不能写断言则输出最小采证计划。

堆栈问题先锁第一业务首帧、失败表达式和输入/配置 fixture；异步任务问题先定义父子任务状态、完成日志、下游任务/消息/展示、重试幂等中的可观察断言。

只允许输出 `NEEDS_REPRO`、`NEEDS_LOGS`、`NEEDS_CONTRACT`、`NEEDS_STACK_INPUT`、`NEEDS_ASYNC_STATE_CHAIN` 或 `STATIC_INFERENCE`；不得直接修改生产代码。

## Mode FIX

1. 先确定第一失败阶段，记录失败范围。
2. 若用户是 bugfix 诉求，先做证据分型：
   - 有失败测试或可写复现断言：进入 RED/GREEN/FIX。
   - 有日志、trace 或生产现象：转 `log-investigator` 或先补可复现测试。
   - 只有口头描述：输出假设、信息缺口、采证计划，不直接改生产代码。
   - 依赖外部系统或协议：先冻结 request/response/config/empty-case contract。
   - 明确异常堆栈：用第一业务首帧构造最小 RED。
   - 异步任务状态或下游触发异常：先补状态链断言或 static guard。
3. 分类失败：
   - 测试代码 bug：修复测试。
   - 源代码 bug：根因分析后最小修复。
   - 环境问题：尝试自动修复，失败则降级。
   - 构建图/验证链路问题：先修命令、范围、依赖顺序。
   - 运行态 blocker：记录 `test_runtime_blocker`，先隔离/串行/重跑验证。
   - 成功后运行态噪音：记录 `runtime_noise_with_success`。
   - 基线 blocker：单独记录，不算需求 RED。
4. 每个失败最多 3 轮 Test-Fix-Verify；没有根因就不修复，三次失败后升级 `deep-plan`。

## FIX Hard Gates

- 失败阶段在 `resolve / compile / testCompile / reactor build` 时，禁止直接修改断言或业务逻辑。
- 只有进入目标测试执行/断言阶段，才允许按“测试代码 bug / 源代码 bug”处理。
- 过滤命令与失败范围不一致时，先修正验证链路。
- runner 成功且退出码为 0 时，后续后台异常只能降低稳定性结论；退出码非 0 才升级为 `test_runtime_blocker`。
- 无失败测试、无日志、无复现输入时，FIX 结论最多是 `static_inference + evidence_gap`。
- 堆栈型 bug 的 RED 必须解释失败表达式与输入/配置 fixture 的映射。
- 数据链路型 bug 优先构造源数据、过滤条件、映射配置和期望输出 payload。
- 异步任务类 bug 至少覆盖状态推进、完成日志或下游触发之一。

## Mode AUDIT

运行项目覆盖率命令，按 `<60% / 60-80% / >=80%` 输出缺口或合格结论；同时检查正常路径、空/null、无效输入、边界、异常路径、must-not 断言、多 surface 逐项覆盖和小 GREEN 防误判矩阵。
