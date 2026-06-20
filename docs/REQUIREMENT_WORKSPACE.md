# 需求工作空间隔离设计

## 概述

需求工作空间隔离是一种为每个需求创建独立工作空间的方法论。每个空间包含该需求的 PRD、技术方案、测试方案、中间产物，以及每个涉及服务的代码分支。

本设计来自刘宇帅的团队 AI 工程化实践——"第三步：需求工作空间隔离"，适配到 ai-workflow-control-kit 的现有框架。

## 核心动机

**多数团队知识库挂在单个服务下，跨服务需求时 AI 看不到全局。**

当需求涉及 3-4 个服务时，AI 只能在一个服务的上下文里打转，看不见全局，出来的方案缺胳膊少腿。

## 设计原则

### 1. 每个需求 = 一个独立工作空间

```
workspaces/req-<id>/
├── README.md              # 空间入口
├── req-manifest.yaml      # 需求元信息（机器可读）
├── prd/                   # PRD 相关
├── plan/                  # 技术方案
├── test/                  # 测试方案
├── services/              # 各服务的 git worktree
│   ├── svc-a/             # feature/req-<id>
│   └── svc-b/             # feature/req-<id>
└── .kit-references.md     # Kit 方法论文档引用
```

### 2. 每个服务一个分支，全部挂在这个空间下

每个服务创建独立的 `feature/req-<id>` 分支，通过 `git worktree` 隔离在工作空间内。Agent 实施时可以同时看见所有服务，跨服务的改动一次性做完。

### 3. 空间是临时的

需求上线后，工作空间可以被归档或删除。Worktree 分离后源码仓库不受影响。PRD、方案等产物可以反哺到知识库的对应领域。

### 4. 空间承载全链路制品

- PRD（需求文档）
- 技术方案（含设计决策记录）
- 测试方案（含边界用例）
- 代码变更（通过 worktree）
- Review 记录
- 复盘记录

## 与现有 Kit 组件的关系

```
start-requirement-workspace.js (本脚本)
    ↓ 创建空间骨架
需求工作空间
    ├── prd/ → requirement-assessment + prd-quality-check
    ├── plan/ → deep-plan + req-alignment-check
    ├── test/ → gen-tests
    ├── services/ → dev-workflow（在 worktree 中执行）
    └── 复盘 → retro → 反哺到 knowledge-base
         ↑
    [replay-autopilot 可在空间上回放验证]
```

### 对应关系

| 空间目录 | 对应 skill | 阶段 |
|---------|-----------|------|
| `prd/` | `requirement-assessment` + PRD 质量检测 | 需求 |
| `plan/` | `reg-alignment-check` → `deep-plan` | 规划 |
| `test/` | `gen-tests` | 测试 |
| `services/` | `dev-workflow` + `pre-flight-check` | 实现 |
| 变更后 | `deep-review` + `quality-check` | 审查 |
| 交付后 | `ship-release` + `retro` | 发布/复盘 |

## 使用方式

```bash
# 快速开始
node scripts/start-requirement-workspace.js REQ-001 --services svc-a,svc-b

# 交互模式
node scripts/start-requirement-workspace.js --interactive

# 只 dry-run 预览
node scripts/start-requirement-workspace.js REQ-001 --services svc-a --dry-run
```

## 与工作流编排地图的集成

需求工作空间是 WORKFLOW_MAP.md 中"需求接入"阶段的可选扩展：

```
[原始需求] ──→ 需求评估 ──→ [可选] 需求工作空间初始化
                               │
                               ├── prd/ → 评估 + 质量检测
                               ├── plan/ → 技术方案
                               └── services/ → 各服务 worktree
                                                    │
                                                    ▼
                                            dev-workflow 执行
```

## 与 Goal 模式的结合

需求工作空间可以作为 Goal 模式的执行环境：

```yaml
title: "实现 REQ-001"
inputs:
  workspace: "workspaces/req-001/"
  services: ["svc-a", "svc-b"]
constraints:
  - "工作空间 prd/ 中的 PRD 是实现契约"
  - "每个服务在 services/ 下有对应 worktree"
success_criteria:
  - "services/svc-a 和 services/svc-b 中代码变更完成"
  - "plan/README.md 中的方案已实施"
  - "test/README.md 中的测试已通过"
```

## 注意事项

- **空间不是代码仓库**：services/ 下的 worktree 指向原始仓库，删除工作空间不会丢失代码。
- **分支前缀**：默认 `feature/req-<id>`，可通过 `--branch-prefix` 自定义。
- **CI 集成**：如果 CI 按分支模式匹配，`feature/req-<id>` 能正常触发流水线。
- **多人协作**：各人可以在自己的机器上创建同名空间，分支推送到远端共享。

## 关联

- [WORKFLOW_MAP.md](./WORKFLOW_MAP.md) — 工作流编排主地图
- [../agents/reference/distillation-methodology/process-s0-to-s6.md](../agents/reference/distillation-methodology/process-s0-to-s6.md) — 系统蒸馏流程（与需求空间结合做领域知识构建）
- [../agents/skills/goal-mode/SKILL.md](../agents/skills/goal-mode/SKILL.md) — Goal 模式 skill（需求空间可作为 Goal 执行环境）
