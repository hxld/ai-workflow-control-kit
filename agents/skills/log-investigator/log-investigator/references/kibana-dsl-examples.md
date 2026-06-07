# Kibana DSL Query Examples

Elasticsearch query templates for log-investigator. See SKILL.md Query Degradation Strategy for level definitions.

## Base Query Template

```json
{"query":{"bool":{"must":[{"query_string":{"query":"{selector} AND message:({keywords})"}}],"filter":[{"range":{"@timestamp":{"gte":"{timeRange}","lte":"now"}}}]}},"size":100,"sort":[{"@timestamp":{"order":"desc"}}]}
```

## Scenario-Based Query Templates

### Scenario 1: Trace by traceId (L1)

**Known traceId — direct full call chain trace.**

```json
{"query":{"bool":{"must":[{"query_string":{"query":"traceId:\"550e8400-e29b-41d4-a716-446655440000\""}}]}},"size":200,"sort":[{"@timestamp":{"order":"asc"}}]}
```

**Note:** L1 query, direct hit. Sort ascending by time to reconstruct call chain.

---

### Scenario 2: Business ID + Method Name (L2)

**No traceId, but have business ID and Facade method name.**

```json
{"query":{"bool":{"must":[{"query_string":{"query":"businessId:\"ORD20260322001\" AND message:(\"createOrder\" OR \"OrderFacade\" OR \"submitOrder\")"}}],"filter":[{"range":{"@timestamp":{"gte":"now-1h","lte":"now"}}}]}},"size":100,"sort":[{"@timestamp":{"order":"desc"}}]}
```

**Note:** L2 query, narrow scope with business ID + framework log class name.

---

### Scenario 3: Framework Class + Method Name (L3)

**No traceId, no business ID — only class and method known.**

```json
{"query":{"bool":{"must":[{"query_string":{"query":"class:(\"PaymentServiceImpl\" OR \"PaymentFacade\") AND message:(\"processPayment\" OR \"handlePay\") AND (level:ERROR OR level:WARN)"}}],"filter":[{"range":{"@timestamp":{"gte":"now-3h","lte":"now"}}}]}},"size":200,"sort":[{"@timestamp":{"order":"desc"}}]}
```

**Note:** L3 query, widest scope. Filter ERROR/WARN to reduce noise.

---

### Scenario 4: Error Type Aggregation

**Unknown specific error — discover top recurring errors.**

```json
{"size":0,"aggs":{"by_error":{"terms":{"field":"message.keyword","size":20}}}}
```

**Note:** Aggregation query. Get specific error messages, then use Scenarios 1-3 for precise lookup.

---

### Scenario 5: Slow Interface Detection

**Find high-latency RPC calls.**

```json
{"query":{"bool":{"must":[{"query_string":{"query":"class:\"FeignMessageDispatcher\" AND message:.*time of used:[5-9][0-9]{3}"}}],"filter":[{"range":{"@timestamp":{"gte":"now-1h","lte":"now"}}}]}},"size":100,"sort":[{"@timestamp":{"order":"desc"}}]}
```

**Note:** Search for RPC calls >= 500ms. Adjust regex threshold as needed.

---

### Scenario 6: Application Logs by App Name (L5)

**Known app name, check recent logs.**

```json
{"query":{"bool":{"must":[{"match_phrase":{"kubernetes.labels.app":"{appName}"}}],"filter":[{"range":{"@timestamp":{"gte":"now-15m","lte":"now"}}}]}},"sort":[{"@timestamp":{"order":"desc"}}],"_source":["@timestamp","message","log.level"],"size":50}
```

**Note:** General app log query. Adjust time range based on issue description.

---

### Scenario 7: Error-Only Filter within App (L5)

**Filter ERROR level and exceptions from specific app.**

```json
{"query":{"bool":{"must":[{"match_phrase":{"kubernetes.labels.app":"{appName}"}},{"bool":{"should":[{"match_phrase":{"message":"Exception"}},{"match_phrase":{"message":"ERROR"}},{"match":{"log.level":"ERROR"}}],"minimum_should_match":1}}],"filter":[{"range":{"@timestamp":{"gte":"{startTime}","lte":"now"}}}]}},"sort":[{"@timestamp":{"order":"desc"}}],"_source":["@timestamp","message","log.level"],"size":50}
```

---

### Scenario 8: Business ID + Module Keyword Quick Locate (L5)

**"Feature not working" issues — use business ID + module keyword to find WARN logs.**

```json
{"query":{"bool":{"must":[{"match_phrase":{"kubernetes.labels.app":"{appName}"}},{"match_phrase":{"message":"{businessId}"}},{"match_phrase":{"message":"{moduleKeyword}"}}],"filter":[{"range":{"@timestamp":{"gte":"now-7d","lte":"now"}}}]}},"sort":[{"@timestamp":{"order":"asc"}}],"_source":["@timestamp","message"],"size":30}
```

**Note:** Extend time range to 7 days (feature issues may persist). Sort ascending to find first occurrence.

---

### Scenario 9: SQL Parameter Logs + Business ID (L4)

**Code-level investigation — verify SQL execution parameters.**

```json
{"query":{"bool":{"must":[{"match_phrase":{"kubernetes.labels.app":"{appName}"}},{"match_phrase":{"message":"Parameters"}},{"match_phrase":{"message":"{businessId}"}}],"filter":[{"range":{"@timestamp":{"gte":"{startTime}","lte":"now"}}}]}},"sort":[{"@timestamp":{"order":"asc"}}],"_source":["@timestamp","message"],"size":50}
```

---

## Degradation Strategy Summary

| Level | Condition | Strategy | Scenario |
|-------|-----------|----------|----------|
| L1 | Has traceId | Direct trace | Scenario 1 |
| L2 | Has business ID + method | ID + Facade method | Scenario 2 |
| L3 | Has class + method (no app restriction) | Framework log class | Scenario 3 |
| L4 | Has app + business ID | SQL parameter logs | Scenario 9 |
| L5 | Only app + keywords | App name + keyword + time | Scenarios 6-8 |

**Principle:** Degrade from precise to broad. If a level finds a lead, do NOT degrade further — pivot to precise investigation around that lead.

## Time Formats

| Format | Example | Use Case |
|--------|---------|----------|
| Relative | now-5m, now-1h, now-3d | Recent issues |
| Absolute | 2026-02-26T10:00:00.000+08:00 | Specific time window investigation |

**Note:** ES stores time in UTC. Beijing time (UTC+8) requires conversion. E.g., log shows 17:02:06 (Beijing) = UTC 09:02:06.

## Keyword Extraction Strategy

| Type | Regex Pattern | Example |
|------|---------------|---------|
| Chinese keywords | `[\u4e00-\u9fff]+` | "order creation failed" |
| Exception class names | `(\w+Exception\|\w+Error)` | `NullPointerException` |
| English keywords | Length >= 2 | `payment`, `timeout` |
| traceId | `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}` | `550e8400-e29b-41d4` |
| Business IDs | Project-defined | `ORD\d{14}`, `USR\d+` |

**Rule:** Max 10 keywords, ordered by relevance. Prioritize keywords actually found in logs (extracted during code analysis phase).
