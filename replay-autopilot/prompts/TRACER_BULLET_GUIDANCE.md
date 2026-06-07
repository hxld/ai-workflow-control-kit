# Tracer Bullet Guidance

## Horizontal Slicing Requirement (v348)

S1 (tracer_bullet) must slice **horizontally** across families, not vertically within a single module.

### Minimum Requirement

S1 must touch **minimum 3 families**:

1. **Frontend**: JSP/HTML/UI contract
2. **Backend**: Service/Controller/Facade
3. **Database**: Entity/Mapper/SQL

### Family Classification

| Category | Files/Packages | Examples |
|----------|----------------|----------|
| Frontend | `.jsp`, `.html`, `/web/`, `/ui/` | `ai-claim-management.jsp` |
| Backend | `*Service.java`, `*Controller.java`, `/claim-core/` | `AiClaimModuleConfigService.java` |
| Database | `*Mapper.java`, `T[A-Z]*.java`, `/claim-provider/` | `TAiClaimModuleConfig`, `AiClaimModuleConfigMapper` |
| Test | `*Test.java`, `/test/` | `AiClaimModuleConfigServiceTest.java` |
| Deploy | `pom.xml`, `application.properties` | Maven config, Spring config |
| External | Integration clients, callbacks | `InsureCompanyPushService` |
| SideEffect | State/Status/Progress | `CaseFlowStatusService` |

### Example Tracer Bullet for aiClaimV2

**Requirement**: AI核赔管理免复核金额 (AI Claim Management - Exempt Review Amount)

**S1 Horizontal Slice**:

| Family | File | Change |
|--------|------|--------|
| Frontend | `ai-claim-management.jsp` | Add `freeReviewAmount` input field |
| Backend | `AiClaimModuleConfigService` | Add `validateFreeReviewAmount()` method |
| Database | `TAiClaimModuleConfig` | Add `free_review_amount` column |
| Test | `AiClaimModuleConfigServiceTest` | RED test for validation |

This touches **4 families** (Frontend, Backend, Database, Test) - meets minimum requirement.

### Anti-Patterns

❌ **WRONG**: Writing only backend code without frontend/DB changes
```
# Wrong: vertical slice within backend only
Files Modified:
- AiClaimModuleConfigService.java (backend only)
Families Touched: 1 (Backend only)
Status: FAIL - Horizontal coverage insufficient
```

✅ **CORRECT**: Touching multiple families in S1
```
# Correct: horizontal slice across families
Files Modified:
- ai-claim-management.jsp (Frontend)
- AiClaimModuleConfigService.java (Backend)
- TAiClaimModuleConfig.java (Database)
- AiClaimModuleConfigServiceTest.java (Test)
Families Touched: 4 (Frontend, Backend, Database, Test)
Status: PASS - Horizontal coverage sufficient
```

### Verification

Before claiming S1 complete:

1. **Run `verify-horizontal-slice.ps1`**:
   ```powershell
   verify-horizontal-slice.ps1 -SliceResultFile <SLICE_RESULT_01.json>
   ```
   - Checks families touched count >= 3
   - Returns PASS/FAIL with horizontal breakdown

2. **List files from each family** in your slice result:
   ```json
   {
     "families_touched": ["Frontend", "Backend", "Database"],
     "files_modified": [
       "ai-claim-management.jsp",
       "AiClaimModuleConfigService.java",
       "TAiClaimModuleConfig.java"
     ]
   }
   ```

### Oracle Reference

Oracle implementation for aiClaimV2 touched **8 families**:
- Frontend (UI contracts)
- Backend (Service/Facade)
- Database (Entity/Mapper)
- Test (JUnit tests)
- Deploy (Maven config)
- External (RPC interfaces)
- Side Effect (Status updates)
- Artifact (Generated templates)

Your S1 should aim for at least 3 of these families to demonstrate horizontal coverage.

### Block Condition

If S1 touches < 3 families:
- Verification returns FAIL
- Slice is not authorized for GREEN phase
- Must expand slice to include additional families

## Core Entry First Rule

If `core_entry` family is present in requirements:
- **S1 must target core_entry** (weight 100)
- Do NOT start with `config_policy_threshold` or helper-only surfaces

See `SURFACE_COVERAGE_GATE.md` for full core_entry requirements.
