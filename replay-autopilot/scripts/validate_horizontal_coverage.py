#!/usr/bin/env python3
"""
Horizontal Slice Coverage Validation (v418 + v419 integration).

v418: Validates that a slice plan touches minimum required categories horizontally.
v419: Calls authorize_horizontal_slice.py for stricter pre-authorization.

This prevents the anti-pattern where slices only touch Backend helpers
without covering the full business flow through UI/API/DB layers.
"""

import json
import re
import sys
import subprocess
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional


# File extension and path patterns for category classification
CATEGORY_RULES = {
    'Frontend': [
        '.jsp', '.js', '.ftl', '.htm', '.html',
        '/pages/', '/static/', '/webapp/', '/resources/',
        'Controller.java', '/controllers/', '/web/'
    ],
    'Backend': [
        'Service.java', 'ServiceImpl.java',
        'Facade.java', 'FacadeImpl.java',
        'Processor.java', 'Handler.java',
        '/src/main/java/', 'claim-core/', 'claim-api/'
    ],
    'Database': [
        'Mapper.java', 'Mapper.xml', 'Dao.java', 'DaoImpl.java',
        '.sql', 'INSERT', 'UPDATE', 'DELETE', 'SELECT',
        '/provider/', '/dao/', '/mapper/'
    ],
    'Test': [
        'Test.java', 'Test.', '/src/test/',
        'Spec.java', 'It.java'
    ],
    'Deploy': [
        'Controller.java', '/web/', '/rest/',
        '@RequestMapping', '@GetMapping', '@PostMapping'
    ]
}

# Required minimum categories for a valid horizontal slice
REQUIRED_CATEGORIES = ['Frontend', 'Backend', 'Database']
MIN_CATEGORIES = 3


def categorize_file(file_path: str) -> Set[str]:
    """
    Categorize a single file by its path.

    A file can belong to multiple categories (e.g., Controller.java is both Frontend and Deploy).
    Returns set of matching categories.
    """
    categories = set()

    for category, patterns in CATEGORY_RULES.items():
        for pattern in patterns:
            if pattern in file_path:
                categories.add(category)
                break

    return categories


def categorize_files(file_list: List[str]) -> Set[str]:
    """
    Categorize multiple files and return all touched categories.

    Returns set of unique categories touched by at least one file.
    """
    categories = set()

    for file_path in file_list:
        file_categories = categorize_file(file_path)
        categories.update(file_categories)

    return categories


def invoke_v419_horizontal_authorization(slice_plan: Dict, min_categories: int = 3, required_categories: List[str] = None) -> Optional[Dict]:
    """
    Invoke v419 authorize_horizontal_slice.py if available.

    v419 has stricter requirements: Database is MANDATORY.

    Returns None if script not found, otherwise returns script result.
    """
    if required_categories is None:
        required_categories = ['Backend', 'Database']

    script_dir = Path(__file__).parent
    v419_script = script_dir / 'authorize_horizontal_slice.py'

    if not v419_script.exists():
        return None

    try:
        # Create a temporary file for the slice plan
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(slice_plan, f)
            temp_file = f.name

        try:
            result = subprocess.run(
                [
                    sys.executable,
                    str(v419_script),
                    '--slice_plan', temp_file,
                    '--min_categories', str(min_categories),
                    '--required', ','.join(required_categories)
                ],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                return json.loads(result.stdout)
            else:
                return {'authorized': False, 'error': result.stderr}
        finally:
            Path(temp_file).unlink(missing_ok=True)
    except Exception as e:
        return {'authorized': False, 'error': str(e)}


def validate_horizontal_coverage(
    slice_plan: Dict,
    min_categories: int = MIN_CATEGORIES,
    required_categories: List[str] = REQUIRED_CATEGORIES
) -> Dict:
    """
    Validate slice plan touches minimum required categories.

    Args:
        slice_plan: Dict containing planned_files list
        min_categories: Minimum number of categories required (default: 3)
        required_categories: List of category names that must all be present (default: Frontend+Backend+Database)

    Returns:
        Dict with validation result: {
            'valid': bool,
            'touched_categories': list of str,
            'missing_categories': list of str,
            'touched_count': int,
            'required_count': int,
            'message': str
        }
    """
    if not isinstance(slice_plan, dict):
        return {
            'valid': False,
            'reason': 'invalid_slice_plan_type',
            'message': 'Slice plan must be a dictionary'
        }

    planned_files = slice_plan.get('planned_files', [])

    if not planned_files:
        return {
            'valid': False,
            'reason': 'no_planned_files',
            'message': 'Slice plan has no planned_files'
        }

    # Categorize all planned files
    touched = categorize_files(planned_files)
    touched_list = sorted(touched)

    # Check required categories
    missing = [cat for cat in required_categories if cat not in touched]

    # Check minimum count
    is_valid = len(touched) >= min_categories and len(missing) == 0

    # v419: Invoke stricter horizontal authorization experiment
    v419_horizontal = invoke_v419_horizontal_authorization(slice_plan, min_categories, ['Backend', 'Database'])
    if v419_horizontal is not None:
        # v419 has stricter requirements: use its result
        is_valid = v419_horizontal.get('authorized', is_valid)

    return {
        'valid': is_valid,
        'touched_categories': touched_list,
        'missing_categories': missing,
        'touched_count': len(touched),
        'required_count': min_categories,
        'reason': 'horizontal_coverage_valid' if is_valid else 'horizontal_slice_minimum_not_met',
        'message': (
            f"Horizontal slice coverage validated ({len(touched)}/{min_categories} categories)"
            if is_valid else
            f"Horizontal slice minimum not met: {len(touched)}/{min_categories} categories, missing: {missing}"
        ),
        'v419_horizontal': v419_horizontal
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: validate_horizontal_coverage.py --slice_plan SLICE_PLAN.json [--min_categories N] [--required CAT1,CAT2,CAT3]", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print('  validate_horizontal_coverage.py --slice_plan plan.json --min_categories 3 --required "Frontend,Backend,Database"', file=sys.stderr)
        sys.exit(1)

    slice_plan_path = None
    min_categories = MIN_CATEGORIES
    required_categories = REQUIRED_CATEGORIES.copy()

    # Parse arguments
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]

        if arg == '--slice_plan' and i + 1 < len(sys.argv):
            slice_plan_path = sys.argv[i + 1]
            i += 2

        elif arg == '--min_categories' and i + 1 < len(sys.argv):
            min_categories = int(sys.argv[i + 1])
            i += 2

        elif arg == '--required' and i + 1 < len(sys.argv):
            required_categories = sys.argv[i + 1].split(',')
            required_categories = [c.strip() for c in required_categories]
            i += 2

        else:
            i += 1

    if not slice_plan_path:
        print("Error: --slice_plan is required", file=sys.stderr)
        sys.exit(1)

    # Read slice plan
    slice_plan_path = Path(slice_plan_path)

    if not slice_plan_path.exists():
        print(f"Error: Slice plan file not found: {slice_plan_path}", file=sys.stderr)
        sys.exit(1)

    with open(slice_plan_path, 'r', encoding='utf-8-sig') as f:
        slice_plan = json.load(f)

    # Validate
    result = validate_horizontal_coverage(slice_plan, min_categories, required_categories)

    # Output result
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with appropriate code
    if result['valid']:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
