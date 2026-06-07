#!/usr/bin/env python3
"""
Coverage Calculation with TODO Penalty (Experiment E2).

Applies coverage penalty for TODO/STUB markers to discourage skeleton implementations.
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any


def calculate_todo_count(implemented_files: List[str], worktree_path: str) -> Dict:
    """
    Count TODO/STUB markers in implemented files.
    Returns detailed breakdown by file and marker type.
    """
    todo_details = []
    total_todo = 0
    total_stub = 0

    for file_path in implemented_files:
        full_path = Path(worktree_path) / file_path
        if not full_path.exists():
            continue

        content = full_path.read_text(encoding='utf-8', errors='ignore')

        # Count TODO markers
        todo_count = 0
        for match in re.finditer(r"TODO", content, re.IGNORECASE):
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line = content[line_start:line_end].strip()
            line_num = content[:match.start()].count("\n") + 1
            todo_details.append({
                "file": file_path,
                "line": line_num,
                "type": "TODO",
                "text": line
            })
            todo_count += 1

        # Count STUB markers
        stub_count = 0
        for match in re.finditer(r"STUB", content, re.IGNORECASE):
            line_start = content.rfind("\n", 0, match.start()) + 1
            line_end = content.find("\n", match.start())
            line = content[line_start:line_end].strip()
            line_num = content[:match.start()].count("\n") + 1
            todo_details.append({
                "file": file_path,
                "line": line_num,
                "type": "STUB",
                "text": line
            })
            stub_count += 1

        total_todo += todo_count
        total_stub += stub_count

    return {
        "total_todo": total_todo,
        "total_stub": total_stub,
        "total_markers": total_todo + total_stub,
        "details": todo_details
    }


def calculate_coverage_with_todo_penalty(
    slice_result: Dict,
    base_coverage: float,
    worktree_path: str
) -> Dict:
    """
    Apply TODO penalty to coverage delta:
    - Each TODO/STUB marker = -5% coverage
    - TODO/STUB in business logic methods = -10% per marker
    - Minimum coverage = 0%
    """
    implemented_files = slice_result.get("implemented_files", [])

    todo_info = calculate_todo_count(implemented_files, worktree_path)

    # Calculate penalty
    # Regular TODO/STUB = -5%
    # TODO/STUB in business methods = -10%
    penalty = 0
    for detail in todo_info.get("details", []):
        # Check if in business logic method (public/private method, not test/helper)
        is_business_logic = any(
            keyword in detail.get("text", "").lower()
            for keyword in ["public", "private", "service", "facade", "mapper"]
        )
        marker_penalty = 10 if is_business_logic else 5
        penalty += marker_penalty

    # Cap penalty at 100%
    penalty = min(penalty, 100)

    # Calculate adjusted coverage
    adjusted_coverage = max(base_coverage - penalty, 0)

    return {
        "base_coverage": base_coverage,
        "todo_count": todo_info.get("total_todo", 0),
        "stub_count": todo_info.get("total_stub", 0),
        "total_markers": todo_info.get("total_markers", 0),
        "penalty": penalty,
        "adjusted_coverage": adjusted_coverage,
        "penalty_details": todo_info.get("details", [])[:10]  # First 10 details
    }


def calculate_oracle_adjusted_coverage(
    assessment: float,
    executable_evidence_factor: float,
    contract_closure_factor: float
) -> Dict:
    """
    Oracle adjusted coverage = (file_overlap * executable_evidence_factor * contract_closure_factor)
    """
    if executable_evidence_factor == 0:
        return {
            "assessment": assessment,
            "executable_evidence_factor": executable_evidence_factor,
            "contract_closure_factor": contract_closure_factor,
            "oracle_adjusted_coverage": 0,
            "reason": "no_executable_evidence"
        }

    if contract_closure_factor < 0.5:
        adjusted = min(assessment, 20)
        return {
            "assessment": assessment,
            "executable_evidence_factor": executable_evidence_factor,
            "contract_closure_factor": contract_closure_factor,
            "oracle_adjusted_coverage": adjusted,
            "reason": "contract_closure_below_threshold"
        }

    oracle_adjusted = assessment * executable_evidence_factor * contract_closure_factor

    return {
        "assessment": assessment,
        "executable_evidence_factor": executable_evidence_factor,
        "contract_closure_factor": contract_closure_factor,
        "oracle_adjusted_coverage": round(oracle_adjusted, 2),
        "reason": "normal_calculation"
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: calculate_coverage.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  todo-penalty <slice_result_json> <base_coverage> <worktree_path>", file=sys.stderr)
        print("  count-todo <implemented_files_json> <worktree_path>", file=sys.stderr)
        print("  oracle-adjusted <assessment> <executable_factor> <closure_factor>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "todo-penalty":
        if len(sys.argv) < 5:
            print("Usage: calculate_coverage.py todo-penalty <slice_result_json> <base_coverage> <worktree_path>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            slice_result = json.load(f)
        base_coverage = float(sys.argv[3])
        worktree = sys.argv[4]

        result = calculate_coverage_with_todo_penalty(slice_result, base_coverage, worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "count-todo":
        if len(sys.argv) < 4:
            print("Usage: calculate_coverage.py count-todo <implemented_files_json> <worktree_path>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            implemented_files = json.load(f)
        worktree = sys.argv[3]

        result = calculate_todo_count(implemented_files, worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "oracle-adjusted":
        if len(sys.argv) < 5:
            print("Usage: calculate_coverage.py oracle-adjusted <assessment> <executable_factor> <closure_factor>", file=sys.stderr)
            sys.exit(1)

        assessment = float(sys.argv[2])
        executable_factor = float(sys.argv[3])
        closure_factor = float(sys.argv[4])

        result = calculate_oracle_adjusted_coverage(assessment, executable_factor, closure_factor)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
