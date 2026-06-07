#!/usr/bin/env python3
"""
Side Effect Ledger Enforcement (Priority 3 experiment).
Ensures all claimed side effects have test assertions.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set


SIDE_EFFECT_PATTERNS = {
    "db_insert": [r"insert\s+into", r"mapper\.insert", r"save\(", r"persist\("],
    "db_update": [r"update\s+", r"mapper\.update", r"set\s+\w+\s*="],
    "db_delete": [r"delete\s+from", r"mapper\.delete"],
    "db_select": [r"select\s+", r"mapper\.select", r"query\("],
    "file_upload": [r"upload\(", r"uploadTo", r"\.upload"],
    "file_generate": [r"generate\w*\(", r"create\w*file", r"write\w*file"],
    "task_create": [r"task.*create", r"createTask", r"addTask"],
    "status_change": [r"status.*change", r"setStatus", r"updateStatus"],
    "notification": [r"notify", r"send\(", r"publish\("]
}

ASSERTION_PATTERNS = [
    r"assert\w+\(",
    r"verify\(",
    r"expect\(",
    r"equalTo\(",
    r"\.is[A-Z]\w*\(",
    r"assertSame",
    r"assertEquals",
    r"assertTrue",
    r"assertFalse",
    r"assertThat"
]


def parse_side_effect_ledger(file_path: str) -> List[Dict]:
    """Parse SIDE_EFFECT_LEDGER.md or extract from plan."""
    if not Path(file_path).exists():
        return []

    content = Path(file_path).read_text(encoding='utf-8')

    # Try to parse as JSON first
    if file_path.endswith('.json'):
        try:
            data = json.loads(content)
            if isinstance(data, list):
                return data
            if isinstance(data, dict) and 'side_effects' in data:
                return data['side_effects']
        except:
            pass

    # Parse markdown format
    effects = []
    current_effect = None

    for line in content.split("\n"):
        line = line.strip()

        # Match markdown list items with side effects
        match = re.match(r'^[-*]\s*(.+?):\s*(.+)$', line)
        if match:
            effect_type = match.group(1).strip()
            description = match.group(2).strip()

            effects.append({
                "type": effect_type,
                "description": description,
                "verified": False
            })

    return effects


def parse_test_file(test_file: str) -> Dict:
    """Parse test file for assertions and side effect patterns."""
    if not Path(test_file).exists():
        return {"assertions": [], "side_effects": []}

    content = Path(test_file).read_text(encoding='utf-8', errors='ignore')

    # Find assertions
    assertions = []
    for pattern in ASSERTION_PATTERNS:
        matches = re.finditer(pattern, content)
        for match in matches:
            # Extract line context
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line = content[line_start:line_end].strip()
            assertions.append(line)

    # Find side effect patterns
    side_effects = []
    for effect_type, patterns in SIDE_EFFECT_PATTERNS.items():
        for pattern in patterns:
            matches = re.finditer(pattern, content, re.IGNORECASE)
            for match in matches:
                line_start = content.rfind("\n", 0, match.start()) + 1
                line_end = content.find("\n", match.start())
                line = content[line_start:line_end].strip()
                side_effects.append({
                    "type": effect_type,
                    "pattern": pattern,
                    "line": line
                })

    return {
        "file": test_file,
        "assertions": assertions,
        "side_effects": side_effects,
        "total_assertions": len(assertions),
        "total_side_effects": len(side_effects)
    }


def verify_side_effect_coverage(side_effects: List[Dict], test_info: Dict) -> Dict:
    """Verify each side effect has corresponding test assertion."""
    verified = []
    unverified = []

    for effect in side_effects:
        effect_desc = effect.get("description", "").lower()
        effect_type = effect.get("type", "").lower()

        # Check if test has matching assertion
        found = False
        for assertion in test_info["assertions"]:
            assertion_lower = assertion.lower()

            # Check if effect description appears in assertion
            # (simple keyword matching)
            keywords = effect_desc.split()[:3]  # First 3 keywords
            if any(kw in assertion_lower for kw in keywords if len(kw) > 3):
                found = True
                break

        # Check if effect type matches
        if not found:
            for se in test_info["side_effects"]:
                if effect_type in se["type"].lower():
                    found = True
                    break

        if found:
            verified.append(effect)
        else:
            unverified.append(effect)

    return {
        "verified": verified,
        "unverified": unverified,
        "verified_count": len(verified),
        "unverified_count": len(unverified),
        "verification_rate": round(len(verified) / len(side_effects) * 100, 1) if side_effects else 100
    }


def check_test_has_db_assertions(test_info: Dict) -> bool:
    """Check if test has DB state verification assertions."""
    db_patterns = [
        r"mapper\.select",
        r"repository\.find",
        r"dao\.get",
        r"assertThat.*\.get",
        r"assertEquals.*\.get"
    ]

    content = " ".join(test_info.get("assertions", []))

    return any(re.search(pattern, content, re.IGNORECASE) for pattern in db_patterns)


def check_no_todo_placeholders(test_file: str) -> Dict:
    """Check for TODO placeholders instead of implementation."""
    content = Path(test_file).read_text(encoding='utf-8', errors='ignore')

    # Find TODO comments related to side effects
    todo_patterns = [
        r"TODO.*实际.*插入",
        r"TODO.*数据库",
        r"TODO.*上传",
        r"TODO.*实现",
        r"placeholder",
        r"占位",
        r"待实现"
    ]

    found_todos = []
    for i, line in enumerate(content.split("\n"), 1):
        for pattern in todo_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                found_todos.append({"line": i, "text": line.strip()})
                break

    return {
        "has_todo_placeholders": len(found_todos) > 0,
        "todos": found_todos
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: enforce_side_effect_ledger.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  verify <ledger_file> <test_file> - Verify side effect ledger coverage", file=sys.stderr)
        print("  check-todos <test_file> - Check for TODO placeholders", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "verify":
        if len(sys.argv) < 4:
            print("Usage: enforce_side_effect_ledger.py verify <ledger_file> <test_file>", file=sys.stderr)
            sys.exit(1)

        ledger_file = sys.argv[2]
        test_file = sys.argv[3]

        side_effects = parse_side_effect_ledger(ledger_file)
        test_info = parse_test_file(test_file)
        coverage = verify_side_effect_coverage(side_effects, test_info)

        # Additional checks
        has_db_assertions = check_test_has_db_assertions(test_info)
        todos = check_no_todo_placeholders(test_file)

        result = {
            "ledger_file": ledger_file,
            "test_file": test_file,
            "total_side_effects": len(side_effects),
            "verified_count": coverage["verified_count"],
            "unverified_count": coverage["unverified_count"],
            "verification_rate": coverage["verification_rate"],
            "has_db_assertions": has_db_assertions,
            "has_todo_placeholders": todos["has_todo_placeholders"],
            "unverified_effects": coverage["unverified"],
            "status": "PASS" if coverage["verification_rate"] >= 80 and not todos["has_todo_placeholders"] else "FAIL"
        }

        print(json.dumps(result, indent=2))

        if result["status"] == "FAIL":
            sys.exit(1)

    elif command == "check-todos":
        if len(sys.argv) < 3:
            print("Usage: enforce_side_effect_ledger.py check-todos <test_file>", file=sys.stderr)
            sys.exit(1)

        test_file = sys.argv[2]
        todos = check_no_todo_placeholders(test_file)

        result = {
            "test_file": test_file,
            "has_todo_placeholders": todos["has_todo_placeholders"],
            "todos": todos["todos"],
            "status": "PASS" if not todos["has_todo_placeholders"] else "FAIL"
        }

        print(json.dumps(result, indent=2))

        if result["status"] == "FAIL":
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
