# AI Workflow Control Kit Productization Guide

本文档说明如何把当前仓库从“个人迁移包”升级为一个更产品化、可分享、可安装、可验证的 AI 驱动研发工作流基础设施仓库。

目标不是分享某个业务项目的实现，也不是分享运行态会话记录，而是分享一套可迁移的控制平面：

- hooks
- skills
- skill-rules.json
- Claude Code / Codex host adapters
- replay-autopilot
- 安装、验证、安全扫描和故障收口脚本

## 推荐仓库定位

推荐对外名称：

```text
AI Workflow Control Kit
```

当前正式 GitHub 仓库名建议使用 `ai-workflow-control-kit`；展示名建议用 `AI Workflow Control Kit`。这个名字比 `skills`、`hooks` 或 `replay-autopilot` 更准确，因为仓库的核心价值不是单个技能，而是把 AI 研发流程变成一套可安装、可审查、可验证、可回滚的控制体系。

一句话定位：

```text
A portable control plane for AI-assisted software delivery: skills, hooks, host adapters, and replay automation.
```

中文定位：

```text
一套可迁移的 AI 研发工作流控制平面，用 hooks、skills、规则路由和 replay 自动评测，把 AI 编码从“凭感觉对话”约束成可验证的工程流程。
```

## 产品边界

应该分享：

| 模块 | 是否分享 | 说明 |
| --- | --- | --- |
| `agents/skills/` | 是 | 通用技能源，包括开发、评审、测试、复盘、replay、平台维护等 |
| `agents/skills/skill-rules.json` | 是 | 技能触发和路由规则 |
| `agents/hooks/` | 是 | 技能激活、执行回执、状态同步等 hook |
| `claude/` | 是 | Claude Code 适配层、hook 脚本、示例配置、命令模板 |
| `codex/` | 是 | Codex 适配层、RTK、hook 脚本、示例配置、规则 |
| `cc-switch/` | 是 | 通用配置模板，但必须使用占位符 |
| `replay-autopilot/` | 是 | 无人值守 replay、评测、反思、失败审计、控制闭环 |
| `scripts/` | 是 | 安装、远程推送、安全扫描、验证脚本 |
| `docs/` | 是 | 架构说明、迁移清单、SOP、故障说明 |

不应该分享：

| 内容 | 原因 |
| --- | --- |
| `.codex/auth.json`、`.claude/settings.json` 里的真实 token | 私密认证 |
| history、sessions、SQLite、cache、logs | 运行态，不可移植 |
| 真实业务仓库代码和 oracle diff | 业务资产，不属于控制平面 |
| 真实个人路径、真实 API key、真实网关 token | 不可分享且不可移植 |
| `.memory/` | 本地个人错误记忆，只代表当前电脑和当前用户 |
| Codex 自动生成的 `.system` 技能 | 宿主运行态，不是仓库源 |

## 推荐目录结构

当前仓库结构已经能工作。产品化时建议保留现有结构，避免大重构：

```text
ai-workflow-control-kit/
  README.md
  agents/
    AGENTS.md
    hooks/
    skills/
      skill-rules.json
      skills-manifest.md
      <skill-name>/SKILL.md
    templates/
  claude/
    hooks/
    rules/
    commands/
    settings.example.json
  codex/
    hooks/
    rules/
    RTK.md
    config.toml.example
  cc-switch/
    common_config_claude.json.template
    common_config_codex.toml.template
  replay-autopilot/
    README.md
    config.yaml
    prompts/
    scripts/
    templates/
    tests/
  scripts/
    Install-AiWorkflowKit.ps1
    Install-CcSwitchCommonConfig.ps1
    Create-RemoteAndPush.ps1
    Test-NoSecrets.ps1
  docs/
    MIGRATION_CHECKLIST.md
    PRODUCTIZATION_GUIDE.md
    SESSION_019e14c6_REPLAY_AUTOPILOT_SOP.md
```

如果后续要进一步产品化成 v2，可以再做一次更清晰的分层：

```text
core/
  skills/
  skill-rules.json
  hooks/
hosts/
  codex/
  claude/
  cc-switch/
control-plane/
  replay-autopilot/
install/
docs/
```

但 v1 不建议立刻改成这种结构，因为当前安装脚本、迁移脚本和运行态链接已经围绕 `agents/`、`codex/`、`claude/` 建好。

## 与 hxld_vault 的关系

产品化仓库不应强依赖 `hxld_vault`。

建议口径：

- `hxld_vault` 可以作为个人知识备份或历史证据库。
- 本仓库必须能在没有 `hxld_vault` 的新电脑上安装。
- `KnowledgeRepo` 只能作为可选参数。
- 如果 `KnowledgeRepo` 不存在，安装脚本应该跳过或提示，而不是失败。
- README 中不要把 `<KNOWLEDGE_ROOT>` 这类本机知识库路径写成必需路径。

推荐安装语义：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -BackupExisting
```

可选知识库参数：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 `
  -KnowledgeRepo "D:\path\to\optional\knowledge-repo" `
  -BackupExisting
```

## README.md 推荐写法

README 的目标不是记录迁移细节，而是让第一次看到仓库的人快速回答四个问题：

1. 这是什么？
2. 它会安装什么？
3. 如何安全安装？
4. 如何验证已经安装成功？

建议 README 使用以下结构。

### 1. 标题和一句话定位

```markdown
# AI Workflow Control Kit

A portable control plane for AI-assisted software delivery: skills, hooks, host adapters, and replay automation.
```

### 2. What It Provides

```markdown
## What It Provides

This repository packages the reusable infrastructure behind an AI-assisted development workflow:

- custom skills and routing rules
- hooks for skill activation, receipts, and workflow state sync
- Claude Code and Codex host adapters
- cc-switch common configuration templates
- replay-autopilot for isolated replay, scoring, reflection, and unattended control loops
- install, verification, and secret-scan scripts
```

### 3. What It Does Not Include

```markdown
## What It Does Not Include

This repository intentionally does not include:

- auth tokens or provider API keys
- Codex or Claude runtime sessions
- SQLite state, cache, logs, history, or local memories
- business project source code
- private oracle diffs or production data
```

### 4. Architecture

````markdown
## Architecture

```text
agents/              Canonical skills, hooks, rules, and templates
claude/              Claude Code adapters and example settings
codex/               Codex adapters, RTK, hooks, and example config
cc-switch/           Portable common config templates
replay-autopilot/    Replay, scoring, reflection, and unattended control loop
scripts/             Install, validation, and remote bootstrap scripts
docs/                Migration checklist and operating guides
```
````

### 5. Quick Start

````markdown
## Quick Start

Run a dry run first:

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -DryRun
```

Install with backup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -BackupExisting
```
````

### 6. Skills Sync Model

```markdown
## Skills Sync Model

`$HOME\.agents\skills` is the canonical custom skill source.

The installer creates:

- `$HOME\.claude\skills` -> `$HOME\.agents\skills`
- `$HOME\.codex\skills` -> `$HOME\.agents\skills`

This keeps Claude Code and Codex on the same skill set while avoiding duplicate maintenance.
```

### 7. Host Integration

```markdown
## Host Integration

Claude Code uses hook-based integration for skill activation and RTK:

- `UserPromptSubmit`
- `Stop`
- `FileChanged`
- `PreToolUse` with `rtk hook claude`

Codex uses `config.toml` for hooks and global `AGENTS.md` / `RTK.md` for RTK guidance.

Do not keep both `$HOME\.codex\hooks.json` and hook definitions in `$HOME\.codex\config.toml`; this can trigger duplicate hook-source warnings.
```

### 8. Replay Autopilot

````markdown
## Replay Autopilot

`replay-autopilot` is the control plane for AI workflow evaluation. It supports:

- isolated worktree replay
- source-of-truth and oracle separation
- round contracts and result reports
- coverage scoring and caps
- stop-and-evolve loops
- failure audit packs
- hard reflection gates
- unattended control cycles

Validate the controller:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Run-UnattendedReplayControl.ps1 -ValidateOnly
```
````

### 9. Security

````markdown
## Security

Before committing or publishing, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-NoSecrets.ps1
```

The repository should contain templates and placeholders only. Real credentials must be restored locally after installation.
````

### 10. New Machine Prompt

````markdown
## New Machine Prompt

After cloning this repository on a new machine, give Codex or Claude Code this prompt:

```text
Read README.md and docs/MIGRATION_CHECKLIST.md in this repository.
Install AI Workflow Control Kit for this machine.

Requirements:
1. Run DryRun first.
2. Back up existing ~/.agents, ~/.codex, and ~/.claude files before overwriting anything.
3. Install agents, hooks, skills, host adapters, cc-switch templates, and replay-autopilot.
4. Do not install auth tokens, real provider keys, runtime sessions, SQLite state, cache, or logs.
5. Keep ~/.agents/skills as the canonical skill source, and link ~/.claude/skills and ~/.codex/skills to it.
6. Run the verification commands from README.
7. Report what succeeded and what still requires manual local credentials or path edits.
```
````

## 产品化路线图

建议按三阶段推进。

### Stage 1: Portable Migration Kit

目标：新电脑可安装。

完成标准：

- README 清楚
- 安装脚本可 dry-run
- `.agents\skills` 作为唯一技能源
- Claude/Codex skills 软链接或 junction 到 `.agents\skills`
- hooks 可安装
- 无敏感信息
- replay-autopilot 可 `ValidateOnly`

### Stage 2: Productized Control Plane

目标：其他项目也能采用。

完成标准：

- 所有项目路径都参数化
- 业务项目规则从通用技能中剥离
- `replay-autopilot/config.yaml` 提供模板和示例
- 支持不同项目 root、需求文档路径、oracle 策略、证据目录
- README 从“迁移”改成“安装和使用”

### Stage 3: Evaluated Workflow Runtime

目标：工作流本身可评测、可演化。

完成标准：

- replay 控制器能生成控制面摘要
- 失败审计包能阻止无效循环
- hard reflection gate 能要求修复全部 must-fix
- 零覆盖或低覆盖不会跨 cycle 空跑
- 技能变更必须有最小 eval 或 no-eval reason
- 每个产品化能力都有回归脚本

## 核心设计原则

1. **控制平面优先**：仓库卖点是约束、验证、复盘和自动评测，不是某个单点 prompt。
2. **运行态隔离**：sessions、history、sqlite、cache、auth 永远不进仓库。
3. **宿主适配分层**：Claude Code、Codex、cc-switch 都是 adapter，不是技能正文。
4. **项目知识下沉**：业务项目特有规则留在业务项目，不污染通用 skill。
5. **安装必须可验证**：README 中每个关键能力都要有验证命令。
6. **无 hxld_vault 强依赖**：知识库可选，控制平面必须独立可运行。
