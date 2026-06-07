# Stop Reason Examples

每种停止原因的真实案例，帮助判断当前状态。

## completed

**场景：** 用户说"请你独自完成用户注册功能"
**过程：** 预检查通过 → 需求扫描 → 实现代码 → 测试通过 → Handoff Summary
**输出：**
```
## Handoff Summary
- 新增: UserService.register(), UserValidator
- 测试: 5/5 通过 (正常/空/重复/null/边界)
- 修改: 3 files, +156/-12 lines
- 遗留: 无
```

## max_turns_reached

**场景：** 功能拆分为8个子任务，完成6个后达到步数上限
**输出：**
```
## 暂停: 达到步数上限
- 已完成: 6/8 子任务
- 剩余: [子任务7: 邮件通知, 子任务8: 日志记录]
- 建议: 继续完成剩余任务
```

## retry_limit

**场景：** 测试修复循环3次仍失败
**输出：**
```
## 暂停: 修复上限
- 失败测试: testRegister_duplicateEmail
- 已尝试: 3次修复
- 根因: 数据库唯一约束名称不一致
- 建议: 手动检查 schema
```

## gate_failed

**场景：** Iron Law 触发（未运行 pre-flight-check）
**输出：**
```
## 暂停: Iron Law
- 原因: 预检查未执行
- 触发规则: 修改2+文件前必须读取 MEMORY.md
- 行动: 执行 pre-flight-check 后继续
```

## DONE_WITH_CONCERNS

**场景：** 功能完成但有遗留问题
**输出：**
```
## 完成（有遗留）
- 功能: 用户注册 ✅
- 测试: 4/5 通过 (邮件通知测试跳过 - SMTP不可用)
- 遗留: 邮件通知需在集成环境验证
- 推荐: `compound-learning` 记录环境差异
```

## NEEDS_CONTEXT

**场景：** 发现隐藏需求但无法自行判断
**输出：**
```
## 暂停: 需要更多信息
- 问题: 注册是否需要手机号验证？
- 影响: UserService 需要额外依赖 SmsService
- 等待: 用户确认
```

## BLOCKED

**场景：** 依赖的服务不可用
**输出：**
```
## 暂停: 被阻塞
- 原因: UserValidator 依赖的 rules-service 无响应
- 已尝试: 1. 检查配置 2. 换策略(本地缓存规则)
- 升级: 需人工确认 rules-service 状态
```
