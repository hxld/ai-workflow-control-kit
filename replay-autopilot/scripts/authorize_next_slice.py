#!/usr/bin/env python3
"""
Core-First Completion Gate (Experiment 1).
No slice can proceed until core_entry is FULLY CLOSED.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional


# Core entry closure verification patterns
CORE_ENTRY_CLOSURE_PATTERNS = {
    "validation_gates": [
        r"isSupportedAutoFlowScope",
        r"checkFreeReviewAmount",
        r"validateBeneficiary",
        r"validatePolicy",
        r"validateCase"
    ],
    "db_operations": [
        r"CompensateInfo\.insert",
        r"CompensateInfo\.update",
        r"CompensateDetail\.insert",
        r"CompensateDetail\.insertList",
        r"t_compensate_info",
        r"t_compensate_detail"
    ],
    "status_update": [
        r"CaseFlowStatusService\.updateFlowStatusForCompensate",
        r"updateFlowStatus",
        r"\.setStatus",
        r"t_case_flow_status"
    ],
    "test_evidence": [
        r"assertThat",
        r"verify",
        r"@Transactional",
        r"AtomicReference",
        r"\.isNotNull\(\)",
        r"\.isEqualTo"
    ]
}


def parse_requirement_family_ledger(ledger_path: str) -> Dict:
    """Parse requirement family ledger JSON."""
    if not Path(ledger_path).exists():
        return {"families": []}

    with open(ledger_path, encoding='utf-8') as f:
        return json.load(f)


def parse_slice_result(slice_result_path: str) -> Dict:
    """Parse slice result JSON."""
    if not Path(slice_result_path).exists():
        return {}

    with open(slice_result_path, encoding='utf-8') as f:
        return json.load(f)


def extract_implemented_files(slice_result: Dict) -> List[str]:
    """Extract list of implemented files from slice result."""
    return slice_result.get("implemented_files", [])


def extract_test_files(slice_result: Dict) -> List[str]:
    """Extract list of test files from slice result."""
    return slice_result.get("test_files", [])


def search_pattern_in_files(files: List[str], patterns: List[str], worktree_path: str) -> Dict[str, List[str]]:
    """Search for patterns in files and return matches by pattern type."""
    if not files:
        return {ptype: [] for ptype in CORE_ENTRY_CLOSURE_PATTERNS}

    found = {ptype: [] for ptype in CORE_ENTRY_CLOSURE_PATTERNS}

    for file_path in files:
        full_path = Path(worktree_path) / file_path
        if not full_path.exists():
            continue

        try:
            content = full_path.read_text(encoding='utf-8', errors='ignore')
        except:
            continue

        for pattern_type, pattern_list in CORE_ENTRY_CLOSURE_PATTERNS.items():
            for pattern in pattern_list:
                if re.search(pattern, content, re.IGNORECASE):
                    if pattern not in found[pattern_type]:
                        found[pattern_type].append(pattern)

    return found


def verify_core_entry_closure(slice_result: Dict, worktree_path: str) -> Dict:
    """Verify core_entry has all required executable proof."""
    implemented_files = extract_implemented_files(slice_result)
    test_files = extract_test_files(slice_result)

    all_files = implemented_files + test_files
    pattern_matches = search_pattern_in_files(all_files, [], worktree_path)

    # For each pattern type, check if at least one pattern was found
    missing_proof = []
    closure_status = {}

    for proof_type, patterns in CORE_ENTRY_CLOSURE_PATTERNS.items():
        found = search_pattern_in_files(all_files, patterns, worktree_path).get(proof_type, [])
        has_evidence = len(found) > 0

        closure_status[proof_type] = {
            "required": patterns,
            "found": found,
            "has_evidence": has_evidence
        }

        if not has_evidence:
            missing_proof.append(proof_type)

    return {
        "is_closed": len(missing_proof) == 0,
        "missing_proof": missing_proof,
        "closure_status": closure_status
    }


def authorize_next_slice(
    ledger_path: str,
    slice_result_path: str,
    target_family: str,
    worktree_path: str
) -> Dict:
    """
    Core-First Completion Gate:
    No slice can proceed until core_entry is FULLY CLOSED.
    """
    ledger = parse_requirement_family_ledger(ledger_path)
    slice_result = parse_slice_result(slice_result_path)

    # Find core_entry family
    core_family = None
    for family in ledger.get("families", []):
        if family.get("id") == "core_entry":
            core_family = family
            break

    if not core_family:
        # No core_entry family in requirement, allow any slice
        return {
            "authorized": True,
            "gate": "core_first_completion",
            "reason": "no_core_entry_in_requirement"
        }

    core_status = core_family.get("status", "OPEN")

    # Check if attempting to bypass core_entry
    if target_family != "core_entry" and core_status != "CLOSED":
        return {
            "authorized": False,
            "gate": "core_first_completion",
            "reason": "core_entry_must_close_first",
            "required_proof": [
                "all_validation_gates_implemented",
                "db_side_effects_verified",
                "status_transition_proven",
                "behavior_test_passing"
            ],
            "current_status": core_status,
            "slices_on_core": core_family.get("slices", []),
            "blocker": f"Attempting to start {target_family} before core_entry closed"
        }

    # If targeting core_entry, verify minimum closure criteria
    if target_family == "core_entry":
        closure_check = verify_core_entry_closure(slice_result, worktree_path)

        if not closure_check["is_closed"]:
            return {
                "authorized": False,
                "gate": "core_first_completion",
                "reason": "core_entry_incomplete",
                "missing_proof": closure_check["missing_proof"],
                "closure_status": closure_check["closure_status"]
            }

    return {
        "authorized": True,
        "gate": "core_first_completion",
        "reason": "core_entry_closed_or_targeting_core"
    }


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: authorize_next_slice.py <ledger_path> <slice_result_path> <target_family> <worktree_path>", file=sys.stderr)
        sys.exit(1)

    ledger_path = sys.argv[1]
    slice_result_path = sys.argv[2]
    target_family = sys.argv[3]
    worktree_path = sys.argv[4]

    result = authorize_next_slice(ledger_path, slice_result_path, target_family, worktree_path)
    print(json.dumps(result, indent=2))

    if not result.get("authorized"):
        sys.exit(1)
