# Plan Oracle Domain Expansion Guidance

**Version**: v451
**Gate**: Coverage Cap Gate (Gate 7) + Surface Coverage Gate (Gate 4)
**Category**: Oracle Coverage Expansion

## Purpose

When oracle coverage is below threshold (50% total, 70% HIGH-weight), use domain-aware expansion to reach thresholds efficiently. This guidance prevents over-expansion into irrelevant domains while ensuring adequate coverage.

## Domain Analysis Framework

### Step 1: Identify Oracle Domain Distribution

Analyze oracle production files by path pattern:

| Domain Pattern | Example Files | Priority |
|---------------|---------------|----------|
| `{module}/src/main/java/com/example/project/core/primary/` | ExampleFlowService, ExampleBookService | **PRIMARY** |
| `{module}/src/main/java/com/example/project/core/review/` | ReviewService, ReviewFlowFacade | SECONDARY |
| `{module}/src/main/java/com/example/project/core/integration/` | ExternalPushService, CallbackContext | SECONDARY |
| `{module}/src/main/java/com/example/project/core/record/` | RecordAcceptService, RecordDetailService | SECONDARY |
| `{module}/src/main/java/com/example/project/core/message/` | MessageHelper, TemplateBuilder | TERTIARY |
| `{module}/src/main/java/com/example/project/domain/` | DTOs, enums | LOW |
| `{module}/src/main/webapp/` | JSP, JS | DEFER (UI) |

### Step 2: Match Requirement to Oracle Domain

From REQUIREMENT_SOURCE_SNAPSHOT.md, identify the primary feature domain:

**Example Mapping**:
- "AI处理自动化" → ai/ domain (PRIMARY)
- "外部对接流程" → dock/ domain (PRIMARY)
- "案件流转" → caseinfo/ domain (PRIMARY)
- "记录审核" → examine/ domain (PRIMARY)
- UI adjustments → web/ domain (DEFER)

### Step 3: Prioritize Expansion by Domain Relevance

**Expansion Priority Order**:

1. **PRIMARY Domain Missing Files** (Highest Priority)
   - Must cover 100% of PRIMARY domain HIGH-weight files
   - Example: If requirement is "AI处理自动化", must cover all ai/ HIGH-weight files

2. **SECONDARY Domain Integration Points** (Medium Priority)
   - Cover files that bridge PRIMARY domain to other domains
   - Example: ExamineService if plan calls ExampleFlowService → ExamineService integration
   - Example: ExamplePushService if plan triggers外部推送

3. **TERTIARY Domain Support** (Low Priority)
   - Cover only if direct dependency from PRIMARY domain
   - Example: TemplateBuilder only if plan generates example-calculation-book.ftl

4. **UI Files** (DEFER)
   - Defer to future sprint unless requirement explicitly states UI changes
   - Mark in oracle_out_of_scope_files with reason: "UI deferred per requirement X.Y.Z"

## Coverage Threshold Calculation

### Total Oracle Overlap Formula

```
total_oracle_overlap = (matched_files / total_domain_filtered_files) * 100

# Domain-filtered excludes:
# - UI files (*.jsp, *.js) if requirement doesn't specify UI changes
# - Tertiary domain files without PRIMARY domain dependency
```

### HIGH-Weight Overlap Formula

```
high_weight_overlap = (matched_high_weight / total_high_weight_files) * 100

# HIGH-weight definition:
# - Service layer files: *Service.java, *Facade.java
# - Core orchestration: *Flow*, *Manager*, *Orchestrator*
# - State transition files: *Context*, *State*, *Transition*
```

## Expansion Strategy Template

### When Coverage < 50%

**Use PRIMARY Domain Expansion**:

1. List missing PRIMARY domain files
2. Map each missing file to a slice
3. Add test assertion that verifies oracle coverage

**Example**:
```
Missing PRIMARY file: ExampleFlowService.java (HIGH, 1502 additions)
→ Map to S1 (Core Auto-Flow Entry)
→ Test: ExampleFlowServiceTest.testHandle_failsWithMissingCaseRoute
→ Coverage impact: +1 HIGH-weight file, +1502 additions
```

### When Coverage 50-70% but HIGH-weight < 70%

**Use SECONDARY Domain Bridge Expansion**:

1. Identify integration points from PRIMARY to SECONDARY domains
2. Add only those SECONDARY files that are direct dependencies
3. Document integration reason in oracle_expansion_plan

**Example**:
```
Plan calls: ExampleFlowService.handle() → triggers外部推送
Missing SECONDARY file: ExamplePushService.pushToExternal()
→ Add to S2 (State Changes & Side Effects)
→ Reason:外部推送 is triggered by auto-flow completion
→ Coverage impact: +1 HIGH-weight file
```

## Oracle Expansion Plan Format

In PLAN_RESULT.md, oracle_expansion_plan should follow:

```
### oracle_expansion_plan

PRIMARY Domain (ai/):
- ExampleFlowService.java → S1 → testHandle_failsWithMissingCaseRoute
- ClaimCalculationBookService.java → S2 → testGenerateCalculationBook

SECONDARY Domain Integration:
- ExamineFlowFacade.java → S3 → testAutoFlowNotification (reason: auto-flow calls examine)
- ExamplePushService.java → S2 → testPushAutoFlowNotification (reason: state change triggers外部推送)

DEFER (UI):
- examine.jsp/examine-material.jsp → DEFER (UI deferred per requirement 2.3.2)
```

## Verification Gates

### After Expansion

Verify that:
1. total_oracle_overlap >= 50%
2. high_weight_overlap >= 70%
3. PRIMARY domain HIGH-weight coverage = 100%
4. oracle_expansion_plan lists all missing files with slice mappings
5. oracle_out_of_scope_files lists deferred files with reasons

### Run Verification

```powershell
pwsh -File scripts\Verify-PlanContract.ps1 -ReplayRoot <replay_root> -Stage Plan
```

Expected output: `verification_status: PASS`

## v451 Evolution Context

This guidance was added after v450-autopilot-r03 observed:
- Oracle overlap: 46% < 50% threshold
- HIGH-weight overlap: 68% < 70% threshold
- Plan blocked legitimately (gates working correctly)
- Missing expansion strategy for multi-domain oracles

**Root Cause**: Plan focused on PRIMARY (ai/) domain but didn't expand to SECONDARY (examine/, dock/) integration points.

**Fix Applied**: Added domain-aware expansion framework to guide coverage growth by priority:
1. PRIMARY domain 100% coverage requirement
2. SECONDARY domain integration point identification
3. DEFER logic for UI files

**Expected Impact**:
- Blocked plans with legitimate domain filtering → Clear expansion path
- PRIMARY domain coverage → 100% guaranteed
- Total coverage threshold → Reachable via targeted SECONDARY expansion
