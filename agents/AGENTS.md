# Custom Skills Governance

This file is the local operating agreement for custom skills. Read it before editing, auditing, syncing, or publishing skills.

## Canonical Source

- Canonical source directory: `%USERPROFILE%\.agents\skills`
- Canonical skill file: `%USERPROFILE%\.agents\skills\<skill>\SKILL.md`
- Root-level governance files in `%USERPROFILE%\.agents\skills` are also source files:
  - `skills-manifest.md`
  - `skill-rules.json`

## Mirror / Host Rule

- Other platform copies are mirrors or distribution targets, not the source of truth.
- Do not edit mirrored skill copies directly when the source exists.
- If a mirror differs from the source, update the source first, then sync outward.
- External methodology can be absorbed into custom skills, but external skill names must not become local downstream dependencies unless the skill actually exists as a custom source skill.

## Workflow History

- Repository-local workflow index: `workflow-history\CHANGELOG.md`
- Concrete change records: `workflow-history\changes\vNNN-*.md`
- Latest pointer: `workflow-history\latest.json`
- External knowledge repositories are optional mirrors. Do not make skills, hooks, or replay control depend on a machine-local vault path.

## Remote Submission

- `%USERPROFILE%\.agents` is the runtime source and may not be a Git repository.
- When the user asks to submit workflow-kit changes, commit and push this repository unless the user explicitly names another repository.
- Do not commit unrelated project worktrees as part of a skill evolution submission.
- The commit should include source changes and a matching `workflow-history` entry when the change affects reusable workflow behavior.

## Required Change Procedure

When modifying source skills:

1. Edit only the canonical source under `%USERPROFILE%\.agents\skills`.
2. Keep generic skill text project-neutral. Project names, repository paths, class names, table names, business incidents, and team-specific commands belong in repository rules or project memory, not generic skills.
3. If the change should be shared through this kit, copy the changed source files into the repository copy under `agents\skills`.
4. Update `workflow-history\CHANGELOG.md`, `workflow-history\latest.json`, and a concrete file under `workflow-history\changes`.
5. Verify the repository copy matches the intended source changes.
6. Run a project-specific pollution scan on changed `SKILL.md` files before calling the work complete.

## Normal Workflow vs Replay / Eval

- Normal development workflow should stay lightweight and risk-scaled.
- Replay / eval / skill-audit workflow may add stricter controls: isolated worktree, oracle separation, source-of-truth classification, and replay disclosure.
- Do not push replay-only rules into normal development unless the rule is broadly useful outside replay.

## Completion Rule

Do not say a skill change is complete until the runtime source, repository copy, and workflow-history entry have all been updated or an explicit blocker is reported.
