# Comment Examples

Long examples live here so `SKILL.md` stays focused on execution rules.

## Good: layered comments

```java
/**
 * 用户服务。
 * <p>
 * <b>核心职责：</b>处理用户注册、登录、信息更新等核心操作。
 * </p>
 */
@Service
public class UserService {

    /**
     * 验证用户名格式。
     * <p>
     * <b>规则：</b>长度4-20位，必须包含字母和数字。
     * </p>
     *
     * @param username 用户名
     * @return true=有效，false=无效
     */
    public boolean isValidUsername(String username) {
        if (username == null || username.length() < 4 || username.length() > 20) {
            return false;
        }
        // Why: 防止 SQL 注入和用户名枚举攻击。
        return username.matches("^[a-zA-Z0-9]+$");
    }
}
```

Why it works:

- L1 class comment explains responsibility.
- L2 method comment explains rule and contract.
- L3 inline comment only explains a security reason.
- It avoids comments like `// 检查长度` or `// 正则匹配`.

## Bad: redundant line comments

```java
/**
 * 验证用户名。
 */
public boolean isValidUsername(String username) {
    // 检查用户名是否为空
    if (username == null) {
        return false;
    }
    // 检查用户名长度
    if (username.length() < 4 || username.length() > 20) {
        return false;
    }
    // 使用正则表达式匹配
    return username.matches("^[a-zA-Z0-9]+$");
}
```

Problem:

- The method comment does not explain the design decision.
- Inline comments repeat code.
- The code is already readable.

## Bad: comments that restate code

```java
// 遍历用户列表
for (User user : users) {
    // 调用保存方法
    userService.save(user);
    // 打印日志
    log.info("用户已保存");
}
```

Problem: every comment describes WHAT the code already shows.

## Good: explaining WHY

```java
// 重试 3 次并退避，因为外部 API 偶发超时，但调用方仍要求尽量完成同步。
for (int i = 0; i < 3; i++) {
    try {
        api.call();
        break;
    } catch (Exception e) {
        Thread.sleep(1000 * (i + 1));
    }
}
```

## Good: explaining verification boundary

```java
// 这里只复验 testCompile 阶段，因为本次改动只影响测试编译链路；
// 若直接宣称全量通过，会掩盖仍未验证的 package 风险。
verifyTestCompileOnly();
```

## Language Format Quick Reference

Java/Kotlin:

```java
/** [一行描述] */
public void method() {
    // Why: [解释]
}
```

TypeScript/JavaScript:

```typescript
/** [一行描述] */
function method() {
    // Why: [解释]
}
```

Python:

```python
def method():
    """[一行描述]."""
    # Why: [解释]
```
