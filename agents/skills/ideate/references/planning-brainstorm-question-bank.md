# Planning Brainstorm Question Bank

Use this reference only for `ideate:planning-brainstorm`. Select the relevant questions; do not paste the whole bank into a plan.

## Minimum Row Selection

Include a `PB-xx` row for every requirement item that matches any signal below:

- fixed literal, field, enum, copy, ordering, empty/null behavior, or exact output shape
- `must-not` behavior, forbidden fallback, forbidden side effect, or unchanged legacy path
- data source / owner / lineage can come from more than one place
- state transition, transaction boundary, async handoff, retry, idempotency, or rollback risk
- user-visible result and internal observability both exist
- multiple runtime surfaces: API, UI, export, report, worker, template, notification, external payload, generated artifact
- external contract, third-party protocol, config, signing, auth, timeout, or retry behavior
- user has corrected the same misunderstanding, or review pressure is explicit

If none of the signals apply, pick the top 3-5 highest-risk rows. Do not create a row for every trivial implementation detail.

## Stable ID Rules

- Use `PB-01`, `PB-02`, ... in the order rows are first created.
- Keep IDs stable across `tech-design.md`, tests, review findings, and closeout.
- If a row splits, keep the original ID for the original decision and add a new ID for the split concern.
- If a row is removed, keep an audit note such as `PB-03 removed: superseded by PB-07`; do not renumber later rows.

## Legal `skip_reason`

Allowed:

- `typo_or_comment_only`
- `pure_formatting_no_behavior`
- `generated_sync_no_behavior`
- `single_file_mechanical_rename_with_static_guard`
- `no_requirement_decision_surface`

Not allowed:

- `prd_exists`
- `looks_simple`
- `time_pressure`
- `tests_pass`
- `model_confident`
- `already_discussed_without_trace`

## Question Prompts

### Entry / Surface

- Which runtime entry actually carries this requirement?
- Is there another entry with the same business term but a different owner or output?
- Is any UI, export, report, worker, template, or generated artifact explicitly named?
- What surface would a reviewer inspect first, and is it in the expected diff?

### Data Source / Lineage

- Which source is authoritative, and which nearby source is tempting but wrong?
- Does the value come from request input, persisted state, external response, cache, config, or derived calculation?
- What stale or fallback source must not be used?
- How will the test prove the source, not only the final value?

### State / Transaction / Async

- Which state table, task status, message, or event owns success and failure?
- Which failures block the main chain, and which are isolated side effects?
- Does this need after-commit behavior, retry, idempotency, or rollback protection?
- What must not be updated if a later step fails?

### User-Visible vs Internal Observability

- Which output is user/customer/business visible?
- Which output is only internal logging, telemetry, audit, or debugging?
- Is an existing helper responsible for fixed visible copy or fields?
- Where can internal detail be added without changing the visible contract?

### Compatibility / Existing Helpers

- Is the existing helper semantically correct, or just conveniently close?
- What default values or hidden side effects does the helper add?
- Is extending the helper safer than adding a new path, or would it change old behavior?
- What old path is explicitly out of scope?

### Validation

- Which assertion proves the chosen option?
- Which assertion proves the rejected option was not accidentally used?
- Is this a behavior test, contract test, static check, or documented blocker?
- What coverage cap applies if only static evidence exists?

## Golden Output Shape

```markdown
| PB id | requirement / fact | question | option A | option B | chosen | rejected because | risk | validation assertion |
|-------|--------------------|----------|----------|----------|--------|------------------|------|----------------------|
| PB-01 | fixed output field has two possible sources | Which source is authoritative? | persisted field | request/display field | persisted field | display input can be stale | stale fallback | test asserts stale display input is ignored |
```
