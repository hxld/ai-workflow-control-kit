# Experiment E4: New Service Whitelist (v425)

## Overview

When implementing a feature that requires **NEW services** (not present in baseline), you MUST declare them in `NEW_SERVICE_WHITELIST` to bypass carrier rank checks.

## When to Use

Use this when your feature requires creating a new:
- Service class (e.g., `ExampleFlowService`)
- Processor/Task handler (e.g., `AiNewFlowProcessor`)
- Facade/Controller (e.g., `ExampleFlowController`)

## How to Declare

Add the following section to your `FIRST_SLICE_PROOF_PLAN.md` or `IMPLEMENTATION_CONTRACT.md`:

```markdown
## NEW_SERVICE_WHITELIST

- ExampleFlowService
- AiNewFlowProcessor
```

## Format Rules

1. Section header must be `## NEW_SERVICE_WHITELIST`
2. Each service on its own line with `- ` prefix
3. Use class name only (no package, no extension)
4. Order doesn't matter

## What Happens

When `NEW_SERVICE_WHITELIST` is declared:
- Pre-slice authorization will **skip** carrier rank check for whitelisted services
- You can proceed with implementation even though the service doesn't exist yet
- After implementation, the carrier rank check will pass

## Example

### Scenario

Feature requires `ExampleFlowService` which doesn't exist in baseline.

### Plan Declaration

```markdown
## FIRST_SLICE_PROOF_PLAN.md

selected_carrier: ExampleFlowService.handle
selected_real_entry: ExampleFlowService.executeAutoFlow

## NEW_SERVICE_WHITELIST

- ExampleFlowService

first_red_test: ExampleFlowServiceTest#testExecuteAutoFlow_CaseNotShanpei_Block
```

### Result

- Pre-slice authorization: **ALLOW** (whitelisted service bypasses rank check)
- Implementation proceeds: Create service, create test
- RED phase: Expected failure (service doesn't exist yet)
- GREEN phase: Implement service, test passes
- Slice verification: Pass

## WRONG - Missing Whitelist

```markdown
## FIRST_SLICE_PROOF_PLAN.md

selected_carrier: ExampleFlowService.handle
# ❌ Missing NEW_SERVICE_WHITELIST section
```

**Result**: `carrier_rank_missing` blocker, slice rejected

## WRONG - Non-New Service

```markdown
## NEW_SERVICE_WHITELIST

- ExampleApplyTaskProcessor  # ❌ This exists in baseline!
```

**Result**: Warning, but still works (unnecessary whitelist)

## Integration with Other Gates

- **Phase0 Contract**: Must still provide carrier search evidence
- **Pre-Slice Authorization**: Whitelist bypasses rank check only
- **RED Phase**: Still requires failing test first
- **GREEN Phase**: Implementation creates the new service

## Gate Enforcement

The `Authorize-PreSliceEvidence.ps1` script:
1. Parses `NEW_SERVICE_WHITELIST` from plan
2. Filters missing carriers against whitelist
3. Allows slice to proceed if all missing carriers are whitelisted
4. Adds `carrier_rank_whitelisted:<service>` warnings for visibility

## Validation

After slice completion:
1. Check that whitelisted service was actually created
2. Check that test file exists and passes
3. Update carrier rank index for future slices

## Common Mistakes

1. **Forgetting to declare whitelist** → `carrier_rank_missing` blocker
2. **Misspelled service name** → Whitelist doesn't match, blocker still fires
3. **Listing existing services** → Harmless but generates warnings
4. **Not implementing the service** → Future slices still need whitelist

## Success Criteria

A new service slice is COMPLETE when:
- [ ] Service declared in `NEW_SERVICE_WHITELIST`
- [ ] Service class created in worktree
- [ ] Test file created and passes
- [ ] Service integrates with existing carriers
- [ ] Side effects verified (if applicable)
