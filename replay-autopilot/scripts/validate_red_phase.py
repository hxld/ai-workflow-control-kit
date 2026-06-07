#!/usr/bin/env python3
"""
RED Phase Business Assertion Validator (Experiment 2).
RED phase must fail with BUSINESS ASSERTION, not compilation error.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional


# Compilation failure patterns (WRONG surface)
COMPILATION_FAILURE_PATTERNS = [
    r"compilation error",
    r"cannot find symbol",
    r"ClassNotFoundException",
    r"NoSuchMethodException",
    r"package .* does not exist",
    r"cannot resolve symbol",
    r"method .* not found",
    r"class .* not found"
]

# Business assertion patterns
BUSINESS_ASSERTION_PATTERNS = [
    r"assertThat\(",
    r"assertEquals\(",
    r"assertTrue\(",
    r"assertFalse\(",
    r"assertSame\(",
    r"assertNull\(",
    r"assertNotNull\(",
    r"verify\(",
    r"expect\(",
    r"\.is[A-Z]\w*\(",
    r"\.isEqualTo\(",
    r"\.isNotNull\(",
    r"\.isNull\("
]

# Structural assertion patterns (WRONG - these check structure, not behavior)
STRUCTURAL_ASSERTION_PATTERNS = [
    r"assertNotNull\(.*service\)",
    r"assertNotNull\(.*mapper\)",
    r"assertThat\(.*\)\.isNotNull\(\)\s*;",
    r"verify\(\w+\)\.exists\(\)"
]


def parse_test_file(test_file: str) -> Dict:
    """Parse test file and extract assertions."""
    if not Path(test_file).exists():
        return {"exists": False, "assertions": [], "content": ""}

    content = Path(test_file).read_text(encoding='utf-8', errors='ignore')

    # Extract assertions
    assertions = []
    for pattern in BUSINESS_ASSERTION_PATTERNS:
        matches = re.finditer(pattern, content)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.end())
            line = content[line_start:line_end].strip()
            assertions.append(line)

    return {
        "exists": True,
        "file": test_file,
        "content": content,
        "assertions": assertions,
        "total_assertions": len(assertions)
    }


def check_compilation_failure(test_output: str) -> Dict:
    """Check if test output indicates compilation failure."""
    output_lower = test_output.lower()

    for pattern in COMPILATION_FAILURE_PATTERNS:
        if re.search(pattern, output_lower, re.IGNORECASE):
            return {
                "has_compilation_failure": True,
                "pattern_matched": pattern
            }

    return {"has_compilation_failure": False}


def extract_business_assertions(test_info: Dict) -> List[Dict]:
    """Extract and categorize business assertions from test."""
    assertions = []
    content = test_info.get("content", "")

    for pattern in BUSINESS_ASSERTION_PATTERNS:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.end())
            line = content[line_start:line_end].strip()
            line_num = content[:match.start()].count("\n") + 1

            assertions.append({
                "pattern": pattern,
                "line": line_num,
                "text": line
            })

    return assertions


def is_structural_assertion(assertion_text: str) -> bool:
    """Check if assertion validates structure instead of behavior."""
    for pattern in STRUCTURAL_ASSERTION_PATTERNS:
        if re.search(pattern, assertion_text, re.IGNORECASE):
            return True
    return False


def validate_red_phase(test_file: str, test_output: str) -> Dict:
    """
    Executable Test Surface Validator:
    RED phase must fail with BUSINESS ASSERTION, not compilation error.
    """
    test_info = parse_test_file(test_file)

    if not test_info.get("exists"):
        return {
            "valid": False,
            "gate": "red_phase_business_assertion",
            "reason": "test_file_not_found",
            "test_file": test_file
        }

    # Check for compilation failure (wrong surface)
    compilation_check = check_compilation_failure(test_output)
    if compilation_check["has_compilation_failure"]:
        return {
            "valid": False,
            "gate": "red_phase_business_assertion",
            "reason": "red_phase_compilation_failure_not_allowed",
            "evidence": "RED test failed with compilation error instead of business assertion",
            "required_pattern": "Test must call production method and assert on business result",
            "example": "assertThat(aiAutoClaimFlowService.handle(caseId, task)).isNull();",
            "compilation_pattern": compilation_check.get("pattern_matched")
        }

    # Check for business assertion pattern
    business_assertions = extract_business_assertions(test_info)

    if not business_assertions:
        return {
            "valid": False,
            "gate": "red_phase_business_assertion",
            "reason": "red_phase_no_business_assertion",
            "evidence": "Test has no business assertions (assertThat, assertEquals, verify)",
            "required_patterns": ["assertThat", "assertEquals", "verify", "@Transactional"],
            "found_assertions": 0
        }

    # Verify assertion tests business logic, not structure
    structural_assertions = []
    behavioral_assertions = []

    for assertion in business_assertions:
        if is_structural_assertion(assertion["text"]):
            structural_assertions.append(assertion)
        else:
            behavioral_assertions.append(assertion)

    # If all assertions are structural, fail
    if len(behavioral_assertions) == 0 and len(structural_assertions) > 0:
        return {
            "valid": False,
            "gate": "red_phase_business_assertion",
            "reason": "red_phase_structural_assertion_only",
            "evidence": "All assertions validate structure, not behavior",
            "structural_assertions": structural_assertions,
            "required": "Assert on business state (DB values, output objects, return values)"
        }

    return {
        "valid": True,
        "gate": "red_phase_business_assertion",
        "business_assertions": behavioral_assertions,
        "structural_assertions": structural_assertions,
        "behavioral_count": len(behavioral_assertions),
        "structural_count": len(structural_assertions)
    }


def validate_test_charter_comprehensive(test_file: str) -> Dict:
    """
    Comprehensive test charter validation combining RED phase validation
    with test charter behavioral assertion checks (v357).
    """
    # First run basic test file parsing
    test_info = parse_test_file(test_file)

    if not test_info.get("exists"):
        return {
            "valid": False,
            "gate": "test_charter_comprehensive",
            "reason": "test_file_not_found",
            "test_file": test_file
        }

    issues = []

    # Check 1: Has behavioral assertions
    if test_info.get("total_assertions", 0) == 0:
        issues.append({
            "code": "no_behavioral_assertions",
            "message": "Test missing required behavioral assertion patterns"
        })

    # Check 2: No forbidden fail() patterns
    content = test_info.get("content", "")
    forbidden_patterns = [
        (r'fail\s*\(\s*["\'].*due to.*not implemented', 'fail_with_todo'),
        (r'fail\s*\(\s*["\'].*TODO', 'fail_todo_placeholder'),
        (r'fail\s*\(\s*["\'].*占位', 'fail_placeholder_chinese')
    ]

    forbidden_found = []
    for pattern, pattern_name in forbidden_patterns:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line_num = content[:match.start()].count("\n") + 1
            forbidden_found.append({
                "pattern_type": pattern_name,
                "line": line_num
            })

    if forbidden_found:
        issues.append({
            "code": "forbidden_fail_pattern",
            "message": "Test uses forbidden fail() anti-pattern instead of behavioral assertions",
            "examples": forbidden_found[:3]
        })

    # Check 3: Has test methods
    test_methods = len(re.findall(r'@Test', content))
    if test_methods == 0:
        issues.append({
            "code": "no_test_methods",
            "message": "No @Test methods found in file"
        })

    # Check 4: Assertions validate business logic, not structure
    structural_assertions = []
    behavioral_assertions = []

    for pattern in BUSINESS_ASSERTION_PATTERNS:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.end())
            line = content[line_start:line_end].strip()

            if is_structural_assertion(line):
                structural_assertions.append({"pattern": pattern, "text": line})
            else:
                behavioral_assertions.append({"pattern": pattern, "text": line})

    if len(behavioral_assertions) == 0 and len(structural_assertions) > 0:
        issues.append({
            "code": "structural_assertions_only",
            "message": "All assertions validate structure, not behavior",
            "structural_count": len(structural_assertions)
        })

    is_valid = len(issues) == 0

    return {
        "valid": is_valid,
        "gate": "test_charter_comprehensive",
        "reason": "test_charter_valid" if is_valid else "test_charter_invalid",
        "issues": issues,
        "summary": {
            "test_methods": test_methods,
            "behavioral_assertions": len(behavioral_assertions),
            "structural_assertions": len(structural_assertions),
            "forbidden_patterns": len(forbidden_found)
        }
    }


def validate_green_phase(test_file: str, expected_side_effects: List[str]) -> Dict:
    """
    GREEN phase must verify side effects with DB capture or output verification.
    """
    test_info = parse_test_file(test_file)

    if not test_info.get("exists"):
        return {
            "valid": False,
            "gate": "green_phase_side_effect_verification",
            "reason": "test_file_not_found"
        }

    content = test_info.get("content", "")

    # Check for side effect verification patterns
    has_db_capture = "AtomicReference" in content or "capture" in content.lower()
    has_output_verification = "assertThat" in content and ("returnValue" in content or "result" in content.lower())
    has_mapper_verification = any(pattern in content for pattern in ["mapper.select", "repository.find", "dao.get"])

    if expected_side_effects and not (has_db_capture or has_output_verification or has_mapper_verification):
        return {
            "valid": False,
            "gate": "green_phase_side_effect_verification",
            "reason": "green_phase_missing_side_effect_verification",
            "evidence": "GREEN test passes but doesn't verify side effects",
            "required": "Use AtomicReference to capture DB arguments or verify output values",
            "expected_side_effects": expected_side_effects,
            "has_db_capture": has_db_capture,
            "has_output_verification": has_output_verification,
            "has_mapper_verification": has_mapper_verification
        }

    return {
        "valid": True,
        "gate": "green_phase_side_effect_verification",
        "has_db_capture": has_db_capture,
        "has_output_verification": has_output_verification,
        "has_mapper_verification": has_mapper_verification,
        "verification_methods": {
            "db_capture": has_db_capture,
            "output_verification": has_output_verification,
            "mapper_verification": has_mapper_verification
        }
    }


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: validate_red_phase.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  validate-red <test_file> <test_output_file> - Validate RED phase", file=sys.stderr)
        print("  validate-green <test_file> <expected_side_effects_json> - Validate GREEN phase", file=sys.stderr)
        print("  validate-charter <test_file> - Validate test charter (v357)", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "validate-charter":
        if len(sys.argv) < 3:
            print("Usage: validate_red_phase.py validate-charter <test_file>", file=sys.stderr)
            sys.exit(1)

        test_file = sys.argv[2]
        result = validate_test_charter_comprehensive(test_file)

        print(json.dumps(result, indent=2))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "validate-red":
        if len(sys.argv) < 4:
            print("Usage: validate_red_phase.py validate-red <test_file> <test_output_file>", file=sys.stderr)
            sys.exit(1)

        test_file = sys.argv[2]
        test_output_file = sys.argv[3]

        test_output = Path(test_output_file).read_text(encoding='utf-8', errors='ignore')
        result = validate_red_phase(test_file, test_output)

        print(json.dumps(result, indent=2))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "validate-green":
        if len(sys.argv) < 4:
            print("Usage: validate_red_phase.py validate-green <test_file> <expected_side_effects_json>", file=sys.stderr)
            sys.exit(1)

        test_file = sys.argv[2]
        effects_json = sys.argv[3]

        expected_effects = json.loads(Path(effects_json).read_text(encoding='utf-8'))
        result = validate_green_phase(test_file, expected_effects)

        print(json.dumps(result, indent=2))

        if not result.get("valid"):
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
