# Complex Requirement Delivery Kit

Use this kit when a requirement has fixed literals, multiple surfaces, cross-module implementation, external integrations, async tasks, reports/exports, logs, state transitions, or data persistence.

The purpose is to turn a blocking NO-GO into a concrete ready-for-implementation package.

## 0. Branch / Commit Reconstruction Addendum

Use this addendum when there is no PRD, but the user provides a branch, commit range, patch, or target diff. The diff is evidence or oracle material; it is not a PRD until a human confirms the reconstructed requirement.

```markdown
| Inferred requirement | Confidence | Evidence | Missing source | Verification gap | Next step |
|----------------------|------------|----------|----------------|------------------|-----------|
```

```markdown
| File family | Role | Expected or surprising | Shared impact | Validation |
|-------------|------|------------------------|---------------|------------|
```

Rules:

- Confidence is `high`, `medium`, or `low`; low/medium rows cannot become implementation contracts without confirmation.
- For no-doc bugfixes, missing logs, stack traces, failing tests, or reproduction inputs must become `verification_gap`.
- External integrations require request, response, signature, encoding, config keys, success/failure codes, and empty/null/fallback behavior.
- If the diff touches shared enums, base handlers, framework files, shared DTOs, shared utilities, or public config, upgrade to shared-impact planning.
- Compile success proves structure only; it does not prove business behavior or external protocol correctness.

## 1. Requirement Freeze Matrix

```markdown
| Req ID | Requirement literal | Order / priority | must happen | must not happen | Owner / surface | Code location | Test assertion | Status |
|--------|---------------------|------------------|-------------|-----------------|-----------------|---------------|----------------|--------|
| R-001 |                     |                  |             |                 |                 |               |                | mapped / gap |
```

Rules:

- Keep the original literal text.
- Ordered conditions are requirements, not implementation details.
- `must not happen` is mandatory for fallback, side effects, empty values, status fields, and failure paths.
- `Status=gap` blocks coding.

## 2. Field And Data Source Matrix

```markdown
| Req ID | Requirement label | Required source | Domain field | DB / external field | Stored value | Display value | Forbidden fallback/default | Test assertion |
|--------|-------------------|-----------------|--------------|---------------------|--------------|---------------|----------------------------|----------------|
```

Rules:

- Adjacent labels such as source/type/count/directory/status/result must map to distinct fields.
- If a value must come from an external payload, do not fall back to page value, manual value, old DB value, or helper default.
- If the backend cannot observe a UI-only raw value, mark it as a design gap before coding.

## 3. Surface Coverage Matrix

```markdown
| Surface ID | Surface | Entry | Orchestration | Query/write point | Output/display | Independent validation | Status |
|------------|---------|-------|---------------|-------------------|----------------|------------------------|--------|
```

Rules:

- Every listed API/page/export/task/log/display is a separate surface.
- Similar entries do not cover each other.
- Each surface needs its own validation.

## 3.5 Autonomous Coverage Ledger

Use this ledger when the user asks for autonomous implementation, minimal interruptions, or 90%+ coverage from a requirement document.

```markdown
| Req ID | Requirement item | Priority | Weight | Literal / wire fields | Surface | Expected files | Verification | Status |
|--------|------------------|----------|--------|-----------------------|---------|----------------|--------------|--------|
```

Priority values:

- `core_path`: main business flow, state transition, primary write/output, or core acceptance path.
- `supporting_surface`: report, export, log, notification, async job, admin task, or secondary surface.
- `optional_or_later`: explicitly deferrable or not required for the current delivery.
- `frontend_or_external`: cannot be completed by the current implementation owner alone.
- `out_of_scope`: not part of this delivery.

Rules:

- Core path rows must be implemented before lower-risk supporting slices.
- Weighted coverage is based on requirement behavior and verification evidence, not file hit rate.
- `optional_or_later`, `frontend_or_external`, and `out_of_scope` do not count toward the numerator.
- If a deferred or external row blocks the core path, the overall result is `PARTIAL` or `BLOCKED`.

## 3.6 Change Impact Search Matrix

Use this before Expected Diff when the change touches rules, conditions, field sources, enums, data-source switching, method signatures, shared helpers, or repeated implementations.

```markdown
| change axis | search evidence | must-change locations | maybe-change locations | explicitly-excluded | consistency rule |
|-------------|-----------------|-----------------------|------------------------|---------------------|------------------|
```

Search evidence should cover method names, field reads/writes, assignments, enum reverse lookups, SQL/filter/select, callers, serialization/deserialization, templates/export columns, and test fixtures. If `must-change locations` are uncertain, implementation readiness is `NO-GO`. Exclusions require a reason; “not involved” without evidence is not enough.

## 4. Expected Diff Matrix

```markdown
| Req ID | Expected modules | Expected file families | Change type | Out-of-scope file families | Validation |
|--------|------------------|------------------------|-------------|----------------------------|------------|
```

Rules:

- File families are enough before coding: service, DTO, mapper, template, tests, config, controller, facade, etc.
- Name out-of-scope families explicitly so scope drift is visible.
- Actual diff must be compared with this matrix before completion.

### 4A. File Family Granularity

Expected Diff must be specific enough to prove the entry and carrier are covered:

- Do not write only generic families such as “service / mapper / test”; name the file family that carries the runtime entry.
- Image, attachment, and template work should include template/rendering, storage or upload, metadata write, and behavior tests.
- Report, export, and query-page work should include request/DTO carrier, SQL select/filter, page/script input, real exporter or controller/service, and header/value assertions.
- Async or automatic-flow work should include trigger point, orchestration service, transaction boundary, state progression, progress/log/task side effects, failure isolation, rollback, and must-not tests.
- External protocol work should include request/response fixtures, payload builder, field casing, array/object/string shape, serialization assertions, and error/null contracts.
- Stateful core paths need a transaction-depth test plan; mock-only collaborator tests require a coverage cap.
- `core_path` must include a real production entry or carrier such as controller, facade, processor, worker, exporter, mapper, or scheduler.

## 5. TDD Coverage Plan

```markdown
| Test ID | Req rows covered | Surface covered | Positive assertion | Reverse assertion | Command | Expected RED |
|---------|------------------|-----------------|--------------------|-------------------|---------|--------------|
```

Rules:

- Small GREEN is not completion.
- Tests must cover freeze rows, surfaces, field-source rows, and must-not side effects.
- `testCompile` or environment failures are not business RED.

## 5.5 Baseline And Verification Blocker Matrix

```markdown
| Stage | Command / evidence | Expected result | Actual result | Blocker classification | Action | What passing proves |
|-------|--------------------|-----------------|---------------|------------------------|--------|---------------------|
```

Allowed blocker classifications:

- `none`: command produced the expected evidence.
- `baseline_compile_blocker`: unchanged baseline cannot compile or collect tests.
- `feature_diff_blocker`: current effective diff introduced compile or test collection failure.
- `test_runtime_blocker`: target test can run but runtime data, container, external service, or fixture blocks it.
- `environment_blocker`: dependency resolution, permission, network, toolchain, or shell parsing blocks validation.

Rules:

- `baseline_compile_blocker` and `environment_blocker` block completion, but they are not requirement RED.
- When a command is intended as RED evidence, record the row or behavior that should fail; generic compile failure is not enough.
- PowerShell static Maven commands with `-Dtest` / `-Dsurefire` can use `mvn --%` for copy-ready output.
- If the command uses variables, generated paths, or dynamic filters, use argument arrays or explicit quoting instead of `--%`.

## 6. Readiness Decision

```markdown
## Implementation Readiness

- Requirement Freeze Matrix: complete / gaps
- Field And Data Source Matrix: complete / gaps / n/a
- Surface Coverage Matrix: complete / gaps / n/a
- Autonomous Coverage Ledger: complete / gaps / n/a
- Expected Diff Matrix: complete / gaps
- TDD Coverage Plan: complete / gaps
- Baseline And Verification Blocker Matrix: complete / gaps
- OpenSpec + .doc: complete / gaps
- Human review: approved / pending
- Decision: READY / NO-GO
- Blocking gaps:
```

`READY` requires no `gap` rows and human approval when the workflow has a review gate.

## 7. Final Completion Check

Before declaring done:

```markdown
| Gate | Evidence | Result |
|------|----------|--------|
| Requirement freeze rows implemented | code + tests | pass/fail |
| Field/source rows implemented | code + tests | pass/fail |
| Surface rows validated | commands/assertions | pass/fail |
| Autonomous weighted coverage | ledger + verification | pass/fail/n-a |
| Expected diff matched actual diff | diff summary | pass/fail |
| Original RED rerun | command output | pass/fail |
| Baseline blockers classified | matrix + action | pass/fail |
| No unplanned scope drift | file list | pass/fail |
```

Any fail means `PARTIAL`, not complete.
