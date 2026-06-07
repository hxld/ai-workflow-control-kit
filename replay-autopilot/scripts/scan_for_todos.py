#!/usr/bin/env python3
"""
TODO Blocker Gate (Experiment 2 from NEXT_EXPERIMENT_PLAN.md).

Scan production files for TODO/FIXME/XXX placeholders.
Block execution if found to prevent placeholder code from reaching production.
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
    r"raise NotImplementedError",
    r"#\s*NOT\s+IMPLEMENTED",
    r"//\s*NOT\s+IMPLEMENTED",
    r"/\*\s*NOT\s+IMPLEMENTED"
]

# File patterns to exclude (test files, comments, documentation)
EXCLUDE_PATTERNS = [
    r"/test/",
    r"Test\.java$",
    r"Spec\.java$",
    r"It\.java$",
    r"/\.tmp/",
    r"/\.git/",
    r"/target/",
    r"/build/"
]


def should_exclude_file(file_path: str) -> bool:
    """Check if file should be excluded from TODO scanning."""
    for pattern in EXCLUDE_PATTERNS:
        if re.search(pattern, file_path, re.IGNORECASE):
            return True
    return False


def get_line_context(content: str, line_num: int, context_lines: int = 1) -> str:
    """Get context around a specific line."""
    lines = content.split("\n")
    start = max(0, line_num - context_lines - 1)
    end = min(len(lines), line_num + context_lines)
    return "\n".join(lines[start:end])


def scan_file_for_todos(file_path: str) -> List[Dict]:
    """
    Scan a single file for TODO patterns.

    Returns list of found TODOs with line number and context.
    """
    todos_found = []

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except:
        return todos_found

    for pattern in TODO_PATTERNS:
        matches = re.finditer(pattern, content, re.IGNORECASE)
        for match in matches:
            # Calculate line number
            before = content[:match.start()]
            line_num = before.count('\n') + 1

            # Get context
            context = get_line_context(content, line_num)

            todos_found.append({
                'file': file_path,
                'line': line_num,
                'pattern': match.group(),
                'context': context
            })

    return todos_found


def scan_for_todos(
    worktree_path: str,
    production_files: List[str] = None,
    include_tests: bool = False
) -> Dict:
    """
    Scan production files for TODO/FIXME/XXX placeholders.
    Block execution if found.

    Args:
        worktree_path: Path to worktree directory
        production_files: List of files to scan (if None, scans all non-test files)
        include_tests: Whether to also scan test files

    Returns:
        Dict with scan results
    """
    if not production_files:
        # Auto-discover production files if not provided
        production_files = []
        worktree = Path(worktree_path)

        # Common production file patterns
        production_patterns = [
            "**/*.java",
            "**/*.py",
            "**/*.js",
            "**/*.ts",
            "**/*.sql",
            "**/*.xml",
            "**/*.jsp",
            "**/*.ftl"
        ]

        for pattern in production_patterns:
            for file_path in worktree.glob(pattern):
                file_str = str(file_path)
                if should_exclude_file(file_str) and not include_tests:
                    continue
                production_files.append(file_str)

    todos_found = []

    for file_path in production_files:
        if should_exclude_file(file_path) and not include_tests:
            continue

        file_todos = scan_file_for_todos(file_path)
        todos_found.extend(file_todos)

    if todos_found:
        # Group by file for cleaner output
        by_file = {}
        for todo in todos_found:
            file = todo['file']
            if file not in by_file:
                by_file[file] = []
            by_file[file].append(todo)

        # Build summary
        file_summaries = []
        for file, items in by_file.items():
            file_summaries.append({
                'file': file,
                'count': len(items),
                'locations': [{'line': t['line'], 'pattern': t['pattern']} for t in items[:5]]
            })

        return {
            'status': 'FAIL',
            'error': 'todos_found_in_production',
            'total_todos': len(todos_found),
            'affected_files': len(by_file),
            'message': (
                f"Found {len(todos_found)} TODO/FIXME placeholders in {len(by_file)} production files.\n"
                f"Tests cannot execute until all TODOs are replaced with real implementation."
            ),
            'file_summaries': file_summaries[:10],  # Limit to 10 files
            'all_todos': todos_found[:50]  # Limit to 50 items
        }

    return {
        'status': 'PASS',
        'message': 'No TODO/FIXME placeholders found in production code',
        'files_scanned': len(production_files)
    }


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python scan_for_todos.py --worktree <path>")
        print("  python scan_for_todos.py --input <input.json>")
        print("  echo '{...}' | python scan_for_todos.py")
        print("\nInput JSON keys: worktree_path, production_files (optional list), include_tests (optional bool)")
        sys.exit(0)

    if len(sys.argv) > 2 and sys.argv[1] == "--worktree":
        worktree = sys.argv[2]
        input_data = {"worktree_path": worktree}
    elif len(sys.argv) > 2 and sys.argv[1] == "--input":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            input_data = json.load(f)
    else:
        # Read from stdin
        input_data = json.loads(sys.stdin.read())

    result = scan_for_todos(
        worktree_path=input_data.get("worktree_path", ""),
        production_files=input_data.get("production_files"),
        include_tests=input_data.get("include_tests", False)
    )

    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(1 if result["status"] == "FAIL" else 0)


if __name__ == "__main__":
    main()
