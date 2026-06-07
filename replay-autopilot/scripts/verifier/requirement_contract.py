#!/usr/bin/env python3
"""
Requirement Contract Validation (Experiment E3).

Requires exact test method names and assertion contracts in the plan.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any


# Test name pattern: test[MethodName]_[Scenario]_[ExpectedOutcome]
TEST_NAME_PATTERN = re.compile(r'^test\w+_[A-Za-z0-9]+_[A-Za-z0-9]+$')


def validate_requirement_contract_binding(plan_result: Dict, requirement_ledger: Dict) -> Dict:
    """
    Plan MUST specify:
    1. first_red_test: Exact test method name (e.g., "testAutoFlow_MissingConfig_ThrowsException")
    2. expected_assertions: List of what each test proves
    3. side_effect_targets: What DB/file changes will occur
    """
    required_fields = {
        "first_red_test": "Exact test method name (format: testMethodName_Scenario_ExpectedOutcome)",
        "expected_assertions": "List of contract assertions (what each test proves)",
        "side_effect_targets": "List of DB/file operations to verify"
    }

    missing = []
    for field, description in required_fields.items():
        if not plan_result.get(field):
            missing.append({
                "field": field,
                "description": description
            })

    if missing:
        return {
            "valid": False,
            "missing_fields": missing,
            "reason": "plan_lacks_semantic_binding"
        }

    # Validate test name format
    test_name = plan_result.get("first_red_test", "")
    if not TEST_NAME_PATTERN.match(test_name):
        return {
            "valid": False,
            "reason": "invalid_test_name_format",
            "expected": "test[MethodName]_[Scenario]_[ExpectedOutcome]",
            "actual": test_name
        }

    # Validate expected_assertions is a non-empty list
    expected_assertions = plan_result.get("expected_assertions", [])
    if not isinstance(expected_assertions, list) or len(expected_assertions) == 0:
        return {
            "valid": False,
            "reason": "expected_assertions_empty_or_invalid",
            "message": "expected_assertions must be a non-empty list"
        }

    # Validate side_effect_targets is a non-empty list for stateful families
    side_effect_targets = plan_result.get("side_effect_targets", [])
    touched_families = plan_result.get("touched_requirement_families", [])

    if "stateful_side_effect" in touched_families:
        if not isinstance(side_effect_targets, list) or len(side_effect_targets) == 0:
            return {
                "valid": False,
                "reason": "side_effect_targets_required_for_stateful_family",
                "message": "stateful_side_effect family requires side_effect_targets specification"
            }

    return {
        "valid": True,
        "test_name": test_name,
        "assertions_count": len(expected_assertions),
        "side_effects_count": len(side_effect_targets)
    }


def validate_plan_semantic_binding(plan_result: Dict, requirement_ledger: Dict) -> Dict:
    """
    Plan must specify:
    - Exact test names for RED phase (not just "write tests")
    - Expected assertion contracts (what exactly will be proven)
    - Side effect ledger entries (what DB/file changes will occur)
    """
    issues = []

    # Check first_red_test exists and is valid
    first_red_test = plan_result.get("first_red_test", "")
    if not first_red_test:
        issues.append("first_red_test_missing")
    elif not TEST_NAME_PATTERN.match(first_red_test):
        issues.append(f"first_red_test_invalid_format: {first_red_test}")

    # Check expected_assertions
    expected_assertions = plan_result.get("expected_assertions", [])
    if not expected_assertions:
        issues.append("expected_assertions_missing")
    elif not isinstance(expected_assertions, list):
        issues.append("expected_assertions_not_list")
    elif len(expected_assertions) < 3:
        issues.append(f"expected_assertions_insufficient: {len(expected_assertions)} < 3")

    # Check side_effect_targets for stateful families
    touched_families = plan_result.get("touched_requirement_families", [])
    if "stateful_side_effect" in touched_families:
        side_effect_targets = plan_result.get("side_effect_targets", [])
        if not side_effect_targets:
            issues.append("side_effect_targets_missing_for_stateful")

    if issues:
        return {
            "valid": False,
            "issues": issues
        }

    return {
        "valid": True,
        "first_red_test": first_red_test,
        "assertions_count": len(expected_assertions),
        "side_effects_count": len(plan_result.get("side_effect_targets", []))
    }


def validate_test_name_format(test_name: str) -> Dict:
    """
    Validate test name follows the pattern: test[MethodName]_[Scenario]_[ExpectedOutcome]
    """
    if not test_name.startswith("test"):
        return {
            "valid": False,
            "reason": "test_name_must_start_with_test",
            "expected_prefix": "test"
        }

    parts = test_name.split("_")
    if len(parts) < 3:
        return {
            "valid": False,
            "reason": "insufficient_underscores",
            "expected_format": "test[MethodName]_[Scenario]_[ExpectedOutcome]",
            "actual_parts": len(parts)
        }

    # Check each part has content
    for i, part in enumerate(parts):
        if not part:
            return {
                "valid": False,
                "reason": f"empty_part_at_position_{i}",
                "test_name": test_name
            }

    return {
        "valid": True,
        "method_name": parts[0],
        "scenario": parts[1],
        "expected_outcome": "_".join(parts[2:])
    }


def validate_assertion_contracts(assertions: List[str]) -> Dict:
    """
    Validate assertion contracts are specific and meaningful.
    """
    if not assertions:
        return {
            "valid": False,
            "reason": "no_assertions_provided"
        }

    # Check for vague assertions
    vague_patterns = [
        r"^test.*$",
        r"^works correctly$",
        r"^is implemented$",
        r"^should work$"
    ]

    vague = []
    for assertion in assertions:
        for pattern in vague_patterns:
            if re.match(pattern, assertion, re.IGNORECASE):
                vague.append(assertion)
                break

    if vague:
        return {
            "valid": False,
            "reason": "vague_assertions_found",
            "vague_assertions": vague
        }

    # Check for behavioral keywords
    behavioral_keywords = [
        "throws", "returns", "inserts", "updates", "deletes", "selects",
        "verifies", "asserts", "equals", "notnull", "isfalse", "istrue"
    ]

    has_behavioral = any(
        any(keyword in assertion.lower() for keyword in behavioral_keywords)
        for assertion in assertions
    )

    if not has_behavioral:
        return {
            "valid": False,
            "reason": "no_behavioral_assertions",
            "message": "Assertions should include behavioral keywords (throws, returns, verifies, etc.)"
        }

    return {
        "valid": True,
        "assertions_count": len(assertions),
        "has_behavioral": True
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: requirement_contract.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  validate <plan_result_json> <requirement_ledger_json>", file=sys.stderr)
        print("  validate-semantic <plan_result_json> <requirement_ledger_json>", file=sys.stderr)
        print("  check-test-name <test_name>", file=sys.stderr)
        print("  check-assertions <assertions_json>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "validate":
        if len(sys.argv) < 4:
            print("Usage: requirement_contract.py validate <plan_result_json> <requirement_ledger_json>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            plan_result = json.load(f)
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            requirement_ledger = json.load(f)

        result = validate_requirement_contract_binding(plan_result, requirement_ledger)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "validate-semantic":
        if len(sys.argv) < 4:
            print("Usage: requirement_contract.py validate-semantic <plan_result_json> <requirement_ledger_json>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            plan_result = json.load(f)
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            requirement_ledger = json.load(f)

        result = validate_plan_semantic_binding(plan_result, requirement_ledger)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "check-test-name":
        if len(sys.argv) < 3:
            print("Usage: requirement_contract.py check-test-name <test_name>", file=sys.stderr)
            sys.exit(1)

        result = validate_test_name_format(sys.argv[2])
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "check-assertions":
        if len(sys.argv) < 3:
            print("Usage: requirement_contract.py check-assertions <assertions_json>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            assertions = json.load(f)

        result = validate_assertion_contracts(assertions)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
