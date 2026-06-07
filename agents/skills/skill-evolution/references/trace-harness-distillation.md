# Trace / Harness Distillation

Use this reference when absorbing papers, knowledge-base notes, historical sessions, replay traces, or external methods into the workflow foundation.

## Checks Before Absorption

1. **Raw evidence**: prefer raw trace, causal chain, transcript, diff, logs, verification output, ROUND documents, or equivalent evidence. Summary-only material can only become wiki notes or candidates.
2. **Verified root cause**: a failure pattern needs a minimal fix, minimal proof, truth comparison, or repeatable command. If the root cause cannot be reproduced or explained, discard the patch.
3. **Repeated or high-weight pattern**: a single round is a pressure scenario, not a generic gate. Promote only repeated, high-weight, or clearly cross-project patterns.
4. **Compact control signal**: absorb as trigger, stop condition, schema, runner/prompt/verifier assertion, proof requirement, or coverage cap. Do not dump long explanations into runtime context.
5. **Question/delete/simplify before automation**: do not automate a polluted or unverifiable loop.

## Classification

| result | meaning | action |
|--------|---------|--------|
| `new_cross_project_failure_class` | Existing gates cannot carry the pattern, and evidence is verified across cases | Modify the owner skill or replay/eval reference |
| `covered_but_not_enforced` | Existing gate covers the pattern, but runner/prompt/verifier does not enforce it | Change execution constraints instead of adding a synonym gate |
| `candidate_only` | Insight exists, but raw evidence, proof, or repeat evidence is missing | Keep in wiki/history only |
| `project_specific_memory` | Requires project paths, class/table names, business incidents, or company commands | Put in repo rules or project memory |
| `discarded_unverified_patch` | Root cause cannot be reproduced or proof does not explain failure | Do not absorb |

## Minimal Eval Anchors

- should-trigger: user asks to absorb pre-win, paper notes, historical sessions, replay traces, or external methods.
- should-trigger: a replay proposal says a repeated gap is already covered but still fails in execution.
- should-not-trigger: ordinary feature implementation, bugfix, or project AGENTS build-command update.
- pressure scenario: only a video-note summary or one unverified replay round exists; output `candidate_only`, not a runtime rule change.
