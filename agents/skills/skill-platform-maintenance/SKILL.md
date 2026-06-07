---
name: skill-platform-maintenance
description: "Use when user says 技能平台维护, 同步技能, 更新技能, update plugins, sync skills, hook 报错, settings 报错, OpenCode/Claude Code/Cursor 技能不同步, duplicate skill, MCP error, or asks to repair custom skill platform activation"
allowed-tools: Bash
---

# 技能平台维护

保持自定义技能在多平台宿主中可发现、可触发、可验证，并在 hook/settings/MCP/重复技能故障时做结构化排查。

**专家角色：** 工具链工程师 — 维护技能分发、宿主配置和运行时健康。

**下游技能：** 所有技能（间接 — 保持工具最新）

---

## 迭代位置

```
[思考] → [规划] → [构建] → [审查] → [测试] → [发布] → [复盘]
             ↑
      不适用 — 基础设施维护，不是功能迭代的一部分
```

---

## 何时使用

- "更新插件" / "更新claude插件"
- "update plugins" / "upgrade plugins"
- "同步技能" / "更新技能" / "sync skills"
- Claude Code / OpenCode / Cursor 的 hook、settings、插件、技能触发或权限报错。
- 平台日志出现 `duplicate skill`、`MCP error`、schema 校验失败、会话发送失败或技能不同步。

## 何时不使用

- 没有安装插件
- 用户想更新特定插件（只更新那个，但仍做对应健康检查）
- 业务代码构建/测试失败（用 `gen-tests` FIX 或 `dev-workflow`）
- 生产应用日志调查（用 `log-investigator`）

---

## 常见陷阱（先读这个！）

| 失败 | 预防 |
|------|------|
| 硬编码路径 → 在其他机器失败 | 总是动态检测路径 |
| Git pull 时冲突 | 工作区不干净时暂停，绝不自动丢弃本地改动 |
| npm 不在 PATH | 用 `which npm` 或 `where npm` |
| 错误分支（main vs master）| 先试 main，回退到 master |
| 只复制文件不看宿主日志 | 同步后必须检查平台加载日志或健康输出 |
| 在镜像侧手修技能 | 先确认 canonical source，再由 source 同步 |
| shell 写法跨平台失效 | 验证 shell、路径引用、编码、stdin 和 JSON 转义 |

---

## 红旗警告（停止）

| 想法 | 为什么错 |
|------|----------|
| "一次全部更新" | 一个一个更新，逐个验证 |
| "跳过备份" | 更新前总是保存工作 |
| "强制更新" | 冲突 = 调查，不要强制 |
| "先清空本地改动再说" | 未经授权不得丢弃工作区改动 |
| "日志里只是 warning，可以忽略" | `duplicate skill` 会让运行版本不确定 |
| "settings 看起来差不多" | 宿主 schema 不同，必须用目标平台格式验证 |

---

## 术语约定（本技能）

- **Hard Gate（硬门槛）**：工作区不干净、pull 冲突、状态不可读、source/mirror 不明、schema 未验证、运行日志仍有重复技能等都属于 Hard Gate，未通过不得宣称“已更新/已修复”
- **PARTIAL**：本技能不使用 `PARTIAL` 表示更新状态；逐项插件状态用真实成功/失败/跳过表达
- **完成标准（DoD）**：统一表示“source/mirror 清楚、同步完成、schema 通过、宿主健康检查无阻断、剩余 warning 已分类”
- **验证范围**：在本技能中表示本次覆盖到哪些平台、插件、hook、settings、日志和 marketplace，不表示业务测试范围

## Iron Law

- 修改技能内容只改 canonical source；镜像、宿主副本、备份只能由 source 同步生成。
- canonical source 有变更时，source → 知识库备份 → changelog/历史记录 → hash 校验 → 备份仓库 commit → push 当前 upstream 分支，是同一个收口链；任一环失败不得宣称技能更新完成。
- 平台故障先冻结 `platform -> config file -> schema/version -> shell -> path quoting -> stdin/stdout encoding -> JSON escaping -> runtime log -> health result`，不得凭单条报错盲改。
- 看到 `duplicate skill`、schema 错误、hook 启动失败、会话发送失败时，先判定是宿主配置问题还是技能内容问题；禁止把宿主故障写成业务技能缺陷。

## 检测

1. **canonical source**：自定义技能唯一源头、治理文件、manifest / rules 文件。
2. **宿主镜像**：Claude Code、OpenCode、Cursor、Codex 等平台的技能目录、hook 目录和配置文件。
3. **插件目录**：平台插件/marketplace 目录。
4. **包管理器与 shell**：`which/where npm`、`node`、`powershell/pwsh/bash` 是否存在。
5. **运行日志**：平台启动日志、doctor/health 输出、hook 执行日志、MCP/skill loader warning。

---

## 工作流程

```
[1] 确认模式
    ├── SYNC：更新/同步技能、插件、hooks
    └── TROUBLESHOOT：hook/settings/MCP/duplicate skill/发送失败
    ↓
[2] 源头治理检查
    ├── canonical source / mirror / backup
    └── 未确认 source → STOP
    ↓
[3] 同步或故障排查
    ├── SYNC → 复制/更新 → hash/mtime 校验
    └── TROUBLESHOOT → schema/shell/path/stdin/JSON/log 逐层定位
    ↓
[4] 知识库备份收口（canonical source 有变更时必做）
    ├── 定位知识库备份根与 Git 仓库
    ├── 工作区不干净或无 upstream → STOP，报告用户
    ├── 同步 source 到 backup → 更新 changelog/历史记录 → hash 校验
    └── commit + push 当前 upstream 分支；失败 → BLOCKED
    ↓
[5] 更新 git 仓库（每个 marketplace）
    ├── 工作区不干净 → STOP，报告用户
    ├── pull 成功后检查 status/log
    └── 任一验证失败 → 不得宣称更新完成
    ↓
[6] 宿主健康检查
    ├── 技能重复加载 / stale mirror / nested copy
    ├── settings/hook schema
    ├── MCP 能力协商
    └── 会话发送/技能触发最小探针
    ↓
[7] 输出逐平台摘要
```

---

## 命令

```bash
# 检测 npm
NPM=$(which npm 2>/dev/null || where npm 2>/dev/null)

# 更新 npm 包
$NPM update -g @scope/package 2>/dev/null || echo "未安装"

# 更新 git 仓库
cd ~/.claude/plugins/marketplaces/<name>
git status --short
git pull origin main || git pull origin master
git status --short
git log -1 --oneline
```

**硬规则：**

- 检测到未提交本地改动、冲突文件、未知状态时，默认停止并报告，禁止 `git checkout .`
- 备份仓库提交只包含 source 同步结果、技能 changelog/历史记录和必要 manifest；不得混入无关知识库漂移。
- push 只推送当前分支到已配置 upstream；禁止 force push，禁止替用户创建远程分支，除非用户明确要求。
- 只有当工作区干净、pull 成功、无冲突、最新提交可读时，才允许报告该插件“已更新”
- 任一插件更新失败，不得输出整体“✅ 插件已更新”，必须逐项报告真实状态
- 同步后若平台日志仍出现同名技能重复，必须输出 `skill name -> canonical -> duplicate path -> resolution`。
- hook/settings 故障必须先验证目标平台 schema，再改命令；Windows 重点检查 `powershell` vs `pwsh`、反斜杠转义、UTF-8、空 stdin 和 JSON 反序列化。
- MCP 报 `prompts/list` / `Method not found` 时，先分类为能力协商不匹配或启动阻断；若核心会话和工具调用正常，不升级为业务阻断。
- 会话无法发送、hook 阻断、权限阻断属于平台可用性 P0；仅有非阻断 warning 时可标为 P2，但必须披露。

---

## 输出格式

```markdown
## 平台技能维护结果

| 平台/插件 | 模式 | 状态 | 证据 | 剩余风险 |
|-----------|------|------|------|----------|
| Claude Code | SYNC | DONE/BLOCKED | hash/log/doctor | [...] |
| OpenCode | TROUBLESHOOT | DONE/BLOCKED | log probe | [...] |

### 健康矩阵
- source/mirror:
- knowledge backup:
- changelog/history:
- backup git:
- duplicate skill:
- settings schema:
- hook execution:
- MCP capability:
- minimal trigger probe:
```

---

## 验证标准

| 检查项 | 验证方法 |
|--------|----------|
| 插件目录存在 | `ls ~/.claude/plugins/` |
| Git pull 成功 | 检查命令返回码 = 0 |
| 无冲突文件 | `git status` 无 "both modified" |
| 版本已更新 | `git log -1 --oneline` |
| 工作区干净 | `git status --short` 为空 |
| source/mirror 一致 | hash 或内容摘要一致 |
| 无重复技能 | loader 日志无 `duplicate skill`，或已列清 cleanup plan |
| settings/hook schema | 平台 doctor/validate 或 JSON/TOML 解析通过 |
| hook 可执行 | shell 存在、路径引用正确、stdin/JSON/编码探针通过 |
| MCP warning 分类 | 启动阻断 / 非阻断能力缺口已区分 |

---

## 失败处理

| 失败类型 | 处理 |
|----------|------|
| npm 不在 PATH | 跳过 npm 更新，报告警告 |
| git pull 冲突 | 停止该插件更新，报告冲突，等待用户处理 |
| 目录不存在 | 跳过并记录 |
| 网络超时 | 重试一次，仍失败则跳过 |
| schema 错误 | 用目标平台格式重建最小配置，验证后再合并 |
| shell 不存在 | 切换到实际存在的 shell，保留跨平台注释 |
| 路径/JSON 转义错误 | 用单一编码与转义规则重放最小输入 |
| 空 stdin / hook 阻断 | 加空输入保护，确认非阻断与阻断状态 |
| duplicate skill | 删除或隔离非 canonical 副本，重新加载后看日志 |
| MCP 方法不存在 | 分类为非阻断能力协商或版本不匹配，必要时升级插件 |

---

## 注意

- 更新前保存工作
- 如更新失败，继续其他的，最后报告
- 检查插件文档了解破坏性变更
- 不把平台同步、hook、MCP、权限和代理问题写进业务项目规则。
