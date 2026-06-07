#!/usr/bin/env python3
"""
GREEN Phase No-Mock Gate enforcement (Experiment 1).
Checks if implementation contains only mock responses or TODOs before GREEN phase.
Blocks GREEN phase if only mock implementation exists.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


# Mock-only patterns that indicate placeholder implementation
MOCK_INDICATORS = [
    r"TODO",
    r"FIXME",
    r"placeholder",
    r"not implemented",
    r"mock return",
    r"stub implementation",
    r"占位",
    r"待实现",
    r"实际.*插入.*TODO",
    r"TODO.*实际.*插入",
]

# Patterns that indicate method returns mock/fixed values
MOCK_RETURN_PATTERNS = [
    r"return\s+null;\s*//\s*TODO",
    r"return\s+\"\";\s*//\s*TODO",
    r"return\s+false;\s*//\s*TODO",
    r"return\s+0;\s*//\s*TODO",
    r"return\s+new\s+\w+\(\);\s*//\s*(TODO|placeholder)",
    r"throw\s+new\s+NotImplementedException",
    r"throw\s+new\s+UnsupportedOperationException",
]

# DB operation patterns that indicate real implementation
DB_OPERATION_PATTERNS = [
    r"mapper\.insert",
    r"mapper\.update",
    r"mapper\.delete",
    r"mapper\.select",
    r"dao\.insert",
    r"dao\.update",
    r"repository\.save",
    r"repository\.delete",
    r"\.insert\(",
    r"\.update\(",
    r"\.delete\(",
]


def has_mock_indicators(content: str) -> List[Dict]:
    """Check if content contains mock indicator patterns."""
    found = []

    for pattern in MOCK_INDICATORS:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line = content[line_start:line_end].strip()
            line_num = content[:match.start()].count("\n") + 1

            found.append({
                "pattern": pattern,
                "line": line_num,
                "text": line
            })

    return found


def has_mock_only_returns(content: str) -> List[Dict]:
    """Check if content has mock-only return statements."""
    found = []

    for pattern in MOCK_RETURN_PATTERNS:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line = content[line_start:line_end].strip()
            line_num = content[:match.start()].count("\n") + 1

            found.append({
                "pattern": pattern,
                "line": line_num,
                "text": line
            })

    return found


def has_db_operations(content: str) -> List[str]:
    """Check if content contains real DB operations."""
    found = []

    for pattern in DB_OPERATION_PATTERNS:
        if re.search(pattern, content, re.IGNORECASE):
            found.append(pattern)

    return found


def check_mock_only_implementation(file_path: str) -> Dict:
    """Check if a file contains only mock implementation."""
    if not Path(file_path).exists():
        return {
            "file": file_path,
            "exists": False,
            "mock_only": False,
            "reason": "file_not_found"
        }

    content = Path(file_path).read_text(encoding='utf-8', errors='ignore')

    mock_indicators = has_mock_indicators(content)
    mock_returns = has_mock_only_returns(content)
    db_ops = has_db_operations(content)

    # Determine if this is mock-only
    is_mock_only = (
        len(mock_indicators) > 0 or
        len(mock_returns) > 0
    ) and len(db_ops) == 0

    return {
        "file": file_path,
        "exists": True,
        "mock_only": is_mock_only,
        "mock_indicators": mock_indicators,
        "mock_returns": mock_returns,
        "db_operations": db_ops,
        "reason": "mock_indicators_or_placeholders_found" if is_mock_only else "real_implementation_found"
    }


def verify_green_phase_allowed(
    worktree_path: str,
    implemented_files: List[str],
    touched_families: List[str]
) -> Dict:
    """
    Verify if GREEN phase is allowed for current slice implementation.
    Blocks GREEN phase if only mock implementation exists for stateful families.
    """
    issues = []
    block_green = False

    # For stateful families, require real implementation
    stateful_families = ["stateful_side_effect", "core_entry"]
    has_stateful_family = any(fam in touched_families for fam in stateful_families)

    mock_only_files = []
    real_impl_files = []

    for file_path in implemented_files:
        full_path = Path(worktree_path) / file_path
        if not full_path.exists():
            continue

        check = check_mock_only_implementation(str(full_path))

        if check.get("mock_only"):
            mock_only_files.append(check)
        else:
            real_impl_files.append(check)

    # Check for stateful family mock-only
    if has_stateful_family:
        if len(mock_only_files) > 0 and len(real_impl_files) == 0:
            block_green = True
            issues.append({
                "code": "mock_only_implementation_not_allowed",
                "message": "Stateful family requires real DB implementation. TODO comments and placeholder returns are not allowed in GREEN phase.",
                "files": [f["file"] for f in mock_only_files]
            })

        # Check if DB operation evidence exists
        has_db_evidence = False
        for impl_check in real_impl_files:
            if len(impl_check.get("db_operations", [])) > 0:
                has_db_evidence = True
                break

        if not has_db_evidence and len(real_impl_files) > 0:
            # Files exist but no DB operations found
            issues.append({
                "code": "db_operation_required",
                "message": "stateful_side_effect family requires real DB operations (mapper.insert/update/delete). Mock DAOs not allowed.",
                "files": [f["file"] for f in real_impl_files]
            })
            # This is a warning, not a block
    else:
        # Non-stateful families
        if len(mock_only_files) > 0:
            issues.append({
                "code": "todo_placeholder_found",
                "message": "Implementation contains TODO comments or placeholders. These should be replaced with real implementation.",
                "files": [f["file"] for f in mock_only_files]
            })

    return {
        "can_proceed": not block_green,
        "block_green": block_green,
        "stateful_family_detected": has_stateful_family,
        "mock_only_files": len(mock_only_files),
        "real_impl_files": len(real_impl_files),
        "issues": issues,
        "mock_only_details": mock_only_files
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: verify_green_phase.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  check <file_path> - Check single file for mock-only patterns", file=sys.stderr)
        print("  verify <worktree> <implemented_files_json> <touched_families_json> - Verify GREEN phase for slice", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "check":
        if len(sys.argv) < 3:
            print("Usage: verify_green_phase.py check <file_path>", file=sys.stderr)
            sys.exit(1)

        file_path = sys.argv[2]
        result = check_mock_only_implementation(file_path)
        print(json.dumps(result, indent=2))

        if result.get("mock_only"):
            sys.exit(1)

    elif command == "verify":
        if len(sys.argv) < 5:
            print("Usage: verify_green_phase.py verify <worktree> <implemented_files_json> <touched_families_json>", file=sys.stderr)
            sys.exit(1)

        worktree = sys.argv[2]
        impl_files_json = sys.argv[3]
        families_json = sys.argv[4]

        implemented_files = json.loads(Path(impl_files_json).read_text(encoding='utf-8'))
        touched_families = json.loads(Path(families_json).read_text(encoding='utf-8'))

        result = verify_green_phase_allowed(worktree, implemented_files, touched_families)
        print(json.dumps(result, indent=2))

        if not result.get("can_proceed"):
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
