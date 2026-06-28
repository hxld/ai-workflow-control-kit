# Subagent Design Contracts

Use this reference only when the host supports parallel agents and the task is explicitly allowed to use them. The default mode is read-only.

## Trigger

Use optional design subagents when one or more signals appear:

- Large requirement, multiple modules, or more than two significant surfaces.
- Review pressure or a known external reviewer will inspect the plan.
- External integration, database/schema, async jobs, templates, export/report, or irreversible release risk.
- Cross-repository or cross-context discovery is needed before the main plan can freeze facts.
- The user has corrected the same misunderstanding before, or the plan has high rework cost.

Do not use subagents for small mechanical edits, user approvals, final scope decisions, git/release operations, or production actions.

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
- max_rows:
- must_not:
  - 不修改文件
  - 不扩大 scope
  - 不把推断写成 confirmed
  - 不创建并行主方案
```

## Recommended Roles

| role | output | use when |
|------|--------|----------|
| Context Scout | Existing implementation map and evidence anchors | Need fast discovery across modules or repositories |
| Contract Extractor | Literal values, API/DB/wire names, source boundaries | Requirements contain fixed fields, enums, payloads, SQL, or display text |
| Surface Miner | Entry/service/side-effect/generated-artifact/test matrix rows | Multi-surface or deploy-facing contract risk |
| Design Red Team | Rejected options, hidden risks, doubt questions | Plan seems plausible but alternatives are not explicit |
| Test Strategy Scout | Risk/depth matrix and runnable verification candidates | Test Design Control needs stronger evidence |

## Result Contract

```markdown
## Subagent Result
- role:
- status: PASS / FINDINGS / BLOCKED
- scope_covered:
- evidence:
  | claim | source | line_or_anchor | confidence | note |
- candidate_rows:
  | target_table | row | evidence | confidence | main_action |
- assumptions:
  | assumption | why_needed | how_to_verify |
- rejected_paths:
  | candidate | rejected_because | evidence |
- not_covered:
- handoff:
  | accepted_by_main? | needs_main_verification |
```

## Main Merge Gate

The main session owns the technical plan.

- Merge accepted rows into the canonical `tech-design.md`, OpenSpec, and slice plan.
- Classify every row as `confirmed_fact`, `inference`, `assumption`, or `verification_gap`.
- Recheck core facts, P0/P1 risks, and implementation carriers directly before freezing them.
- Keep rejected rows with reasons when they matter for future review or user questions.
- If subagents disagree, use source evidence to resolve; unresolved conflicts become human review questions.
- Do not leave multiple parallel technical designs.

## Subagent Evidence Ledger

When subagents were used, add this compact ledger to the plan or close-out artifact:

```markdown
| subagent role | accepted rows | rejected rows | main verification | remaining gap |
|---------------|---------------|---------------|-------------------|---------------|
```

## Hard Stops

- Subagent output cannot replace requirement alignment, Planning Brainstorm, OpenSpec, user approval, or Implementation Readiness.
- Historical or oracle sources cannot become implementation requirements unless the latest task explicitly enters a diff-port or replay mode.
- Write-capable subagents are out of scope for normal design; use isolated work only when the user explicitly authorizes it and the write boundaries are disjoint.
