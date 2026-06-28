# 复杂需求交付包

当需求包含固定字面量、多 surface、跨模块实现、外部集成、异步任务、报表/导出、日志、状态流转或数据持久化时使用。

目标：把阻塞性的 NO-GO 转成具体、可实现、可验证的交付包。

## 0. 分支 / 提交反推补充

没有 PRD，但用户提供分支、commit range、patch 或目标 diff 时使用。diff 是证据或后验材料；在人工确认反推需求前，不是 PRD。

```markdown
| 反推需求 | 置信度 | 证据 | 缺失来源 | 验证缺口 | 下一步 |
|----------|--------|------|----------|----------|--------|
```

```markdown
| 文件族 | 角色 | 预期内/意外 | 共享影响 | 验证方式 |
|--------|------|------------|----------|----------|
```

Rules:

- Confidence is `high`, `medium`, or `low`; low/medium rows cannot become implementation contracts without confirmation.
- For no-doc bugfixes, missing logs, stack traces, failing tests, or reproduction inputs must become `verification_gap`.
- External integrations require request, response, signature, encoding, config keys, success/failure codes, and empty/null/fallback behavior.
- If the diff touches shared enums, base handlers, framework files, shared DTOs, shared utilities, or public config, upgrade to shared-impact planning.
- Compile success proves structure only; it does not prove business behavior or external protocol correctness.

## 1. 需求冻结矩阵

```markdown
| 需求ID | 需求字面量 | 顺序/优先级 | 必须发生 | 禁止发生 | owner/surface | 代码落点 | 测试断言 | 状态 |
|--------|------------|-------------|----------|----------|---------------|----------|----------|------|
| R-001 |                     |                  |             |                 |                 |               |                | mapped / gap |
```

Rules:

- Keep the original literal text.
- Ordered conditions are requirements, not implementation details.
- `must not happen` is mandatory for fallback, side effects, empty values, status fields, and failure paths.
- `Status=gap` blocks coding.

## 2. 字段与数据来源矩阵

```markdown
| 需求ID | 需求标签 | 必需来源 | 领域字段 | DB/外部字段 | 落库值 | 展示值 | 禁止 fallback/default | 测试断言 |
|--------|----------|----------|----------|------------|--------|--------|-----------------------|----------|
```

Rules:

- Adjacent labels such as source/type/count/directory/status/result must map to distinct fields.
- If a value must come from an external payload, do not fall back to page value, manual value, old DB value, or helper default.
- If the backend cannot observe a UI-only raw value, mark it as a design gap before coding.

## 3. Surface 覆盖矩阵

```markdown
| Surface ID | Surface | 入口 | 编排 | 查询/写入点 | 输出/展示 | 独立验证 | 状态 |
|------------|---------|------|------|------------|----------|----------|------|
```

Rules:

- Every listed API/page/export/task/log/display is a separate surface.
- Similar entries do not cover each other.
- Each surface needs its own validation.

## 3.5 自主实现覆盖账本

当用户要求基于需求文档自主实现、少打扰或 90%+ 覆盖时使用。

```markdown
| 需求ID | 需求项 | 优先级 | 权重 | 字面量/协议字段 | Surface | 预计文件 | 验证方式 | 状态 |
|--------|--------|--------|------|----------------|---------|----------|----------|------|
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

## 3.6 改动影响搜索矩阵

当改动涉及规则、条件、字段来源、枚举、数据源切换、方法签名、共享 helper 或重复实现时，在预计变更前使用。

```markdown
| 改动轴 | 搜索证据 | 必改位置 | 可能改动位置 | 明确排除 | 一致性规则 |
|--------|----------|----------|--------------|----------|------------|
```

Search evidence should cover method names, field reads/writes, assignments, enum reverse lookups, SQL/filter/select, callers, serialization/deserialization, templates/export columns, and test fixtures. If `must-change locations` are uncertain, implementation readiness is `NO-GO`. Exclusions require a reason; “not involved” without evidence is not enough.

## 4. 预计变更矩阵

```markdown
| 需求ID | 预计模块 | 预计文件族 | 改动类型 | 范围外文件族 | 验证方式 |
|--------|----------|------------|----------|--------------|----------|
```

Rules:

- File families are enough before coding: service, DTO, mapper, template, tests, config, controller, facade, etc.
- Name out-of-scope families explicitly so scope drift is visible.
- Actual diff must be compared with this matrix before completion.

### 4A. 文件族粒度

Expected Diff must be specific enough to prove the entry and carrier are covered:

- Do not write only generic families such as “service / mapper / test”; name the file family that carries the runtime entry.
- Image, attachment, and template work should include template/rendering, storage or upload, metadata write, and behavior tests.
- Report, export, and query-page work should include request/DTO carrier, SQL select/filter, page/script input, real exporter or controller/service, and header/value assertions.
- Async or automatic-flow work should include trigger point, orchestration service, transaction boundary, state progression, progress/log/task side effects, failure isolation, rollback, and must-not tests.
- External protocol work should include request/response fixtures, payload builder, field casing, array/object/string shape, serialization assertions, and error/null contracts.
- Stateful core paths need a transaction-depth test plan; mock-only collaborator tests require a coverage cap.
- `core_path` must include a real production entry or carrier such as controller, facade, processor, worker, exporter, mapper, or scheduler.

## 5. TDD 覆盖计划

```markdown
| 测试ID | 覆盖需求行 | 覆盖 Surface | 正向断言 | 反向断言 | 命令 | 预期 RED |
|--------|------------|--------------|----------|----------|------|----------|
```

Rules:

- Small GREEN is not completion.
- Tests must cover freeze rows, surfaces, field-source rows, and must-not side effects.
- `testCompile` or environment failures are not business RED.

## 5.5 基线与验证阻断矩阵

```markdown
| 阶段 | 命令/证据 | 预期结果 | 实际结果 | blocker 分类 | 行动 | 通过后能证明什么 |
|------|----------|----------|----------|-------------|------|----------------|
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

## 6. 实现就绪决策

```markdown
## 实现就绪

- 需求冻结矩阵: complete / gaps
- 字段与数据来源矩阵: complete / gaps / n/a
- Surface 覆盖矩阵: complete / gaps / n/a
- 自主实现覆盖账本: complete / gaps / n/a
- 预计变更矩阵: complete / gaps
- TDD 覆盖计划: complete / gaps
- 基线与验证阻断矩阵: complete / gaps
- OpenSpec + .doc: complete / gaps
- 人工审查: approved / pending
- 决策: READY / NO-GO
- 阻断缺口:
```

`READY` requires no `gap` rows and human approval when the workflow has a review gate.

## 7. 最终完成检查

宣称完成前必须检查：

```markdown
| 门禁 | 证据 | 结果 |
|------|------|------|
| 需求冻结行已实现 | 代码 + 测试 | pass/fail |
| 字段/来源行已实现 | 代码 + 测试 | pass/fail |
| Surface 行已验证 | 命令/断言 | pass/fail |
| 自主实现加权覆盖 | 账本 + 验证 | pass/fail/n-a |
| 预计变更匹配实际 diff | diff 摘要 | pass/fail |
| 原始 RED 已复跑 | 命令输出 | pass/fail |
| 基线 blocker 已分类 | 矩阵 + 行动 | pass/fail |
| 无计划外范围漂移 | 文件列表 | pass/fail |
```

Any fail means `PARTIAL`, not complete.
