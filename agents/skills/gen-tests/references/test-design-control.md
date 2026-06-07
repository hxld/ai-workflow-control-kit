# AI-Assisted Test Design Control

Use this reference when a requirement is non-trivial, multi-surface, stateful, external-facing, or has explicit compatibility / must-not risk.

Core rule: humans confirm scope and risk; AI assists impact scanning, grouping, step generation, and coverage checking. Do not let AI free-generate tests without an agreed risk surface.

## Step 1: Impact Scope

```markdown
| Surface | Entry | Related change | Call/traffic/code evidence | Old data affected | Initial risk | Test in scope |
|---------|-------|----------------|----------------------------|-------------------|--------------|---------------|
```

Scan from both code diff and runtime/API/page/task entries. Remove false positives before test generation.

## Step 2: Risk Grading

```markdown
| Target | Change size | Branch point | Old data compatibility | External visibility | Risk | Test depth |
|--------|-------------|--------------|------------------------|---------------------|------|------------|
```

Answer three questions: how much changed, where the branch sits, and whether old data remains compatible.

## Step 3: Decision Table

```markdown
| Condition A | Condition B | Condition C | Expected result | Must test | Merge/keep reason |
|-------------|-------------|-------------|-----------------|-----------|-------------------|
```

Expand first, then merge equivalent cases. Do not merge away high-risk, boundary, old-data, or must-not cases.

## Step 4: Executable Steps

```markdown
| Case | Fixture/precondition | Action | Positive assertion | Side-effect assertion | Reverse assertion | Auto/manual |
|------|----------------------|--------|--------------------|-----------------------|-------------------|-------------|
```

Prefer one action with multiple verification dimensions: response, DB, state, log, file, page, export, message, or external payload.

## Step 5: Coverage Check

```markdown
| Surface | Positive | Negative | Old data compatibility | Side effects | Must-not | Status |
|---------|----------|----------|------------------------|--------------|----------|--------|
```

Status values: `covered`, `partial`, `not_applicable:<reason>`, `blocked:<reason>`.

## Mini Form

Small requirements may use:

```markdown
| Change | Impact | Risk | Test point | Must-not | Status |
|--------|--------|------|------------|----------|--------|
```

Mini form compresses expression only. It does not remove impact, risk, must-not, or coverage checks.
