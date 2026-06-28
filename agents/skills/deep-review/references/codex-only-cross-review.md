# Codex-Only Cross-Review Protocol

Use this reference when the user asks for cross-review, second look, multiple reviewers, or a stronger review workflow while using only Codex.

## Modes

| mode | independence | use when | required disclosure |
|------|--------------|----------|---------------------|
| `single_context_lens` | low | Thread or fork tools are unavailable, or the task is L0-L2 and does not justify isolation | Not independent; same model and same context |
| `codex_thread_isolated` | medium | The host supports read-only Codex threads/forks and the task has L3 risk, review pressure, large diff, or multiple surfaces | Separate Codex context, still same model family |
| `external_cross_model` | high | Only when the user explicitly asks for an outside reviewer or external model | Outside this Codex-only protocol |

## Workflow

1. Freeze the objective, source boundary, risk tier, and exact artifacts under review.
2. Select role lenses from `review-lens-templates.md`; each lens needs a different failure mode to search for.
3. Choose execution:
   - `single_context_lens`: run the lenses sequentially in the main session, marking evidence and assumptions per lens.
   - `codex_thread_isolated`: send read-only scoped prompts to separate Codex threads/forks when the host provides such tools.
4. Require every reviewer result to use this schema: `role`, `scope`, `evidence read`, `findings`, `confidence`, `assumptions`, `not covered`.
5. Main session adjudicates: dedupe findings, re-read sources for P0/P1 and core facts, run a counter-evidence challenge, classify facts vs assumptions.
6. Final report discloses mode, independence level, lenses, external model usage, main verification, and not-covered areas.

## Hard Gates

- Never call `single_context_lens` an independent external review.
- Codex thread isolation cannot authorize fixes, commits, releases, or completion status by itself.
- P0/P1 findings, core facts, requirements, wire contracts, DB/state effects, and test evidence must be rechecked by the main session.
- If thread isolation was requested but unavailable, downgrade to `single_context_lens`, disclose the downgrade, and cap the conclusion if risk remains.
