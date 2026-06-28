# Pre-Commit Check Rules

提交前自动检查规则，按严重程度分级。

## Git Boundary / Staging Guard

- 不混合多个任务。
- 不把功能、重构、测试修复、文档大包混成一个提交。
- 不把 generated artifacts 和 effective diff 混进同一提交。
- 如不能频繁提交，输出 atomic commit plan。
- 用户未要求发布时，不自动 push。
- 不使用 `git add .` 作为默认动作；只暂存已确认的 effective diff、测试、文档和规格文件。
- 若用户或仓库要求公司 Git 规范，先完成本技能收口，再路由到对应 Git 规范技能或发布技能。

## Intelligent Staging Gate

提交或发布前按文件角色分类：

| class | examples | action |
|-------|----------|--------|
| `include` | 本轮有效业务代码、测试、规格、必要文档 | 可暂存 |
| `confirm` | lockfile、批量格式化、生成文档/截图、脚本、跨模块配置 | 说明原因，必要时让用户确认 |
| `exclude` | secrets、本地配置、缓存、日志、构建产物、临时 harness、无关漂移 | 不暂存 |

同时输出 test focus：`changed surface -> required verification -> executed/missing -> risk`。缺少关键 surface 验证时，不得把 Git 边界标 `DONE`。

## Staged Artifact Guard

进入 commit / push / PR 前必须基于暂存区再检查一次：

- `git diff --cached --name-status` 必须可解释为本轮 effective diff、测试、规格或已确认文档。
- local docs、规格草稿、记忆、生成物、截图、日志、缓存、临时 harness、replay 输出、评审包或大批量格式化默认 `confirm` 或 `exclude`，不能被 `git add .` 顺带纳入。
- ignore 边界内文件默认只作为本地真值；除非用户明确要求版本化，否则不得 `git add -f`。
- 若发现误暂存，先 unstaged 并重新输出 staging plan；不能用“后续再清理”进入提交。

## 🔴 Critical（阻断提交）

### 安全

| # | 规则 | 检测方式 | 典型场景 |
|---|------|---------|---------|
| S01 | 硬编码密钥/密码/Token | Grep 敏感关键词 | `API_KEY=xxx`, `password=123` |
| S02 | SQL 注入风险 | Grep `${` 在 mapper/query | MyBatis `${userId}` |
| S03 | 敏感数据未脱敏（返回值） | 检查 DTO 字段 | 身份证、银行卡明文返回 |
| S04 | 敏感数据写入日志 | Grep PII in log | `log.info("userPhone={}")` |

### 逻辑

| # | 规则 | 检测方式 | 典型场景 |
|---|------|---------|---------|
| L01 | 空指针/未定义解引用 | 静态分析 | `user.getName()` without null check |
| L02 | N+1 查询（循环内 DB/RPC） | Grep 循环内调用 | `for(user : users) { rpc.find(user.id) }` |
| L03 | 金额用浮点数 | 类型检查 | `double total = price * qty` |
| L04 | 空集合直接取值 | Grep `.get(0)`, `.getFirst().get()` | 无空判断 |
| L05 | 竞态条件（check-then-act） | 逻辑分析 | 检查库存→扣减无锁 |

### 并发

| # | 规则 | 检测方式 | 典型场景 |
|---|------|---------|---------|
| C01 | static 非线程安全对象 | Grep `static` + 线程不安全类 | `static SimpleDateFormat` |
| C02 | 单例 Bean 可变实例变量 | 检查 @Service/@Component | `private int count` in singleton |
| C03 | ThreadLocal 未清理 | Grep ThreadLocal 无 remove | finally 块中缺少 `threadLocal.remove()` |

### 异常处理

| # | 规则 | 检测方式 | 典型场景 |
|---|------|---------|---------|
| E01 | 空 catch 块 | Grep 空的 catch | `catch (e) {}` |
| E02 | catch 后无日志 | 检查 catch 块 | `catch (e) { throw new BizException() }` |
| E03 | @Async + @Transactional 不生效 | Grep 注解组合 | 同一类内两个注解同时出现 |

## 🟡 Warning（建议修复）

| # | 规则 | 典型场景 |
|---|------|---------|
| W01 | 大结果集无分页 | 查询接口无 page/limit |
| W02 | 事务范围包含 RPC | @Transactional 内有 Feign/Dubbo 调用 |
| W03 | 同步操作可异步 | 通知/日志同步执行阻塞主流程 |
| W04 | 查询返回 SELECT * | Mapper XML 使用 SELECT * |
| W05 | BigDecimal 用 equals 比较 | `.equals()` 比较 BigDecimal |
| W06 | Optional 未判断就取值 | `optional.get()` 无 isPresent |
| W07 | 错误码未用常量 | `throw new BizException(10001)` |

## 🟢 Info（可选优化）

| # | 规则 | 典型场景 |
|---|------|---------|
| I01 | System.out.println 残留 | 调试代码未清理 |
| I02 | 日志级别不当 | 正常流程用 ERROR |
| I03 | 魔法数字 | 硬编码的业务常量 |
| I04 | 方法过长 | 单方法 > 50 行 |
| I05 | 参数过多 | 方法参数 > 4 个 |
| I06 | 重复代码 | 相似逻辑未提取 |

## 特定语言附加规则

### Java (Spring)

- BigDecimal 比较必须用 `compareTo`
- Self-call `this.xxx()` 绕过 @Transactional 代理
- @RemoteService 返回值必须判空
- BizException（业务规则违反）vs SysException（系统故障）

### TypeScript/JavaScript

- 禁止 `any` 类型（除非有注释说明原因）
- API 调用必须有错误处理
- 组件必须有 key prop（列表渲染）
- 状态管理：持久化必要数据、及时清理

### Python

- 类型提示必须覆盖公共函数签名
- 异步操作必须有超时设置
- 环境变量必须通过 `.env` 管理，不硬编码
