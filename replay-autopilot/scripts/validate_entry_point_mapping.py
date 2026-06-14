#!/usr/bin/env python3
"""
Entry Point Verification Gate (v418 + v419 integration).

v418: Validates that selected carrier maps to requirement workflow.
v419: Calls phase0_requirement_traceability_bind.py to create carrier bindings BEFORE planning.

Prevents the anti-pattern where agents target wrong processors
(e.g., ExampleCalculatorApiTaskProcessor instead of ExampleApplyClaimApiTaskProcessor).
"""

import json
import re
import sys
import subprocess
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional


# Common entry point patterns in Java projects
ENTRY_POINT_PATTERNS = [
    r'ApiTaskProcessor',
    r'TaskProcessor',
    r'Controller',
    r'Facade',
    r'Handler',
    r'Endpoint',
    r'RestController',
]

# Workflow keyword patterns from requirements
WORKFLOW_KEYWORD_PATTERNS = {
    '申请': ['Apply', 'Application', 'Submit', 'Create'],
    '核赔': ['Claim', 'Review', 'Calculate', 'Loss'],
    '理算': ['Calculate', 'Settlement', 'Loss', 'Adjust'],
    '报案': ['Report', 'Register', 'Case'],
    '审核': ['Review', 'Audit', 'Approve', 'Verify'],
    '支付': ['Payment', 'Pay', 'Transfer'],
    '通知': ['Notify', 'Notification', 'Callback'],
    '回调': ['Callback', 'Handle', 'Response'],
    '查询': ['Query', 'Search', 'Get', 'Find'],
    '取消': ['Cancel', 'Close', 'Terminate'],
}


def extract_workflow_keywords_from_requirement(requirement_text: str) -> Set[str]:
    """
    Extract workflow keywords from requirement snapshot text.

    Looks for patterns like:
    - "当...时，触发..."
    - "申请成功后"
    - "核赔结果回调"
    """
    keywords = set()

    # Find Chinese workflow keywords
    for chinese, english_list in WORKFLOW_KEYWORD_PATTERNS.items():
        if chinese in requirement_text:
            keywords.update(english_list)

    # Find direct English keywords in requirement
    for english_list in WORKFLOW_KEYWORD_PATTERNS.values():
        for keyword in english_list:
            # Look for the keyword in various forms
            patterns = [
                rf'\b{keyword}\b',
                rf'{keyword}[A-Z]',
                rf'{keyword}s?',  # plural
            ]
            for pattern in patterns:
                if re.search(pattern, requirement_text, re.IGNORECASE):
                    keywords.add(keyword)

    return keywords


def extract_processor_name(carrier_name: str) -> Optional[str]:
    """
    Extract the processor/class name from a carrier string.

    Handles formats like:
    - "ExampleApplyClaimApiTaskProcessor.handleTaskResponse"
    - "ExampleCalculatorApiTaskProcessor (verified in worktree)"
    - "SomeClass.methodName"
    """
    # Extract first part before parenthesis or dot
    match = re.match(r'([A-Za-z0-9_]+)', carrier_name.strip())
    if match:
        return match.group(1)

    # Try to extract from dotted notation
    parts = carrier_name.split('.')
    for part in parts:
        if any(pattern in part for pattern in ENTRY_POINT_PATTERNS):
            return part.split('(')[0].strip()

    return None


def invoke_v419_traceability_binding(worktree_path: str, requirement_path: str, output_path: str) -> Optional[Dict]:
    """
    Invoke v419 phase0_requirement_traceability_bind.py if available.

    This creates REQUIREMENT_CARRIER_BINDINGS.json BEFORE planning starts.

    Returns None if script not found, otherwise returns script result.
    """
    script_dir = Path(__file__).parent
    v419_script = script_dir / 'phase0_requirement_traceability_bind.py'

    if not v419_script.exists():
        return None

    try:
        result = subprocess.run(
            [sys.executable, str(v419_script), worktree_path, requirement_path, output_path],
            capture_output=True,
            text=True,
            timeout=60
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            return {'status': 'FAIL', 'error': result.stderr}
    except Exception as e:
        return {'status': 'ERROR', 'error': str(e)}


def carrier_matches_workflow_keywords(processor_name: str, workflow_keywords: Set[str]) -> Tuple[bool, str]:
    """
    Check if processor name matches requirement workflow keywords.

    Returns (is_match, reason) tuple.
    """
    if not workflow_keywords:
        return True, "No workflow keywords found in requirement"

    processor_lower = processor_name.lower()

    # Check each workflow keyword
    for keyword in workflow_keywords:
        if keyword.lower() in processor_lower:
            return True, f"Carrier {processor_name} matches requirement keyword '{keyword}'"

    # No match found
    return False, f"Carrier {processor_name} doesn't match any requirement workflow keywords: {sorted(workflow_keywords)}"


def verify_entry_point_mapping(
    requirement_snapshot_path: str,
    family_ledger_path: str,
    baseline_index_path: Optional[str] = None,
    worktree_path: Optional[str] = None
) -> Dict:
    """
    Verify that selected carriers map to requirement workflow.

    Args:
        requirement_snapshot_path: Path to REQUIREMENT_SOURCE_SNAPSHOT.md
        family_ledger_path: Path to REQUIREMENT_FAMILY_LEDGER.json
        baseline_index_path: Optional path to BASELINE_INDEX.md for additional validation
        worktree_path: Optional path to worktree for v419 traceability binding

    Returns:
        Dict with validation result:
            - valid: bool
            - verified_carriers: list of dicts with carrier_id, carrier_name, match_status
            - unverified_carriers: list of dicts with carrier_id, carrier_name, reason
            - total_carriers: int
            - verified_count: int
            - unverified_count: int
            - message: str
            - v419_traceability: dict with v419 experiment result
    """
    # Load requirement snapshot
    requirement_path = Path(requirement_snapshot_path)

    if not requirement_path.exists():
        return {
            'valid': False,
            'reason': 'requirement_snapshot_not_found',
            'message': f'Requirement snapshot not found: {requirement_snapshot_path}'
        }

    requirement_text = requirement_path.read_text(encoding='utf-8-sig', errors='ignore')
    workflow_keywords = extract_workflow_keywords_from_requirement(requirement_text)

    # Load family ledger
    ledger_path = Path(family_ledger_path)

    if not ledger_path.exists():
        return {
            'valid': False,
            'reason': 'family_ledger_not_found',
            'message': f'Family ledger not found: {family_ledger_path}'
        }

    with open(ledger_path, 'r', encoding='utf-8-sig') as f:
        ledger = json.load(f)

    families = ledger.get('families', [])

    # v419: Invoke traceability binding experiment if worktree provided
    v419_traceability = None
    if worktree_path:
        replay_root = Path(requirement_snapshot_path).parent
        bindings_output = replay_root / 'REQUIREMENT_CARRIER_BINDINGS.json'
        v419_traceability = invoke_v419_traceability_binding(
            str(Path(worktree_path) / 'worktree' if (Path(worktree_path) / 'worktree').exists() else worktree_path),
            requirement_snapshot_path,
            str(bindings_output)
        )

    # Verify each carrier
    verified_carriers = []
    unverified_carriers = []

    for family in families:
        family_id = family.get('id', 'unknown')
        carrier = family.get('first_executable_carrier', '')

        if not carrier:
            continue

        processor_name = extract_processor_name(carrier)

        if not processor_name:
            unverified_carriers.append({
                'family_id': family_id,
                'carrier_name': carrier,
                'reason': 'Cannot extract processor name from carrier string'
            })
            continue

        is_match, reason = carrier_matches_workflow_keywords(processor_name, workflow_keywords)

        if is_match:
            verified_carriers.append({
                'family_id': family_id,
                'carrier_name': carrier,
                'processor_name': processor_name,
                'reason': reason
            })
        else:
            unverified_carriers.append({
                'family_id': family_id,
                'carrier_name': carrier,
                'processor_name': processor_name,
                'reason': reason
            })

    # Final verdict
    total_carriers = len(verified_carriers) + len(unverified_carriers)
    is_valid = len(unverified_carriers) == 0

    return {
        'valid': is_valid,
        'verified_carriers': verified_carriers,
        'unverified_carriers': unverified_carriers,
        'total_carriers': total_carriers,
        'verified_count': len(verified_carriers),
        'unverified_count': len(unverified_carriers),
        'workflow_keywords': sorted(workflow_keywords),
        'reason': 'entry_point_mapping_valid' if is_valid else 'wrong_entry_point_detected',
        'message': (
            f'All {total_carriers} carriers verified against requirement workflow'
            if is_valid else
            f'Entry point verification failed: {len(unverified_carriers)}/{total_carriers} carriers do not match requirement workflow'
        ),
        'v419_traceability': v419_traceability
    }


def main():
    if len(sys.argv) < 5:
        print("Usage: validate_entry_point_mapping.py --requirement SNAPSHOT.md --ledger LEDGER.json [--baseline BASELINE_INDEX.md]", file=sys.stderr)
        print("\nExample:", file=sys.stderr)
        print('  validate_entry_point_mapping.py \\', file=sys.stderr)
        print('    --requirement REQUIREMENT_SOURCE_SNAPSHOT.md \\', file=sys.stderr)
        print('    --ledger REQUIREMENT_FAMILY_LEDGER.json \\', file=sys.stderr)
        print('    --baseline BASELINE_INDEX.md', file=sys.stderr)
        sys.exit(1)

    requirement_path = None
    ledger_path = None
    baseline_path = None

    # Parse arguments
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]

        if arg == '--requirement' and i + 1 < len(sys.argv):
            requirement_path = sys.argv[i + 1]
            i += 2

        elif arg == '--ledger' and i + 1 < len(sys.argv):
            ledger_path = sys.argv[i + 1]
            i += 2

        elif arg == '--baseline' and i + 1 < len(sys.argv):
            baseline_path = sys.argv[i + 1]
            i += 2

        else:
            i += 1

    if not requirement_path or not ledger_path:
        print("Error: --requirement and --ledger are required", file=sys.stderr)
        sys.exit(1)

    # Verify
    result = verify_entry_point_mapping(requirement_path, ledger_path, baseline_path)

    # Output result
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with appropriate code
    if result['valid']:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
