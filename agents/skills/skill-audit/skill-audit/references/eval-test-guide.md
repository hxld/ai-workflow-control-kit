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
| `dry_run` | 模拟推演，未实际执行 | 中 |

优先 `full_test`。如子 agent 不可用（超时/环境限制）则退化为 `dry_run`。

## 与现有 EVAL 路由的关系

- `EVAL`（现有）：读 `evals/evals.json` 逐条断言验证 → 验证技能文本质量
- `EVAL-TEST`（新增）：设计测试 prompt 对比跑 → 验证技能实际效果
- 两者互补，不替代
