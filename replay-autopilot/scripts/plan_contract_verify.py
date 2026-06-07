#!/usr/bin/env python3
"""
Verify plan contract against requirements (oracle files for non-blind mode).

EXPERIMENT 1: Carrier Existence Verification
This script includes verify_carrier_exists() function to validate
that the selected carrier exists in the codebase before plan approval.

EXPERIMENT 2: Exact Contract Verification (v365)
This script now includes verify_exact_contract_match() function to validate
that planned signatures exactly match oracle signatures (no synthetic carriers).
"""

import json
import sys
import subprocess
from pathlib import Path


def verify_exact_contract_match(plan_result, oracle_contracts_path, codebase_root):
    """
    Verify that planned signatures exactly match oracle signatures (Experiment 2).

    EXPERIMENT 2: Exact Contract Verification at Plan Stage (MANDATORY v365)

    Args:
        plan_result: dict with plan data containing planned carriers/signatures
        oracle_contracts_path: str path to ORACLE_CONTRACTS.json
        codebase_root: str path to codebase root

    Returns:
        dict: {
            'status': 'PASS'|'FAIL'|'WARN',
            'carriers_verified': list of verification results per carrier,
            'issues': list of problems found,
            'synthetic_carrier_count': int
        }
    """
    import json
    from pathlib import Path

    carriers_verified = []
    issues = []
    synthetic_carrier_count = 0

    # Load oracle contracts if available
    oracle_contracts = {}
    oracle_path = Path(oracle_contracts_path)
    if oracle_path.exists():
        try:
            with open(oracle_path, 'r', encoding='utf-8') as f:
                oracle_contracts = json.load(f)
        except Exception as e:
            issues.append({
                'code': 'oracle_contracts_load_failed',
                'message': f'Failed to load oracle contracts: {str(e)}',
                'severity': 'high'
            })

    # Extract planned carriers from plan_result
    planned_carriers = plan_result.get('planned_carriers', [])
    if not planned_carriers:
        # Try alternative keys
        if 'selected_carrier' in plan_result:
            planned_carriers = [{'class_name': plan_result['selected_carrier']}]
        elif 'selected_real_entry' in plan_result:
            planned_carriers = [{'class_name': plan_result['selected_real_entry']}]

    for carrier in planned_carriers:
        class_name = carrier.get('class_name', '').split('(')[0].split('.')[-1]
        method_name = carrier.get('method_name', 'handle')
        planned_signature = carrier.get('signature', '')

        verification = {
            'class_name': class_name,
            'method_name': method_name,
            'planned_signature': planned_signature,
            'oracle_signature': None,
            'match_status': 'none'
        }

        # Check against oracle contracts
        if oracle_contracts:
            # Search for matching oracle signature
            for oracle_class, oracle_data in oracle_contracts.items():
                if class_name in oracle_class or oracle_class in class_name:
                    oracle_signature = oracle_data.get('signature', '')
                    verification['oracle_signature'] = oracle_signature

                    # Compare signatures
                    if planned_signature == oracle_signature:
                        verification['match_status'] = 'exact'
                    elif method_name in oracle_signature:
                        verification['match_status'] = 'partial'
                        verification['drift_details'] = 'Method name matches but signature differs'
                        issues.append({
                            'code': 'signature_drift_partial',
                            'message': f'Partial match for {class_name}.{method_name}: planned vs oracle differ',
                            'severity': 'high',
                            'location': f'{class_name}.{method_name}'
                        })
                    else:
                        verification['match_status'] = 'synthetic'
                        verification['drift_details'] = 'Synthetic carrier - no oracle match found'
                        synthetic_carrier_count += 1
                        issues.append({
                            'code': 'synthetic_carrier_created',
                            'message': f'Synthetic carrier {class_name}.{method_name} has no oracle match',
                            'severity': 'critical',
                            'location': f'{class_name}.{method_name}'
                        })
                    break

        carriers_verified.append(verification)

    # Determine overall status
    if any(i.get('severity') == 'critical' for i in issues):
        status = 'FAIL'
    elif any(i.get('severity') == 'high' for i in issues):
        status = 'WARN'
    else:
        status = 'PASS'

    return {
        'status': status,
        'carriers_verified': carriers_verified,
        'issues': issues,
        'synthetic_carrier_count': synthetic_carrier_count
    }


def verify_carrier_exists(plan_result, codebase_root):
    """
    Verify that the selected carrier exists in the codebase.

    EXPERIMENT 1: Pre-Slice Carrier Existence Verification (HIGHEST PRIORITY)

    Args:
        plan_result: dict with plan data containing 'selected_carrier' and 'selected_entry'
        codebase_root: str path to codebase root

    Returns:
        dict: {
            'exists': bool,
            'method_signature': str or None,
            'file_path': str or None,
            'error': str or None,
            'search_query': str or None
        }
    """
    carrier = plan_result.get('selected_carrier') or plan_result.get('selected_real_entry')
    if not carrier:
        return {
            'exists': False,
            'error': 'No carrier selected in plan',
            'search_query': None
        }

    # Extract class name from carrier string
    # Handle formats like "AiAutoClaimFlowService.handle" or just "AiAutoClaimFlowService"
    class_name = carrier.split('(')[0].split('.').pop() if '(' in carrier else carrier.split('.').pop()

    # Search for carrier class in codebase
    search_cmd = ['rg', '--type', 'java', f'class {class_name}', codebase_root]
    try:
        result = subprocess.run(search_cmd, capture_output=True, text=True, timeout=30)
    except (subprocess.TimeoutExpired, FileNotFoundError):
        result = subprocess.run(['rg', '--type', 'java', class_name, codebase_root],
                              capture_output=True, text=True, timeout=30)

    if result.returncode != 0 or not result.stdout.strip():
        return {
            'exists': False,
            'error': f'Carrier class {class_name} not found in codebase',
            'search_query': f'rg "class {class_name}" --type java',
            'carrier_searched': carrier
        }

    # Extract method signature if available
    method = None
    if '.' in carrier and '(' in carrier:
        method = carrier.split('(')[0].split('.')[-1]
    elif 'selected_entry' in plan_result:
        entry = plan_result.get('selected_entry', 'handleAutoFlow')
        method = entry.split('(')[0] if '(' in entry else entry

    method_signature = None
    if method:
        method_search = ['rg', '--type', 'java', f'public.*{method}\\(', codebase_root]
        try:
            method_result = subprocess.run(method_search, capture_output=True, text=True, timeout=30)
            if method_result.returncode == 0 and method_result.stdout.strip():
                method_signature = method_result.stdout.strip().split('\n')[0]
        except:
            pass

    # Extract file path from first match
    file_path = None
    for line in result.stdout.strip().split('\n')[:5]:
        if line.strip():
            file_path = line.split(':')[0]
            break

    return {
        'exists': True,
        'method_signature': method_signature,
        'file_path': file_path,
        'error': None,
        'search_query': f'rg "class {class_name}" --type java',
        'carrier_verified': carrier
    }


def verify_first_slice_proof_v457(first_slice_proof_path):
    """
    Verify FIRST_SLICE_PROOF_PLAN.md against V457 schema requirements.

    EXPERIMENT 3: V457 Executable Evidence Gate Verification

    Checks:
    1. target_carrier_line_number is not a placeholder (TBD, unknown, etc.)
    2. expected_assertions exists and has at least 3 items in JSON array format
    3. expected_side_effects exists and has at least 1 item in JSON array format
    4. target_carrier_file_path is not a placeholder

    Returns:
        dict: {
            'status': 'PASS'|'FAIL',
            'issues': list of problems found,
            'fields_checked': list of field names verified
        }
    """
    import re
    import json

    proof_path = Path(first_slice_proof_path)
    if not proof_path.exists():
        return {
            'status': 'FAIL',
            'issues': ['first_slice_proof_file_not_found'],
            'fields_checked': []
        }

    content = proof_path.read_text(encoding='utf-8', errors='ignore')

    issues = []
    fields_checked = []

    # Check 1: target_carrier_line_number is not a placeholder
    # v461: Allow NEW_SERVICE pattern - line number will be determined during implementation
    line_number_match = re.search(r'target_carrier_line_number:\s*(.+)', content)
    if line_number_match:
        line_number = line_number_match.group(1).strip()
        fields_checked.append('target_carrier_line_number')

        # v461: Allow NEW_SERVICE pattern (line number not yet known for new services)
        if 'NEW_SERVICE' in line_number or line_number.startswith('NEW_SERVICE'):
            # Valid - the line number will be determined during implementation
            pass
        # Check for explicit placeholders
        elif line_number in ['TBD', 'unknown', 'N/A', 'placeholder', 'TBD_facade_save_method', '待确认', '未确认']:
            issues.append(f'first_slice_proof_v457_invalid_line_number:{line_number}')
        # v461: Extract numeric part if it has description (e.g., "123 - main method")
        elif not re.match(r'^\d+', line_number):
            issues.append(f'first_slice_proof_v457_invalid_line_number:{line_number}')
    else:
        issues.append('first_slice_proof_v457_missing_field:target_carrier_line_number')

    # Check 2: target_carrier_file_path is not a placeholder
    file_path_match = re.search(r'target_carrier_file_path:\s*(.+)', content)
    if file_path_match:
        file_path = file_path_match.group(1).strip()
        fields_checked.append('target_carrier_file_path')
        if file_path in ['TBD', 'unknown', 'N/A', 'placeholder', '待确认', '未确认']:
            issues.append(f'first_slice_proof_v457_invalid_file_path:{file_path}')
    else:
        issues.append('first_slice_proof_v457_missing_field:target_carrier_file_path')

    # Check 3: expected_assertions exists and has at least 3 items
    assertions_match = re.search(r'expected_assertions:\s*(.+)', content)
    if assertions_match:
        fields_checked.append('expected_assertions')
        assertions_text = assertions_match.group(1).strip()
        try:
            # Try to parse as JSON array
            assertions = json.loads(assertions_text)
            if isinstance(assertions, list) and len(assertions) >= 3:
                # Valid assertions
                pass
            elif isinstance(assertions, list) and len(assertions) < 3:
                issues.append(f'first_slice_proof_v457_assertions_insufficient:{len(assertions)}/3')
            else:
                issues.append('first_slice_proof_v457_assertions_invalid_format')
        except json.JSONDecodeError:
            # Check if it's narrative format (invalid)
            if assertions_text and len(assertions_text) > 10:
                issues.append('first_slice_proof_v457_assertions_missing:narrative_format_not_json_array')
            else:
                issues.append('first_slice_proof_v457_assertions_missing')
    else:
        issues.append('first_slice_proof_v457_assertions_missing')

    # Check 4: expected_side_effects exists and has at least 1 item
    side_effects_match = re.search(r'expected_side_effects:\s*(.+)', content)
    if side_effects_match:
        fields_checked.append('expected_side_effects')
        side_effects_text = side_effects_match.group(1).strip()
        try:
            # Try to parse as JSON array
            side_effects = json.loads(side_effects_text)
            if isinstance(side_effects, list) and len(side_effects) >= 1:
                # Valid side effects
                pass
            elif isinstance(side_effects, list) and len(side_effects) < 1:
                issues.append('first_slice_proof_v457_side_effects_missing:empty_array')
            else:
                issues.append('first_slice_proof_v457_side_effects_invalid_format')
        except json.JSONDecodeError:
            # Check if it's narrative format (invalid)
            if side_effects_text and len(side_effects_text) > 10:
                issues.append('first_slice_proof_v457_side_effects_missing:narrative_format_not_json_array')
            else:
                issues.append('first_slice_proof_v457_side_effects_missing')
    else:
        issues.append('first_slice_proof_v457_side_effects_missing')

    # Check 5: layer validation for core_entry family
    # v461: Extract actual carrier name before checking for 'Service' to avoid false positives
    highest_weight_gate_match = re.search(r'highest_weight_open_gate:\s*(.+)', content)
    selected_carrier_match = re.search(r'selected_carrier:\s*(.+)', content)

    if highest_weight_gate_match and selected_carrier_match:
        highest_weight_gate = highest_weight_gate_match.group(1).strip()
        selected_carrier = selected_carrier_match.group(1).strip()
        fields_checked.extend(['highest_weight_open_gate', 'selected_carrier'])

        # v461: Extract actual carrier name (before first '(') to avoid false positives
        # Example: "AiApplyClaimApiTaskProcessor (EXISTING -> calls NEW AiAutoClaimFlowService)"
        # should extract "AiApplyClaimApiTaskProcessor" not match on "AiAutoClaimFlowService"
        actual_carrier = selected_carrier.split('(')[0].strip()

        # For core_entry family, carrier must be Facade/Controller, not Service
        if 'core_entry' in highest_weight_gate.lower():
            # v461: Check actual carrier name, not the full string with parenthetical notes
            if 'Service' in actual_carrier and 'Facade' not in actual_carrier and 'Controller' not in actual_carrier:
                issues.append('first_slice_proof_invalid:core_entry_static_carrier')
                issues.append('layer_validation_failed:core_entry_requires_facade_controller_no_facade_found')

    if issues:
        return {
            'status': 'FAIL',
            'issues': issues,
            'fields_checked': fields_checked
        }

    return {
        'status': 'PASS',
        'issues': [],
        'fields_checked': fields_checked
    }


def verify_plan_contract(plan_result_path, oracle_files_path, replay_mode="strict-blind", codebase_root=None, enable_carrier_verify=False, enable_exact_contract_verify=False, oracle_contracts_path=None, first_slice_proof_path=None):
    """Verify plan contract with all experiment checks enabled."""

    with open(plan_result_path) as f:
        plan = json.load(f)

    with open(oracle_files_path) as f:
        oracle = json.load(f)

    # EXPERIMENT 1: Carrier Existence Verification (if enabled)
    if enable_carrier_verify and codebase_root:
        carrier_check = verify_carrier_exists(plan, codebase_root)
        if not carrier_check['exists']:
            return {
                "stage": "Plan",
                "verification_status": "FAIL",
                "replay_mode": replay_mode,
                "carrier_verification": "FAILED",
                "carrier_error": carrier_check.get('error'),
                "search_query": carrier_check.get('search_query'),
                "issues": [f"carrier_not_found: {carrier_check.get('error')}"]
            }
        # Add carrier verification pass to result
        carrier_result = {
            "carrier_verification": "PASSED",
            "carrier_exists": True,
            "verified_file": carrier_check.get('file_path'),
            "verified_method": carrier_check.get('method_signature')
        }
    else:
        carrier_result = {}

    # EXPERIMENT 3: V457 First Slice Proof Verification (if enabled)
    v457_result = {}
    if first_slice_proof_path:
        v457_check = verify_first_slice_proof_v457(first_slice_proof_path)
        if v457_check['status'] == 'FAIL':
            return {
                "stage": "Plan",
                "verification_status": "FAIL",
                "replay_mode": replay_mode,
                "v457_first_slice_proof_verification": "FAILED",
                "issues": v457_check.get('issues', []),
                "fields_checked": v457_check.get('fields_checked', [])
            }
        v457_result = {
            "v457_first_slice_proof_verification": "PASSED",
            "v457_fields_checked": v457_check.get('fields_checked', [])
        }

    # EXPERIMENT 2: Exact Contract Verification (if enabled and oracle contracts available)
    exact_contract_result = {}
    if enable_exact_contract_verify and oracle_contracts_path and codebase_root:
        exact_contract_check = verify_exact_contract_match(plan, oracle_contracts_path, codebase_root)
        if exact_contract_check['status'] == 'FAIL':
            return {
                "stage": "Plan",
                "verification_status": "FAIL",
                "replay_mode": replay_mode,
                "exact_contract_verification": "FAILED",
                "synthetic_carrier_count": exact_contract_check.get('synthetic_carrier_count', 0),
                "issues": exact_contract_check.get('issues', [])
            }
        exact_contract_result = {
            "exact_contract_verification": exact_contract_check['status'],
            "carriers_verified": len(exact_contract_check.get('carriers_verified', [])),
            "synthetic_carrier_count": exact_contract_check.get('synthetic_carrier_count', 0)
        }

    if replay_mode == "strict-blind":
        # BLIND MODE: Use requirement family coverage, NOT oracle overlap
        req_coverage = plan.get("requirement_family_coverage", 0)
        high_weight_coverage = plan.get("high_weight_family_coverage", 0)
        core_entry_targeted = plan.get("first_slice_targets_core_entry", False)
        side_effects_count = plan.get("side_effects_identified", 0)

        issues = []

        # New thresholds for blind mode
        if req_coverage < 70:
            issues.append(f"requirement_family_coverage {req_coverage}% < 70%")

        if high_weight_coverage < 60:
            issues.append(f"high_weight_family_coverage {high_weight_coverage}% < 60%")

        if not core_entry_targeted:
            issues.append("first_slice_does_not_target_core_entry")

        if side_effects_count < 3:
            issues.append(f"side_effects_identified {side_effects_count} < 3")

        if issues:
            result = {
                "stage": "Plan",
                "verification_status": "FAIL",
                "replay_mode": "blind",
                "issues": issues,
                "oracle_overlap_skipped": "Not measurable in blind mode"
            }
            result.update(carrier_result)
            result.update(exact_contract_result)
            result.update(v457_result)
            return result

        result = {
            "stage": "Plan",
            "verification_status": "PASS",
            "replay_mode": "blind",
            "requirement_family_coverage": req_coverage,
            "high_weight_family_coverage": high_weight_coverage,
            "oracle_overlap_skipped": "Blind mode validated via requirements"
        }
        result.update(carrier_result)
        result.update(exact_contract_result)
        result.update(v457_result)
        return result

    else:
        # NON-BLIND MODE: Use oracle overlap validation
        return verify_oracle_overlap(plan, oracle, plan_result_path)

def calculate_oracle_overlap(plan, oracle):
    """Calculate oracle overlap metrics."""
    oracle_files = set()
    oracle_high_weight_files = set()

    for f in oracle.get("files", []):
        if f.get("is_production", False):
            oracle_files.add(f["path"])
            if f.get("weight") == "HIGH":
                oracle_high_weight_files.add(f["path"])

    # Get planned files from plan result
    planned_files = set()
    plan_content = plan.get("required_files", "")
    if isinstance(plan_content, str):
        # Parse file paths from plan content
        for line in plan_content.split("\n"):
            line = line.strip()
            if line and not line.startswith("#") and ".java" in line:
                # Extract file path from line
                file_path = line.split()[-1]
                if file_path.endswith(".java") or file_path.endswith(".xml") or file_path.endswith(".jsp"):
                    planned_files.add(file_path)

    # Calculate overlap
    matched_files = oracle_files & planned_files
    matched_high_weight = oracle_high_weight_files & planned_files

    return {
        "oracle_total": len(oracle_files),
        "oracle_high_weight_total": len(oracle_high_weight_files),
        "matched": len(matched_files),
        "matched_high_weight": len(matched_high_weight),
        "overlap_percent": int(len(matched_files) / len(oracle_files) * 100) if oracle_files else 0
    }

def verify_oracle_overlap(plan, oracle, plan_result_path):
    """Verify oracle overlap meets thresholds."""
    overlap = calculate_oracle_overlap(plan, oracle)

    issues = []
    warnings = []

    # FAIL threshold: oracle overlap below 30%
    if overlap["overlap_percent"] < 30:
        issues.append(f"oracle_overlap_below_threshold:{overlap['overlap_percent']}% < 30%")

    # WARN threshold: oracle overlap below 50%
    if overlap["overlap_percent"] < 50:
        warnings.append("implementation_contract_weak:shallow-green-ban")

    # High-weight files coverage check
    high_weight_coverage = int(overlap["matched_high_weight"] / overlap["oracle_high_weight_total"] * 100) if overlap["oracle_high_weight_total"] > 0 else 0
    if high_weight_coverage < 50:
        warnings.append(f"high_weight_coverage_low:{high_weight_coverage}% < 50%")

    if issues:
        return {
            "stage": "Plan",
            "verification_status": "FAIL",
            "replay_mode": "non-blind",
            "oracle_overlap_percent": overlap["overlap_percent"],
            "oracle_overlap_matched": overlap["matched"],
            "oracle_overlap_total_production": overlap["oracle_total"],
            "oracle_high_weight_matched": overlap["matched_high_weight"],
            "oracle_high_weight_total": overlap["oracle_high_weight_total"],
            "issues": issues,
            "warnings": warnings
        }

    return {
        "stage": "Plan",
        "verification_status": "PASS",
        "replay_mode": "non-blind",
        "oracle_overlap_percent": overlap["overlap_percent"],
        "oracle_overlap_matched": overlap["matched"],
        "oracle_overlap_total_production": overlap["oracle_total"],
        "oracle_high_weight_matched": overlap["matched_high_weight"],
        "oracle_high_weight_total": overlap["oracle_high_weight_total"],
        "warnings": warnings
    }

if __name__ == "__main__":
    # Usage: python plan_contract_verify.py <plan_result_path> <oracle_files_path> <replay_mode> [codebase_root] [oracle_contracts_path] [first_slice_proof_path] [--enable_carrier_verify] [--enable_exact_contract_verify]
    args = sys.argv[1:]
    plan_path = args[0] if len(args) > 0 else None
    oracle_path = args[1] if len(args) > 1 else None
    replay_mode = args[2] if len(args) > 2 else "strict-blind"
    codebase_root = None
    oracle_contracts_path = None
    first_slice_proof_path = None
    enable_carrier_verify = False
    enable_exact_contract_verify = False

    # Parse optional arguments
    for i in range(3, len(args)):
        if args[i] == "--enable_carrier_verify":
            enable_carrier_verify = True
        elif args[i] == "--enable_exact_contract_verify":
            enable_exact_contract_verify = True
        elif args[i].startswith("--"):
            continue
        elif codebase_root is None:
            codebase_root = args[i]
        elif oracle_contracts_path is None:
            oracle_contracts_path = args[i]
        elif first_slice_proof_path is None:
            first_slice_proof_path = args[i]

    verify_plan_contract(plan_path, oracle_path, replay_mode, codebase_root, enable_carrier_verify, enable_exact_contract_verify, oracle_contracts_path, first_slice_proof_path)
