# AI Workflow Control Kit

A portable control plane for AI-assisted software delivery: skills, hooks, host adapters, and replay automation.

AI Workflow Control Kit packages the reusable infrastructure behind an AI-assisted development workflow. It is designed to make AI coding less dependent on ad hoc conversation and more dependent on explicit gates, executable evidence, review loops, and replay-based evaluation.

## What It Provides

- Custom skills and skill routing rules.
- Hooks for skill activation, receipts, and workflow state sync.
- Claude Code and Codex host adapters.
- cc-switch common configuration templates.
- RTK integration guidance for token-aware shell usage.
- replay-autopilot for isolated replay, scoring, reflection, and unattended control loops.
- Install, validation, and secret-scan scripts.

## What It Does Not Include

This repository intentionally does not include runtime or private state:

- auth tokens or provider API keys
- Codex or Claude runtime sessions
- SQLite state, cache, logs, history, or local memories
- business project source code
- private oracle diffs or production data
- machine-specific `.env` files

## Architecture

```text
agents/              Canonical skills, hooks, rules, and templates
claude/              Claude Code adapters and example settings
codex/               Codex adapters, RTK, hooks, and example config
cc-switch/           Portable common config templates
replay-autopilot/    Replay, scoring, reflection, and unattended control loop
workflow-history/    Repository-local workflow change index and records
scripts/             Install, validation, and remote bootstrap scripts
docs/                Migration, productization, and operating guides
```

## Quick Start

Run a dry run first:

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -DryRun -BackupExisting
```

Install with backups:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AiWorkflowKit.ps1 -BackupExisting
```

## Skills Sync Model

`$HOME\.agents\skills` is the canonical custom skill source.

The installer creates:

- `$HOME\.claude\skills` -> `$HOME\.agents\skills`
- `$HOME\.codex\skills` -> `$HOME\.agents\skills`

This keeps Claude Code and Codex on the same skill set while avoiding duplicate maintenance.

Runtime-generated Codex `.system` skills are not vendored. They may appear locally after Codex starts, and that is expected runtime behavior.

## Host Integration

Claude Code uses hook-based integration for skill activation and RTK:

- `UserPromptSubmit`
- `Stop`
- `FileChanged`
- `PreToolUse` with `rtk hook claude`

Codex uses `config.toml` for hooks and global `AGENTS.md` / `RTK.md` for RTK guidance.

Do not keep both `$HOME\.codex\hooks.json` and hook definitions in `$HOME\.codex\config.toml`; this can trigger duplicate hook-source warnings.

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

## Workflow History

`workflow-history/CHANGELOG.md` is the built-in master index for this kit's workflow changes. Each concrete change lives under `workflow-history/changes/`, and `workflow-history/latest.json` points to the newest entry.

`replay-autopilot` discovers the latest workflow version from `workflow-history` first, then falls back to legacy history locations for older installations. This keeps the clean repository self-contained and avoids a hard dependency on a personal knowledge base such as `hxld_vault`.

Key regression checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Test-v372-UnattendedControlLoop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\replay-autopilot\scripts\Test-v470-FailureAuditPackAndHardReflection.ps1
```

## Security

Before committing or publishing, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-NoSecrets.ps1
```

The repository should contain templates and placeholders only. Real credentials must be restored locally after installation.

## New Machine Prompt

After cloning this repository on a new machine, give Codex or Claude Code this prompt:

```text
Read README.md and docs/MIGRATION_CHECKLIST.md in this repository.
Install AI Workflow Control Kit for this machine.

Requirements:
1. Run DryRun with BackupExisting first.
2. Back up existing ~/.agents, ~/.codex, and ~/.claude files before overwriting anything.
3. Install agents, hooks, skills, host adapters, cc-switch templates, and replay-autopilot.
4. Do not install auth tokens, real provider keys, runtime sessions, SQLite state, cache, or logs.
5. Keep ~/.agents/skills as the canonical skill source, and link ~/.claude/skills and ~/.codex/skills to it.
6. Run the verification commands from README.
7. Report what succeeded and what still requires manual local credentials or path edits.
```

## Optional Knowledge Repository

This kit does not require `hxld_vault` or any other personal knowledge repository.

If a knowledge backup repository exists, pass it as an optional install parameter. If it does not exist, the workflow kit should still install and run.
