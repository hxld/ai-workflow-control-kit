# Allowed Oracle Scan Mode for NEW Carrier Discovery

## Trigger Condition

Execute ONLY when:
- `target_carrier not found in base commit`
- `replay_mode == strict-blind`

## Allowed Commands

```bash
# File names only (no content)
git diff --name-only ${base_commit} ${oracle_commit}

# Class declaration only (no methods)
grep "^public class ${carrier_name}" ${oracle_branch}:${file_path}

# Method signatures only (no bodies)
grep "public.*handle.*(" ${oracle_branch}:${file_path}
grep "public.*execute.*(" ${oracle_branch}:${file_path}
```

## Forbidden Operations

- ❌ Reading method body/implementation
- ❌ Reading test implementations
- ❌ Copying oracle code structure
- ❌ Viewing oracle business logic
- ❌ Reading oracle test assertions

## Output Format

```json
{
  "carrier": "AiAutoClaimFlowService",
  "exists_in_base": false,
  "signatures": {
    "claim-core/.../AiAutoClaimFlowService.java": [
      "public class AiAutoClaimFlowService",
      "public void handle(Long caseId, AiApplyClaimApiTask task)"
    ]
  }
}
```

## Usage in TDD Cycle

1. **BEFORE RED**: Run `discover_new_carriers.py`
2. **Create Minimal Stubs**: Create interface with discovered signatures
3. **Write RED Test**: Test can now reference correct method signature
4. **Implement GREEN**: Write implementation to pass test
5. **Delete Stubs**: Remove stub files (implementation replaces them)

## Token Savings

- Full oracle scan: ~100K tokens (80 files, full implementations)
- Signature-only scan: ~5K tokens (class names + method signatures only)
- Savings: 95% token reduction
