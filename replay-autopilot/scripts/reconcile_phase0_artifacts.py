#!/usr/bin/env python3
"""
Contract Reconciliation Pipeline - Phase 0 Artifact Cross-Validation

This script validates that REQUIREMENT_FAMILY_LEDGER.json and FAMILY_CONTRACT.json
do not contradict each other before Phase 1 begins.

Experiment 1 from NEXT_EXPERIMENT_PLAN.md - addresses v318's contract contradiction blocker.
"""

import json
import sys
from typing import Dict, Any, Optional


def load_json(path: str) -> Dict:
    """Load JSON file safely."""
    try:
        with open(path, 'r', encoding='utf-8-sig') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in {path}: {e}", file=sys.stderr)
        sys.exit(1)


def family_name_from_item(item: Any, fallback: Optional[str] = None) -> Optional[str]:
    """Return a stable family key from either legacy name or newer id fields."""
    if isinstance(item, dict):
        for key in ('name', 'id', 'family', 'family_name', 'familyName'):
            value = item.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()

    if isinstance(fallback, str) and fallback.strip():
        return fallback.strip()

    return None


def normalize_families(raw: Any) -> Dict[str, Dict[str, Any]]:
    """
    Normalize Phase 0 family payloads.

    Older artifacts use {"families": {"core": {...}}}; newer planner output often
    uses {"families": [{"id": "core", ...}]}. Reconciliation should validate the
    contract content, not fail because the carrier shape changed.
    """
    families: Dict[str, Dict[str, Any]] = {}

    if isinstance(raw, dict):
        for fallback_name, value in raw.items():
            if isinstance(value, dict):
                name = family_name_from_item(value, str(fallback_name))
                if name:
                    families[name] = value
            elif isinstance(fallback_name, str) and fallback_name.strip():
                families[fallback_name.strip()] = {'value': value}

    elif isinstance(raw, list):
        for value in raw:
            if isinstance(value, dict):
                name = family_name_from_item(value)
                if name:
                    families[name] = value
            elif isinstance(value, str) and value.strip():
                families[value.strip()] = {'name': value.strip()}

    return families


def reconcile_contracts(ledger_path: str, contract_path: str) -> Dict[str, Any]:
    """
    Reconcile REQUIREMENT_FAMILY_LEDGER.json with FAMILY_CONTRACT.json.

    Detects contradictions where:
    - Ledger says family is required, but Contract says NOT_APPLICABLE
    - Ledger says family is not required, but Contract has applicable blockers
    """
    ledger = load_json(ledger_path)
    contract = load_json(contract_path)

    contradictions = []
    warnings = []
    resolved = []

    # Extract families from ledger and contract. Both artifacts may use either a
    # dict keyed by family name or a list of objects with id/name fields.
    ledger_families = normalize_families(ledger.get('families')) if isinstance(ledger, dict) else {}
    contract_families = normalize_families(contract.get('families')) if isinstance(contract, dict) else {}

    # Check all families in ledger
    for family_name, ledger_data in ledger_families.items():
        ledger_required = ledger_data.get('required', False)
        ledger_status = ledger_data.get('status', 'UNKNOWN')
        ledger_weight = ledger_data.get('weight', 0)

        contract_data = contract_families.get(family_name, {})
        contract_blocker = contract_data.get('blocker', '')
        contract_applicable = contract_blocker != 'NOT_APPLICABLE'

        # Case 1: Ledger requires family, but Contract says NOT_APPLICABLE
        if ledger_required and not contract_applicable:
            contradictions.append({
                'family': family_name,
                'issue': 'ledger_required_but_contract_not_applicable',
                'ledger_status': ledger_status,
                'ledger_weight': ledger_weight,
                'contract_blocker': contract_blocker,
                'severity': 'HIGH',
                'resolution': 'remove_from_ledger'
            })

        # Case 2: Ledger doesn't require family, but Contract says applicable with weight
        elif not ledger_required and contract_applicable and ledger_weight > 0:
            contradictions.append({
                'family': family_name,
                'issue': 'contract_required_but_ledger_not_required',
                'ledger_status': ledger_status,
                'ledger_weight': ledger_weight,
                'contract_blocker': contract_blocker,
                'severity': 'MEDIUM',
                'resolution': 'add_to_ledger'
            })

        # Case 3: Family in contract but not in ledger (warning)
        elif family_name not in ledger_families and contract_applicable:
            warnings.append({
                'family': family_name,
                'issue': 'family_in_contract_but_missing_from_ledger',
                'contract_blocker': contract_blocker,
                'severity': 'LOW'
            })

    # Check for families in contract that have production carriers but missing from ledger
    for family_name, contract_data in contract_families.items():
        if family_name not in ledger_families:
            blocker = contract_data.get('blocker', '')
            if blocker and blocker != 'NOT_APPLICABLE':
                warnings.append({
                    'family': family_name,
                    'issue': 'contract_family_not_in_ledger',
                    'blocker': blocker,
                    'severity': 'LOW'
                })

    # Calculate metrics
    total_families = len(ledger_families)
    contradiction_count = len(contradictions)
    warning_count = len(warnings)

    result = {
        'status': 'PASS' if contradiction_count == 0 else 'RESOLVE',
        'total_families_checked': total_families,
        'contradiction_count': contradiction_count,
        'contradiction_rate': round(contradiction_count / total_families * 100, 1) if total_families > 0 else 0,
        'warning_count': warning_count,
        'contradictions': contradictions,
        'warnings': warnings,
        'summary': {
            'high_severity': len([c for c in contradictions if c.get('severity') == 'HIGH']),
            'medium_severity': len([c for c in contradictions if c.get('severity') == 'MEDIUM']),
            'low_severity': len([c for c in contradictions if c.get('severity') == 'LOW'])
        }
    }

    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: reconcile_phase0_artifacts.py <ledger.json> <contract.json> [--output output.json]", file=sys.stderr)
        sys.exit(1)

    ledger_path = sys.argv[1]
    contract_path = sys.argv[2]

    result = reconcile_contracts(ledger_path, contract_path)

    # Output to file if specified
    if '--output' in sys.argv:
        output_idx = sys.argv.index('--output')
        if output_idx + 1 < len(sys.argv):
            output_path = sys.argv[output_idx + 1]
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(result, f, indent=2)
            print(f"Reconciliation result written to {output_path}", file=sys.stderr)

    # Always print to stdout for parsing
    print(json.dumps(result, indent=2))

    # Exit with error if contradictions found
    if result['status'] == 'RESOLVE':
        print(f"RECONCILIATION_FAILED: {result['contradiction_count']} contradictions detected", file=sys.stderr)
        sys.exit(1)

    return 0


if __name__ == '__main__':
    main()
