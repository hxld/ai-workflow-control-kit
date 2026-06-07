#!/usr/bin/env python3
"""
Coverage Penalty Calculator (Experiment 2 from NEXT_EXPERIMENT_PLAN.md).

Calculates implementation credit penalty based on TODO placeholders and
empty methods. Applies penalty to coverage delta.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


# Patterns that indicate placeholder/incomplete code
TODO_PATTERNS = [
    r"TODO",
    r"FIXME",
    r"XXX",
    r"NotImplementedError",
    r"throw new UnsupportedOperationException",
    r"raise NotImplementedError"
]

# Patterns for empty/placeholder methods
PLACEHOLDER_METHOD_PATTERNS = [
    r"public\s+\w+\s+\w+\([^)]*\)\s*\{\s*(return\s+(true|false|null);?)?\s*\}",
    r"public\s+\w+\s+\w+\([^)]*\)\s*\{\s*throw\s+new\s+(UnsupportedOperationException|NotImplementedError)",
    r"def\s+\w+\([^)]*\):\s*(pass|raise\s+NotImplementedError|return\s+(True|False|None))"
]


def should_exclude_file(file_path: str) -> bool:
    """Check if file should be excluded from scanning."""
    exclude_patterns = [
        r"/test/",
        r"Test\.java$",
        r"Spec\.java$",
        r"It\.java$",
        r"/\.tmp/",
        r"/\.git/",
        r"/target/",
        r"/build/"
    ]
    for pattern in exclude_patterns:
        if re.search(pattern, file_path, re.IGNORECASE):
            return True
    return False


def scan_file_for_todos(file_path: str) -> int:
    """Scan a single file for TODO patterns and return count."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except:
        return 0

    todo_count = 0
    for pattern in TODO_PATTERNS:
        matches = re.findall(pattern, content, re.IGNORECASE)
        todo_count += len(matches)

    return todo_count


def scan_file_for_placeholder_methods(file_path: str) -> int:
    """Scan a single file for placeholder (empty/body-only) methods."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except:
        return 0

    placeholder_count = 0
    for pattern in PLACEHOLDER_METHOD_PATTERNS:
        matches = re.findall(pattern, content, re.MULTILINE | re.DOTALL)
        placeholder_count += len(matches)

    return placeholder_count


def calculate_penalty(
    worktree_path: str,
    changed_files: List[str] = None
) -> Dict:
    """
    Calculate coverage penalty based on TODOs and placeholder methods.

    Args:
        worktree_path: Path to worktree directory
        changed_files: List of files to check (if None, scans all production files)

    Returns:
        Dict with penalty calculation results
    """
    worktree = Path(worktree_path)
    production_files = []

    if changed_files:
        production_files = [worktree / f for f in changed_files if (worktree / f).exists()]
    else:
        # Auto-discover production files
        for pattern in ["**/*.java", "**/*.py"]:
            production_files.extend(worktree.glob(pattern))

    # Filter out test files
    production_files = [f for f in production_files if not should_exclude_file(str(f))]

    todo_count = 0
    placeholder_count = 0

    for file_path in production_files:
        file_str = str(file_path)
        if should_exclude_file(file_str):
            continue

        todo_count += scan_file_for_todos(file_str)
        placeholder_count += scan_file_for_placeholder_methods(file_str)

    # Calculate penalty
    # TODO: 10% penalty per TODO
    # Placeholder method: 20% penalty per method
    todo_penalty = min(todo_count * 10, 50)  # Cap at 50%
    placeholder_penalty = min(placeholder_count * 20, 50)  # Cap at 50%
    total_penalty = min(todo_penalty + placeholder_penalty, 100)

    implementation_credit = max(0, 100 - total_penalty)

    return {
        "status": "PASS" if total_penalty <= 50 else "FAIL",
        "todo_count": todo_count,
        "placeholder_method_count": placeholder_count,
        "todo_penalty_percent": todo_penalty,
        "placeholder_penalty_percent": placeholder_penalty,
        "total_penalty_percent": total_penalty,
        "implementation_credit_percent": implementation_credit,
        "files_scanned": len(production_files),
        "penalty_applied": total_penalty > 0
    }


def apply_penalty_to_coverage(slice_result_path: str, penalty_result: Dict) -> Dict:
    """
    Apply penalty calculation to slice result coverage delta.

    Args:
        slice_result_path: Path to SLICE_RESULT_XX.json
        penalty_result: Result from calculate_penalty()

    Returns:
        Updated slice result with adjusted coverage
    """
    slice_path = Path(slice_result_path)
    if not slice_path.exists():
        return {"error": "slice_result_not_found", "path": str(slice_path)}

    try:
        with open(slice_path, 'r', encoding='utf-8') as f:
            slice_result = json.load(f)
    except:
        return {"error": "invalid_slice_result_json", "path": str(slice_path)}

    original_delta = slice_result.get("coverage_delta", 0)
    credit = penalty_result.get("implementation_credit_percent", 100)

    # Apply penalty to coverage delta
    adjusted_delta = int(original_delta * credit / 100)

    # Update slice result
    slice_result["coverage_delta"] = adjusted_delta
    slice_result["original_coverage_delta"] = original_delta
    slice_result["implementation_credit_percent"] = credit
    slice_result["coverage_penalty_applied"] = penalty_result.get("total_penalty_percent", 0)

    # Write back
    with open(slice_path, 'w', encoding='utf-8') as f:
        json.dump(slice_result, f, indent=2, ensure_ascii=False)

    return {
        "status": "SUCCESS",
        "original_coverage_delta": original_delta,
        "adjusted_coverage_delta": adjusted_delta,
        "credit_percent": credit,
        "penalty_percent": penalty_result.get("total_penalty_percent", 0)
    }


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python calculate-coverage-penalty.py --worktree <path> [--slice-result <path>]")
        print("  python calculate-coverage-penalty.py --input <input.json>")
        print("\nInput JSON keys: worktree_path, changed_files (optional list), slice_result_path (optional)")
        sys.exit(0)

    if len(sys.argv) > 2 and sys.argv[1] == "--worktree":
        worktree = sys.argv[2]
        slice_result = None
        changed_files = None

        # Parse optional arguments
        i = 3
        while i < len(sys.argv):
            if sys.argv[i] == "--slice-result" and i + 1 < len(sys.argv):
                slice_result = sys.argv[i + 1]
                i += 2
            elif sys.argv[i] == "--changed-files" and i + 1 < len(sys.argv):
                changed_files = sys.argv[i + 1].split(',')
                i += 2
            else:
                i += 1

        input_data = {"worktree_path": worktree, "changed_files": changed_files, "slice_result_path": slice_result}
    elif len(sys.argv) > 2 and sys.argv[1] == "--input":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            input_data = json.load(f)
    else:
        input_data = json.loads(sys.stdin.read())

    worktree_path = input_data.get("worktree_path", "")
    changed_files = input_data.get("changed_files")
    slice_result_path = input_data.get("slice_result_path")

    # Calculate penalty
    penalty_result = calculate_penalty(worktree_path, changed_files)

    # Apply to slice result if provided
    if slice_result_path:
        apply_result = apply_penalty_to_coverage(slice_result_path, penalty_result)
        if "error" in apply_result:
            penalty_result["apply_error"] = apply_result["error"]
        else:
            penalty_result["coverage_adjustment"] = apply_result

    print(json.dumps(penalty_result, indent=2, ensure_ascii=False))

    # Exit with error if penalty > 50%
    if penalty_result["total_penalty_percent"] > 50:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
