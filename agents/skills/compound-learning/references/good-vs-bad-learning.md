# Good vs Bad Learning Entries

## Good Example (Bug Track)

```jsonl
{"id":"2026-04-08-001","track":"bug","date":"2026-04-08","severity":"🟡","topic":"JPA N+1查询","lesson":"@OneToMany关系默认LAZY但循环调用getSize()触发N次查询","files":["src/OrderService.java"],"tags":["jpa","performance","n+1"],"misconception":"以为LAZY就不会查数据库，实际是首次访问属性时触发","prevention":"使用JOIN FETCH或@EntityGraph一次性加载关联数据","root_cause":"未配置批量加载策略","resolution_type":"fix"}
```

**为什么好：** lesson 具体（不是"查询慢"而是"循环调用getSize()触发N次查询"），prevention 可执行，misconception 揭示了错误心智模型。

## Bad Example (Bug Track)

```jsonl
{"id":"2026-04-08-002","track":"bug","date":"2026-04-08","severity":"🟡","topic":"查询慢","lesson":"数据库查询太慢了要优化","files":[],"tags":["performance"]}
```

**为什么差：** lesson 模糊（"太慢了"没有具体原因），没有 prevention，没有 misconception，files 为空。

## Good Example (Knowledge Track)

```jsonl
{"id":"2026-04-08-003","track":"knowledge","date":"2026-04-08","category":"pattern","topic":"策略模式消除if-else","lesson":"当同类型if-else超过3个分支时，提取为策略接口+Map注册","applies_when":"同类型条件分支≥3个","tags":["design-pattern","strategy"],"confidence":0.9}
```

**为什么好：** applies_when 明确（"≥3个分支"），lesson 有具体阈值和方案。

## Bad Example (Knowledge Track)

```jsonl
{"id":"2026-04-08-004","track":"knowledge","date":"2026-04-08","category":"practice","topic":"写好代码","lesson":"代码要写得干净","applies_when":"写代码时","tags":["clean-code"]}
```

**为什么差：** "写得干净"是废话，applies_when 太宽泛（什么时候不写代码？），无实际价值。

## Decision Rule

| 维度 | Good | Bad |
|------|------|-----|
| lesson | 具体到操作级别 | 模糊的泛泛而谈 |
| prevention | 可执行的步骤 | "注意" "小心" |
| misconception | 揭示了错误的思维模型 | 无 |
| applies_when | 有明确触发条件 | "总是" "写代码时" |
| files | 涉及的具体文件 | 空 |
| tags | 3+ 具体标签 | 1个泛标签 |
