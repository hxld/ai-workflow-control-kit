# Replay / Eval Development Gate

仅在用户明确要求历史重跑、oracle 对比、技能实测、独立验证或分支/提交复现时读取。普通 `planned-dev` 和 `hotfix` 不默认展开本文件。

## Before Phase 4

- 已切换到隔离 worktree / sandbox。
- 所有 `.doc`、`openspec`、测试产物和代码写入目标都位于隔离目录。
- 构建/测试命令指向当前隔离 workspace root；项目 profile 中的原 root 只能作为模板。
- 已声明 replay mode、oracle 使用时机、validation root 和是否修改技能/备份。
- 已拆分 `intended_change_slice` 与 `out_of_scope_drift`，禁止整分支或整补丁无筛选导入。

## Branch / Commit Derived

- 输出 `Inferred Requirement Matrix`：`inferred requirement -> confidence -> evidence -> missing source -> verification gap -> next step`。
- 输出 `Diff Role Matrix`：`file family -> role -> expected/surprising -> shared impact -> validation`。
- no-doc bugfix 没有日志、堆栈、失败测试或复现输入时，结论最多是 `compile_pass + static_inference + verification_gap`。
- 外部协议、共享文件、数据迁移或多 surface 命中时，必须升级设计或冻结契约。

## Test And Completion

- guard / contract / 冻结表测试必须逐行证明基线失败；整体 RED 不能替代行级 RED。
- replay/eval 报告不能把 oracle 对比结果表述成纯盲写能力。
- 集成测试涉及共享运行态时默认串行；并行只适合静态分析、文件切片、diff 对比和编译探测。
