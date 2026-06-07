#!/usr/bin/env python3
"""
Executable Evidence Gate (Experiment E1).

Requires test execution evidence and DB state verification for stateful families.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any


def validate_executable_evidence(slice_result: Dict, requirement_ledger: Dict) -> Dict:
    """
    Executable evidence requires:
    1. Test execution PASS/FAIL result (not just "implemented")
    2. For stateful_side_effect families: DB SELECT verification
    3. For async operations: completion verification
    """
    evidences = slice_result.get("test_evidence", [])

    # Check 1: Test execution verified
    test_execution = any(
        e.get("phase") == "GREEN" and e.get("result") in ["PASS", "FAIL"]
        for e in evidences
    )

    if not test_execution:
        return {
            "valid": False,
            "reason": "tests_not_executed",
            "coverage_cap": 0,
            "message": "GREEN phase must produce PASS or FAIL test result, not just implementation"
        }

    # Check 2: DB state verification for stateful families
    touched_families = slice_result.get("touched_requirement_families", [])
    if "stateful_side_effect" in touched_families:
        db_verification = any(
            "SELECT" in str(e).upper() or "verify" in str(e).lower()
            for e in evidences
        )
        if not db_verification:
            return {
                "valid": False,
                "reason": "no_db_state_verification",
                "coverage_cap": 5,
                "message": "stateful_side_effect family requires DB SELECT verification (e.g., SELECT after INSERT)"
            }

    # Check 3: No TODO/STUB markers
    implemented_files = slice_result.get("implemented_files", [])
    for file_path in implemented_files:
        full_path = Path(slice_result.get("worktree_path", "")) / file_path
        if full_path.exists():
            content = full_path.read_text(encoding='utf-8', errors='ignore')
            if "TODO" in content or "STUB" in content:
                return {
                    "valid": False,
                    "reason": "todo_stub_present",
                    "coverage_cap": 0,
                    "message": f"TODO/STUB markers found in {file_path}. Complete implementation required for GREEN phase."
                }

    return {
        "valid": True,
        "reason": "executable_evidence_verified",
        "coverage_cap": 100,
        "message": "Test execution and DB verification evidence validated"
    }


def extract_maven_test_evidence(maven_output: str) -> Dict:
    """Extract test execution evidence from Maven output."""
    tests_run = re.search(r"Tests run: (\d+)", maven_output)
    failures = re.search(r"Failures: (\d+)", maven_output)
    errors = re.search(r"Errors: (\d+)", maven_output)
    build_success = "BUILD SUCCESS" in maven_output
    build_failure = "BUILD FAILURE" in maven_output

    result = {
        "tests_run": int(tests_run.group(1)) if tests_run else 0,
        "failures": int(failures.group(1)) if failures else 0,
        "errors": int(errors.group(1)) if errors else 0,
        "build_status": "SUCCESS" if build_success else "FAILURE" if build_failure else "UNKNOWN",
        "phase": "GREEN",
        "result": "PASS" if build_success else "FAIL" if build_failure else "UNKNOWN"
    }

    return result


def check_db_operations_in_test(test_file_path: str) -> List[str]:
    """Check if test file contains DB verification patterns."""
    if not Path(test_file_path).exists():
        return []

    content = Path(test_file_path).read_text(encoding='utf-8', errors='ignore')

    db_patterns = [
        r"mapper\.select",
        r"dao\.select",
        r"repository\.find",
        r"\.selectOne\(",
        r"\.selectList\(",
        r"SELECT.*FROM",
        r"assertThat.*.*select"
    ]

    found = []
    for pattern in db_patterns:
        if re.search(pattern, content, re.IGNORECASE):
            found.append(pattern)

    return found


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: executable_evidence.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  validate <slice_result_json> <requirement_ledger_json>", file=sys.stderr)
        print("  parse-maven <maven_output>", file=sys.stderr)
        print("  check-db <test_file>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "validate":
        if len(sys.argv) < 4:
            print("Usage: executable_evidence.py validate <slice_result_json> <requirement_ledger_json>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            slice_result = json.load(f)
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            requirement_ledger = json.load(f)

        result = validate_executable_evidence(slice_result, requirement_ledger)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "parse-maven":
        if len(sys.argv) < 3:
            print("Usage: executable_evidence.py parse-maven <maven_output_file>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            maven_output = f.read()

        result = extract_maven_test_evidence(maven_output)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "check-db":
        if len(sys.argv) < 3:
            print("Usage: executable_evidence.py check-db <test_file>", file=sys.stderr)
            sys.exit(1)

        db_ops = check_db_operations_in_test(sys.argv[2])
        print(json.dumps({"db_operations_found": db_ops}, indent=2, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
