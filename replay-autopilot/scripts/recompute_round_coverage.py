#!/usr/bin/env python3
"""Recompute round coverage only from verifier-closed requirement families."""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List


SLICE_VERIFY_RE = re.compile(r"^SLICE_VERIFY_\d+\.json$")


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


def extract_round_status(text: str) -> str:
    patterns = [
        r"(?im)^\s*-?\s*final[_ ]status\s*[:=]\s*`?([A-Z_]+)`?",
        r"(?im)^\s*-?\s*status\s*[:=]\s*`?([A-Z_]+)`?",
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(1).strip().upper()
    return ""


def read_coverage_cap(root: Path) -> int:
    router_path = root / "FAMILY_ROUTER_AND_CAP.json"
    if router_path.exists():
        try:
            router = read_json(router_path)
            cap = as_int(router.get("coverage_cap_from_ledger"))
            if cap > 0:
                return cap
        except Exception:
            pass

    ledger_path = root / "REQUIREMENT_FAMILY_LEDGER.json"
    if ledger_path.exists():
        try:
            ledger = read_json(ledger_path)
            cap = as_int(ledger.get("coverage_cap"))
            if cap > 0:
                return cap
        except Exception:
            pass

    return 100


def recompute(root: Path) -> Dict[str, Any]:
    verifies = []
    blockers: List[str] = []
    non_authorizing_verifies: List[str] = []
    closed_families = set()
    authorized_for_synthesis = True
    adjusted_total = 0
    coverage_cap = read_coverage_cap(root)

    for path in sorted(path for path in root.glob("SLICE_VERIFY_*.json") if SLICE_VERIFY_RE.match(path.name)):
        verify = read_json(path)
        verifies.append(path.name)
        if not as_bool(verify.get("authorized_for_synthesis")):
            authorized_for_synthesis = False
            non_authorizing_verifies.append(path.name)
            blockers.append(f"authorized_for_synthesis=false:{path.name}")
        families = [str(item).strip() for item in verify.get("closed_requirement_families", []) if str(item).strip()]
        if not families:
            blockers.append(f"closed_requirement_families_empty:{path.name}")
        for family in families:
            closed_families.add(family)
        adjusted_total += as_int(verify.get("adjusted_coverage_delta"))

    if adjusted_total < 0:
        adjusted_total = 0
    recomputed_capped = min(adjusted_total, coverage_cap)

    round_path = root / "ROUND_RESULT.md"
    reported = {}
    if round_path.exists():
        text = round_path.read_text(encoding="utf-8", errors="ignore")
        reported = {
            "blind_self_assessed_coverage": extract_round_metric(text, "blind_self_assessed_coverage"),
            "verification_capped_coverage": extract_round_metric(text, "verification_capped_coverage"),
            "final_status": extract_round_status(text),
        }

    return {
        "status": "PASS",
        "root": str(root),
        "slice_verifies": verifies,
        "authorized_for_synthesis": authorized_for_synthesis,
        "non_authorizing_slice_verifies": non_authorizing_verifies,
        "closed_requirement_families": sorted(closed_families),
        "recomputed_adjusted_coverage": adjusted_total,
        "coverage_cap_from_ledger": coverage_cap,
        "recomputed_verification_capped_coverage": recomputed_capped,
        "reported": reported,
        "blockers": blockers,
        "coverage_counting_mode": "verifier_adjusted_partial_progress",
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
        reported = result["reported"]
        reported_blind = as_int(reported.get("blind_self_assessed_coverage"))
        reported_capped = as_int(reported.get("verification_capped_coverage"))
        reported_status = str(reported.get("final_status") or "").upper()
        recomputed_capped = as_int(result["recomputed_verification_capped_coverage"])
        if reported_status in {"PASS", "DONE"}:
            issues.append("synthesis_authorization_missing_for_pass")
        if reported_blind >= 90 or reported_capped >= 90:
            issues.append("coverage_target_without_synthesis_authorization")
        if reported_capped > recomputed_capped:
            issues.append("reported_coverage_exceeds_verifier_adjusted")
    if issues:
        result["status"] = "FAIL"
        result["issues"] = issues

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if result["status"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
