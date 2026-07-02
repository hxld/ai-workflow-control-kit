#!/usr/bin/env python3
"""
Horizontal Slice Pre-Authorization (Experiment 3 from NEXT_EXPERIMENT_PLAN.md).

Verifies slice plan touches minimum 3 categories (Backend + Database + at least one of Frontend/Deploy/Test)
BEFORE implementation starts.

This prevents the anti-pattern where slices only touch Backend helpers
without covering the full business flow.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Optional


# File classification rules
CATEGORY_RULES = {
    'Backend': [
        'Service.java', 'ServiceImpl.java',
        'Facade.java', 'FacadeImpl.java',
        'Processor.java', 'Handler.java',
        'Manager.java', 'Helper.java',
        '/src/main/java/',
        'example-core/', 'example-api/',
    ],
    'Database': [
        'Mapper.java', 'Mapper.xml',
        'Dao.java', 'DaoImpl.java',
        'Entity.java', 'Model.java',
        '.sql',
        'INSERT', 'UPDATE', 'DELETE', 'SELECT',
        '/provider/', '/dao/', '/mapper/',
        '/entity/', '/model/',
    ],
    'Frontend': [
        '.jsp', '.js', '.ftl', '.htm', '.html',
        '.vue', '.jsx', '.tsx',
        '/pages/', '/static/', '/webapp/',
        '/resources/', '/web/',
        '/templates/',
    ],
    'Deploy': [
        'Controller.java', 'Rest.java',
        '/web/', '/rest/',
        '@RequestMapping', '@GetMapping', '@PostMapping',
        '@PutMapping', '@DeleteMapping',
        'application.properties',
        'application.yml',
        '.xml',
    ],
    'Test': [
        'Test.java', 'Test.',
        'Spec.java', 'It.java',
        '/src/test/',
    ],
}

# Required minimum categories
MIN_CATEGORIES = 3
REQUIRED_CATEGORIES = ['Backend', 'Database']  # Must always have these


def categorize_file(file_path: str) -> Set[str]:
    """
    Categorize a single file by its path.

    A file can belong to multiple categories (e.g., Controller.java is both Backend and Deploy).
    Returns set of matching categories.
    """
    categories = set()

    for category, patterns in CATEGORY_RULES.items():
        for pattern in patterns:
            if pattern in file_path:
                categories.add(category)
                break

    return categories


def categorize_files(file_list: List[str]) -> Dict[str, Set[str]]:
    """
    Categorize multiple files and return category-to-files mapping.

    Returns: {
        'Backend': set of files,
        'Database': set of files,
        ...
    }
    """
    category_files = {cat: set() for cat in CATEGORY_RULES.keys()}

    for file_path in file_list:
        file_categories = categorize_file(file_path)
        for cat in file_categories:
            category_files[cat].add(file_path)

    return category_files


def horizontal_slice_pre_authorization(
    slice_plan: Dict,
    min_categories: int = MIN_CATEGORIES,
    required_categories: List[str] = REQUIRED_CATEGORIES
) -> Dict:
    """
    Verifies slice plan touches minimum required categories BEFORE implementation starts.

    Args:
        slice_plan: Dict containing planned_files list
        min_categories: Minimum number of categories required (default: 3)
        required_categories: List of category names that must all be present

    Returns:
        Dict with authorization result
    """
    if not isinstance(slice_plan, dict):
        return {
            'authorized': False,
            'reason': 'invalid_slice_plan_type',
            'message': 'Slice plan must be a dictionary'
        }

    planned_files = slice_plan.get('planned_files', [])
    if isinstance(planned_files, dict):
        # Handle case where planned_files is {file: change_description}
        planned_files = list(planned_files.keys())

    if not planned_files:
        return {
            'authorized': False,
            'reason': 'no_planned_files',
            'message': 'Slice plan has no planned_files'
        }

    # Categorize all planned files
    category_files = categorize_files(planned_files)
    touched_categories = {cat for cat, files in category_files.items() if files}

    # Check required categories
    missing_required = [cat for cat in required_categories if cat not in touched_categories]

    # Check minimum count
    touched_count = len(touched_categories)
    meets_minimum = touched_count >= min_categories

    # Check all required present
    has_required = len(missing_required) == 0

    is_authorized = meets_minimum and has_required

    # Build result
    result = {
        'authorized': is_authorized,
        'touched_categories': sorted(touched_categories),
        'touched_count': touched_count,
        'required_categories': required_categories,
        'missing_required_categories': missing_required,
        'min_categories': min_categories,
        'category_files': {cat: sorted(list(files)) for cat, files in category_files.items() if files},
        'total_files': len(planned_files)
    }

    if is_authorized:
        result['message'] = (
            f"Horizontal slice pre-authorized: {touched_count}/{min_categories} categories, "
            f"all required present: {sorted(required_categories)}"
        )
        result['reason'] = 'horizontal_slice_authorized'
    else:
        failures = []
        if not meets_minimum:
            failures.append(f"only {touched_count}/{min_categories} categories touched")
        if not has_required:
            failures.append(f"missing required categories: {missing_required}")

        result['message'] = (
            f"Horizontal slice NOT authorized: {', '.join(failures)}. "
            f"Add files to missing categories before slice authorization. "
            f"Required: Backend + Database + at least one of Frontend/Deploy/Test."
        )
        result['reason'] = 'horizontal_slice_minimum_not_met'

    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: authorize_horizontal_slice.py --slice_plan PLAN.json [--min_categories N] [--required CAT1,CAT2,...]", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print('  authorize_horizontal_slice.py --slice_plan plan.json --min_categories 3 --required "Backend,Database"', file=sys.stderr)
        sys.exit(1)

    slice_plan_path = None
    min_categories = MIN_CATEGORIES
    required_categories = REQUIRED_CATEGORIES.copy()

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

    # Authorize
    result = horizontal_slice_pre_authorization(slice_plan, min_categories, required_categories)

    # Output result
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with appropriate code
    sys.exit(0 if result['authorized'] else 1)


if __name__ == '__main__':
    main()
