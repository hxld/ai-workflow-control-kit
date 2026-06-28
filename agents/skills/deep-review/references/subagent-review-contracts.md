# Subagent Review Contracts

Use this reference only when the host supports parallel agents and the task is explicitly allowed to use them. The default mode is read-only.

## Trigger

Use optional review subagents for one or more of:

- Large diff or multi-module review.
- Multiple surfaces such as API, database, UI, export, job, template, or external payload.
- Review pressure: another AI, external reviewer, or strict second-look review will inspect the result.
- Skill, prompt, knowledge-base, or technical-design review where independent lenses reduce blind spots.

Do not use subagents for quick lint checks, tiny single-file reviews, user decision making, release operations, or production actions.

## Task Contract

```markdown
## Subagent Task
- mode: read_only
- role:
- question:
- allowed_roots:
- required_sources:
- forbidden_sources:
- source_boundary: requirement / current_plan / historical / oracle
- output_schema:
- max_findings:
- must_not:
  - 不修改文件
  - 不扩大 scope
  - 不把推断写成 confirmed
  - 不创建并行主报告
```

## Recommended Roles

| role | use when | focus |
|------|----------|-------|
| Review Lens Specialist | Need a distinct review angle | Requirement fit, correctness, security, performance, maintainability, or testing |
| Surface Drift Specialist | Multi-surface change | Entry points, visible outputs, generated artifacts, side effects |
| Contract Specialist | API, DB, config, external payload | Literal values, compatibility, idempotency, error semantics |
| Test Evidence Specialist | Tests or verification may be weak | RED/GREEN evidence, true surface, mock-only gaps, missing must-not assertions |
| Documentation Drift Specialist | Docs, specs, or knowledge files changed | Source of truth, stale claims, changelog/sync gaps |

## Result Contract

```markdown
## Subagent Result
- role:
- status: PASS / FINDINGS / BLOCKED
- scope_covered:
- files_read_or_searches:
- not_covered:
- findings:
  | id | severity | finding | evidence | confidence | recommendation | verification |
- assumptions:
  | assumption | why_needed | how_to_verify |
- rejected_paths:
  | candidate | rejected_because | evidence |
- handoff:
  | accepted_by_main? | needs_main_verification |
```

## Merge Gate

The main session owns the final review result.

- Deduplicate by file, line, behavior, and requirement row.
- Classify every row as `confirmed_fact`, `inference`, `assumption`, or `verification_gap`.
- Recheck P0/P1 findings and core facts directly from source before reporting them as confirmed.
- Preserve conflicts as explicit review questions when evidence does not settle them.
- Reject findings that depend on forbidden sources, stale oracle material, or out-of-scope assumptions.
- Keep a single final report; do not leave parallel subagent reports as competing conclusions.

## Hard Stops

- A subagent result cannot mark the review as passed by itself.
- A subagent cannot authorize fixes, commits, release actions, production queries, or scope expansion.
- Unverified P0/P1 findings must remain `verification_gap` or `ASK`, not confirmed defects.
