#!/usr/bin/env python3
"""
Test Charter Validation (Experiment 2 from NEXT_EXPERIMENT_PLAN.md).

Validates test file contains behavioral assertion patterns BEFORE slice execution.
This prevents the anti-pattern of using fail() placeholders instead of real assertions.

Required patterns: assertThat(), assertEquals(), verify()
Forbidden pattern: fail("due to not implemented")

Tests must fail with BUSINESS ASSERTION in RED phase, not fail() placeholder.
"""

import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple


# Required behavioral assertion patterns
REQUIRED_PATTERNS = [
    r'assertThat\s*\(',
    r'assertEquals\s*\(',
    r'verify\s*\(',
    r'assertTrue\s*\(',
    r'assertFalse\s*\(',
    r'assertNull\s*\(',
    r'assertNotNull\s*\(',
    r'\.is[A-Z]\w*\(',  # AssertJ/AssertJ-style: isEqualTo(), isNotNull()
    r'sameElementAs\s*\(',  # AssertJ
]

# Forbidden anti-patterns
FORBIDDEN_PATTERNS = [
    (r'fail\s*\(\s*["\'].*due to.*not implemented', 'fail_with_todo_message'),
    (r'fail\s*\(\s*["\'].*TODO', 'fail_with_todo'),
    (r'fail\s*\(\s*["\'].*placeholder', 'fail_with_placeholder'),
    (r'fail\s*\(\s*["\'].*占位', 'fail_with_placeholder_chinese'),
]


def analyze_test_file(test_file_path: str) -> Dict:
    """
    Analyze test file for assertion patterns.

    Returns dict with:
        - exists: bool (file exists)
        - required_patterns_found: list of str (patterns found)
        - required_patterns_missing: list of str (patterns not found)
        - forbidden_patterns_found: list of dict (pattern, match, line)
        - has_behavioral_assertions: bool
        - has_forbidden: bool
        - assertion_count: int
    """
    test_path = Path(test_file_path)

    if not test_path.exists():
        return {
            'exists': False,
            'file_path': str(test_file_path),
            'reason': 'test_file_not_found'
        }

    content = test_path.read_text(encoding='utf-8-sig', errors='ignore')

    # Check for required patterns
    found_patterns = []
    found_pattern_details = []

    for i, pattern in enumerate(REQUIRED_PATTERNS):
        matches = list(re.finditer(pattern, content))
        if matches:
            pattern_name = pattern.replace(r'\s*\(', '').replace(r'\(', '').strip()
            found_patterns.append(pattern_name)
            for match in matches:
                line_start = content.rfind('\n', 0, match.start()) + 1
                line_end = content.find('\n', match.start())
                line_num = content[:match.start()].count('\n') + 1
                line_text = content[line_start:line_end].strip()
                found_pattern_details.append({
                    'pattern': pattern_name,
                    'line': line_num,
                    'text': line_text[:100]  # Truncate long lines
                })

    # Check for forbidden patterns
    forbidden_found = []

    for pattern, pattern_name in FORBIDDEN_PATTERNS:
        matches = list(re.finditer(pattern, content, re.IGNORECASE))
        for match in matches:
            line_start = content.rfind('\n', 0, match.start()) + 1
            line_end = content.find('\n', match.start())
            line_num = content[:match.start()].count('\n') + 1
            line_text = content[line_start:line_end].strip()
            forbidden_found.append({
                'pattern_type': pattern_name,
                'line': line_num,
                'text': line_text
            })

    missing_patterns = [
        p.replace(r'\s*\(', '').replace(r'\(', '').strip()
        for p in REQUIRED_PATTERNS
        if not re.search(p, content)
    ]

    # Check if any behavioral assertions exist
    has_behavioral = len(found_patterns) > 0
    has_forbidden = len(forbidden_found) > 0

    return {
        'exists': True,
        'file_path': str(test_file_path),
        'required_patterns_found': found_patterns,
        'required_patterns_missing': missing_patterns[:5],  # Limit to first 5
        'forbidden_patterns_found': forbidden_found,
        'has_behavioral_assertions': has_behavioral,
        'has_forbidden_patterns': has_forbidden,
        'assertion_count': len(found_pattern_details),
        'total_test_methods': len(re.findall(r'@Test', content)),
        'reason': 'test_charter_valid' if (has_behavioral and not has_forbidden) else 'test_charter_invalid'
    }


def validate_test_charter(test_file_path: str) -> Dict:
    """
    Validate test file meets charter requirements.

    A valid test charter:
    1. Contains at least one behavioral assertion pattern
    2. Does NOT contain forbidden fail() anti-patterns

    Returns validation result with status: PASS/FAIL and details.
    """
    analysis = analyze_test_file(test_file_path)

    if not analysis.get('exists'):
        return {
            'valid': False,
            'status': 'FAIL',
            'reason': analysis.get('reason', 'unknown'),
            'message': f"Test file not found: {test_file_path}",
            'analysis': analysis
        }

    issues = []

    # Check 1: Has behavioral assertions
    if not analysis.get('has_behavioral_assertions'):
        issues.append({
            'code': 'no_behavioral_assertions',
            'message': 'Test missing required behavioral assertion patterns',
            'missing_patterns': analysis.get('required_patterns_missing', [])[:3]
        })

    # Check 2: No forbidden patterns
    if analysis.get('has_forbidden_patterns'):
        issues.append({
            'code': 'forbidden_fail_pattern',
            'message': 'Test uses forbidden fail() anti-pattern instead of behavioral assertions',
            'forbidden_examples': analysis.get('forbidden_patterns_found', [])[:3]
        })

    # Check 3: Has test methods
    if analysis.get('total_test_methods', 0) == 0:
        issues.append({
            'code': 'no_test_methods',
            'message': 'No @Test methods found in file'
        })

    is_valid = len(issues) == 0

    return {
        'valid': is_valid,
        'status': 'PASS' if is_valid else 'FAIL',
        'reason': analysis.get('reason'),
        'message': (
            'Test charter validated - contains behavioral assertions without forbidden patterns'
            if is_valid else
            f'Test charter validation failed: {issues[0]["message"]}'
        ),
        'issues': issues,
        'analysis': analysis
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: validate_test_charter.py --test_file TEST_FILE.java [--mode validate|analyze]", file=sys.stderr)
        print("\nExamples:", file=sys.stderr)
        print('  validate_test_charter.py --test_file MyTest.java --mode validate', file=sys.stderr)
        print('  validate_test_charter.py --test_file MyTest.java --mode analyze', file=sys.stderr)
        sys.exit(1)

    test_file = None
    mode = 'validate'

    # Parse arguments
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]

        if arg == '--test_file' and i + 1 < len(sys.argv):
            test_file = sys.argv[i + 1]
            i += 2

        elif arg == '--mode' and i + 1 < len(sys.argv):
            mode = sys.argv[i + 1]
            i += 2

        else:
            i += 1

    if not test_file:
        print("Error: --test_file is required", file=sys.stderr)
        sys.exit(1)

    # Execute based on mode
    if mode == 'analyze':
        result = analyze_test_file(test_file)
    else:
        result = validate_test_charter(test_file)

    # Output JSON result
    import json
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with appropriate code
    if result.get('valid', True):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
