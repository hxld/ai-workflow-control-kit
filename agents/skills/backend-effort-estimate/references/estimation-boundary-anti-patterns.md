# Estimation Boundary Anti-Patterns

Use this note when the effort estimate starts drifting away from a scoped backend implementation. Keep the estimate tied to explicit scope, verification boundaries, and integration risk.

## Anti-Patterns

| Anti-pattern | Why it is risky | Safer handling |
|---|---|---|
| Counting only coding time | Understates validation, review, deployment, and environment risk | Include implementation, self-test, integration support, review fixes, and release support as separate rows |
| Treating unclear requirements as simple work | Hides product, API, data, or ownership ambiguity | Add an analysis/clarification row and mark assumptions |
| Removing integration risk in an AI-compressed estimate | AI can compress drafting time, not upstream/downstream coordination | Keep joint testing, environment, and dependency-risk rows even in compressed estimates |
| Estimating frontend, DBA, or operations work as backend implementation | Blurs ownership and creates false delivery commitments | Split non-backend ownership into notes or separate owner rows |
| Reusing a previous estimate without checking changed scope | Carries stale assumptions across different surfaces | Re-map interfaces, data tables, jobs, messages, and validation scope before copying |
| Collapsing unknown external dependencies into development time | Makes blocked time look like productive implementation | Track external dependency wait/coordination separately |
| Marking test work as zero because code generation is assisted | Misses regression, fixture, and environment setup effort | Keep verification rows and explain what is automated |

## Boundary Checklist

- Scope is limited to backend deliverables that this estimate owns.
- API, persistence, async job, message, cache, and third-party boundaries are explicitly listed when present.
- Assumptions are visible in the notes instead of hidden inside a lower effort number.
- Compression, if requested, is applied to implementation drafting effort only.
- Joint testing, environment setup, regression, review, and release support are not silently removed.
