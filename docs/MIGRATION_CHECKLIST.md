# Migration Checklist

## 1. Clone

```powershell
git clone https://github.com/hxld/ai-workflow-control-kit.git
cd ai-workflow-control-kit
```

如果远程仓库还没有创建，先在已有本地仓库中执行：

```powershell
$env:GH_TOKEN = "<your github token>"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Create-RemoteAndPush.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Create-RemoteAndPush.ps1
```

## 2. Dry Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -DryRun
```

确认输出的目标路径无误。

## 3. Install With Backup

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -BackupExisting
```

脚本会把被覆盖的现有文件备份到：

```text
<target>.backup-YYYYMMDD-HHMMSS
```

安装后 `$HOME\.codex\skills` 和 `$HOME\.claude\skills` 必须是指向 `$HOME\.agents\skills` 的目录链接。通用技能只维护 `$HOME\.agents\skills`。Codex 自带 `.system` 是运行态内置技能，可能被自动生成，不需要手动删除；但不要把它提交进仓库。`update-claude-plugins` 不作为通用技能放进 `.agents\skills`。

如果新电脑使用 cc-switch，安装脚本会在发现 `$HOME\.cc-switch\cc-switch.db` 且使用 `-BackupExisting` 时，写入 Claude / Codex 的通用配置模板。仓库模板只能包含 `<USERPROFILE>`、`<USERPROFILE_SLASH>`、`<CLAIM_PROJECT_ROOT>` 等占位符，不能包含真实 API key、个人用户名路径或 provider token。

Codex hooks 应统一写在 `config.toml` / cc-switch common config。若 `$HOME\.codex\hooks.json` 存在，安装脚本会备份改名，避免 Codex 启动时报 hook 双来源告警。默认 Codex 配置不启用 PowerShell `codex-skill-adapter.ps1` 的 `UserPromptSubmit` hook，先降低 Windows PowerShell 5.1 的 `R6016` 风险。

## 4. Manual Secrets

手动补齐：

- `$HOME\.codex\auth.json`
- `$HOME\.claude\settings.json` 中的真实 env token
- cc-switch provider 自身的 API key / token / base url
- `$HOME\.agents\skills\log-investigator\.env` 中的账号、密码、token 占位符
- 本机路径，例如 `D:\opt\claim`、`D:\maven\settings\settings.xml`

## 5. Validate

```powershell
Test-Path "$HOME\.agents\skills"
(Get-Item "$HOME\.codex\skills").Target
(Get-Item "$HOME\.claude\skills").Target
Test-Path "$HOME\.agents\skills\update-claude-plugins" # 应为 False
Test-Path "$HOME\.agents\skills\.system"               # 可为 True；Codex 运行态内置技能
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CcSwitchCommonConfig.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File D:\opt\replay-autopilot\scripts\Run-UnattendedReplayControl.ps1 -ValidateOnly
powershell -NoProfile -ExecutionPolicy Bypass -File D:\opt\replay-autopilot\scripts\Test-v372-UnattendedControlLoop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\opt\replay-autopilot\scripts\Test-v470-FailureAuditPackAndHardReflection.ps1
```

## 6. First Codex Session On New Machine

给 Codex：

```text
请检查我的 AI workflow control kit 是否安装成功。
读取 ~/.agents/AGENTS.md、~/.codex/RTK.md、~/.codex/config.toml、~/.claude/settings.json、D:\opt\replay-autopilot\config.yaml。
不要读取 auth/token/session/history/sqlite。
验证 hooks、skills、replay-autopilot 的关键路径，并输出需要我手动补的配置。
```

## 7. Ongoing Sync

本地修改后：

```powershell
git status
git add .
git commit -m "chore: sync workflow kit"
git push origin main
```
