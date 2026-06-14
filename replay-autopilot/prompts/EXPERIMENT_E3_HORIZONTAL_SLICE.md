# Experiment E3: Horizontal Slice Pre-Authorization

## Overview

Your slice MUST touch at least 3 of 5 categories BEFORE implementation starts.
**Database is MANDATORY** - Every slice must include at least one DB operation.

## Categories

| Category | Description | Examples |
|----------|-------------|----------|
| **Backend** | Service/Facade/Controller classes | *Service.java, *FacadeImpl.java, *Processor.java |
| **Database** | Schema/Mapper/Entity changes | *Mapper.xml, *.sql, *Entity.java, INSERT/UPDATE/DELETE |
| **Frontend** | JSP/JS/Vue files | *.jsp, *.js, *.vue, pages/, static/ |
| **Deploy** | Config/Controller/REST endpoints | *Controller.java, application.properties, *.xml |
| **Test** | Test classes with DB verification | *Test.java, *Spec.java, src/test/ |

## Minimum Requirements

1. **At least 3 categories** touched
2. **Database category is REQUIRED**
3. Each category must have specific file paths documented

## Pre-Authorization Checklist

Before slice implementation starts, you must have:

- [ ] At least 3 categories planned
- [ ] Database category included
- [ ] For each category: specific file path and change description
- [ ] Test file that verifies DB state changes

## VALID Example

```
Categories: Backend + Database + Test (3/3) ✓

Backend:
  - ExampleFlowService.java (executeAutoFlow method)

Database:
  - TExampleModuleConfig.java (ADD COLUMN free_review_amount)
  - TExampleModuleConfigMapper.xml (ADD COLUMN MAPPING)

Test:
  - ExampleFlowServiceTest.java (SELECT query verifies column value)
```

**Result**: AUTHORIZED

## INVALID Example

```
Categories: Backend only (1/3) ✗

Backend:
  - ExampleFlowService.java (TODO placeholder)

Database: (NONE) ✗
Test: (NONE) ✗
```

**Result**: BLOCKED - Add Database and Test categories

## INVALID Example 2

```
Categories: Backend + Frontend + Test (3/3) ✗

Backend: *Service.java
Frontend: *.jsp
Test: *Test.java
Database: (NONE) ✗
```

**Result**: BLOCKED - Database is required

## If Your Feature "Doesn't Touch Database"

You're probably implementing the wrong surface. Re-examine:

1. Does this feature have user-visible impact?
2. Does it change system state?
3. Where is the business value?

If truly no DB (very rare):
- Document why this is deployable without data changes
- Explain what existing data is being used
- Verify with reviewer before proceeding

## Gate Enforcement

The `authorize_horizontal_slice.py` script runs during slice pre-authorization and will BLOCK if:
- Less than 3 categories planned
- Database category not included
- Planned files don't match declared categories

## Common Anti-Patterns

1. **"I'll add DB changes in the next slice"** → NO. Either include DB work now or make this a different feature.
2. **"This is just a helper function"** → Helpers without DB/Deploy/Test don't deliver value. Re-think the slice.
3. **"The test is in a different slice"** → NO. Each slice needs its own test proving its DB changes.
