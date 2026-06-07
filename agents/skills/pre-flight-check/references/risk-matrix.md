# Risk Matrix for Pre-Flight Check

## 常见风险类型 vs 检查项

| 风险类型 | 典型症状 | 检查项 | 数据源 |
|----------|---------|--------|--------|
| 重复错误 | 同类错误再次出现 | MEMORY.md 中有相同 topic | `.memory/MEMORY.md` |
| 集成问题 | 接口契约不匹配 | error-lessons 中有 integration 标签 | `.memory/error-lessons.md` |
| 环境差异 | 本地通过线上失败 | 有 environment 标签的条目 | `.memory/learnings.jsonl` |
| 数据迁移 | 数据结构变更 | 有 migration/database 标签 | `docs/solutions/` |
| 并发问题 | 竞态条件/死锁 | 有 concurrency 标签 | `.memory/learnings.jsonl` |
| 安全漏洞 | 注入/XSS/越权 | 有 security 标签 | `.memory/error-lessons.md` |
| 性能退化 | N+1/全表扫描/大对象 | 有 performance 标签 | `.memory/learnings.jsonl` |

## 风险评估矩阵

| 操作类型 | 高风险 | 中风险 | 低风险 |
|----------|--------|--------|--------|
| 数据库 | DDL变更、数据迁移 | 新增索引、查询修改 | 只读查询 |
| API | 破坏性变更（删字段） | 新增字段、新增接口 | 修改文档 |
| 配置 | 生产环境变量修改 | 测试环境配置 | 本地配置 |
| 依赖 | 版本升级（大版本） | 新增依赖 | 版本锁定 |
| 并发 | 引入共享状态 | 新增锁机制 | 无状态操作 |

## 评估输出

预检查完成后输出：
```
已重读 MEMORY.md，识别到 {N} 条相关教训
风险等级: 🔴高 / 🟡中 / 🟢低
关联教训: [topic1, topic2, ...]
建议预防: [prevention1, prevention2, ...]
```
