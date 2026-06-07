# Audit Checklists

本文件承接 `skill-audit` 的长清单，避免主 `SKILL.md` 超预算。

## P0 检查清单

| # | 检查项 | 验证方法 |
|---|--------|----------|
| 1 | description 包含足够触发关键词/短语 | 提取 description，数关键词 |
| 2 | description 不含功能摘要 | 检查是否保持纯触发器 |
| 3 | 无硬编码路径/用户名/邮箱 | grep 硬编码模式 |
| 4 | 高风险技能有 Iron Law 或等效规则 | 检查纪律段 |
| 5 | 行数符合类型预算 | `SKILL.md` 行数审计 |
| 6 | 上/下游技能关系正确 | 引用的技能实际存在 |
| 7 | YAML frontmatter 有 name + description | frontmatter 解析 |
| 8 | references/ 引用一致 | 声明文件存在且被引用 |
| 9 | 技能源头/镜像/备份规则清楚 | 读取 `.agents/AGENTS.md` 或 manifest |
| 10 | replay/eval 规则未污染普通主链 | replay-only 门禁限制在 audit/eval 分支 |
| 11 | replay 报告披露模式和 oracle 使用 | 检查 mode / oracle / validation root |
| 12 | 技能变更有最小 eval 证据或跳过原因 | 查 trigger/output/pressure/no_eval_reason |

## 深度检查维度

- 验证纪律：有验证标准和硬证据。
- 红旗词汇：有 Red Flags / Common Rationalizations。
- 证据分级：区分命令输出与软判断。
- 增量验证：每阶段有独立验证。
- 失败处理：有 graceful exit。
- 上下文隔离：任务描述完整。
- 结构化流程：有 route table / decision tree / mandatory workflow。
- 覆盖率审计：处理路径和输出格式一致。
- 外部集成覆盖：覆盖鉴权、幂等、集成依赖。
- 专家派遣、结构化发现、双轨道知识、Replay 失败吸收、Source Governance、Mode Separation。

## 行数预算审计

| 类型 | 目标 | 超预算判定 |
|------|-----:|------------|
| 路由类 | 80-150 | >200 通常 P1，>250 通常 P0 |
| 守门类 | 120-220 | >250 需拆分理由与 `references/` 承接 |
| 主流程类 | 180-300 | >250 可接受，但每段必须直接影响执行 |
| 审查/测试类 | 180-300 | >250 可接受，但案例/模板必须外移 |
| 领域工具类 | 200-350 | >300 需说明触发频率低且步骤不可再拆 |

`250` 是默认预算，不是绝对红线。超过 250 行但正文直接影响执行、案例/模板已外移且审计报告说明暂不拆分，可记 P2 或通过。超过 300 行默认 P1；超过 350 行默认 P0，除非是低频领域工具且有明确理由。
