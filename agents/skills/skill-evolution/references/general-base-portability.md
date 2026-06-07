# General Base Portability

Use this reference before absorbing practices from a host-specific agent, IDE, session bridge, auto-memory system, proprietary platform, company workflow, or external tooling ecosystem.

## North Star

The foundation must remain host-neutral: it should improve verified requirement-to-delivery coverage without requiring one specific agent, CLI, file layout, cloud service, or hook system.

## Classification

| result | meaning | action |
|--------|---------|--------|
| `core_base` | The pattern is host-neutral, cross-project, and directly improves delivery control, evidence, or anti-false-completion behavior. | Absorb into the owner skill or manifest with compact gates. |
| `optional_adapter` | The pattern is useful but depends on a specific host API, session format, filesystem layout, hook, or service. | Keep as plugin/adapter/reference guidance; do not make it a main-chain dependency. |
| `reference_only` | The pattern is plausible but has only summary-level evidence, weak repeatability, or unclear execution value. | Keep in wiki/history as a candidate. |
| `reject_vendor_lockin` | The pattern would bind the foundation to one host, duplicate an existing gate, or import a tool identity instead of an abstract control. | Do not absorb. |

## Absorption Checklist

1. Can the rule be stated without naming a specific agent, CLI, path, service, or repository?
2. Does it create a compact control signal: trigger, stop condition, schema field, verifier assertion, proof requirement, or coverage cap?
3. Does it reduce false completion, context drift, memory drift, or unverifiable handoff?
4. Is there raw evidence or repeated high-weight failure, not only a tool's marketing or a one-off anecdote?
5. If host-specific capability is still useful, is it clearly isolated behind an adapter/plugin boundary?

## Memory / Session Source Rule

Host-generated memories, session translations, and conversation summaries are candidate evidence, not ground truth. Before they affect execution:

1. verify the referenced files, commands, functions, or requirements still exist;
2. extract the host-neutral pattern;
3. record `source_ref`, `confidence`, `last_verified`, and `status`;
4. promote only `verified` patterns into the long-term foundation.

## Minimal Eval Anchors

- should-trigger: user asks whether to absorb a host-specific memory system, session bridge, agent workflow, or proprietary tool into the generic foundation.
- should-trigger: an external workflow is useful but would require a special CLI, hook, or session format.
- should-not-trigger: a normal project rule, repository build command, or local business incident should go to project rules or project memory.
- pressure scenario: a session bridge preserves context but loses reasoning, task graph, or memory provenance; absorb `lossy disclosure` and `source_ref`, not the bridge itself.
