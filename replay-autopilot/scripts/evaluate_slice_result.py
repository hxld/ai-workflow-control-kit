#!/usr/bin/env python3
"""
Evaluate slice result and enforce zero-delta rule when RED is blocked.

This script implements Experiment 2 from the evolution plan:
- Zero Executable Delta Enforcement After Blocked RED
"""

import json
import sys
from typing import Dict, List, Any


def evaluate_slice_result(slice_result: Dict, phase0_contract: Dict) -> Dict:
    """
    Evaluate slice result and apply zero-delta enforcement.

    Rules:
    1. If RED phase is blocked: implementation_allowed = false, executable_delta = 0
    2. If business assertion not observed: implementation_allowed = false, executable_delta = 0
    3. If TDD RED not replayed: implementation_allowed = false, executable_delta = 0
    """
    red_phase = slice_result.get("red_phase", {})
    red_status = red_phase.get("status", "unknown")
    business_assertion_observed = slice_result.get("business_assertion_observed", False)
    tdd_red_replayed = slice_result.get("tdd_red_replayed", False)

    # Check if RED was blocked
    red_blocked = (
        red_status == "blocked" or
        not business_assertion_observed or
        not tdd_red_replayed
    )

    if red_blocked:
        # Enforce zero-delta
        slice_result["implementation_allowed"] = False
        slice_result["executable_delta"] = 0
        slice_result["stop_reason"] = "red_blocked_zero_implementation"

        # Add blocker flags
        blockers = slice_result.get("blockers", [])
        if red_status == "blocked":
            blockers.append("red_phase_blocked")
        if not business_assertion_observed:
            blockers.append("business_assertion_not_observed")
        if not tdd_red_replayed:
            blockers.append("tdd_red_not_replayed")
        slice_result["blockers"] = list(set(blockers))

        # Set slice status
        slice_result["status"] = "BLOCKED"

    return slice_result


def detect_environment_blockers(red_output: str) -> List[str]:
    """Detect environment blockers in RED output."""
    environment_blockers = [
        "compilation error",
        "cannot find symbol",
        "class not found",
        "package does not exist",
        "dependency error",
        "lifecycle phase",
        "OutOfMemoryError",
        "Could not resolve dependencies"
    ]

    detected = []
    output_lower = red_output.lower()

    for blocker in environment_blockers:
        if blocker in output_lower:
            detected.append(blocker)

    return detected


def has_business_assertion(red_output: str) -> bool:
    """Check if RED output contains a business assertion."""
    # Look for assertion keywords in test code or output
    assertion_keywords = [
        "assert",
        "expect",
        "should",
        "must",
        "verify",
        "check"
    ]

    # Also check for actual test failure messages
    failure_patterns = [
        "expected",
        "but was",
        "failed",
        "error"
    ]

    output_lower = red_output.lower()
    has_assertion = any(kw in output_lower for kw in assertion_keywords)
    has_failure = any(kw in output_lower for kw in failure_patterns)

    return has_assertion or has_failure


def generate_slice_result_evaluation(
    slice_id: str,
    red_result: Dict,
    green_result: Dict,
    implementation_files: List[str],
    phase0_contract: Dict
) -> Dict:
    """Generate complete slice result evaluation with zero-delta enforcement."""

    # Extract RED phase info
    red_status = red_result.get("status", "unknown")
    red_command = red_result.get("command", "")
    red_output = red_result.get("output", "")

    # Detect environment blockers
    env_blockers = detect_environment_blockers(red_output)
    red_blocked_by_env = len(env_blockers) > 0

    # Check for business assertion
    business_assertion_present = has_business_assertion(red_output)

    # Check if RED was actually executed and failed on business assertion
    red_executed = red_status in ["fail", "error"]
    tdd_red_replayed = red_executed and not red_blocked_by_env and business_assertion_present

    # Build slice result
    slice_result = {
        "slice_id": slice_id,
        "red_phase": {
            "status": "blocked" if red_blocked_by_env else red_status,
            "command": red_command,
            "output": red_output[:500] if len(red_output) > 500 else red_output,
            "environment_blockers": env_blockers
        },
        "business_assertion_observed": business_assertion_present and not red_blocked_by_env,
        "tdd_red_replayed": tdd_red_replayed,
        "implementation_files": implementation_files,
        "green_phase": green_result,
        "implementation_allowed": None,  # Will be set by evaluate_slice_result
        "executable_delta": None,  # Will be set by evaluate_slice_result
        "stop_reason": None
    }

    # Apply zero-delta enforcement
    evaluated = evaluate_slice_result(slice_result, phase0_contract)

    return {
        "slice_result": evaluated,
        "zero_delta_enforced": evaluated.get("implementation_allowed") == False,
        "blockers": evaluated.get("blockers", []),
        "red_blocked_by_environment": red_blocked_by_env,
        "environment_blockers": env_blockers
    }


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python evaluate_slice_result.py --input <input.json>")
        print("  echo '{...}' | python evaluate_slice_result.py")
        print("\nInput JSON keys: slice_id, red_result, green_result, implementation_files, phase0_contract")
        sys.exit(0)

    if len(sys.argv) > 2 and sys.argv[1] == "--input":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            input_data = json.load(f)
    else:
        # Read from stdin
        input_data = json.loads(sys.stdin.read())
    result = generate_slice_result_evaluation(**input_data)
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with error code if blocked
    sys.exit(1 if result["zero_delta_enforced"] else 0)
