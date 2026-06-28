---
name: rdc-git
description: 慧择研发中心 Git 规范，包含分支命名、Commit 规范、MR 流程。当用户需要创建分支、提交代码、创建 MR 时使用此技能。
compatibility: 需要 git 命令行工具
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  name-zh: Git 规范
  category: git-workflow
  version: 1.1.1
  author: 陈武才
  email: chenwucai@huize.com
  department: 研发中心
  tags: git,commit,PR,code-review,huize
---

# 慧择 Git 规范

基于慧择研发中心 Git 规范，适用于前端和后端开发。

## 何时使用

- 创建符合规范的分支
- 提交代码并生成规范的 commit message
- 创建 Merge Request
- 查看 Git 状态和变更

---

## 分支规范

### 命名格式

```
[分支类型]-[银河版本号]-[分支备注]
```

要求：分支命名全部**小写**

### 分支类型

| 类型 | 含义 | 备注 |
|------|------|------|
| `feat` | 功能分支 | 一般迭代或者日常 |
| `bug` | 修复分支 | 修复 bug |
| `experiment` | 实验性分支 | 试验新技术等 |
| `wip` | 临时分支 | 不确定类型时使用 |

### 银河版本号

- 一般为英文和数字组合：`BIBD_AT_V1.0.0`、`QX_A_P_v4.6.1`
- 无版本号时：使用需求编号（如 `10489`）或日期（如 `20190103`）
- 临时/实验性分支：可为空

### 示例

```bash
feat-bibd_at_v1.0.0          # 功能分支
feat-bibd_at_v1.0.1_scx      # 带负责人
bug-10564_scx                # Bug 修复
wip-merge_conflict           # 临时分支
```

---

## Commit 规范

### 格式

```
<type>(<scope>): <subject>
```

- **type**: 变更类型（必填）
- **scope**: 影响范围（可选）
- **subject**: 简短描述（必填）

### 常用类型

| 类型 | 描述 |
|------|------|
| `feat` | 新增功能 |
| `fix` | 修复 Bug |
| `refactor` | 重构代码 |
| `perf` | 性能优化 |
| `docs` | 文档相关 |
| `test` | 测试相关 |
| `db` | 数据库变更 |
| `api` | 接口变更 |
| `wip` | 临时提交（满足每天提交要求） |

完整类型列表见 [references/COMMIT_TYPES.md](references/COMMIT_TYPES.md)

### 示例

```bash
feat(user-service): 添加用户注册接口
fix(order-service): 修复订单状态更新问题
db(policy): 添加保单状态索引
wip: 功能开发中
```

---

## MR 规范

### 需要提 MR

- 具有一定复杂度的功能
- 对业务有影响的修改
- 涉及数据库 DDL 变更
- 涉及分布式事务、缓存策略
- 实习试用阶段的同学

### 可以不提 MR

- 线上小 bug 修复
- 日常迭代、图片修改
- 配置文件微调

---

## 重要规则

- **没事别删除分支**
- **每天下班前提交分支**
- 功能未完成使用 `wip` 类型提交

### 禁止操作（除非用户明确要求）

```bash
git push --force origin master/main  # 禁止强推主分支
git reset --hard                      # 禁止硬重置
git clean -f                          # 禁止强制清理
git commit --no-verify                # 禁止跳过 hooks
```

### 安全检查

不提交：`.env`、`credentials.json`、`application-local.yml` 等敏感文件

---

## 安装 Git Hooks

项目提供了 Git hooks 脚本，可自动验证 commit message 格式和检查敏感文件。

```bash
# Unix/Mac/Git Bash
sh scripts/install-hooks.sh

# Windows PowerShell
.\scripts\install-hooks.ps1
```

安装后的 hooks：
- `commit-msg`: 验证 commit message 格式
- `pre-commit`: 检查敏感文件和大文件

---

## 交互流程

### 创建分支

当用户说"创建分支"或"新建分支"时：

| 步骤 | 条件 | 动作 |
|------|------|------|
| 1 | 未提供分支类型 | 询问："请选择分支类型：feat / bug / experiment / wip" |
| 2 | 未提供银河版本号 | 询问："请提供银河版本号或需求编号" |
| 3 | 可选 | 询问："是否添加分支备注？" |
| 4 | 信息完整 | 执行 `git checkout -b <type>-<version>[-<remark>]` |

### 提交代码

当用户说"提交代码"或"commit"时：

| 步骤 | 动作 |
|------|------|
| 1 | 执行 `git status` 和 `git diff` 查看变更 |
| 2 | 分析变更，推荐 commit type |
| 3 | 生成建议的 commit message |
| 4 | 询问用户确认或修改 |
| 5 | 确认后执行提交 |

### 下班提交

当用户说"下班了"或"代码没写完"时：

自动执行：
```bash
git add .
git commit -m "wip: <简要描述>"
git push
```

---

## 示例对话

### 创建分支（引导式）

```
用户: 创建分支

助手: 请选择分支类型：
- feat - 功能分支
- bug - 修复分支
- experiment - 实验性分支
- wip - 临时分支

用户: feat

助手: 请提供银河版本号或需求编号：

用户: BIBD_AT_V2.0.0

助手: 是否添加分支备注？（可跳过）

用户: scx

助手: git checkout -b feat-bibd_at_v2.0.0_scx
分支已创建。
```

### 提交代码

```
用户: 提交代码

助手: 检查变更...
- 修改了 UserService.java（添加用户注册方法）
- 新增了 RegisterRequest.java

建议: feat(user-service): 添加用户注册接口

确认提交吗？

用户: 确认

助手: 已提交。
```

### 下班提交

```
用户: 下班了，代码没写完

助手: 好的，用 wip 类型提交：
git add .
git commit -m "wip: 用户注册功能开发中"
git push

已提交并推送。
```
