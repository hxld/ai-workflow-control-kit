# Integration Test Fallback

当目标测试需要 Spring 容器、数据库连接、外部 RPC 或其他重量级依赖才能运行时，先执行可行性探测，再决定测试策略。

## 可行性探测

| 信号 | 检测方式 |
|------|----------|
| 测试基类需要完整容器启动 | 读取现有测试基类注解和依赖 |
| 容器启动依赖外部服务 | 读取 application 配置 |
| 编译或运行需要特定环境变量、配置文件或密钥 | 检查测试注解和条件配置 |
| 现有测试大面积忽略 | grep `@Ignore` / `@Disabled` 占比 |
| 已有测试运行报 bean 创建或依赖缺失 | 尝试编译 + 最小运行探测 |

## 降级矩阵

| 情况 | 策略 | 覆盖标记 |
|------|------|----------|
| 容器能启动，依赖完整 | 正常集成测试 | `integration` |
| 容器能启动但缺少外部服务 | mock 外部依赖 | `integration_with_mocks` |
| 容器无法启动或启动成本极高 | 纯 mock 单元测试 | `mock_unit` |
| 无法启动且依赖链过深 | Static Guard + 手工验证锚点 | `static_only` |

## Mock 单元测试纪律

- 不继承需要完整容器的基类，不使用完整容器注解。
- 用 Mockito 或同类工具手动 mock 所有外部依赖。
- 每个核心方法至少一个正向测试，条件分支、异常路径、must-not 行为、状态变更和字段来源必须显式断言。
- `mock_unit` 核心主链最高 `PARTIAL`；`integration_with_mocks` 可与 `integration` 同等看待。
- 需求涉及跨模块事务、MyBatis 映射、Spring 事件/AOP/拦截器、序列化/反序列化时，应标注 `needs_integration_test`，由 `sync-progress` 跟踪。
- stateful core path 涉及状态流转、事务边界、进度/日志、持久化重写或任务推进时，应优先 DB/事务级测试；若只能 mock 协作者，报告必须写 `needs_transaction_test`，core path 不能标 `DONE`。

Mock 降级不是“不写测试”，而是换一种可执行策略。零测试永远是 `NO-GO`。
