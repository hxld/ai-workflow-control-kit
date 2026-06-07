#!/usr/bin/env python3
"""
Real-time slice verification after execution.

EXPERIMENT 2: Behavioral Assertion Requirement
EXPERIMENT 3: Real-Time Coverage Cap Enforcement
"""

import json
import sys
import re
from pathlib import Path


def check_shallow_module_implementation(test_file_path, implemented_files):
    """
    V425-GAP-1: Check for shallow/pass-through module implementations.

    A shallow module is a new abstraction that only delegates to another
    method without adding real behavior. These should either:
    1. Have a deletion test (prove it's needed)
    2. Be collapsed into the caller

    Returns dict with gap detection result.
    """
    if not test_file_path or not Path(test_file_path).exists():
        return {'has_shallow_module': False, 'reason': 'test_file_not_found'}

    if not implemented_files:
        return {'has_shallow_module': False, 'reason': 'no_implementation_files'}

    try:
        with open(test_file_path, 'r', encoding='utf-8') as f:
            test_content = f.read()
    except:
        return {'has_shallow_module': False, 'reason': 'test_read_failed'}

    # Shallow module indicators in test:
    # 1. Only verifies method was called (delegation-only)
    # 2. No state change verification
    # 3. No side effect verification
    # 4. Test only checks return value from direct delegation

    delegation_only_patterns = [
        r'verify\s*\(\s*\w+\s*\)\s*\.method\(',  # Only verifies method call
        r'when\s*\(\s*\w+\.delegate',  # Delegation pattern
        r'\.delegate\(',  # Delegate method
    ]

    has_delegation_only = any(
        re.search(pattern, test_content)
        for pattern in delegation_only_patterns
    )

    # Check if test has business verification
    has_business_assert = any(
        re.search(pattern, test_content)
        for pattern in [
            r'assertEquals',
            r'assertThat.*\.isEqualTo',
            r'verify\s*\(.*mapper',
            r'verify\s*\(.*service',
        ]
    )

    # Check if test has deletion test (collapsing justification)
    has_deletion_test = bool(re.search(r'delet|remove|collapse', test_content, re.IGNORECASE))

    if has_delegation_only and not has_business_assert and not has_deletion_test:
        return {
            'has_shallow_module': True,
            'reason': 'delegation_only_without_business_assertion_or_deletion_test',
            'pattern': 'test_only_verifies_delegation'
        }

    return {'has_shallow_module': False, 'reason': 'pass'}


def check_wrong_test_surface(test_file_path, plan_carrier):
    """
    V425-GAP-3: Check if test validates the wrong surface.

    Wrong test surface means:
    1. Test targets helper/internals instead of real entry
    2. Test uses mock-only assertions without real carrier
    3. Test validates structure not behavior

    Returns dict with gap detection result.
    """
    if not test_file_path or not Path(test_file_path).exists():
        return {'has_wrong_surface': False, 'reason': 'test_file_not_found'}

    try:
        with open(test_file_path, 'r', encoding='utf-8') as f:
            test_content = f.read()
    except:
        return {'has_wrong_surface': False, 'reason': 'test_read_failed'}

    # Check if test targets helper instead of real entry
    # (test class name doesn't match plan carrier class)
    test_filename = Path(test_file_path).stem
    if plan_carrier:
        # Extract carrier class name from path
        carrier_class = plan_carrier.split('/')[-1].replace('.java', '')
        # Test should be named CarrierTest or CarrierSpec
        if test_filename.replace('Test', '').replace('Spec', '') != carrier_class:
            # Check if test is for a helper
            helper_indicators = ['Helper', 'Util', 'HelperTest', 'UtilTest']
            if any(ind in test_filename for ind in helper_indicators):
                return {
                    'has_wrong_surface': True,
                    'reason': 'test_targets_helper_not_entry',
                    'test_class': test_filename,
                    'expected_class': carrier_class
                }

    # Check for mock-only without real carrier
    has_mock = bool(re.search(r'@Mock|Mockito\.mock|when\s*\(', test_content))
    has_real_injection = bool(re.search(r'@InjectMocks|@Autowired|@Resource', test_content))

    if has_mock and not has_real_injection:
        # Check if mock-only is justified
        has_integration_note = bool(re.search(
            r'integration|real.*test|component.*test', test_content, re.IGNORECASE
        ))
        if not has_integration_note:
            return {
                'has_wrong_surface': True,
                'reason': 'mock_only_without_real_carrier_test',
                'has_mock': has_mock,
                'has_real_injection': has_real_injection
            }

    return {'has_wrong_surface': False, 'reason': 'pass'}


def verify_behavioral_assertion(test_file_path):
    """
    Verify that the test file contains at least one behavioral assertion.

    EXPERIMENT 2: Behavioral Assertion Requirement in RED Phase
    V425-GAP-3: Enhanced wrong_test_surface detection

    Args:
        test_file_path: str path to test file

    Returns:
        dict: {
            'has_behavioral_assertion': bool,
            'assertion_type': str or None,  # 'business_outcome', 'db_state', 'api_contract'
            'error': str or None,
            'behavioral_count': int,
            'structural_count': int
        }
    """
    try:
        with open(test_file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return {
            'has_behavioral_assertion': False,
            'error': f'Failed to read test file: {e}',
            'behavioral_count': 0,
            'structural_count': 0
        }

    # Behavioral assertion patterns (acceptable)
    behavioral_patterns = [
        (r'assertEquals\s*\([^)]+\)', 'business_outcome'),
        (r'assertThat\s*\([^)]+\)\s*\.(isEqualTo|contains|matches|isNotNull|isTrue|isFalse)', 'business_outcome'),
        (r'verify\s*\([^)]+\)\s*\.times', 'mock_verification'),
        (r'select\s+.*\s+from\s+.*where', 'db_state_verification'),
        (r'assertTrue\s*\([^)]+\)', 'business_condition'),
        (r'assertFalse\s*\([^)]+\)', 'business_condition'),
    ]

    behavioral_found = []
    for pattern, assertion_type in behavioral_patterns:
        matches = re.findall(pattern, content)
        if matches:
            behavioral_found.append({'pattern': pattern, 'type': assertion_type, 'count': len(matches)})

    # Structural-only patterns (unacceptable as primary assertion)
    structural_patterns = [
        (r'assertNotNull\s*\([^)]+\)', 'structural_only'),
        (r'assertThat\s*\([^)]+\)\.isNotNull\s*\;', 'structural_only'),
        (r'TypePresent\s*<[^>]+>\s*\(\s*[^)]+\s*\)\.isPresent\s*\(\s*\)', 'structural_only'),
    ]

    structural_found = []
    for pattern, assertion_type in structural_patterns:
        matches = re.findall(pattern, content)
        if matches:
            structural_found.append({'pattern': pattern, 'type': assertion_type, 'count': len(matches)})

    # Blocked patterns (fail with TODO)
    blocked_patterns = [
        (r'fail\s*\(\s*["\'].*TODO', 'fail_todo'),
        (r'fail\s*\(\s*["\'].*not implemented', 'fail_not_implemented'),
    ]

    blocked_found = []
    for pattern, block_type in blocked_patterns:
        matches = re.findall(pattern, content, re.IGNORECASE)
        if matches:
            blocked_found.append({'pattern': pattern, 'type': block_type, 'count': len(matches)})

    if blocked_found:
        return {
            'has_behavioral_assertion': False,
            'error': 'Test contains blocked patterns (fail with TODO/not implemented)',
            'blocked_patterns': blocked_found,
            'behavioral_count': 0,
            'structural_count': 0
        }

    if not behavioral_found:
        return {
            'has_behavioral_assertion': False,
            'error': 'No behavioral assertions found. Add assertEquals, verify, or assertThat with business outcome check.',
            'behavioral_count': 0,
            'structural_count': len(structural_found)
        }

    # Check if only structural assertions exist
    behavioral_total = sum(item['count'] for item in behavioral_found)
    structural_total = sum(item['count'] for item in structural_found)

    if behavioral_total == 0 and structural_total > 0:
        return {
            'has_behavioral_assertion': False,
            'error': 'Test contains only structural assertions. Add behavioral assertion (assertEquals, verify, assertThat.isEqualTo).',
            'structural_patterns': structural_found,
            'behavioral_count': 0,
            'structural_count': structural_total
        }

    return {
        'has_behavioral_assertion': True,
        'assertion_type': behavioral_found[0]['type'] if behavioral_found else None,
        'behavioral_patterns': behavioral_found,
        'error': None,
        'behavioral_count': behavioral_total,
        'structural_count': structural_total
    }


def compute_realtime_oracle_delta(slice_result, requirement_family_ledger, worktree_root=None):
    """
    Estimate oracle overlap in real-time after slice completion.

    EXPERIMENT 3: Real-Time Coverage Cap Enforcement

    Args:
        slice_result: dict slice result data
        requirement_family_ledger: dict with families data
        worktree_root: str path to worktree (optional, for file-based verification)

    Returns:
        dict: {
            'estimated_overlap': float (0-100),
            'behavioral_evidence_exists': bool,
            'cap_exceeded': bool,
            'coverage_delta': int,
            'reason': str
        }
    """
    # Check if behavioral evidence exists
    has_behavior = slice_result.get('has_behavior_evidence', False)
    has_side_effects = slice_result.get('side_effects_verified', 0) > 0

    if not has_behavior and not has_side_effects:
        return {
            'estimated_overlap': 0.0,
            'behavioral_evidence_exists': False,
            'cap_exceeded': False,
            'coverage_delta': 0,
            'reason': 'No behavioral evidence or side effects verified'
        }

    # Estimate overlap based on families touched
    touched_families = slice_result.get('touched_requirement_families', [])
    families = requirement_family_ledger.get('families', [])

    # Simple heuristic for real-time estimation
    estimated_overlap = 0.0

    # core_entry with behavioral evidence: 30%
    if 'core_entry' in touched_families and has_behavior:
        estimated_overlap += 30.0

    # stateful_side_effect with verification: 20%
    if 'stateful_side_effect' in touched_families and has_side_effects:
        estimated_overlap += 20.0

    # Other families add 10% each
    weight_map = {
        'deploy_export_page': 10,
        'wire_payload_api_contract': 10,
        'config_policy_threshold': 5,
        'generated_artifact_template_upload': 10,
        'external_integration': 15,
        'automation_test_interface': 5,
        'lifecycle_cleanup_retention': 5
    }

    for family in touched_families:
        if family in weight_map:
            estimated_overlap += weight_map[family]

    # Cap at coverage_cap if specified
    coverage_cap = slice_result.get('coverage_cap', 100)
    estimated_overlap = min(estimated_overlap, coverage_cap)

    return {
        'estimated_overlap': round(estimated_overlap, 1),
        'behavioral_evidence_exists': True,
        'cap_exceeded': False,
        'coverage_delta': int(estimated_overlap),
        'reason': f'Estimated based on {len(touched_families)} families touched with behavioral evidence'
    }


def verify_slice_post_execution(slice_result_path, requirement_family_ledger_path, enable_behavioral_check=False, enable_realtime_coverage=False, worktree_root=None):
    """Verify slice execution result BEFORE allowing next slice."""

    with open(slice_result_path) as f:
        slice_result = json.load(f)

    with open(requirement_family_ledger_path) as f:
        ledger = json.load(f)

    gaps = []
    blockers = []

    # Get core_entry family from ledger
    core_entry_family = None
    for family in ledger.get("families", []):
        if family.get("id") == "core_entry":
            core_entry_family = family
            break

    # V425: Enhanced gap detection for recurring issues
    implemented_files = slice_result.get('implemented_files', [])
    plan_carrier = slice_result.get('selected_carrier', '')

    # V425-GAP-1: Check shallow_module
    test_file = slice_result.get('behavior_test_charter', {}).get('evidence_file')
    if test_file and worktree_root:
        test_path = Path(worktree_root) / test_file if not Path(test_file).is_absolute() else Path(test_file)
        if test_path.exists():
            shallow_check = check_shallow_module_implementation(str(test_path), implemented_files)
            if shallow_check.get('has_shallow_module'):
                gaps.append(f"shallow_module: {shallow_check.get('reason')}")
                blockers.append("shallow_module")
                slice_result["shallow_module_check"] = shallow_check

    # V425-GAP-3: Check wrong_test_surface
    if test_file and worktree_root:
        test_path = Path(worktree_root) / test_file if not Path(test_file).is_absolute() else Path(test_file)
        if test_path.exists():
            surface_check = check_wrong_test_surface(str(test_path), plan_carrier)
            if surface_check.get('has_wrong_surface'):
                gaps.append(f"wrong_test_surface: {surface_check.get('reason')}")
                blockers.append("wrong_test_surface")
                slice_result["wrong_test_surface_check"] = surface_check

    # EXPERIMENT 2: Behavioral Assertion Check
    if enable_behavioral_check:
        test_file = slice_result.get('behavior_test_charter', {}).get('evidence_file')
        if test_file and worktree_root:
            test_path = Path(worktree_root) / test_file if not Path(test_file).is_absolute() else Path(test_file)
            if test_path.exists():
                behavior_check = verify_behavioral_assertion(str(test_path))
                if not behavior_check['has_behavioral_assertion']:
                    gaps.append(f"behavior_test_charter_gap: {behavior_check.get('error')}")
                    blockers.append("no_behavioral_assertion")
                    slice_result["behavioral_assertion_check"] = behavior_check

    # EXPERIMENT 3: Real-Time Coverage Calculation
    if enable_realtime_coverage:
        realtime_coverage = compute_realtime_oracle_delta(slice_result, ledger, worktree_root)
        slice_result["realtime_coverage"] = realtime_coverage
        # Update coverage_delta based on real-time estimation
        if realtime_coverage['coverage_delta'] == 0 and slice_result.get('implemented_files'):
            gaps.append("realtime_coverage_zero: Files created but no behavioral evidence")
            blockers.append("no_behavioral_evidence")

    # Check 1: Helper-only surface in S1
    slice_number = slice_result.get("slice_number", 1)
    target_family = slice_result.get("target_family")

    if slice_number == 1:
        if target_family == "config_policy_threshold":
            gaps.append("helper_only_surface_gap: S1 must target core_entry, not validator")
            blockers.append("helper_only_surface_gap")

        if target_family != "core_entry" and core_entry_family:
            gaps.append("s1_does_not_target_core_entry: core_entry family required in S1")
            blockers.append("s1_target_wrong")

    # Check 2: Side-effect ledger
    side_effects_verified = slice_result.get("side_effects_verified", 0)
    if side_effects_verified == 0:
        gaps.append("side_effect_ledger_gap: No side effects verified")
        blockers.append("side_effect_ledger_gap")

    # Check 3: Core entry closure
    if target_family == "core_entry":
        core_entry_closed = slice_result.get("core_entry_closed", False)
        if not core_entry_closed:
            gaps.append("core_entry_unclosed: core_entry family not closed")
            blockers.append("core_entry_unclosed")

    # Check 4: Mock-only proof
    proof_type = slice_result.get("proof_type", "")
    if proof_type == "mock_only":
        gaps.append("mock_only_proof: Tests must execute real carrier, not mocks")
        blockers.append("mock_only_proof")

    # Block if gaps exist
    if gaps or blockers:
        slice_result["authorized_for_next_slice"] = False
        slice_result["authorized_for_synthesis"] = False
        slice_result["blockers"] = blockers
        slice_result["gaps"] = gaps

        with open(slice_result_path, "w") as f:
            json.dump(slice_result, f, indent=2)

        return "BLOCKED", gaps

    return "PASS", []

if __name__ == "__main__":
    # Usage: python slice_verify.py <slice_result_path> <requirement_family_ledger_path> [options]
    # Options:
    #   --enable_behavioral_assertion : Enable behavioral assertion check
    #   --enable_realtime_cap : Enable real-time coverage calculation
    #   --worktree <path> : Worktree root path

    args = sys.argv[1:]
    slice_path = args[0] if len(args) > 0 else None
    ledger_path = args[1] if len(args) > 1 else None

    enable_behavioral = False
    enable_realtime = False
    worktree = None

    for i in range(2, len(args)):
        if args[i] == '--enable_behavioral_assertion':
            enable_behavioral = True
        elif args[i] == '--enable_realtime_cap':
            enable_realtime = True
        elif args[i] == '--worktree' and i + 1 < len(args):
            worktree = args[i + 1]

    status, gaps = verify_slice_post_execution(
        slice_path,
        ledger_path,
        enable_behavioral_check=enable_behavioral,
        enable_realtime_coverage=enable_realtime,
        worktree_root=worktree
    )
    print(f"Status: {status}")
    if gaps:
        print("Gaps:", gaps)
