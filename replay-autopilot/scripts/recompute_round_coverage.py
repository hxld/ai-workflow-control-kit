#!/usr/bin/env python3
"""Recompute round coverage only from verifier-closed requirement families."""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def as_int(value: Any) -> int:
    try:
        return int(value)
    except Exception:
        return 0


def extract_round_metric(text: str, name: str) -> int:
    pattern = re.compile(rf"(?im)^\s*-?\s*{re.escape(name)}\s*:\s*([0-9]{{1,3}})")
    match = pattern.search(text)
    if not match:
        return 0
    return int(match.group(1))


def recompute(root: Path) -> Dict[str, Any]:
    verifies = []
    blockers: List[str] = []
    closed_families = set()
    authorized_for_synthesis = True
    adjusted_total = 0

    for path in sorted(root.glob("SLICE_VERIFY_*.json")):
        verify = read_json(path)
        verifies.append(path.name)
        if not as_bool(verify.get("authorized_for_synthesis")):
            authorized_for_synthesis = False
            blockers.append(f"authorized_for_synthesis=false:{path.name}")
            continue
        families = [str(item).strip() for item in verify.get("closed_requirement_families", []) if str(item).strip()]
        if not families:
            blockers.append(f"closed_requirement_families_empty:{path.name}")
            continue
        for family in families:
            closed_families.add(family)
        adjusted_total += as_int(verify.get("adjusted_coverage_delta"))

    if not authorized_for_synthesis or not closed_families:
        adjusted_total = 0

    round_path = root / "ROUND_RESULT.md"
    reported = {}
    if round_path.exists():
        text = round_path.read_text(encoding="utf-8", errors="ignore")
        reported = {
            "blind_self_assessed_coverage": extract_round_metric(text, "blind_self_assessed_coverage"),
            "verification_capped_coverage": extract_round_metric(text, "verification_capped_coverage"),
        }

    return {
        "status": "PASS",
        "root": str(root),
        "slice_verifies": verifies,
        "authorized_for_synthesis": authorized_for_synthesis,
        "closed_requirement_families": sorted(closed_families),
        "recomputed_adjusted_coverage": adjusted_total,
        "reported": reported,
        "blockers": blockers,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--require-closed-family", action="store_true")
    parser.add_argument("--fail-on-positive-without-synthesis", action="store_true")
    args = parser.parse_args()

    root = Path(args.root)
    result = recompute(root)
    issues: List[str] = []
    if args.require_closed_family and not result["closed_requirement_families"]:
        issues.append("closed_requirement_families_empty")
    if args.fail_on_positive_without_synthesis and not result["authorized_for_synthesis"]:
        reported_positive = any(as_int(v) > 0 for v in result["reported"].values())
        if reported_positive or result["recomputed_adjusted_coverage"] > 0:
            issues.append("positive_coverage_without_synthesis_authorization")
    if issues:
        result["status"] = "FAIL"
        result["issues"] = issues

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if result["status"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
