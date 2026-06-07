# Review Lens Templates

Use this reference when the user asks for multi-round/deep review, says another AI reviewer will check the result, or the task needs a second-opinion review. Pick the smallest matching template. Do not run every template by default.

## Universal Finding Fields

Every non-trivial finding must include:

- Evidence source
- Severity
- Confidence or certainty
- Verification method
- Assumption marker when not directly verified

If evidence is missing, write `verification_gap` instead of turning the claim into a conclusion.

## Backend Business Code

1. Requirement literal alignment
2. Data flow and state flow
3. Transaction boundary and side effects
4. Error and empty branches
5. Concurrency, idempotency, retry, and duplicate execution
6. Test coverage and must-not assertions
7. Logs, metrics, and observability
8. Regression and shared-entry risk
9. API, database, and document consistency
10. Reviewer challenge

## Frontend UI

1. Requirement and user-facing copy alignment
2. User journey and interaction state
3. Input, validation, loading, empty, and error states
4. Responsive layout and text overflow
5. Accessibility and keyboard behavior
6. API contract and data mapping
7. Visual consistency with the existing design system
8. Performance and asset loading
9. Regression risk across pages/components
10. Reviewer challenge

## Prompt Or Agent Workflow

1. Goal and success criteria
2. Context sufficiency and irrelevant-context risk
3. Constraints and executable gates
4. Tool boundary and write/read permissions
5. Failure, ambiguity, and escalation handling
6. Output format stability
7. Evidence, citation, and anti-hallucination controls
8. Reusability across task types
9. Cost, latency, and context budget
10. Reviewer challenge

## Technical Design

1. Requirement scope and non-goals
2. Domain language and field/source mapping
3. Data flow, state flow, and integration boundary
4. Transaction, consistency, and rollback strategy
5. Failure modes and operational risks
6. Implementation slice and dependency order
7. Test strategy and acceptance evidence
8. Observability, logs, and diagnostics
9. Rollout, compatibility, and document consistency
10. Reviewer challenge

## Skill Evolution

1. Trigger precision and should-not-trigger coverage
2. Core identity and owner skill fit
3. Iron Law, Hard Gates, and red flags
4. Workflow placement and downstream routing
5. Output format and completion semantics
6. Eval evidence and pressure scenarios
7. Token budget and progressive disclosure
8. Source/mirror/changelog governance
9. Project-neutral wording and pollution scan
10. Reviewer challenge

## Knowledge Wiki

1. Source traceability
2. Claim status: extracted, inferred, unverified, or normative pending validation
3. Cross-source agreement or conflict
4. Time sensitivity and current-validity risk
5. Concept/entity/theme promotion boundary
6. Link integrity and index placement
7. Naming, frontmatter, and schema consistency
8. Raw/source immutability
9. Maintenance or refresh trigger
10. Reviewer challenge
