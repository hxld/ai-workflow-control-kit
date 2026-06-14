# Experiment E3: Pre-Authorization Surface Validation

**v425 Enforcement**: Before authorizing a slice for implementation, validate that the test targets the correct architectural layer.

---

## Overview

Real entry points (Facade/Controller) are the preferred surfaces for testing business requirements. Testing Service layer directly is only valid when no Facade/Controller exists for the entry point.

---

## Layer Classification

### Real Entry Layers (PREFERRED)

**Facade Layer**
- Classes ending with `Facade`, `FacadeImpl`
- Examples: `ExampleFacade`, `ExamineFlowFacadeImpl`, `ClaimDataFacade`

**Controller Layer**
- Classes ending with `Controller`, `ApiController`
- Examples: `ExampleController`, `ExamineFlowController`, `ClaimApiController`

**Api Layer**
- Classes ending with `Api`
- Examples: `ClaimApi`, `FlowApi`

### Internal Layers (USE ONLY WHEN NECESSARY)

**Service Layer**
- Classes ending with `Service`, `Task`, `Processor`
- Examples: `ExampleFlowService`, `ExampleApiTaskProcessor`

**Data Layer**
- Classes ending with `Mapper`, `Dao`, `Repository`
- Examples: `ClaimInfoMapper`, `CompensateInfoDao`

---

## Validation Rules

### Rule 1: Prefer Facade/Controller for Real Entries

When testing a business requirement that enters through a web request or external call:

✅ **CORRECT**: Test at Facade/Controller layer
```java
// Test at real entry
@Test
public void testHandleClaim_AutoFlowTriggered_CompensateInfoInserted() {
    // Calling facade method
    boolean result = exampleFacade.handleExample(caseId, task);
    // Assert side effects
}
```

❌ **WRONG**: Test at Service layer when Facade exists
```java
// Testing service directly (anti-pattern)
@Test
public void testProcess_TaskExecuted() {
    aiApplyClaimApiTaskProcessor.process(task);
    // Missing facade validation
}
```

### Rule 2: Service Layer Only When Facade/Controller Absent

Service layer tests are ONLY valid when:
- No Facade exists for this entry point
- No Controller exists for this entry point
- The service is a standalone internal processor with documented justification

**Justification Required**:
```markdown
## Why Service Layer Testing

The ExampleFlowService has no Facade or Controller boundary because:
1. It's triggered by internal task queue (not HTTP)
2. The task processor (ExampleApiTaskProcessor) is the real entry
3. Testing at Service layer validates the complete flow
```

---

## Verifier Integration

The `Authorize-PreSliceEvidence.ps1` script automatically validates surface:

```bash
.\scripts\Authorize-PreSliceEvidence.ps1 -ReplayRoot <root> -SliceIndex 1
```

### Validation Result

```json
{
  "surface_validation": {
    "status": "PASS",
    "target_layer": "Facade",
    "gap": "",
    "reason": ""
  }
}
```

### Failure Result

```json
{
  "surface_validation": {
    "status": "FAIL",
    "target_layer": "Service",
    "recommended_layer": "Facade/Controller",
    "gap": "wrong_test_surface",
    "reason": "Target carrier 'ExampleApiTaskProcessor' is in Service layer, but real entries should be in Facade/Controller layer per architecture.",
    "correction": "Move test target to Facade layer (e.g., ExampleFacade or ExamineFlowController)"
  }
}
```

---

## Gap Flag

If surface validation fails:
- `gap_flags`: [`wrong_test_surface`]
- `slice_status`: "BLOCKED"
- `coverage_delta`: 0

---

## Examples by Scenario

| Scenario | Correct Surface | Wrong Surface |
|----------|----------------|---------------|
| HTTP request handling | `*Controller` | `*Service`, `*Task` |
| External API integration | `*Facade`, `*Api` | `*Service` |
| Internal scheduled task | `*Service` (with justification) | N/A |
| Message queue consumer | `*Service`, `*Handler` (with justification) | N/A |

---

## Common Mistakes

1. **Testing Task/Processor directly when Facade exists**
   - Wrong: `ExampleApiTaskProcessorTest`
   - Right: `ExampleFacadeTest` or `ExamineFlowControllerTest`

2. **Not documenting why Service layer is used**
   - Always add justification when using Service layer

3. **Testing Mapper directly for business logic**
   - Mapper tests verify data persistence only
   - Business logic must be tested at Service/Facade level

---

## Success Criteria

A surface is VALID when:
- [ ] Target carrier is in Facade/Controller/Api layer, OR
- [ ] Target carrier is in Service layer with documented justification

---

**CRITICAL**: The verifier will block slices that test the wrong surface without justification. Always prefer Facade/Controller for real entries.
