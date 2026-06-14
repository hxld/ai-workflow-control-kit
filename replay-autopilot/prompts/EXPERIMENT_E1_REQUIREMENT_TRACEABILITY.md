# Experiment E1: Requirement-to-Carrier Traceability

## Overview

Before selecting any strategy or carrier, you MUST establish traceability between requirement phrases and production carriers.

## Process

### 1. Extract Action Phrases

Extract action verbs from requirements, for example:
- "AI核赔申请" → Apply, Application
- "自动理算" → Calculate, Settlement
- "免复核金额配置" → Config, Field

### 2. Search the Codebase

For each action phrase, use ripgrep to find matching carriers:

```bash
# Search for TaskProcessor classes
rg -i "Apply" --glob="*TaskProcessor.java" claim-core/

# Search for Service classes
rg -i "AutoFlow" --glob="*Service.java" claim-core/

# Search for Config handlers
rg -i "ModuleConfig" --glob="*Service.java" claim-core/
```

### 3. Record Bindings

Create `REQUIREMENT_CARRIER_BINDINGS.json`:

```json
{
  "AI核赔申请": {
    "file": "claim-core/.../AiApplyClaimApiTaskProcessor.java",
    "class": "AiApplyClaimApiTaskProcessor",
    "method": "handleTaskResponse",
    "line": 442
  },
  "自动理算": {
    "file": "claim-core/.../AiCalculateLossApiTaskProcessor.java",
    "class": "AiCalculateLossApiTaskProcessor",
    "method": "handle",
    "line": 320
  }
}
```

### 4. Verification Rules

- Each requirement phrase MUST have exactly ONE carrier binding
- The carrier file MUST exist in the baseline worktree
- If a phrase has NO matching carrier:
  - Broaden the search (try related keywords)
  - Document why a NEW service is needed (with existing carrier integration point)

## DO NOT PROCEED without complete traceability bindings.

## Common Mismatches

| Requirement Phrase | Wrong Carrier | Correct Carrier | Reason |
|-------------------|---------------|------------------|--------|
| AI核赔申请 | AiCalculateLossApiTaskProcessor | AiApplyClaimApiTaskProcessor | Calculate=理算, Apply=申请 |
| 免复核金额 | AiClaimFlowService | AiClaimModuleConfigService | Flow=流程, Config=配置 |
| 自动流转 | AiApplyClaimService | AiAutoClaimFlowService | Apply=申请, AutoFlow=自动流转 |

## Gate Enforcement

The `phase0_requirement_traceability_bind.py` script runs during plan verification and will BLOCK if:
- No action phrases extracted
- Action phrases have no carrier bindings
- Bound carrier doesn't exist in worktree
