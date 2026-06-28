---
name: project-context-compiler
description: Compile or refresh AI-readable project context packs from an existing local repository. Use when Codex needs to onboard to a project, strengthen weak .doc context, create or update project root AGENTS.md/CLAUDE.md guidance, summarize architecture and core workflows, or turn local source/docs/database metadata into a lightweight project knowledge base before analysis, debugging, planning, or implementation.
---

# Project Context Compiler

Build a project-local context pack that helps future AI sessions understand the project quickly without depending on external graph tools.

## Core Rule

Keep methodology in this skill. Keep project facts in the target project's `.doc/` and root guidance files.

Do not place project names, absolute repo paths, class names, table names, business incidents, or team-only commands in this generic skill. Those belong in the project being compiled.

## Operating Modes

Choose the smallest useful level:

| Level | Output | Use when |
| --- | --- | --- |
| L0 root entry | `AGENTS.md` and `CLAUDE.md` point to existing docs | A project already has useful `.doc` context but sessions miss it |
| L1 starter context | `README.md`, `项目AI上下文指南.md`, `项目总分析报告.md` | The project has weak or missing AI context |
| L2 working context | add module map, workflow index, data/config index | AI must support real debugging, planning, and code changes |
| L3 expert context | add state dictionary, investigation guide, impact guide | The project is high-frequency, cross-system, or operationally risky |

Prefer L0/L1 first. Expand only when a real task exposes a knowledge gap.

## Workflow

1. Locate the project root from the current working directory:
   - Prefer `git rev-parse --show-toplevel`.
   - If unavailable, use the current directory only when it contains source roots or project manifests.
2. Read local instructions first:
   - `AGENTS.md`, `CLAUDE.md`, README files, `.doc/README.md`, and existing `.doc/*-system-context/README.md`.
3. Classify current context maturity:
   - `strong`: root guidance exists and points to current context docs.
   - `partial`: docs exist but root guidance, entry order, or evidence rules are missing.
   - `missing`: no useful `.doc` context exists.
4. Build the minimum context pack:
   - L0 for `strong` or `partial` projects with good docs.
   - L1 for `missing` projects.
   - L2/L3 only after the user asks to deepen context or a task needs it.
5. Gather evidence with lightweight local commands:
   - Use `rg --files` and targeted `rg -n`.
   - Read manifests such as `pom.xml`, `package.json`, build files, and route/config files.
   - Exclude generated folders such as `target/`, `node_modules/`, `dist/`, `build/`, logs, and binaries.
6. Write conclusions with evidence status:
   - `源码已验证`: backed by current source or manifests.
   - `文档已记录`: backed by existing docs but not rechecked in source.
   - `高可信推断`: inferred from names, structure, and multiple weak signals.
   - `待配置/日志/生产确认`: depends on runtime config, data, logs, or external owners.
7. Update project changelog when project context changes:
   - Prefer `.doc/changelog.md` if present.
   - Keep entries short: date, files changed, and why.

## Root Guidance Contract

When creating or refreshing `AGENTS.md` and `CLAUDE.md`, keep them short and practical:

- language preference
- project-local `.doc` read order
- key business identifiers or runtime boundaries
- recommended search commands
- evidence layering rule: read docs first, verify source before code changes
- local-only or submit policy if the project uses local AI docs

`AGENTS.md` and `CLAUDE.md` should be equivalent unless the host requires different syntax.

## Context Pack Contract

For an L1 starter context, create:

```text
.doc/
  <project>-system-context/
    README.md
    项目AI上下文指南.md
    项目总分析报告.md
  changelog.md
```

For L2/L3 details and templates, read `references/context-pack-contract.md`.

## Safety

- Default to read-only until the user asks to create or refresh context files.
- Do not modify business code while compiling context.
- Do not copy secrets, passwords, tokens, connection strings, or production credentials into `.doc`.
- Mark database relations as inferred unless physical constraints or schema evidence prove otherwise.
- Do not claim runtime behavior from directory existence alone. Check build manifests, runtime dependencies, route registration, config, or startup modules.

## Completion

Finish with:

- files created or changed
- context level achieved per project
- known gaps
- next recommended deepening step
