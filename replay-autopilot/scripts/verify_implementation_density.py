#!/usr/bin/env python3
"""
Implementation Density Gate (Experiment 2 from NEXT_EXPERIMENT_PLAN.md).

Calculates ratio of executable lines to total lines.
Rejects implementation with TODO/placeholder ratio > 0% or density < 70%.

This prevents the anti-pattern where TODO placeholders count as implementation.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


# Patterns that indicate placeholder/incomplete code (non-executable)
PLACEHOLDER_PATTERNS = [
    r'TODO',
    r'FIXME',
    r'XXX',
    r'NotImplementedError',
    r'UnsupportedOperationException',
    r'raise NotImplementedError',
    r'throw new UnsupportedOperationException',
    r'#\s*NOT\s+IMPLEMENTED',
    r'//\s*NOT\s+IMPLEMENTED',
    r'/\*\s*NOT\s+IMPLEMENTED',
    r'stem:[\s\S]*?end',
]

# Patterns that count as executable code
EXECUTABLE_PATTERNS = [
    r'if\s*\(',
    r'else\s*(?:if\s*\(|{)',
    r'for\s*\(',
    r'while\s*\(',
    r'switch\s*\(',
    r'case\s+',
    r'return\s+',
    r'throw\s+',
    r'\.\s*[a-zA-Z]+\s*\(',
    r'=\s*new\s+',
    r'INSERT\s+',
    r'UPDATE\s+',
    r'DELETE\s+',
    r'SELECT\s+',
    r'\.insert\(',
    r'\.update\(',
    r'\.delete\(',
    r'\.select\(',
    r'\.save\(',
    r'\.query\(',
    r'@Transactional',
    r'@Insert',
    r'@Update',
    r'@Delete',
    r'@Select',
]


def is_comment_or_whitespace(line: str) -> bool:
    """Check if line is a comment or whitespace."""
    stripped = line.strip()
    if not stripped:
        return True
    # Single-line comments
    if stripped.startswith('//') or stripped.startswith('#'):
        return True
    return False


def is_placeholder_line(line: str) -> bool:
    """Check if line contains placeholder pattern."""
    for pattern in PLACEHOLDER_PATTERNS:
        if re.search(pattern, line, re.IGNORECASE):
            return True
    return False


def has_executable_content(line: str) -> bool:
    """Check if line has executable content."""
    for pattern in EXECUTABLE_PATTERNS:
        if re.search(pattern, line):
            return True
    return False


def calculate_file_metrics(file_path: Path) -> Dict:
    """
    Calculate metrics for a single file.

    Returns: {
        'total_lines': int,
        'executable_lines': int,
        'todo_lines': int,
        'comment_lines': int,
        'empty_lines': int,
        'density': float,
        'todo_ratio': float
    }
    """
    if not file_path.exists():
        return {
            'total_lines': 0,
            'executable_lines': 0,
            'todo_lines': 0,
            'comment_lines': 0,
            'empty_lines': 0,
            'density': 0.0,
            'todo_ratio': 0.0
        }

    try:
        content = file_path.read_text(encoding='utf-8', errors='ignore')
    except:
        return {
            'total_lines': 0,
            'executable_lines': 0,
            'todo_lines': 0,
            'comment_lines': 0,
            'empty_lines': 0,
            'density': 0.0,
            'todo_ratio': 0.0
        }

    lines = content.split('\n')

    total_lines = len(lines)
    executable_lines = 0
    todo_lines = 0
    comment_lines = 0
    empty_lines = 0

    in_block_comment = False

    for line in lines:
        stripped = line.strip()

        # Track block comments
        if '/*' in stripped:
            in_block_comment = True
        if '*/' in stripped:
            in_block_comment = False
            comment_lines += 1
            continue

        # Empty lines
        if not stripped:
            empty_lines += 1
            continue

        # Comments
        if in_block_comment or stripped.startswith('//') or stripped.startswith('#') or stripped.startswith('*'):
            comment_lines += 1
            # Still check for TODO in comments
            if is_placeholder_line(stripped):
                todo_lines += 1
            continue

        # Check for placeholders
        if is_placeholder_line(stripped):
            todo_lines += 1
            continue

        # Check for executable content
        if has_executable_content(stripped):
            executable_lines += 1

    # Calculate ratios
    code_lines = total_lines - empty_lines - comment_lines
    density = executable_lines / code_lines if code_lines > 0 else 0.0
    todo_ratio = todo_lines / code_lines if code_lines > 0 else 0.0

    return {
        'total_lines': total_lines,
        'executable_lines': executable_lines,
        'todo_lines': todo_lines,
        'comment_lines': comment_lines,
        'empty_lines': empty_lines,
        'code_lines': code_lines,
        'density': density,
        'todo_ratio': todo_ratio
    }


def calculate_implementation_density(modified_files: List[str]) -> Dict:
    """
    Calculate aggregate implementation density across all modified files.

    Returns aggregated metrics and per-file breakdown.
    """
    if not modified_files:
        return {
            'status': 'FAIL',
            'error': 'no_files_provided',
            'message': 'No modified files provided'
        }

    total_lines = 0
    total_executable = 0
    total_todo = 0
    total_code = 0

    file_metrics = []

    for file_path_str in modified_files:
        file_path = Path(file_path_str)
        metrics = calculate_file_metrics(file_path)

        file_metrics.append({
            'file': file_path_str,
            **metrics
        })

        total_lines += metrics['total_lines']
        total_executable += metrics['executable_lines']
        total_todo += metrics['todo_lines']
        total_code += metrics['code_lines']

    # Calculate aggregate ratios
    overall_density = total_executable / total_code if total_code > 0 else 0.0
    overall_todo_ratio = total_todo / total_code if total_code > 0 else 0.0

    return {
        'total_files': len(modified_files),
        'total_lines': total_lines,
        'total_executable_lines': total_executable,
        'total_todo_lines': total_todo,
        'total_code_lines': total_code,
        'overall_density': overall_density,
        'overall_todo_ratio': overall_todo_ratio,
        'file_metrics': file_metrics
    }


def implementation_density_gate(
    modified_files: List[str],
    min_density: float = 0.7,
    max_todo_ratio: float = 0.0
) -> Dict:
    """
    Fails if implementation density < min_density or TODO ratio > max_todo_ratio.

    Args:
        modified_files: List of file paths to check
        min_density: Minimum density threshold (default 0.7 = 70%)
        max_todo_ratio: Maximum TODO ratio threshold (default 0.0 = 0%)

    Returns:
        Dict with validation result
    """
    metrics = calculate_implementation_density(modified_files)

    # Check thresholds
    todo_fail = metrics['overall_todo_ratio'] > max_todo_ratio
    density_fail = metrics['overall_density'] < min_density

    is_valid = not (todo_fail or density_fail)

    result = {
        'valid': is_valid,
        'metrics': metrics,
        'thresholds': {
            'min_density': min_density,
            'max_todo_ratio': max_todo_ratio
        },
        'failures': []
    }

    if todo_fail:
        result['failures'].append({
            'type': 'todo_ratio_exceeded',
            'message': f"TODO ratio {metrics['overall_todo_ratio']:.1%} exceeds maximum {max_todo_ratio:.1%}",
            'value': metrics['overall_todo_ratio'],
            'threshold': max_todo_ratio
        })

    if density_fail:
        result['failures'].append({
            'type': 'density_below_minimum',
            'message': f"Implementation density {metrics['overall_density']:.1%} below minimum {min_density:.1%}",
            'value': metrics['overall_density'],
            'threshold': min_density
        })

    if is_valid:
        result['message'] = (
            f"Implementation density valid: {metrics['overall_density']:.1%} executable, "
            f"{metrics['overall_todo_ratio']:.1%} TODOs across {metrics['total_files']} files"
        )
    else:
        failure_types = ', '.join([f['type'] for f in result['failures']])
        result['message'] = (
            f"Implementation quality gate failed: {failure_types}. "
            f"Remove all TODO placeholders and add executable behavior before slice completion."
        )

    return result


def main():
    if len(sys.argv) < 2 or '--help' in sys.argv:
        print("Usage: verify_implementation_density.py --files <file1,file2,...> [--min_density N] [--max_todo N]", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print('  verify_implementation_density.py --files "path/to/File1.java,path/to/File2.java" --min_density 0.7 --max_todo 0.0', file=sys.stderr)
        sys.exit(1 if '--help' in sys.argv else 1)

    files_list = None
    min_density = 0.7
    max_todo_ratio = 0.0

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]

        if arg == '--files' and i + 1 < len(sys.argv):
            files_list = sys.argv[i + 1].split(',')
            i += 2

        elif arg == '--min_density' and i + 1 < len(sys.argv):
            min_density = float(sys.argv[i + 1])
            i += 2

        elif arg == '--max_todo' and i + 1 < len(sys.argv):
            max_todo_ratio = float(sys.argv[i + 1])
            i += 2

        else:
            i += 1

    if not files_list:
        print("Error: --files is required", file=sys.stderr)
        sys.exit(1)

    result = implementation_density_gate(files_list, min_density, max_todo_ratio)

    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(0 if result['valid'] else 1)


if __name__ == '__main__':
    main()
