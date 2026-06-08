# RTK - Rust Token Killer (Codex CLI)

RTK is useful for reducing noisy command output before it reaches the model context. Use it selectively.

## Rule

Prefer RTK for high-volume, read-only output where token reduction helps.

On Windows, prefer direct executables for build, test, package-manager, Git, Node, Python, Maven, npm, pnpm, bun, uv, and similar toolchain commands.

Do not wrap commands with Windows PowerShell.

Avoid:

```bash
rtk proxy powershell ...
rtk run powershell ...
powershell -Command ...
powershell.exe -Command ...
```

Prefer:

```bash
git status
node scripts/verify-ai-workflow-kit.js
python script.py
mvn.cmd -s D:/maven/settings/settings.xml -Dmaven.repo.local=D:/maven/repo -f D:/path/to/project/pom.xml test
npm test
pnpm test
bun test
```

Good RTK use cases:

```bash
rtk git status
rtk read README.md
rtk grep "pattern" .
rtk test npm test
rtk gain
```

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk proxy <cmd>     # Track raw command usage only when it does not invoke Windows PowerShell
```

## Verification

```bash
rtk --version
rtk gain
where rtk
```
