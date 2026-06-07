#!/usr/bin/env python3
"""
RED Phase Hard Gate enforcement (Priority 2 experiment).
Ensures tests fail before implementation (RED→GREEN cycle).
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


BEHAVIORAL_KEYWORDS = [
    "assert", "verify", "equals", "populate", "insert", "update",
    "generate", "create", "status", "progress", "compensate",
    "select", "mapper", "dao", "repository", "transaction",
    "rollback", "persist", "save", "delete", "upload", "download",
    "send", "receive", "notify", "trigger", "execute"
]

STRUCTURAL_KEYWORDS = [
    "exists", "notexist", "ClassNotFound", "NoSuchMethod",
    "file.*not.*found", "missing.*class", "missing.*method"
]

STRUCTURAL_PATTERNS = [
    r"@Test\(expected\s*=\s*ClassNotFoundException\.class\)",
    r"@Test\(expected\s*=\s*NoSuchMethodException\.class\)",
    r"expectedExceptions\s*=\s*ClassNotFoundException\.class",
    r"assertTrue\(.*\.exists\(\)\)",
    r"assertFalse\(.*\.exists\(\)\)"
]


def parse_test_file(file_path: str) -> Dict:
    """Parse test file and categorize test methods."""
    content = Path(file_path).read_text(encoding='utf-8', errors='ignore')

    tests = []
    # Find @Test methods
    test_methods = re.finditer(r'@Test\s*\n\s*(?:public\s+|private\s+)?(\w+)\s+(\w+)\s*\([^)]*\)\s*(?:throws\s+\w+)?\s*\{', content)

    for match in test_methods:
        method_start = match.start()
        method_name = match.group(2)

        # Extract method body (simple heuristic)
        brace_count = 0
        found_open_brace = False
        method_end = method_start
        for i in range(match.end(), len(content)):
            if content[i] == '{':
                brace_count += 1
                found_open_brace = True
            elif content[i] == '}':
                brace_count -= 1
                if found_open_brace and brace_count == 0:
                    method_end = i
                    break

        method_body = content[method_start:method_end]

        # Categorize test
        category = categorize_test(method_name, method_body)

        tests.append({
            "name": method_name,
            "category": category,
            "behavioral_keywords": find_keywords(method_body, BEHAVIORAL_KEYWORDS),
            "structural_patterns": find_patterns(method_body, STRUCTURAL_PATTERNS)
        })

    return {
        "file": str(file_path),
        "tests": tests
    }


def categorize_test(method_name: str, body: str) -> str:
    """Categorize test as BEHAVIORAL or STRUCTURAL."""
    body_lower = body.lower()
    method_lower = method_name.lower()

    # Check for structural patterns
    for pattern in STRUCTURAL_PATTERNS:
        if re.search(pattern, body):
            return "STRUCTURAL"

    # Check for structural keywords
    if any(re.search(rf"\b{re.escape(kw)}\b", body_lower, re.IGNORECASE) for kw in STRUCTURAL_KEYWORDS):
        return "STRUCTURAL"

    # Check for behavioral keywords
    behavioral_hits = sum(1 for kw in BEHAVIORAL_KEYWORDS if re.search(rf"\b{re.escape(kw)}\b", body_lower, re.IGNORECASE))

    if behavioral_hits >= 2:
        return "BEHAVIORAL"

    # Check method name for behavioral intent
    if any(word in method_lower for word in ["success", "fail", "valid", "invalid", "correct", "incorrect"]):
        return "BEHAVIORAL"

    return "STRUCTURAL"


def find_keywords(text: str, keywords: List[str]) -> List[str]:
    """Find which keywords appear in text."""
    found = []
    text_lower = text.lower()
    for kw in keywords:
        if re.search(rf"\b{re.escape(kw.lower())}\b", text_lower):
            found.append(kw)
    return found


def find_patterns(text: str, patterns: List[str]) -> List[str]:
    """Find which patterns match in text."""
    found = []
    for pattern in patterns:
        if re.search(pattern, text, re.IGNORECASE):
            found.append(pattern)
    return found


def check_red_phase_violations(test_info: Dict) -> Dict:
    """Check for RED phase violations."""
    violations = []

    if not test_info["tests"]:
        violations.append("no_tests_found")
        return {
            "violations": violations,
            "can_proceed": False
        }

    behavioral_count = sum(1 for t in test_info["tests"] if t["category"] == "BEHAVIORAL")
    structural_count = sum(1 for t in test_info["tests"] if t["category"] == "STRUCTURAL")

    # Violation: All tests are structural
    if structural_count > 0 and behavioral_count == 0:
        violations.append("all_tests_structural")

    # Violation: No behavioral tests
    if behavioral_count == 0:
        violations.append("no_behavioral_tests")

    # Warning: Low behavioral test ratio
    total = len(test_info["tests"])
    behavioral_ratio = behavioral_count / total if total > 0 else 0
    if behavioral_ratio < 0.5:
        violations.append("low_behavioral_ratio")

    return {
        "violations": violations,
        "can_proceed": behavioral_count > 0,
        "behavioral_count": behavioral_count,
        "structural_count": structural_count,
        "behavioral_ratio": round(behavioral_ratio * 100, 1)
    }


def verify_maven_red_phase(worktree_path: str, test_class: str, maven_settings: str) -> Dict:
    """Verify that tests actually fail before implementation (RED phase)."""
    import subprocess

    # Run Maven test
    cmd = [
        "mvn",
        "-s", maven_settings,
        "-f", f"{worktree_path}\\pom.xml",
        "test",
        f"-Dtest={test_class}",
        "-Dsurefire.failIfNoSpecifiedTests=false"
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300
        )

        output = result.stdout + "\n" + result.stderr

        # Parse Maven output
        build_success = "BUILD SUCCESS" in output
        build_failure = "BUILD FAILURE" in output
        tests_run = re.search(r"Tests run: (\d+)", output)

        # RED phase requires tests to FAIL
        if build_success:
            return {
                "red_phase_satisfied": False,
                "reason": "tests_passed_without_implementation",
                "message": "Tests passed before implementation - likely structural tests"
            }

        if build_failure and tests_run:
            # Check if failure is due to compilation or test failure
            compilation_error = "COMPILATION ERROR" in output or "cannot find symbol" in output
            test_failures = re.search(r"Failures: (\d+)", output)

            if compilation_error:
                return {
                    "red_phase_satisfied": False,
                    "reason": "compilation_error",
                    "message": "Code does not compile - fix compilation errors first"
                }

            if test_failures and int(test_failures.group(1)) > 0:
                return {
                    "red_phase_satisfied": True,
                    "reason": "tests_failed_as_expected",
                    "message": "Tests correctly fail before implementation (RED phase OK)"
                }

        return {
            "red_phase_satisfied": False,
            "reason": "inconclusive",
            "message": "Could not determine RED phase status from Maven output"
        }

    except subprocess.TimeoutExpired:
        return {
            "red_phase_satisfied": False,
            "reason": "timeout",
            "message": "Maven test execution timed out"
        }
    except Exception as e:
        return {
            "red_phase_satisfied": False,
            "reason": "error",
            "message": str(e)
        }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: enforce_red_phase_gate.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  analyze <test_file> - Analyze test file for behavioral/structural classification", file=sys.stderr)
        print("  verify-red <worktree> <test_class> <maven_settings> - Verify RED phase with Maven", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "analyze":
        if len(sys.argv) < 3:
            print("Usage: enforce_red_phase_gate.py analyze <test_file>", file=sys.stderr)
            sys.exit(1)

        test_file = sys.argv[2]
        test_info = parse_test_file(test_file)
        check = check_red_phase_violations(test_info)

        result = {
            "file": test_file,
            "total_tests": len(test_info["tests"]),
            "behavioral_count": check.get("behavioral_count", 0),
            "structural_count": check.get("structural_count", 0),
            "behavioral_ratio": check.get("behavioral_ratio", 0),
            "violations": check["violations"],
            "red_phase_compliant": check["can_proceed"],
            "tests": test_info["tests"]
        }

        print(json.dumps(result, indent=2))

        if not check["can_proceed"]:
            sys.exit(1)

    elif command == "verify-red":
        if len(sys.argv) < 5:
            print("Usage: enforce_red_phase_gate.py verify-red <worktree> <test_class> <maven_settings>", file=sys.stderr)
            sys.exit(1)

        worktree = sys.argv[2]
        test_class = sys.argv[3]
        maven_settings = sys.argv[4]

        result = verify_maven_red_phase(worktree, test_class, maven_settings)
        print(json.dumps(result, indent=2))

        if not result.get("red_phase_satisfied"):
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
