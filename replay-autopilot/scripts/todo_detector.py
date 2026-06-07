#!/usr/bin/env python3
"""
TODO Placeholder Detection and Ban (v418 + v419 integration).

v418: Explicitly bans TODO placeholders in implementation code.
v419: Calls verify_implementation_density.py for density threshold enforcement.

Forces either real implementation or honest BLOCKED declaration.
"""

import sys
import re
import subprocess
import json
from pathlib import Path
from typing import List, Tuple, Optional, Dict


# TODO patterns that indicate placeholders (not informative comments)
TODO_PATTERNS = [
    (r'TODO.*实现', 'Action TODO - needs implementation'),
    (r'TODO.*implement', 'Action TODO - needs implementation'),
    (r'TODO.*待实现', 'Action TODO - needs implementation'),
    (r'TODO.*待补充', 'Action TODO - needs completion'),
    (r'TODO.*需要', 'Action TODO - requires action'),
    (r'TODO.*need to', 'Action TODO - requires action'),
    (r'TODO.*should', 'Action TODO - should do something'),
    (r'//\s*TODO\s+[A-Z]', 'Capital TODO - action item'),
    (r'/\*\*.*TODO.*\*/', 'Javadoc TODO - action item'),
    (r'TODO.*write', 'Action TODO - needs writing'),
    (r'TODO.*add', 'Action TODO - needs adding'),
    (r'TODO.*complete', 'Action TODO - needs completion'),
]

# Informative TODOs that are allowed (documentation, future enhancements)
ALLOWED_TODO_CONTEXTS = [
    r'TODO.*优化',
    r'TODO.*optimize',
    r'TODO.*性能',
    r'TODO.*performance',
    r'TODO.*重构',
    r'TODO.*refactor',
    r'TODO.*deprecated',
    r'TODO.*移除',
    r'TODO.*remove',
    r'TODO.*future',
    r'TODO.*later',
]


def check_file_for_todos(java_file: Path) -> List[Tuple[int, str, str]]:
    """
    Returns list of TODO lines with context

    Each tuple: (line_number, line_content, pattern_description)
    """
    if not java_file.exists():
        return []

    content = java_file.read_text(encoding='utf-8')
    todos = []

    for line_num, line in enumerate(content.split('\n'), 1):
        stripped_line = line.strip()

        # Skip if it's an allowed context TODO
        is_allowed = False
        for allowed_pattern in ALLOWED_TODO_CONTEXTS:
            if re.search(allowed_pattern, stripped_line, re.IGNORECASE):
                is_allowed = True
                break

        if is_allowed:
            continue

        # Check for placeholder TODOs
        for pattern, description in TODO_PATTERNS:
            if re.search(pattern, stripped_line, re.IGNORECASE):
                todos.append((line_num, stripped_line[:80], description))
                break

    return todos


def check_java_files(file_paths: List[Path]) -> Tuple[List[Tuple[str, int, str, str]], int]:
    """
    Check multiple Java files for TODOs

    Returns: (list of todos, total_files_checked)
    Each todo: (file_path, line_num, line_content, description)
    """
    all_todos = []
    files_checked = 0

    for file_path in file_paths:
        if not file_path.exists():
            continue

        if not file_path.suffix == '.java':
            continue

        todos = check_file_for_todos(file_path)
        for line_num, line, description in todos:
            all_todos.append((str(file_path), line_num, line, description))

        files_checked += 1

    return all_todos, files_checked


def invoke_v419_implementation_density(file_paths: List[str], min_density: float = 0.7, max_todo_ratio: float = 0.0) -> Optional[Dict]:
    """
    Invoke v419 verify_implementation_density.py if available.

    v419 enforces 70% density threshold and 0% TODO ratio.

    Returns None if script not found, otherwise returns script result.
    """
    script_dir = Path(__file__).parent
    v419_script = script_dir / 'verify_implementation_density.py'

    if not v419_script.exists():
        return None

    try:
        files_arg = ','.join(file_paths)
        result = subprocess.run(
            [
                sys.executable,
                str(v419_script),
                '--files', files_arg,
                '--min_density', str(min_density),
                '--max_todo', str(max_todo_ratio)
            ],
            capture_output=True,
            text=True,
            timeout=60
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            return {'valid': False, 'error': result.stderr}
    except Exception as e:
        return {'valid': False, 'error': str(e)}


def find_java_files(directory: Path) -> List[Path]:
    """Find all Java files in directory recursively"""
    if not directory.exists():
        return []

    java_files = []
    for java_file in directory.rglob('*.java'):
        # Skip test files for now (focus on implementation)
        if 'test' in java_file.parts:
            continue
        java_files.append(java_file)

    return java_files


def main():
    if len(sys.argv) < 2:
        print("Usage: todo_detector.py [--v419_density] <file_or_directory...>")
        print("  Check specific files: todo_detector.py File1.java File2.java")
        print("  Check directory: todo_detector.py claim-core/src/main/java/...")
        print("  v419 density check: todo_detector.py --v419_density File1.java File2.java")
        sys.exit(1)

    # Check for v419 flag
    use_v419_density = '--v419_density' in sys.argv
    args = [arg for arg in sys.argv[1:] if arg != '--v419_density']

    all_todos = []
    files_checked = 0
    file_paths_for_v419 = []

    for arg in args:
        path = Path(arg)

        if path.is_file():
            todos = check_file_for_todos(path)
            for line_num, line, description in todos:
                all_todos.append((str(path), line_num, line, description))
            files_checked += 1
            file_paths_for_v419.append(str(path))

        elif path.is_dir():
            java_files = find_java_files(path)
            todos, count = check_java_files(java_files)
            all_todos.extend(todos)
            files_checked += count
            file_paths_for_v419.extend([str(f) for f in java_files])

        else:
            print(f"WARNING: Path not found: {arg}")

    if all_todos:
        print("TODO_PLACEHOLDERS_DETECTED")
        print("")
        print("Action Required:")
        print("  1. Replace TODO with real implementation, OR")
        print("  2. Declare BLOCKED and explain what's missing")
        print("")
        print("Detected TODOs:")
        for file_path, line_num, line, description in all_todos[:20]:  # First 20
            print(f"  {file_path}:{line_num}: [{description}]")
            print(f"    {line}")
            print("")

        if len(all_todos) > 20:
            print(f"  ... and {len(all_todos) - 20} more TODOs")

        sys.exit(1)

    print(f"NO_TODO_PLACEHOLDERS")
    print(f"Checked {files_checked} Java files")

    # v419: Run implementation density check if requested
    if use_v419_density and file_paths_for_v419:
        v419_result = invoke_v419_implementation_density(file_paths_for_v419)
        if v419_result is not None:
            print("v419_IMPLEMENTATION_DENSITY_CHECK")
            print(json.dumps(v419_result, indent=2, ensure_ascii=False))
            if not v419_result.get('valid', False):
                sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
