# Test Charter Template

**Feature**: {{FEATURE_NAME}}
**Slice**: {{SLICE_ID}}
**Family**: {{FAMILY_ID}}

---

## Layer Validation (Mandatory Pre-Flight)

**CRITICAL**: Entry point MUST be in Facade/Controller layer, NOT Service layer.

- [ ] Entry point is in Facade/Controller layer?
  - Target: `*Facade` or `*Controller` class
  - **FORBIDDEN**: `*Service` direct test (violates architecture)
- [ ] Test triggers through @Remote/@CatfishRemote Facade?
- [ ] If Service layer is selected, document why Facade layer is NOT available

**Layer Violation Detection**:
- Pattern: `*ServiceTest` without corresponding `*FacadeTest`
- Action: Reject charter before EXECUTOR phase
- Recovery: Use corresponding Facade entry point

**Why Facade Layer?**
- Facade layer exposes the complete request/response contract
- Service layer misses transaction boundary, validation, and remote aspects
- Tests at Service layer cannot verify real-world behavior

---

## Entry Point

**Facade/Controller Class**: `{{FACADE_CLASS_NAME}}`
**Method**: `{{METHOD_NAME}}`
**Signature**: `{{METHOD_SIGNATURE}}`

**Example**:
```java
// Facade entry
@Remote
public class ExampleModuleConfigFacade {
    public ExampleModuleConfigDto getConfig(String moduleName) { ... }
}

// Test targets Facade, NOT Service
@Test
public void testGetConfig_WhenValid_ShouldReturnDto() {
    ExampleModuleConfigDto dto = facade.getConfig("test");
    assertThat(dto).isNotNull();
}
```

---

## Test Scenarios

### RED Phase

**Scenario 1**: {{RED_SCENARIO_1}}
- **Given**: {{RED_GIVEN_1}}
- **When**: {{RED_WHEN_1}}
- **Then**: {{RED_THEN_1}} (business assertion that FAILS before implementation)

**Scenario 2**: {{RED_SCENARIO_2}}
- **Given**: {{RED_GIVEN_2}}
- **When**: {{RED_WHEN_2}}
- **Then**: {{RED_THEN_2}} (business assertion that FAILS before implementation)

### GREEN Phase

**Implementation Verification**:
- [ ] RED test now passes
- [ ] All assertions satisfied
- [ ] No TODO placeholders
- [ ] Side effects verified (if applicable)

---

## Side Effects (Required for stateful families)

**Is this stateful?**: {{IS_STATEFUL}}

**If YES, list all expected DB changes**:

| Table | Operation | Verification Query | Assertion Pattern |
|-------|-----------|-------------------|-------------------|
| {{TABLE_1}} | {{OPERATION_1}} | `SELECT * FROM {{TABLE_1}} WHERE {{KEY}} = ?` | `assertThat(captured.get().{{KEY}}()).isEqualTo({{VALUE}})` |
| {{TABLE_2}} | {{OPERATION_2}} | `SELECT * FROM {{TABLE_2}} WHERE {{KEY}} = ?` | `verify(mapper).insert(argThat(...))` |

**Verification Method** (choose one):
- [ ] AtomicReference capture
- [ ] DB SELECT query in test
- [ ] Mapper verify() call

---

## Transaction Test (Required for stateful families)

**Test Isolation**:
```java
@Test
@Transactional
@Rollback
public void test{{SCENARIO_NAME}}() {
    // Test code with automatic rollback
}
```

---

## Test Class Structure

**Test Class Name**: `{{FACADE_CLASS_NAME}}Test`
**Package**: `{{TEST_PACKAGE}}`

**Example**:
```java
package com.example.project.facade;

@RunWith(SpringRunner.class)
@SpringBootTest
public class ExampleModuleConfigFacadeTest {

    @Autowired
    private ExampleModuleConfigFacade facade;

    @Test
    public void test{{SCENARIO_NAME}}() {
        // Given
        {{GIVEN_CODE}}

        // When
        {{WHEN_CODE}}

        // Then
        assertThat({{ASSERTION_TARGET}}).{{ASSERTION_CONDITION}};
    }
}
```

---

## Pre-Flight Checklist

Before submitting TEST_CHARTER.md for execution:

- [ ] Entry point is Facade/Controller, NOT Service
- [ ] RED scenarios have FAILING business assertions
- [ ] Side effects listed (if stateful)
- [ ] Verification queries documented
- [ ] Test class follows naming convention: `*FacadeTest`
- [ ] No `fail()` or `TODO` placeholders in RED phase

---

## Gap Prevention

This template prevents:
- **wrong_test_surface**: Forces Facade/Controller layer selection
- **side_effect_ledger_gap**: Requires side effect documentation
- **implementation_after_blocked_red**: Pre-flight checklist ensures RED is valid

---

*Generated from TEST_CHARTER_TEMPLATE.md (v431)*
