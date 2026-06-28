#!/usr/bin/env python3
"""Validate a replay context index for freshness and required family coverage."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def pick_head(audit: Dict[str, Any]) -> str:
    for key in ("initial_after_start_replay_round", "initial_head", "baseline_head", "head"):
        value = audit.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    for value in audit.values():
        if isinstance(value, str) and len(value.strip()) >= 7:
            return value.strip()
    return ""


def family_ids(context: Dict[str, Any]) -> List[str]:
    candidates = context.get("required_family_proof_contracts")
    if candidates is None:
        candidates = context.get("required_families")
    if isinstance(candidates, dict):
        return [str(key) for key in candidates.keys()]
    if isinstance(candidates, list):
        ids = []
        for item in candidates:
            if isinstance(item, str):
                ids.append(item)
            elif isinstance(item, dict):
                ids.append(str(item.get("id") or item.get("family") or item.get("family_id") or ""))
        return [item for item in ids if item]
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--require-family", action="append", default=[])
    parser.add_argument("--require-fresh-head", action="store_true")
    args = parser.parse_args()

    root = Path(args.root)
    context_path = Path(args.context)
    if not context_path.is_absolute():
        context_path = root / context_path

    issues: List[str] = []
    if not context_path.exists():
        issues.append("context_index_missing")
        context: Dict[str, Any] = {}
    else:
        context = read_json(context_path)

    audit_path = root / "WORKTREE_HEAD_AUDIT.json"
    audit = read_json(audit_path) if audit_path.exists() else {}
    audit_head = pick_head(audit) if isinstance(audit, dict) else ""

    metadata = context.get("freshness_metadata", {}) if isinstance(context, dict) else {}
    context_head = ""
    if isinstance(metadata, dict):
        context_head = str(metadata.get("initial_after_start_replay_round") or metadata.get("baseline_head") or "").strip()

    if args.require_fresh_head:
        if not audit_head or not context_head or audit_head != context_head:
            issues.append("context_index_stale_or_incomplete")

    families = family_ids(context)
    for family in args.require_family:
        if family not in families:
            issues.append(f"required_family_missing:{family}")

    if not context.get("real_entry_candidates"):
        issues.append("real_entry_candidates_missing")
    if not context.get("allowed_test_harness_modules"):
        issues.append("allowed_test_harness_modules_missing")
    if not context.get("forbidden_test_annotations"):
        issues.append("forbidden_test_annotations_missing")

    result = {
        "status": "PASS" if not issues else "FAIL",
        "root": str(root),
        "context": str(context_path),
        "audit_head": audit_head,
        "context_head": context_head,
        "families": families,
        "issues": issues,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
