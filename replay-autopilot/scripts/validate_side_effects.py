#!/usr/bin/env python3
"""
Side Effect Ledger Pre-Completion Validator (Experiment 3).
All expected side effects must have corresponding verification BEFORE slice completion.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Optional


# DB operation patterns for extraction
DB_PATTERNS = {
    'insert': [r'(\w+)Mapper\.insert', r'(\w+)Mapper\.insertList', r'\.insert\(', r'save\('],
    'update': [r'(\w+)Mapper\.update', r'(\w+)Mapper\.updateFlowStatus', r'\.update\(', r'setStatus'],
    'delete': [r'(\w+)Mapper\.delete', r'(\w+)Mapper\.remove', r'\.delete\('],
    'select': [r'(\w+)Mapper\.select', r'(\w+)Mapper\.get', r'(\w+)Mapper\.query']
}

# Test verification patterns
VERIFICATION_PATTERNS = [
    r"AtomicReference",
    r"doAnswer",
    r"thenAnswer",
    r"when\(",
    r"verify\(",
    r"assertThat",
    r"@Transactional"
]


def parse_requirement_family_ledger(ledger_path: str) -> Dict:
    """Parse requirement family ledger to extract expected side effects."""
    if not Path(ledger_path).exists():
        return {"families": [], "stateful_side_effect": {"proof_required": []}}

    with open(ledger_path, encoding='utf-8') as f:
        return json.load(f)


def get_expected_side_effects(ledger: Dict) -> List[str]:
    """Extract expected side effects from requirement family ledger."""
    for family in ledger.get("families", []):
        if family.get("id") == "stateful_side_effect":
            return family.get("proof_required", [])

    # If no stateful_side_effect family, check for side_effects key
    return ledger.get("side_effects", ledger.get("expected_side_effects", []))


def extract_db_operations_from_test(test_content: str) -> Set[str]:
    """Extract DB operations from test source code."""
    operations = set()

    for op_type, patterns in DB_PATTERNS.items():
        for pattern in patterns:
            matches = re.finditer(pattern, test_content, re.IGNORECASE)
            for match in matches:
                # Try to extract table/entity name
                if "Mapper" in pattern:
                    # Look for the pattern in context
                    line_start = test_content.rfind("\n", 0, match.start()) + 1
                    line_end = test_content.find("\n", match.end())
                    line = test_content[line_start:line_end]

                    # Extract mapper name
                    mapper_match = re.search(r'(\w+)Mapper', line, re.IGNORECASE)
                    if mapper_match:
                        entity = mapper_match.group(1)
                        operations.add(f"{entity}.{op_type}")

    return operations


def extract_verification_patterns(test_content: str) -> Dict[str, List[str]]:
    """Extract verification patterns from test."""
    found = {}

    for pattern in VERIFICATION_PATTERNS:
        if re.search(pattern, test_content, re.IGNORECASE):
            matches = re.finditer(pattern, test_content, re.IGNORECASE)
            found[pattern] = [m.group(0) for m in matches]

    return found


def get_test_pattern_for_effect(test_content: str, effect: str) -> Optional[str]:
    """Get the test pattern used for a specific side effect."""
    # Look for verification related to the effect
    entity = effect.split('.')[0] if '.' in effect else effect

    # Check if test has verification for this entity
    patterns = [
        f"{entity}Mapper",
        f"{entity}",
        f"captured.*{entity}",
        f"{entity}.*captured"
    ]

    for pattern in patterns:
        if re.search(pattern, test_content, re.IGNORECASE):
            return pattern

    return None


def is_valid_side_effect_pattern(pattern: Optional[str]) -> bool:
    """Check if pattern represents valid side effect verification."""
    if not pattern:
        return False

    # Valid patterns include AtomicReference capture, DB verification, etc.
    valid_indicators = [
        "AtomicReference",
        "doAnswer",
        "thenAnswer",
        "when",
        "verify",
        "@Transactional",
        "mapper",
        "assertThat"
    ]

    return any(indicator.lower() in pattern.lower() for indicator in valid_indicators)


def verify_side_effects_pre_completion(
    ledger_path: str,
    test_evidence_path: str,
    worktree_path: str
) -> Dict:
    """
    Side Effect Ledger Pre-Completion Validator:
    All expected side effects must have corresponding verification BEFORE slice can complete.
    """
    ledger = parse_requirement_family_ledger(ledger_path)
    expected_effects = get_expected_side_effects(ledger)

    if not expected_effects:
        # No side effects required, pass
        return {
            "authorized": True,
            "gate": "side_effect_ledger_complete",
            "reason": "no_side_effects_required"
        }

    # Read test evidence
    test_path = Path(worktree_path) / test_evidence_path
    if not test_path.exists():
        return {
            "authorized": False,
            "gate": "side_effect_ledger_complete",
            "reason": "test_file_not_found",
            "test_path": test_evidence_path
        }

    test_content = test_path.read_text(encoding='utf-8', errors='ignore')

    # Extract actual DB operations verified in test
    actual_effects = extract_db_operations_from_test(test_content)

    # Check for missing effects
    expected_set = set(expected_effects)
    actual_set = set(actual_effects)

    missing_effects = expected_set - actual_set

    if missing_effects:
        # Check if test has verification patterns at all
        verification_patterns = extract_verification_patterns(test_content)

        return {
            "authorized": False,
            "gate": "side_effect_ledger_complete",
            "reason": "side_effect_ledger_incomplete",
            "missing_effects": list(missing_effects),
            "expected_count": len(expected_effects),
            "actual_count": len(actual_effects),
            "expected_effects": expected_effects,
            "actual_effects": list(actual_effects),
            "has_verification_patterns": len(verification_patterns) > 0,
            "verification_patterns": verification_patterns,
            "required_pattern": '''
For each expected side effect, test MUST have verification:

Example:
    AtomicReference<CompensateInfo> captured = new AtomicReference<>();
    doAnswer(invocation -> {
        Object[] args = invocation.getArguments();
        captured.set((CompensateInfo) args[0]);
        return 1;
    }).when(compensateInfoMapper).insert(any());

    // After execution
    assertThat(captured.get().getCaseId()).isEqualTo(caseId);
    assertThat(captured.get().getCompensateAmount()).isEqualTo(expectedAmount);
            '''
        }

    # Verify each effect has proper test pattern
    invalid_effects = []
    verified_effects = []

    for effect in actual_effects:
        pattern = get_test_pattern_for_effect(test_content, effect)
        if not is_valid_side_effect_pattern(pattern):
            invalid_effects.append({
                "effect": effect,
                "pattern": pattern,
                "required": "@Transactional rollback test with AtomicReference capture or DB state query"
            })
        else:
            verified_effects.append(effect)

    if invalid_effects:
        return {
            "authorized": False,
            "gate": "side_effect_ledger_complete",
            "reason": "side_effect_verification_pattern_invalid",
            "invalid_effects": invalid_effects,
            "verified_effects": verified_effects
        }

    return {
        "authorized": True,
        "gate": "side_effect_ledger_complete",
        "verified_effects": verified_effects,
        "verification_count": len(verified_effects),
        "expected_count": len(expected_effects),
        "verification_rate": round(len(verified_effects) / len(expected_effects) * 100, 1) if expected_effects else 100
    }


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: validate_side_effects.py <ledger_path> <test_evidence_path> <worktree_path>", file=sys.stderr)
        sys.exit(1)

    ledger_path = sys.argv[1]
    test_evidence_path = sys.argv[2]
    worktree_path = sys.argv[3]

    result = verify_side_effects_pre_completion(ledger_path, test_evidence_path, worktree_path)
    print(json.dumps(result, indent=2))

    if not result.get("authorized"):
        sys.exit(1)
