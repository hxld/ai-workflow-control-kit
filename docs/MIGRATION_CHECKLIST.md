# Migration Checklist

This checklist is for installing AI Workflow Control Kit on a new Windows machine.

## 1. Clone

```powershell
git clone https://github.com/hxld/ai-workflow-control-kit.git
cd ai-workflow-control-kit
```

## 2. Check Prerequisites

Required:

- Git
- Node.js
- Codex or Claude Code

Recommended:

- Python, required only when updating `cc-switch.db`
- PowerShell 7 (`pwsh`), required only for legacy replay scripts or one-off Windows maintenance
- cc-switch, required only when using shared Claude/Codex common config
- rtk, required for the Claude `PreToolUse` hook path
- uv, bun, ffmpeg, and openspec if your skills call them

## 3. Dry Run

```bash
node scripts/install-ai-workflow-kit.js --dry-run --backup-existing
```

Confirm the target paths before installing. The default replay-autopilot target is:

```text
$HOME\.ai-workflow-control-kit\replay-autopilot
```

Use `-ReplayAutopilotRoot D:\opt\replay-autopilot` only if that is your intended local convention.

## 4. Install With Backup

```bash
node scripts/install-ai-workflow-kit.js --backup-existing
```

The script backs up replaced files or directories as:

```text
<target>.backup-YYYYMMDD-HHMMSS
```

After installation:

- `$HOME\.agents\skills` is the canonical custom skill source.
- `$HOME\.codex\skills` should link to `$HOME\.agents\skills`.
- `$HOME\.claude\skills` should link to `$HOME\.agents\skills`.
- Codex runtime `.system` skills may appear locally after Codex starts; do not vendor them.
- `update-claude-plugins` is not a generic skill and should not be placed under `.agents\skills`.
- Codex hooks should live in `config.toml` or cc-switch common config, not both `config.toml` and `hooks.json`.
- Claude `UserPromptSubmit` should use the Node hook at `$HOME\.agents\hooks\skill-activation-prompt.js`, not Windows PowerShell 5.1.

## 5. cc-switch

If `$HOME\.cc-switch\cc-switch.db` exists and you install with `-BackupExisting`, the installer writes portable Claude and Codex common config templates into cc-switch.

The templates use placeholders such as `<USERPROFILE>` and `<CODEX_HOME_SLASH>`. They must not contain real API keys, provider tokens, or machine-specific private paths.

Project trust entries are intentionally not preconfigured. Add trusted projects when a real project first needs them.

## 6. Manual Secrets

Restore secrets from your password manager or provider login flow, not from this repository:

- `$HOME\.codex\auth.json`
- provider API keys or base URLs in cc-switch
- real Claude Code environment tokens
- project-specific `.env` files
- skill-specific private credentials, such as log-investigator account details

## 7. Verify

Run the built-in verifier:

```bash
node scripts/verify-ai-workflow-kit.js
```

Run the repository checks:

```bash
node scripts/test-no-secrets.js
node scripts/verify-ai-workflow-kit.js
```

Legacy replay controllers are still PowerShell scripts. Prefer `pwsh` when running them:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Run-UnattendedReplayControl.ps1 -ValidateOnly
```

Optional replay regression checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Test-v372-UnattendedControlLoop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Test-v470-FailureAuditPackAndHardReflection.ps1
```

## 8. First Codex Session On New Machine

Give Codex this prompt after installation:

```text
Please verify my AI Workflow Control Kit installation.

Read README.md and docs/MIGRATION_CHECKLIST.md from the cloned repository.
Inspect ~/.agents/AGENTS.md, ~/.codex/RTK.md, ~/.codex/config.toml, ~/.claude/settings.json, and the installed replay-autopilot config if they exist.
Do not read auth, token, session, history, sqlite, cache, or log files.
Verify skills, skill-rules.json, hooks, symlink/junction targets, cc-switch common config if present, and replay-autopilot ValidateOnly.
Report what succeeded and what still needs manual credentials or project-specific path edits.
```

## 9. Ongoing Sync

When changing reusable workflow behavior:

```powershell
git status
git add <changed-files>
git commit -m "chore: sync workflow kit"
git push origin main
```

Also update `workflow-history/CHANGELOG.md`, `workflow-history/latest.json`, and a concrete change record under `workflow-history/changes`.
