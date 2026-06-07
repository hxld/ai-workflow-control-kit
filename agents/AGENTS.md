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

## Knowledge Base Backup

- Backup root: `D:\study\hxld_vault\learning\raw\sources\ai-knowledge`
- Skill backup mirror: `D:\study\hxld_vault\learning\raw\sources\ai-knowledge\custom-skills-zh`
- Main guide / changelog entry point: `D:\study\hxld_vault\learning\raw\sources\ai-knowledge\custom-skills-guide.md`
- Section changelog: `D:\study\hxld_vault\learning\raw\sources\ai-knowledge\guide-sections\changelog.md`

## Remote Submission

- `%USERPROFILE%\.agents` is the runtime source and may not be a Git repository.
- When the user asks to submit skill changes to a remote repository, commit and push the knowledge-base backup repository after source-to-backup sync, unless the canonical source directory itself is explicitly a Git repository.
- Do not commit unrelated project worktrees as part of a skill evolution submission.
- The commit must include the synced backup files and changelog entries, and the final report must name the pushed branch and remote.

## Required Change Procedure

When modifying source skills:

1. Edit only the canonical source under `%USERPROFILE%\.agents\skills`.
2. Keep generic skill text project-neutral. Project names, repository paths, class names, table names, business incidents, and team-specific commands belong in repository rules or project memory, not generic skills.
3. Sync changed source skills and root governance files to `custom-skills-zh`.
4. Update both changelog surfaces:
   - `custom-skills-guide.md`
   - `guide-sections\changelog.md`
5. Verify the backup mirror matches the source for changed files.
6. Run a project-specific pollution scan on changed `SKILL.md` files before calling the work complete.

## Normal Workflow vs Replay / Eval

- Normal development workflow should stay lightweight and risk-scaled.
- Replay / eval / skill-audit workflow may add stricter controls: isolated worktree, oracle separation, source-of-truth classification, and replay disclosure.
- Do not push replay-only rules into normal development unless the rule is broadly useful outside replay.

## Completion Rule

Do not say a skill change is complete until the source, backup mirror, and changelog have all been updated or an explicit blocker is reported.
