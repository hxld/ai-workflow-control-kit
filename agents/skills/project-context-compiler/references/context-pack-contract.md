# Context Pack Contract

Use this reference when a project needs more than root guidance.

## L1 Starter Context

Create these files under `.doc/<project>-system-context/`.

### README.md

Purpose: navigation only.

Required sections:

- recommended reading order
- source boundaries
- maintenance rules
- known gaps

### 项目AI上下文指南.md

Purpose: the first document AI should read.

Required sections:

- project positioning
- fact sources
- module or application structure
- main runtime entry points
- core workflows or user journeys
- data anchors or identifiers
- external dependencies and configuration sources
- evidence layering rules
- current gaps

### 项目总分析报告.md

Purpose: compact architecture and ownership summary.

Required sections:

- project role in the system
- technology stack
- module responsibilities
- important APIs, jobs, listeners, or UI routes
- important data/config surfaces
- operational or implementation risks

## L2 Working Context

Add files only when useful:

| File | Use |
| --- | --- |
| `模块与运行入口地图.md` | map modules to controllers, services, jobs, commands, launchers, pages, or routes |
| `核心流程索引.md` | document primary workflows and call chains |
| `数据库上下文索引.md` | summarize schemas, tables, relations, and data anchors |
| `外部系统与配置索引.md` | list config sources, RPC/HTTP/MQ dependencies, and runtime overrides |

## L3 Expert Context

Add files for high-frequency or risky projects:

| File | Use |
| --- | --- |
| `状态字典与业务码索引.md` | state machines, enums, business codes, and transition risks |
| `排查手册.md` | case/order/task oriented investigation paths |
| `变更影响分析指南.md` | blast radius rules for shared methods, DTOs, APIs, SQL, jobs, and pages |
| `跨仓库关系索引.md` | frontend/backend/scheduler/provider relationships |

## Entity And Relationship Tables

When helpful, use lightweight graph-style tables:

```markdown
| 实体 | 类型 | 所属模块 | 运行入口 | 数据锚点 | 外部依赖 | 置信度 | 证据 |
| --- | --- | --- | --- | --- | --- | --- | --- |

| From | 关系 | To | 证据 | 置信度 |
| --- | --- | --- | --- | --- |
```

## Evidence Status

Use only these statuses:

- `源码已验证`
- `文档已记录`
- `高可信推断`
- `待配置/日志/生产确认`

Do not collapse inferred relations into verified facts.
