#!/usr/bin/env python3
"""
Trigger Point Validation (Experiment 1 for v447)

Validates that the selected carrier matches the trigger point in requirement text.
This addresses the 'wrong_test_surface' gap by ensuring correct AI task processor selection.

Maps 'XX成功后' language patterns to correct AI task processor types:
- 'AI核赔结果获取成功后' → AiApplyClaimApiTaskProcessor (Apply Claim task)
- '赔款计算成功后' → AiCalculateLossApiTaskProcessor (Calculate Loss task)
"""

import sys
import re
import json
from pathlib import Path
from typing import Dict, List, Tuple, Optional


# Trigger point to processor mapping
TRIGGER_PATTERNS = {
    "AI核赔结果获取成功后": "AiApplyClaimApiTaskProcessor",
    "核赔结果获取成功后": "AiApplyClaimApiTaskProcessor",
    "AI核赔成功后": "AiApplyClaimApiTaskProcessor",
    "核赔成功后": "AiApplyClaimApiTaskProcessor",
    "赔款计算成功后": "AiCalculateLossApiTaskProcessor",
    "计算损失成功后": "AiCalculateLossApiTaskProcessor",
    "理算成功后": "AiCalculateLossApiTaskProcessor",
}

# Task processor to trigger pattern reverse mapping (for validation)
PROCESSOR_TO_TRIGGER = {
    "AiApplyClaimApiTaskProcessor": [
        "AI核赔结果获取成功后",
        "核赔结果获取成功后",
        "AI核赔成功后",
        "核赔成功后",
    ],
    "AiCalculateLossApiTaskProcessor": [
        "赔款计算成功后",
        "计算损失成功后",
        "理算成功后",
    ],
}


class ValidationError(Exception):
    """Raised when trigger point validation fails."""
    pass


def extract_trigger_point_from_requirement(requirement_text: str) -> Optional[str]:
    """
    Extract trigger point pattern from requirement text.

    Returns the first matching trigger pattern, or None if no match.
    """
    for pattern in TRIGGER_PATTERNS.keys():
        if pattern in requirement_text:
            return pattern
    return None


def validate_trigger_point(
    requirement_text: str,
    selected_carrier: str
) -> Tuple[bool, str, Dict]:
    """
    Validate that the selected carrier matches the trigger point in requirement text.

    Args:
        requirement_text: The requirement source text
        selected_carrier: The selected carrier class name

    Returns:
        Tuple of (is_valid, error_message, validation_details)
    """
    validation_details = {
        "requirement_text_snippet": requirement_text[:200] + "..." if len(requirement_text) > 200 else requirement_text,
        "selected_carrier": selected_carrier,
        "trigger_patterns_found": [],
        "expected_processors": [],
    }

    # Extract trigger point from requirement
    trigger_point = extract_trigger_point_from_requirement(requirement_text)

    if not trigger_point:
        # No trigger pattern found - this is a warning, not a failure
        validation_details["status"] = "WARN"
        validation_details["reason"] = "no_trigger_pattern_found"
        return True, "", validation_details

    validation_details["trigger_patterns_found"] = [trigger_point]

    # Get expected processor for this trigger
    expected_processor = TRIGGER_PATTERNS.get(trigger_point)
    validation_details["expected_processors"] = [expected_processor]

    # Check if selected carrier matches expected processor
    if expected_processor and expected_processor not in selected_carrier:
        # Wrong processor selected
        validation_details["status"] = "FAIL"
        validation_details["reason"] = "wrong_task_type"
        validation_details["expected_processor"] = expected_processor
        validation_details["actual_processor"] = selected_carrier

        error_msg = (
            f"Wrong task type: Requirement says '{trigger_point}' which maps to "
            f"{expected_processor} (Apply Claim task), but selected {selected_carrier} "
            f"(Calculate Loss task). The Calculate Loss task only calculates amounts; "
            f"the Apply Claim task is the comprehensive AI interface that triggers auto-flow."
        )
        return False, error_msg, validation_details

    # Correct processor selected
    validation_details["status"] = "PASS"
    validation_details["reason"] = "correct_task_type"
    return True, "", validation_details


def suggest_correct_carrier(
    requirement_text: str,
    available_carriers: List[str]
) -> Optional[Dict]:
    """
    Suggest the correct carrier based on trigger point in requirement.

    Returns a dict with suggestion if trigger point found and alternative available.
    """
    trigger_point = extract_trigger_point_from_requirement(requirement_text)

    if not trigger_point:
        return None

    expected_processor = TRIGGER_PATTERNS.get(trigger_point)
    if not expected_processor:
        return None

    # Check if expected processor is in available carriers
    for carrier in available_carriers:
        if expected_processor in carrier:
            return {
                "suggested_carrier": carrier,
                "trigger_point": trigger_point,
                "reason": f"Trigger '{trigger_point}' requires {expected_processor}",
            }

    return {
        "suggested_carrier": expected_processor,
        "trigger_point": trigger_point,
        "reason": f"Trigger '{trigger_point}' requires {expected_processor}, but carrier not found in available list",
    }


def validate_phase0_trigger_point(
    requirement_path: Path,
    selected_carrier: str
) -> Dict:
    """
    Validate trigger point during Phase 0.

    Reads requirement from file and validates against selected carrier.
    """
    if not requirement_path.exists():
        return {
            "status": "ERROR",
            "reason": "requirement_not_found",
            "path": str(requirement_path),
        }

    try:
        requirement_text = requirement_path.read_text(encoding='utf-8')
    except Exception as e:
        return {
            "status": "ERROR",
            "reason": "requirement_read_error",
            "error": str(e),
        }

    is_valid, error_msg, details = validate_trigger_point(requirement_text, selected_carrier)

    result = {
        "status": "PASS" if is_valid else "FAIL",
        "selected_carrier": selected_carrier,
        "validation_details": details,
    }

    if not is_valid:
        result["error"] = error_msg

    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: trigger_point_validator.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  validate <requirement_text> <selected_carrier>", file=sys.stderr)
        print("  validate-file <requirement_path> <selected_carrier>", file=sys.stderr)
        print("  extract <requirement_text>", file=sys.stderr)
        print("  suggest <requirement_text> <available_carriers_json>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "validate":
        if len(sys.argv) < 4:
            print("Usage: trigger_point_validator.py validate <requirement_text> <selected_carrier>", file=sys.stderr)
            sys.exit(1)

        requirement_text = sys.argv[2]
        selected_carrier = sys.argv[3]

        is_valid, error_msg, details = validate_trigger_point(requirement_text, selected_carrier)

        result = {
            "valid": is_valid,
            "error": error_msg if error_msg else None,
            "details": details,
        }

        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not is_valid:
            sys.exit(1)

    elif command == "validate-file":
        if len(sys.argv) < 4:
            print("Usage: trigger_point_validator.py validate-file <requirement_path> <selected_carrier>", file=sys.stderr)
            sys.exit(1)

        requirement_path = Path(sys.argv[2])
        selected_carrier = sys.argv[3]

        result = validate_phase0_trigger_point(requirement_path, selected_carrier)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if result.get("status") == "FAIL":
            sys.exit(1)

    elif command == "extract":
        if len(sys.argv) < 3:
            print("Usage: trigger_point_validator.py extract <requirement_text>", file=sys.stderr)
            sys.exit(1)

        requirement_text = sys.argv[2]
        trigger_point = extract_trigger_point_from_requirement(requirement_text)

        if trigger_point:
            expected = TRIGGER_PATTERNS.get(trigger_point, "")
            result = {
                "trigger_point": trigger_point,
                "expected_processor": expected,
            }
        else:
            result = {
                "trigger_point": None,
                "message": "No trigger pattern found in requirement text",
            }

        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "suggest":
        if len(sys.argv) < 4:
            print("Usage: trigger_point_validator.py suggest <requirement_text> <available_carriers_json>", file=sys.stderr)
            sys.exit(1)

        requirement_text = sys.argv[2]
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            available_carriers = json.load(f)

        suggestion = suggest_correct_carrier(requirement_text, available_carriers)

        if suggestion:
            print(json.dumps(suggestion, indent=2, ensure_ascii=False))
        else:
            print(json.dumps({"suggestion": None}, indent=2, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
