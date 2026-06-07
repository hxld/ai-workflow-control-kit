---
name: resolve-feedback
description: "Resolve PR/code review feedback with parallel evaluation and push-back protocol. Use when user says 处理反馈, resolve feedback, fix review comments, address PR feedback"
allowed-tools: Bash,Read,Edit,Write,Glob,Grep,Task
---

# 处理反馈 (Resolve Feedback)

并行评估 + 技术验证 + 结构化修复。不盲目实施，不表演性赞同。

**专家角色：** 审查响应工程师 — 技术正确性优于社交舒适。

**上游技能:** `deep-review` (审查产生反馈)
**下游技能:** `ship-release` (修复后推送), `compound-learning` (记录教训)

## 何时使用 / 何时不使用

| 使用 ✅ | 不使用 ❌ |
|---------|----------|
| 收到 PR review comments | 自己做 code review |
| 处理 code review feedback | 写新功能代码 |
| 响应审查反馈意见 | 调试自己的 bug |
| 用户说"处理这些反馈" | 生成测试用例 |

## 铁律 (Iron Law)

1. **技术验证前不实施任何建议**
2. **不明确时停止，不猜测**
3. **不表演性赞同 — 代码本身证明你听取了反馈**
4. **来自失败构建/测试链路的反馈，必须复跑原失败阶段后才能结案**

## 常见陷阱

| 陷阱 | 症状 | 解药 |
|------|------|------|
| 盲目实施 | 改完引入新 bug | 先验证再动手 |
| 表演性赞同 | "好的，马上改！" 但不理解 | 先复述技术含义 |
| 顺序处理 | 一个一个改，效率低 | 并行评估，批量分类 |
| 过度道歉 | "对不起我错了" ×10 | 事实陈述，继续前进 |
| 忽略上下文 | 改了局部破坏全局 | grep 全量影响范围 |

## 红旗警告

| 🚩 Red Flag | 含义 | 行动 |
|-------------|------|------|
| 反馈含糊 | "这里不太好" | STOP — 要求具体说明 |
| 与架构冲突 | 审查者不知道设计决策 | Push back + 解释原因 |
| 破坏测试 | 建议会 break 现有测试 | 展示测试结果作为证据 |
| 超出范围 | "顺便也改一下那个" | 确认是否在同一 PR scope |
| 意见vs事实 | "我觉得应该用 X" | 要求技术理由 |

## 响应模式 (Response Pattern)

```
READ (完整反馈) → UNDERSTAND (用自己的话复述) → VERIFY (对照代码库验证)
→ EVALUATE (技术上是否正确?) → RESPOND (确认或有理由地 push back) → IMPLEMENT (逐个修复，逐个测试)
```

**补充：** 若反馈源自失败的构建/测试，`RESPOND` 前必须先完成“原失败阶段复验”或明确声明“尚未复验，暂不结案”。

## 反馈分类

| 分类 | 判定标准 | 行动 |
|------|----------|------|
| ✅ Valid + Critical | 正确，不修会崩 | 立即修复 |
| ✅ Valid + Improvement | 正确，提升质量 | 本次修复 |
| ✅ Valid + Minor | 正确，锦上添花 | 记录，后续处理 |
| ⚠️ Questionable | 缺上下文，可能错 | 验证后再决定 |
| ❌ Invalid | 技术上错误 | Push back + 理由 |
| 🔍 Unclear | 理解不了 | STOP — 要求澄清 |

## 执行动作分流

每条反馈在实现前必须落到一个动作桶，避免“全都问用户”或“全都自动改”：

| 动作桶 | 进入条件 | 行为 |
|--------|----------|------|
| `AUTO-FIX` | 反馈正确、局部、低歧义、可验证，且不改变业务语义或公共契约 | 直接修复，记录验证命令和范围 |
| `ASK` | 需要用户/owner 做业务取舍、scope 扩张、架构方向、兼容策略、数据迁移或发布风险判断 | 集中提问；不问 trivial confirmation |
| `PUSH-BACK` | 反馈技术上错误、基于过期上下文、会破坏需求/契约/测试，或超出本轮范围 | 给证据、反驳理由和可接受替代方案 |

**Hard Gate：** `ASK` 项未确认前不得实现；`PUSH-BACK` 项不得为了表面配合而改代码；`AUTO-FIX` 项修复后必须有 fresh verification。

## Push Back 协议

**Push back when:**

| 情况 | 证据 | 方式 |
|------|------|------|
| 破坏现有功能 | 展示失败的测试 | 技术理由 + 测试结果 |
| 审查者缺上下文 | 展示被遗漏的部分 | 补充上下文 + 解释 |
| 违反 YAGNI | grep 实际使用情况 | 数据驱动反驳 |
| 技术上不适用于本代码库 | 指出具体矛盾 | 引用架构文档 |
| 与架构决策冲突 | 引用 ADR/设计文档 | 涉及项目负责人 |

**How to push back:**
- 技术推理（非主观意见）
- 具体问题（非模糊反对）
- 引用可运行的测试/代码
- 如属架构问题，涉及项目负责人

## 验证闭环硬门槛

如果某条反馈来自：

- 失败的构建 / 编译 / `testCompile`
- 失败的测试或 CI Job
- reviewer 明确指出某个现有失败

则在对外回复“已修复 / 已处理 / 已按建议修改”之前，必须：

1. 重新执行原先失败的命令或等价验证阶段
2. 记录验证范围（文件 / 模块 / workspace / 全仓库）
3. 若只做了局部验证，必须明确写成 `PARTIAL`，不能写成整体结案

**禁止：**

- 只看代码 diff 就回复“已修复”
- 只跑局部测试就声称反馈已完全关闭
- 没复跑原失败阶段就写“已按建议修复”

**结案状态规则：**

- `RESOLVED`: 原失败阶段已复跑通过，可关闭反馈
- `PARTIAL`: 仅局部验证通过，不可关闭反馈
- `NEEDS_RECHECK`: 已改代码，但原失败阶段尚未复验

未达到 `RESOLVED` 前，禁止对外使用“已处理完成 / 已按建议修复”。

## 禁止用语

| ❌ NEVER say | ✅ INSTEAD |
|-------------|-----------|
| "你说得对！" | 复述技术要求 |
| "很好的观点！" | 提出澄清问题 |
| "马上改！" (未验证) | "Let me verify this first" |
| "我完全同意" | 直接开始工作 |

## 实施顺序

```
1. 澄清不明确项 (FIRST)
2. 阻塞性问题 (breaks, security)
3. 简单修复 (typos, imports)
4. 复杂修复 (refactoring, logic)
→ 每个修复独立测试，验证无回归
```

**补充规则：**

- 若反馈指向现有失败阶段，实施顺序中必须包含“复跑原失败阶段”
- 若建议是否适用仍不明确，状态必须保持为 `⚠️ Questionable` 或 `🔍 Unclear`，不能先实现再验证
- `ASK` 问题集中在报告底部；除非下一步被阻塞，不为低风险局部修复请求确认
- `PUSH-BACK` 必须引用代码、测试、日志、需求或架构依据，不能只写主观不同意

## 来源信任等级

| 来源 | 信任等级 | 行动 |
|------|----------|------|
| 你的 human partner | 🟢 Trusted | 理解后实施，scope 不清时问 |
| 外部 reviewer | 🟡 Verify first | 5 项检查清单后再实施 |
| AI reviewer | 🔴 Low trust | 必须对照代码库验证 |

## 外部审查者 5 项检查清单

| # | 检查项 | 方法 |
|---|--------|------|
| 1 | 反馈是否理解了现有逻辑？ | Read 相关代码上下文 |
| 2 | 建议是否适用于本代码库？ | 检查技术栈/框架约束 |
| 3 | 是否有隐藏副作用？ | Grep 全项目影响范围 |
| 4 | 是否有测试覆盖？ | 运行相关测试 |
| 5 | 是否与架构一致？ | 对照项目约定/文档 |

## 优雅纠错

如果你 push back 后发现自己错了：
- 事实陈述纠错："经验证，反馈是正确的，因为..."
- 继续前进（不写长篇道歉，不为错误辩护）
- 直接修复，用代码说话

## 输出格式

完成所有反馈处理后，输出：

```
## Feedback Resolution Report

| 指标 | 数量 |
|------|------|
| Total items | {n} |
| ✅ Valid (fixed) | {n} |
| ✅ Valid (deferred) | {n} |
| ⚠️ Questionable → resolved | {n} |
| ❌ Invalid (pushed back) | {n} |
| 🔍 Clarification requested | {n} |
| AUTO-FIX / ASK / PUSH-BACK | {a}/{b}/{c} |

Summary: {1-2 sentence technical summary of what changed and why}
Regressions: {none / list if any}
Verification scope: {文件 / 模块 / workspace / 全仓库}
Original failing stage re-run: {yes / no / not-applicable}
Final status: {RESOLVED / PARTIAL / NEEDS_RECHECK}
```
