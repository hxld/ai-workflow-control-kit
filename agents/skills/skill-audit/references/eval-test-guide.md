# EVAL-TEST 实测验证指南

借鉴 darwin-skill 的实测理念：不只看 SKILL.md 写得规不规范，更看**实际跑出来的效果是否更好**。

## 测试 Prompt 设计

为每个技能设计 2-3 个测试 prompt，覆盖：

| 类型 | 说明 |
|------|------|
| happy path | 最典型的使用场景 |
| 复杂/歧义 | 稍有难度或可多重理解的场景 |

保存到 `skill目录/evals/test-prompts.json`：

```json
[
  {"id": 1, "prompt": "用户会说的话", "expected": "期望输出的简短描述"},
  {"id": 2, "prompt": "...", "expected": "..."}
]
```

## 最小回归集（EVAL-MIN）

技能正文发生行为变化时，不一定每次都要跑完整子 agent 对比，但至少保留最小回归证据：

| 类型 | 数量 | 说明 |
|------|-----:|------|
| should-trigger | 2 | 用户这样说时应该加载该技能 |
| should-not-trigger | 1 | 相似但不该加载，防误触发 |
| pressure scenario | 1 | 旧技能容易失败或漏规则的真实压力场景 |
| golden output | 0-1 | 输出格式或门禁变化时必填 |
| no_eval_reason | 0-1 | 仅限错字、备份同步、changelog、路径说明 |

推荐保存到 `skill目录/evals/minimal-regression.json`，或写入当次审计/变更报告。

## 对比测试流程

```
[1] 设计测试 prompt → 用户确认
    ↓
[2] 对比执行：
    ├── with_skill: 加载该技能后执行 prompt
    └── baseline: 不带技能执行同一 prompt
    ↓
[3] 对比评分（1-10 分）：
    ├── 是否完成了用户意图？
    ├── 相比 baseline 质量提升明显吗？
    └── 技能是否引入了负面影响？
    ↓
[4] 记录 eval_mode：full_test 或 dry_run
```

## Evidence Schema

评估记录至少保留这些字段，便于后续复审而不是只看结论：

```json
{
  "id": "skill-name-case-001",
  "prompt": "真实或贴近真实的用户输入",
  "mode": "with_skill_vs_old_skill",
  "baseline": {"summary": "旧技能或不带技能的输出问题"},
  "with_skill": {"summary": "新技能输出的关键行为"},
  "assertions": [
    {"claim": "应识别触发边界", "status": "pass", "evidence": "输出中包含技能链和门禁"}
  ],
  "cost": {"time_seconds": null, "tokens": null, "extra_steps": 0},
  "human_feedback": "confirmed / rejected / not-collected",
  "transcript_notes": "触发点、偏离点、副作用或人工介入点"
}
```

字段规则：

- `assertions` 必须是可判定的行为，不写“更好、更完整”这类主观句。
- `evidence` 要能回到 transcript、输出锚点、命令、文件或人工反馈。
- `cost` 为空时要说明未采集；若额外步骤明显增加，应判断是否过度工程。
- 没有 `baseline` 时只能叫单版本静态检查，不能叫对比 eval。

## 评分标准

| 分数 | 含义 |
|:----:|------|
| 9-10 | 带技能明显优于 baseline，输出精准 |
| 7-8 | 带技能优于 baseline，有改进但不显著 |
| 5-6 | 两者持平，技能未产生明显差异 |
| 3-4 | 带技能反而比 baseline 差，可能过度约束 |
| 1-2 | 带技能严重干扰输出 |

## eval_mode 标记

| 模式 | 含义 | 可信度 |
|------|------|--------|
| `full_test` | 实际跑了子 agent 对比 | 高 |
| `minimal_regression` | 跑了 EVAL-MIN 轻量触发/输出回归 | 中高 |
| `dry_run` | 模拟推演，未实际执行 | 中 |

优先 `full_test`。如子 agent 不可用（超时/环境限制）则退化为 `dry_run`。

## 与现有 EVAL 路由的关系

- `EVAL`（现有）：读 `evals/evals.json` 逐条断言验证 → 验证技能文本质量
- `EVAL-MIN`（新增）：技能变更后的最小 trigger/output 回归 → 防误触发、漏触发、输出漂移
- `EVAL-TEST`（新增）：设计测试 prompt 对比跑 → 验证技能实际效果
- 两者互补，不替代
