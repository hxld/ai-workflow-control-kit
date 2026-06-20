# Skills Manifest

This directory is the canonical source for loadable custom skills.

## Canonical Rule

- Canonical skill file: `.agents/skills/<skill>/SKILL.md`
- Local governance file: `.agents/AGENTS.md`; read it before editing, auditing, syncing, or publishing skills.
- Nested copies such as `.agents/skills/<skill>/<skill>/SKILL.md` are not canonical.
- Edit only the canonical file unless a sync script explicitly requires a mirror update.
- If a platform mirrors these skills, treat the platform copy as generated output.
- External methodology names must not appear as downstream skill dependencies.
- Do not keep local external skill copies; absorb useful patterns into the custom skill that owns the workflow, then delete the external copy.

## Runtime Truth

- Skill directories are inventory; `skill-rules.json` is the managed auto-trigger registry.
- A skill may intentionally exist outside `skill-rules.json` when it is company-specific, manually invoked, or not safe as a generic runtime trigger.
- `rdc-git` is intentionally kept as a company-specific manual skill unless the runtime registry explicitly adds it later.
- Current/historical workflow docs in a knowledge base are advisory. Runtime routing is governed by `workflow-router`, `skill-rules.json`, this manifest, and the active repository `AGENTS.md`.
- When these sources disagree, update the canonical source first, then sync mirrors and mark older knowledge-base pages as historical instead of treating them as executable rules.

## Workflow North Star

This workflow is a generic AI engineering delivery foundation, not a collection of external skills.

North Star: given a real requirement source, maximize verified deliverable implementation coverage while minimizing false completion, rework, and project-specific pollution.

Non-negotiables:

1. Requirement coverage beats code volume.
2. Core path closure beats helper or service progress.
3. Executable evidence beats static confidence.
4. Verification-capped coverage beats self-reported completion.
5. Replay/eval improves the foundation but does not pollute normal delivery.
6. External methods are nutrients, not runtime dependencies.
7. Project and company rules plug into the foundation; they do not define the foundation.
8. Foundation tuning distills raw traces into compact execution controls; it does not dump more material into runtime context.
9. The foundation is host-neutral: agent-specific CLIs, session formats, hooks, filesystem layouts, and cloud services belong behind optional adapters.
10. Memory is evidence-indexed: automatic memories, summaries, and translated sessions are candidates until verified with `source_ref`, confidence, and current validity.
11. Lossy handoffs must be explicit: cross-host conversion, compaction, summary, or replay evidence must disclose what was lost, inferred, or unverifiable.
12. Project-derived lessons must be distilled before entering the foundation: no project names, repository paths, business classes, tables, fixed business copy, incident text, or team-only commands in core skills.
13. Staging is explicit: `git add .` is never the default; generated/local artifacts require include / confirm / exclude classification and a cached-diff check before commit.

## Main Workflow Skills

| Skill | Role |
|---|---|
| `workflow-router` | Route user intent to the right workflow. |
| `restore-context` | Restore lightweight project state before work continues. |
| `pre-flight-check` | Run safety, memory, boundary, and isolation gates before edits. |
| `req-alignment-check` | Freeze requirements, literals, surfaces, and open issues before planning. |
| `ideate` | Run dialogue design or planning brainstorm before technical design is frozen. |
| `deep-plan` | Produce technical design, OpenSpec, surface matrix, and expected diff matrix. |
| `goal-mode` | Define structured goals for long-running autonomous agent tasks. |
| `dev-workflow` | Implement only after planning, OpenSpec, TDD, isolation, and scope gates pass. |
| `gen-tests` | Generate and verify tests from requirement and surface matrices. |
| `deep-review` | Review implementation risks and regressions. |
| `sync-progress` | Final completeness gate and `.doc` / OpenSpec / memory synchronization. |

## Replay/Eval Specialist Skills

| Skill | Role |
|---|---|
| `replay-pre-flight-check` | Validate test environment (JUnit/TestNG, compilation, smoke test) before Phase 1 execution. |
| `replay-tdd-enforcer` | Force complete TDD cycle: RED-only is invalid progress, GREEN phase with production code required. |
| `replay-test-charter-validator` | Require side-effect proof (DB/state/file/API) in tests, reject helper-only validations. |

## SKILL.md Size Budget

`250` lines is the default budget, not an absolute red line. The goal is that the model can reliably capture trigger conditions, Iron Law / Hard Gates, workflow, and output format from the main `SKILL.md`.

| Skill type | Suggested lines | Rule |
|---|---:|---|
| Router, for example `workflow-router` | 80-150 | Keep shortest; no downstream workflow inlining. |
| Gatekeeper, for example `pre-flight-check` | 120-220 | Keep Hard Gates; move history and cases to `references/`. |
| Main workflow, for example `dev-workflow` | 180-300 | May exceed 250 only when every section directly affects execution. |
| Review/test, for example `gen-tests`, `skill-audit` | 180-300 | Dense rules are acceptable; long examples move to `references/`. |
| Domain tool, for example `obsidian-wiki`, `video-to-obsidian` | 200-350 | Less frequently triggered skills may be longer if procedural. |
| Methodology appendix / `references/` | 80-180 | Not triggerable; holds templates, examples, long checklists, and cases. |

Audit rule: if the main `SKILL.md` exceeds 250 lines, it must explain why it is not split, contain only execution-critical content, and move cases/templates/long tables to `references/`. More than 300 lines defaults to `needs split`; more than 350 lines is a structural issue unless it is a rare domain tool with explicit justification.

## External Methodologies Absorbed

| External method | Custom owner |
|---|---|
| Brainstorming / planning brainstorm / dialogue design / deep idea exploration | `ideate`, `workflow-router`, `req-alignment-check`, `deep-plan`, `deep-review`, `sync-progress` |
| Systematic debugging | `gen-tests` FIX mode, `log-investigator`, `deep-plan` escalation |
| Test-driven development | `dev-workflow`, `gen-tests`, `sync-progress` |
| Skill writing rules | `skill-audit`, `skill-evolution` |
| Skill eval evidence | `skill-audit`, `skill-evolution` |
| Testing mock anti-patterns | `gen-tests`, `deep-review` |
| AI-assisted test design control / human-in-the-loop testing SOP | `deep-plan`, `gen-tests`, `dev-workflow`, `sync-progress` |
| Evidence-first debugging | `workflow-router`, `log-investigator`, `gen-tests` FIX mode |
| Review feedback triage | `deep-review`, `resolve-feedback` |
| Review pressure and second-opinion lens routing | `workflow-router`, `deep-review`, `resolve-feedback` |
| Domain language, tracer bullets, deep modules, and throwaway prototypes | `req-alignment-check`, `deep-plan`, `dev-workflow`, `gen-tests`, `deep-review`, `sync-progress` |
| Trace distillation, harness tuning, and anti-sequential-drift learning | `skill-evolution`, `skill-audit`, `pre-flight-check` replay/eval references |
| Host-neutral portability, memory promotion, and lossy handoff disclosure | `skill-evolution`, `pre-flight-check`, `sync-progress` |

No external skill source remains required after absorption.

## Canonicalization Status

Duplicate nested `SKILL.md` files are discovery hazards. They should be removed or converted by tooling so only canonical paths above are loaded.

## Replay Lessons Integrated

The main workflow must treat broadly reusable delivery patterns as normal gates, and replay/eval-only patterns as audit gates.

Normal development gates:

1. Requirement freeze matrix before coding.
2. Surface matrix before coding.
3. Expected diff/scope prediction before coding.
4. Test Design Control is required for non-trivial, multi-surface, stateful, external-facing, async, report/export, frontend-visible, old-data, or must-not requirements; `deep-plan` produces it, `gen-tests` consumes it, and `sync-progress` closes it.
5. Small requirements use a lightweight lane: compact matrices and short reports, but no skipped source/literal/surface/diff/TDD/final-diff gates.
6. Completion cannot rely on small GREEN tests only.
7. Reusing an existing implementation or branch requires a deliberate slice: `intended_change_slice` vs `out_of_scope_drift`.
8. Generated artifacts, caches, local indexes, screenshots, logs, temporary scripts, and tool outputs must be separated from the effective diff.
9. Scope classification must distinguish backend scope, frontend-only work, already implemented behavior, pending confirmation, support tooling, and unrelated drift.
10. Baseline capability scan is required when the base implementation is not empty.
11. Baseline blockers must be classified separately from requirement RED: `baseline_compile_blocker`, `feature_diff_blocker`, `test_runtime_blocker`, or `environment_blocker`.
12. Verification commands must be copy-ready for the active shell; static PowerShell Maven commands with `-Dtest` / `-Dsurefire` may use `mvn --%`, while dynamic commands must use argument arrays or explicit quoting.
13. Test reports must distinguish successful assertions from `runtime_noise_with_success`; runner success with exit code 0 is not overwritten by later background output, but the noise must be disclosed.
14. Generated artifacts need a ledger before completion: path, source, generated/effective classification, keep/delete decision, and commit/no-commit decision.
15. Long or garbled verification logs must be summarized through stable anchors: phase, exit code, module, file/class/method, exception type, and first failing symbol.
16. Large requirements must be split into capability slices with independent DoD, verification scope, rollback boundary, and dependencies.
17. Imported requirement documents must be normalized before matrices when tables, copied HTML, image placeholders, update notes, one-line Markdown, or broken formatting obscure the source.
18. Greenfield multi-module features need a skeleton gate before behavior RED; missing classes, mappers, or beans are not business RED.
19. Large diffs need a role matrix: business diff, supporting infrastructure, external/frontend surface, release/config/SQL, generated/local docs, and unrelated drift.
20. Branch/commit-derived work without PRD must first reconstruct requirements through confidence-ranked inferred rows, not treat diff as PRD.
21. No-doc bugfixes without logs, stack traces, failing tests, or reproduction inputs can only conclude `compile_pass + static_inference + verification_gap`.
22. External integrations require request/response/signature/config/empty-case contract freeze before implementation or completion.
23. Shared enum, base handler, framework, shared DTO, shared utility, or public config changes auto-upgrade to shared-impact planning.
24. Bugfix and debugging work must classify available evidence before edits: failing test, logs/trace, reproduction steps, external contract, environment blocker, or oral-only report.
25. Oral-only bug reports without logs, stack traces, failing tests, reproduction inputs, or contract evidence can only produce hypotheses, evidence gaps, and collection plans.
26. Stack-trace bugs must lock the first business frame, failing expression, variable source, and minimal input/config reproduction before changing production code.
27. External interface bugs must freeze raw request, raw response, business code/message, idempotency/retry, config version, and owner evidence before assigning responsibility.
28. Data-lineage bugs must trace source rows, filters, mapping/config, transform, persistence, output payload, and visible result before assigning responsibility.
29. Configuration/cache bugs must lock expected rule, actual source, precedence/fallback, cache/version, request time, and retry/new-request boundary.
30. Missing-log bugs must verify log emission code, level, app/index/time range, traceId/message query, and whether the payload is actually printed.
31. Asynchronous task bugs must trace the state chain before fixes: parent task, child task, status transitions, scheduler/worker, persistence boundary, completion log, downstream trigger, and retry/idempotency.
32. When the user asks for a conclusion during investigation, output confirmed facts, high-confidence inferences, and evidence gaps first; do not continue silent exploration.
33. Host-platform skill failures must be diagnosed as infrastructure before business workflow: freeze platform, config schema/version, shell, path quoting, stdin/stdout encoding, JSON escaping, runtime log, duplicate skill sources, MCP capability mismatch, and minimal trigger probe.
34. Tests that mainly verify mocked return values, test-only production hooks, or incomplete mock contracts cannot count as GREEN; classify as `mock_behavior_gap` or add contract/integration guards.
35. Review feedback must be triaged into `AUTO-FIX`, `ASK`, or `PUSH-BACK`; do not ask for trivial confirmations, and do not auto-implement business or architecture decisions.
36. Explicit review pressure such as "Claude Code/Codex will review this" raises evidence standards and review lens selection, but does not by itself expand scope, create a second deliverable, or enter replay/eval.
37. Expected Diff Matrix must close at file-family level: each high-risk family ends as `changed+tested`, `changed+static_only+cap`, `deferred+reason+coverage_cap`, or `blocker`.
36. Core-path completion requires a real entry or carrier path, not only a newly created helper/service or mock-only GREEN.
37. Non-blocking failure handling does not make the underlying feature optional; missing image, attachment, report, export, async, notification, or external-protocol work remains a coverage gap unless explicitly deferred.
38. When high-weight core or explicit supporting surfaces are still unclosed, the workflow should stop and report blockers instead of spending budget on low-risk helper/DTO/log slices.
39. Large or multi-surface requirements need a read-only Surface Mining Pass before Expected Diff Matrix: runtime entry, orchestration service, side effects, generated artifacts/templates, frontend/export surface, and test harness.
40. Autonomous or 90%+ implementation must reserve the first implementation budget for the highest-weight core slice; supporting surfaces follow, optional slices do not compensate for an unclosed core path.
41. High-weight core slices require a Behavior Test Charter before production code: real entry, fixture/source, side effects, must-not behavior, assertion, execution mode, and fallback/blocker.
42. If the core path remains unclosed, the workflow should emit `core_path_unclosed` and stop rather than continue with helper/DTO/constant/log-only progress.
43. Explicit deploy-facing surfaces such as report/export/frontend/template/generated artifact/OCR/external payload must be locked to concrete file families, implementation actions, and validation points before coding.
44. Stateful core paths involving status transitions, transactions, progress/logs, persistence rewrites, or task progression require DB/transaction-level test planning; mock collaborator tests cannot mark them DONE.
45. Non-blocking features still require a success path plus failure isolation; nonblocking only changes failure handling, not delivery scope.
46. High-weight core paths must close a real production entry file family in the plan, implementation diff, and tests; helper/service/DTO progress cannot substitute for entry closure.
47. Stateful core paths require a side-effect ledger covering status, task, progress, log, persistence, transaction/rollback, and failure isolation assertions.
48. If a replay identifies the core entry but does not modify or test that entry family, mark `core_entry_unclosed` and cap coverage before counting supporting surfaces.
49. Deploy-facing exact contracts must freeze code symbol, DB/API/wire name, exact value or payload shape, owner, and test assertion before they count as DONE.
50. High-weight missing file families found in oracle post-hoc should feed back as abstract gate categories, not as leaked oracle filenames in blind prompts.
51. For autonomous 90% work, high-weight deploy-facing families need a first RED, static contract, or implementation slice before expanding low-value helper/service internals; otherwise mark `surface_budget_gap`.
52. High-weight deploy-facing family allocation must include an executable first slice; static-only guards and blocker-only rows can cap or stop work, but cannot count as `DONE`.
53. Non-trivial decisions need a doubt checkpoint: claim, why it matters, artifact/contract, disproof questions, and reconciliation before implementation stands.
54. Implementation tasks should be small, dependency-ordered, verifiable slices; tasks over about five files or multiple independent subsystems should be split.
55. Public or shared interfaces must freeze observable behavior, not only declared fields: output shape, error semantics, ordering, null/empty behavior, idempotency, and compatibility.
56. Unexpected build/test/runtime failures stop feature work until evidence is preserved, root cause is classified, and a regression guard or blocker is recorded.
57. Domain language conflicts must be resolved before design and testing: canonical term, aliases to avoid, source evidence, code/doc impact, and unresolved status.
58. Bugfixes and complex implementation need an agent-runnable feedback loop before source edits; if no loop can be built, report `feedback_loop_blocker` instead of guessing.
59. TDD proceeds by tracer bullets: one behavior RED, one minimal GREEN, then the next behavior; horizontal bulk tests are a coverage risk.
60. New abstractions and seams need a depth check: deletion test, adapter count, hidden complexity, and whether the interface is the correct test surface.
61. Throwaway prototypes must answer a named question and be deleted, absorbed, or classified as generated/debug artifacts before completion.
62. Durable rejected/deferred scope or surprising hard-to-reverse decisions should be recorded in the repo's decision/scope memory, not re-litigated every session.
63. Deploy-facing contracts need triangulation before coding: requirement literal, current schema/code/API evidence, and wire/display/test assertion must agree before a row counts as DONE.
64. Same business terms across multiple task, query, retry, report, UI, callback, or external-payload families must be disambiguated before implementation; similar names are not evidence of the same surface.
65. Report/export/page-query work must close query carrier, filter/select, UI/script parameter, header/value, and real output verification separately; export columns alone do not prove query-surface completion.
66. External payload work must freeze observable casing and array/object/string wrapping, not only semantic field names.
67. Stateful core paths with transactions, rollback, after-commit, failure-log isolation, or task-state changes require transaction-depth test planning; mock-only collaborator tests force a coverage cap.
68. Repeated high-weight gaps must backpressure the next implementation slice: map the gap to a target surface/file family, executable proof, and exit condition, or stop instead of adding low-risk support changes.
69. Removed side effects need regression assertions: prove the old log/task/message/write/callback no longer happens and the remaining success path still happens.
70. Terminal artifacts such as success logs, final flags, final messages, export columns, or displayed labels are assertion targets, not substitute implementations; tests must prove the producing entry/orchestration/side-effect chain.
71. Bugfixes, complex implementation, and replay/eval rounds require an agent-runnable feedback loop before source edits; otherwise report `feedback_loop_blocker` and stop instead of guessing.
72. Replay/eval evolution proposals must map every candidate to the eight productized gates before editing skills; `workflow-gate-needs-evolution` changes gate text, while `tooling-evolution-needed` changes runner, prompt, verifier, or replay/eval reference enforcement.
73. A real-entry tracer bullet is not stateful completion by itself; if only a hook, negative isolation, placeholder service, or mock-only assertion exists, the next slice must close a stateful success path or deploy-facing executable slice, and close-out must mark `tracer_bullet_only` with a coverage cap.
74. After a real-entry tracer bullet or two consecutive core-only/internal slices, open high-weight deploy-facing contracts and surfaces must receive an executable first slice before more helper/service expansion; side-effect proof must include writes, no-writes, transaction boundary, and observable deploy output, or mark `exact_contract_gap` / `surface_budget_gap` / `side_effect_ledger_gap`.
75. A repeated replay gap that is already covered by an existing gate is not automatically no-op; classify it as `already-covered-but-not-enforced` unless there is concrete evidence that the runner, prompt, and verifier already force the gate.
76. Replay/eval runner enforcement needs artifact evidence before slice execution; without previous open gaps, highest-weight target, fail-closed condition, and verifier assertion, stop with `tooling_enforcement_stop` instead of spending the slice budget.
77. Runner enforcement must target concrete subsurfaces, not only coarse families: endpoint/page/export sibling, payload builder, template/render/upload chain, stateful production entry, proof kind, RED expectation, and fail-closed condition.
78. A deploy-facing family with multiple required sibling surfaces cannot be marked `DONE` after closing only one sibling; each required sibling must be executable-closed or explicitly deferred with blocker and coverage cap.
79. Core entry closure and stateful core-path closure are separate. Entry hook, negative isolation, placeholder service, or shallow orchestration cannot close status/write/log/progress/task/transaction side-effect families.
80. Exact contract and generated-artifact proofs must assert the production boundary: request builder payload shape, DB/wire/display field, external protocol casing/wrapping, template rendering, upload, and metadata. Helper-only, synthetic, or static evidence caps the family.
81. If an intended RED does not fail, runs zero tests, or is blocked by test infrastructure, the family cannot be `DONE`; preserve the blocker, cap coverage, and force the next slice to create executable feedback.
82. Verifiers must distinguish production-surface executable evidence from replay-local/static/helper assertions; the latter can support a cap or blocker but cannot close high-weight deploy-facing or stateful families alone.
83. Replay/eval runner contracts must pass schema validation before the first slice: `target_subsurface_or_carrier`, `required_sibling_surfaces`, `production_boundary`, `proof_kind`, `red_expectation`, and `fail_closed_condition` are mandatory for high-weight families; broad-family rows alone trigger `tooling_enforcement_stop`.
84. Multi-stage replay planners must fail closed on missing stage artifacts before tournament, selection, or implementation contract steps. Missing candidate plans, absent selected candidate, empty contract inputs, or unauthorized synthesis keep first-slice suggestions non-authorizing and trigger `tooling_enforcement_stop` or `BLOCKED_PLAN_MISMATCH`.
85. Replay automation must be non-GUI and reproducible: prompts and agents use shell, git, build/test commands, and direct file edits only; GUI/IDE dependence is an environment blocker, not execution evidence.
86. Missing or non-failing RED evidence is zero executable delta for replay scoring. `red_phase_did_not_fail`, `tdd_red_not_replayed`, or 0 tests run cannot close a family and should stop continuation until a real feedback loop exists.
87. High-weight generated artifacts, external payloads, deploy sibling surfaces, and stateful side effects require proof at their production boundary: render/upload/metadata, request shape, sibling carrier output, or side-effect ledger assertion.
88. Before spending a fresh replay slice on broad context or support files, create a cost-bounded first-slice proof plan for the highest-weight open carrier, selected RED, expected diff family, and stop condition.
89. Replay artifact dependency checks need a shared artifact acceptance registry. If an equivalent runner contract is allowed, verifier failure must be based on schema gaps, not on a missing exact filename; if only one filename authorizes Phase 1, the prompt must produce that file and the rule must not advertise equivalence.
90. Replay-derived skill changes must pass trace distillation before absorption: raw causal trace or equivalent evidence, verified root cause or minimal proof, repeated/high-weight pattern, compact control signal, and runner/prompt/verifier enforcement target.
91. First-slice carriers need semantic validation before implementation: selected carrier, production boundary, downstream side effect or output, forbidden substitute check, and why it is not a test-only seam; no-op hooks, placeholder carriers, subclass counters, or missing downstream production invocation trigger `tooling_enforcement_stop`.
92. Replay verifiers must fail closed on missing RED or synthetic proof: `red_phase_did_not_fail`, `tdd_red_not_replayed`, 0 tests run, subclass-only proof, static/no-op proof, or synthetic carrier proof set executable delta to 0 and high-weight core-entry coverage cap to at most 10 unless an environment or baseline blocker is explicitly classified.
93. Fresh replay runs need a cost-bounded dry-run gate before broad context loading, Maven, or implementation; existing first-slice plans, runner contracts, slice results, verifier outputs, round results, and diff metadata must produce `STOP`, `ALLOW`, or `BLOCKED_PLAN_MISMATCH`.
94. Stop-loss replay proposals with repeated `already-covered-but-not-enforced` gaps require three-part enforcement closure before another replay: first-slice dry-run, verifier hard stop for non-authorizing evidence, and highest-weight open surface routing; reference text alone is not proof that the real runner/prompt/verifier enforces it.
95. Replay verifiers must emit authorization flags, not only warnings. Missing/non-failing RED, tracer-only, shallow service, static-only, synthetic, or mock-only proof must set `authorized_for_next_slice=false` and `authorized_for_synthesis=false` unless it is an explicit environment or baseline blocker.
96. Replay slice routing follows the highest-weight `OPEN/PARTIAL` required family after each verifier pass. A blocked family may be skipped only with blocker evidence; convenience, helper readiness, or already-touched core support cannot override the router.
97. Requirement family closure needs proof-type matching. Each family declares `required_proof_type`, each slice reports `actual_proof_type`, and DTO/entity/constant/file-presence/mock-only proof cannot close stateful, wire-payload, rendered-artifact, export-output, or lifecycle-cleanup families.
98. Replay runner invocation is part of the proof chain. Before implementation slices, the runner must smoke-check the exact non-interactive command and script parameter contract; unsupported parameters, quoting gaps, or wrapper mismatches stop as `runner_invocation_error` with no behavior evidence.
99. Executor-blocked or no-production-boundary slices are no-progress evidence, not implementation progress. They must set `implemented_files=[]`, `has_behavior_evidence=false`, `authorized_for_synthesis=false`, and be recorded in `no_progress_slices` or an equivalent blocker ledger.
100. Ledger-derived coverage cannot ignore open required families. If any required family remains `OPEN/PARTIAL`, any touched family lacks matching proof types, or any executor-blocked slice exists, `coverage_cap_from_ledger` cannot be 100.
101. Stop-loss `STOP_AND_EVOLVE` decisions require validation evidence, not another replay: dry-run must output `STOP` / `ALLOW` / `BLOCKED_PLAN_MISMATCH` before broad context loading or implementation prompts, with highest-weight gate, selected carrier, production boundary, proof kind, RED expectation, and fail-closed condition.
102. Carrier authorization needs concrete production proof fields. High-weight core/stateful/deploy-facing slices lacking selected carrier, production boundary, downstream side-effect/output, forbidden-substitute check, or non-test-only rationale must set `authorized_for_next_slice=false`, `authorized_for_synthesis=false`, and `executable_delta=0`.
103. Highest-weight family routing and ledger caps are acceptance gates. A proposed slice that misses the top `OPEN/PARTIAL` required family without verifier-approved blocker returns `BLOCKED_PLAN_MISMATCH`, and any open family, proof-type mismatch, or no-progress slice forbids final `PASS`.
104. Stop-loss experiment artifacts must be schema-verifiable before a fresh replay: carrier authorization, exact-contract assertion matrix, and side-effect evidence each need required fields and fail-closed results.
105. Carrier authorization must stop helper-only, log-only, delegate-only, synthetic, or no-downstream-output carriers before implementation slices; renaming a synthetic carrier cannot satisfy real-entry or production-boundary proof.
106. Exact-contract and side-effect families need matching proof at their production boundary; touched open contracts, non-failing RED, static/mock/helper/subclass-only evidence, or missing writes/no-writes assertions keep executable delta at 0.
107. Planned, candidate, TBD, pending, helper-only, static-only, DTO/entity/constant, or no-downstream-output carriers are planning/support evidence only; they cannot authorize a replay implementation slice or synthesis.
108. A touched exact-contract family with `exact_contract_gap` fails closed: behavior evidence is false, executable delta is 0, authorization flags are false, and the family remains open until production-boundary assertions or a blocker exist.
109. Round synthesis must obey the required-family ledger cap. Open/partial required families, proof-type mismatches, no-progress slices, or `final_pass_allowed=false` forbid `PASS` and cap `verification_capped_coverage` even when individual slices report higher scores.

Skill evolution gates:

1. Changing trigger conditions, workflow, hard gates, output format, or downstream routing requires minimal trigger/output eval evidence.
2. Minimal eval means 2 should-trigger prompts, 1 should-not-trigger prompt, 1 pressure scenario, and a golden output when output format changes.
3. Pure typo, backup sync, changelog, or path-note changes may skip eval only with `no_eval_reason`.
4. External methodology remains input material only; do not add external skill names as local downstream dependencies.
5. Skill eval reports should include `baseline`, `with_skill`, assertions, evidence, transcript notes, human feedback when available, and cost impact; missing assertions/evidence means `NEEDS_EVIDENCE`.

Replay/eval gates:

1. Replay/eval work must write inside an isolated worktree or sandbox, not the main workspace.
2. Requirement source, current planning source, historical documents, and oracle material must be classified before implementation.
3. Target commits or historical final-state documents may be used only after implementation as oracle material unless the user explicitly requests a diff port.
4. Replay reports must disclose mode: `blind_from_scratch`, `oracle_port`, `hybrid_replay`, `static_audit`, `branch_derived_replay`, or `commit_derived_replay`, plus oracle usage, worktree path, validation scope, and whether skills or backups were modified.
5. Post-oracle comparison must classify target diff into effective requirement diff, support tooling, temporary/debug drift, frontend-only work, and unrelated drift.
6. Multi-round replay may parallelize static analysis, slicing, diff comparison, and compile probes; integration tests with shared runtime state default to serial execution or must declare isolation.
7. Branch/commit-derived reports must include `Inferred Requirement Matrix`, `Diff Role Matrix`, and explicit verification gaps.
8. Replay audit must classify `expected_diff_unclosed`, `real_entry_gap`, `nonblocking_feature_gap`, and `context_contamination_risk` separately from ordinary implementation gaps.
9. Replay diff accounting must include both tracked and untracked files; untracked production/test/SQL/template/frontend files are coverage evidence, not optional workspace noise.
10. Oracle-adjusted replay scoring must separate exact file-family overlap, conceptual role overlap, and missing deploy-facing family penalties.
11. Workflow deliverability requires two-stage evidence: repeated strict blind replay on a representative complex requirement, then generalization replay on a different requirement type; before both pass, call the workflow candidate or improving, not deliverable.
12. Replay reports must flag `core_entry_unclosed` and `side_effect_ledger_gap` when core entry closure or stateful side-effect evidence is missing, even if helper/static tests pass.
13. Replay oracle review must flag `exact_contract_gap` for field, column, flag, enum, payload shape, or display-column mismatches, and convert missing file-family patterns into project-neutral next-round gates.
14. Replay audits must distinguish stricter scoring from better execution: if deploy-facing families stay untouched, evolve budget routing and first-slice allocation, not only coverage caps.
15. Replay audits must flag `executable_surface_slice_gap` when high-weight surface allocation is satisfied only by static guards, file-presence checks, or blocker rows.
16. Replay learning must avoid sequential drift: do not promote a single unverified round into generic rules; pool evidence, discard patches whose root cause cannot be reproduced or minimally proven, and automate only after questioning, deleting, and simplifying the loop.
