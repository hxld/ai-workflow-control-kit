# Pre-S1 Plan Check

## Carrier Verification Step (v348)

Before writing the RED test for S1, you must verify the selected carrier matches the requirement.

### Process

1. **Extract requirement keywords**
   - Identify core business terms from the requirement
   - Examples: "配置字段" (config field), "免复核金额" (exempt review amount), "自动流转" (auto flow)

2. **Search codebase for existing carriers**
   - Use ripgrep to find existing services handling similar functionality:
     ```bash
     rg -i "配置字段" --type java -g "*Service.java" claim-core/
     rg -i "免复核" --type java -g "*Service.java" claim-core/
     ```
   - Look for pattern matches like `ModuleConfigService` for config-related keywords

3. **Verify selected carrier**
   - Run `verify-carrier.ps1` to validate carrier selection
   - Parameters: `-Worktree <path> -RequirementKeywords <keywords> -PlannedCarrier <carrier>`
   - The script checks if the planned carrier matches patterns suggested by keywords

4. **Document carrier search results**
   - In `PLAN_RESULT.md`, ensure these fields are populated:
     - `carrier_search: performed`
     - `carrier_search_queries:` (at least 3 search commands)
     - `existing_production_carriers:` (carriers found in search)
     - `selected_carrier_from_search:` (must be from existing carriers)

### Anti-Patterns

❌ **WRONG**: Selecting the first mentioned class without verifying architectural fit
```
# Wrong: selecting TaskProcessor when requirement describes configuration
Planned Carrier: AiCalculateLossApiTaskProcessor
Requirement Keywords: 配置字段, 免复核金额
Expected: AiClaimModuleConfigService (config-related service)
```

✅ **CORRECT**: Verifying carrier matches requirement patterns
```
# Correct: carrier matches config-related keywords
Planned Carrier: AiClaimModuleConfigService
Requirement Keywords: 配置字段, 免复核金额
Evidence: Search for "config" returns ModuleConfigService pattern
```

### Block Conditions

If `verify-carrier.ps1` returns WARN and you cannot justify the carrier selection:
1. Re-run codebase search with alternative keywords
2. Document why existing carriers don't fit (new service justification)
3. If no justification exists, the plan is BLOCKED

### Common Patterns

| Requirement Keywords | Expected Carrier Pattern |
|---------------------|-------------------------|
| config, 配置, 字段 | ModuleConfigService, ConfigService |
| auto, 自动, 流转 | AutoFlowService, AutoClaimFlowService |
| examine, 审核 | ExamineService, ReviewService |
| refund, 退票 | RefundService, ReturnTicketService |
| claim, 理赔 | ClaimService, ClaimFlowService |
| ai, AI核赔 | AiClaimService, AiAutoClaimFlowService |

## Domain Compatibility Check (v347)

Before finalizing carrier selection, verify oracle and requirement domains are compatible.

1. Read `{{ORACLE_DIFF_ANALYSIS}}` to extract oracle file domains
2. Check `domain_compatibility` in PLAN_RESULT.md
3. If MISMATCH, planning is BLOCKED

See `phase-plan-tournament.prompt.md` for full v347 domain compatibility rules.

## Entry Point Workflow Verification (v357)

Before finalizing plan carriers, automated verification checks that selected carriers match requirement workflow.

### Automated Check

The `validate_entry_point_mapping.py` script runs automatically during plan contract verification:

```bash
python scripts/validate_entry_point_mapping.py \
    --requirement REQUIREMENT_SOURCE_SNAPSHOT.md \
    --ledger REQUIREMENT_FAMILY_LEDGER.json
```

### What It Checks

1. **Requirement Workflow Extraction**: Identifies workflow keywords from requirement
   - Chinese keywords: 申请, 核赔, 理算, 报案, 审核, 支付, 通知, 回调
   - English equivalents: Apply, Claim, Calculate, Report, Review, Payment, Notify, Callback

2. **Carrier Matching**: Verifies selected carrier contains workflow keywords
   - Example: Requirement "AI核赔申请" → carrier must contain "Apply" (AiApplyClaim)
   - Rejects: AiCalculateLoss (wrong workflow phase)

3. **Verification Output**:
   ```json
   {
     "valid": true,
     "verified_carriers": [
       {
         "family_id": "core_entry",
         "carrier_name": "AiApplyClaimApiTaskProcessor",
         "reason": "Carrier matches requirement keyword 'Apply'"
       }
     ],
     "unverified_carriers": []
   }
   ```

### Block Conditions

If verification fails:
1. Check REQUIREMENT_FAMILY_LEDGER.json for wrong entry points
2. Verify carrier selection against requirement workflow
3. Update carrier to match actual workflow phase

### Common Mismatches

| Requirement Keyword | Wrong Carrier | Correct Carrier |
|---------------------|---------------|-----------------|
| 申请 | AiCalculateLossTaskProcessor | AiApplyClaimTaskProcessor |
| 核赔/理算 | AiApplyClaimTaskProcessor | AiCalculateLossTaskProcessor |
| 回调 | AiApplyTaskService | AiClaimCallbackService |
