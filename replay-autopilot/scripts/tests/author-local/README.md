# Author-local regression tests

这 5 个测试是**作者专属**的回归测试，依赖作者本机的证据树（`D:\opt\replay-evidence\...`）和特定历史回放 fixture。它们不参与通用产品化的可移植测试集，单独隔离在此。

## 为什么单独放

- 部分 fixture 是作者真实回放历史的产物（evolution-result `changed_files:`、特定 feature 的 PLAN_CONTRACT）
- 别的机器上即使设置 `AI_WORKFLOW_*` 环境变量，缺少对应 fixture 仍会 skip 或失败

这是 Stage 3（可评测演化）的已知边界，见 `replay-autopilot/README.md` 的路径配置章节和根仓库 `docs/PRODUCTIZATION_GUIDE.md`。

## 文件

- `Test-v289-TestHarnessAndWrapperSafety.ps1` — 校验 phase1 prompt 强制 test harness 使用；可移植（已修复架构债）
- `Test-v315-EvolutionResultStrictness.ps1` — 校验 evolution-result `changed_files` 严格性；fixture 含作者历史 evolution 输出
- `Test-v318-EarlyEvolutionValidation.ps1` — 校验早期 evolution 验证；同上
- `Test-v322-GreenPhaseGateIntegration.ps1` — GREEN phase 集成校验；fixture 含作者历史 run
- `Test-v395-CarrierOraclePathFallback.ps1` — carrier oracle 路径回退；引用作者项目 codebase
- `_debug-v289.ps1` — 调试辅助脚本，单独运行 v289

## 状态

- v289 已验证可移植：使用 `-SkipCarrierAndOracleChecks` 跳过 carrier/oracle 实时扫描，fixture 完全自包含
- 其余 4 个仍需 fixture 化（从作者 evidence 树抽成 in-repo 合成 fixture）才能移除 author-local 隔离
