# Review Independence Disclosure

Use this reference when close-out includes multi-round review, a second look, subagents, Codex thread isolation, or an external reviewer signal.

```markdown
| review mode | independence level | reviewers/lenses | external model used | main reverification | status impact |
|-------------|--------------------|------------------|---------------------|---------------------|---------------|
```

## Rules

- `single_context_lens`: disclose `independence_level=same_context_lens`. For L3 work, missing core-fact reverification or counter-evidence caps final status at `PARTIAL`.
- `codex_thread_isolated`: list the read-only scope of each isolated thread/fork and the main-session reverification result. Unverified P0/P1 findings, core facts, requirements, DB/API/wire contracts, and test evidence cannot support `DONE`.
- `external_cross_model`: fill only when a real external reviewer result exists. Otherwise write `external model used=no`.
- The main session owns deduplication, conflict resolution, final status, commit/release decisions, and completion wording.
