# Commit 类型完整列表

## 核心类型（会出现在 CHANGELOG）

| 类型 | 标题 | 描述 |
|------|------|------|
| `feat` | 功能 | 新增功能 |
| `fix` | Bug | 修复 Bug |
| `ui` | UI样式 | 更新 UI 或者样式 |
| `build` | 构建 | 构建相关 (maven/gradle/npm/jenkins) |
| `docs` | 文档 | 文档相关 |
| `style` | 优化代码 | 改善代码结构/格式化代码（不影响业务） |
| `refactor` | 重构代码 | 重构代码 |
| `perf` | 性能 | 提高性能 |
| `test` | 测试 | 添加/编辑测试代码 |
| `ci` | 持续集成 | CI 相关 |
| `revert` | 回滚 | 回滚改动 |
| `config` | 配置文件 | 修改配置文件 |
| `quickfix` | HotFix | hotfix |
| `security` | 安全 | 修复安全问题 |
| `k8s` | Kubernetes | Kubernetes 相关 |
| `docker` | Docker | Docker 相关 |
| `deploy` | 部署 | 部署相关 |
| `analytics` | 埋点分析 | 添加埋点/分析相关代码 |
| `animation` | 动画 | 动画相关修改 |
| `breaking` | Breaking | 引入了破坏性的修改 |
| `poo` | 挖坑 | 写了一段待改进的糟糕代码 |
| `access` | 辅助功能 | 改善辅助功能 |
| `db` | 数据库 | 数据库相关修改（DDL/DML/索引/存储过程） |
| `ux` | UX | 提高用户体验/易用性 |
| `arch` | 架构 | 架构变更 |
| `responsive` | 响应式 | 响应式设计相关 |
| `seo` | SEO | SEO 相关 |
| `api` | API | 接口新增/修改/废弃 |
| `cache` | 缓存 | 缓存策略相关（Redis/本地缓存） |
| `mq` | 消息队列 | 消息队列相关（Kafka/RocketMQ/RabbitMQ） |
| `rpc` | RPC | 远程调用相关（Dubbo/gRPC/Feign） |

## 辅助类型（不出现在 CHANGELOG）

| 类型 | 描述 |
|------|------|
| `wip` | 临时提交，还在进度中（满足每天提交要求） |
| `beer` | 喝醉了写点代码 |
| `prune` | 删除代码或文件 |
| `init` | 初始化 commit |
| `release` | Releasing / Version tags |
| `lint` | 优化代码改善工具警告 |
| `docs-code` | 给源码加上注释 |
| `texts` | 更新文案或文字 |
| `downgrade` | 降级依赖版本 |
| `upgrade` | 升级依赖版本 |
| `dep-add` | 添加依赖 |
| `dep-rm` | 删除依赖 |
| `dep-up` | 更新依赖 |
| `i18n` | 国际化多语言支持 |
| `typo` | 修复错别字 |
| `merge` | 合并分支 |
| `mv` | 移动或重命名文件 |
| `review` | 由于代码 review 而更新代码 |
| `osx` | 修复 macOS 上的问题 |
| `linux` | 修复 Linux 上的问题 |
| `windows` | 修复 Windows 上的问题 |
| `android` | 修复 Android 上的问题 |
| `ios` | 修复 iOS 上的问题 |
| `experiment` | 试验新技术（功能）点 |
