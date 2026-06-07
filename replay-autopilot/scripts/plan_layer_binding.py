#!/usr/bin/env python3
"""
Phase 0 Layer Binding Validation (Experiment 2)

Validates carrier layer in IMPLEMENTATION_CONTRACT.md before Phase 1.
This moves layer validation earlier in the workflow to fail fast.
"""

import sys
import re
import json
from pathlib import Path
from typing import List, Dict, Optional


# Layer classification patterns
LAYERS = {
    "Facade": r".*Facade(\.java)?$",
    "Controller": r".*Controller(\.java)?$",
    "Service": r".*Service(\.java)?$",
    "Mapper": r".*Mapper(\.java)?$",
    "Dao": r".*Dao(\.java)?$",
    "Unknown": r".*"
}

# Family layer requirements
FAMILY_LAYER_REQUIREMENTS = {
    "core_entry": ["Facade", "Controller"],
    "stateful_side_effect": ["Service", "Facade"],
    "config_policy_threshold": ["Service", "Facade"],
    "deploy_export_page": ["Controller", "Facade"],
    "wire_payload_api_contract": ["Service", "Facade"],
}


class PlanningError(Exception):
    """Raised when planning contract validation fails."""
    pass


def classify_layer(classpath: str) -> str:
    """Classify a Java class path into its architectural layer."""
    if not classpath:
        return "Unknown"

    # Extract class name from full path
    # Handle both paths (com/example/MyFacade.java) and class names (MyFacade)
    if '/' in classpath or '\\' in classpath:
        # It's a file path
        class_name = Path(classpath).stem
    else:
        # It's a class name
        class_name = classpath

    for layer, pattern in LAYERS.items():
        if re.search(pattern, class_name):
            return layer
    return "Unknown"


def validate_plan_contract(
    contract_path: Path,
    families: List[Dict]
) -> Dict:
    """
    Validate that plan contract specifies correct layer for each carrier.

    Contract must include:
    - selected_carriers[].classpath
    - selected_carriers[].target_family
    - selected_carriers[].target_layer (MUST be one of allowed layers)
    - selected_carriers[].layer_justification
    """
    if not contract_path.exists():
        return {
            "status": "FAIL",
            "reason": "contract_not_found",
            "path": str(contract_path)
        }

    # Read contract
    try:
        if contract_path.suffix == '.json':
            with open(contract_path, 'r', encoding='utf-8') as f:
                contract = json.load(f)
        else:
            # Try to parse markdown
            with open(contract_path, 'r', encoding='utf-8') as f:
                content = f.read()

            # Extract selected_carriers section
            contract = extract_carriers_from_markdown(content)
    except Exception as e:
        return {
            "status": "FAIL",
            "reason": "contract_parse_error",
            "error": str(e)
        }

    selected_carriers = contract.get("selected_carriers", [])
    if not selected_carriers:
        return {
            "status": "FAIL",
            "reason": "no_carriers_selected",
            "message": "IMPLEMENTATION_CONTRACT.md must specify selected_carriers"
        }

    validation_issues = []
    validated_carriers = []

    for carrier in selected_carriers:
        classpath = carrier.get("classpath", "")
        target_family = carrier.get("target_family", "")
        target_layer = carrier.get("target_layer", "")
        layer_justification = carrier.get("layer_justification", "")

        # Validate target_layer is specified
        if not target_layer:
            validation_issues.append({
                "code": "target_layer_missing",
                "carrier": classpath,
                "target_family": target_family,
                "message": "target_layer field is required (must be one of: Facade, Controller, Service, Mapper, Dao)"
            })
            continue

        # Validate target_layer is a recognized layer
        if target_layer not in LAYERS.keys():
            validation_issues.append({
                "code": "invalid_target_layer",
                "carrier": classpath,
                "target_layer": target_layer,
                "valid_layers": list(LAYERS.keys()),
                "message": f"target_layer must be one of: {', '.join(LAYERS.keys())}"
            })
            continue

        # Validate target_layer matches classpath
        inferred_layer = classify_layer(classpath)
        if inferred_layer != "Unknown" and inferred_layer != target_layer:
            validation_issues.append({
                "code": "layer_mismatch",
                "carrier": classpath,
                "inferred_layer": inferred_layer,
                "specified_layer": target_layer,
                "message": f"Classpath suggests {inferred_layer} layer but specified as {target_layer}"
            })

        # Validate target_layer is allowed for target_family
        allowed_layers = FAMILY_LAYER_REQUIREMENTS.get(
            target_family,
            ["Facade", "Controller", "Service"]
        )

        if target_layer not in allowed_layers:
            validation_issues.append({
                "code": "layer_not_allowed_for_family",
                "carrier": classpath,
                "target_family": target_family,
                "target_layer": target_layer,
                "allowed_layers": allowed_layers,
                "message": f"Family {target_family} requires one of: {', '.join(allowed_layers)}"
            })
            continue

        # Validate layer_justification is present
        if not layer_justification:
            validation_issues.append({
                "code": "layer_justification_missing",
                "carrier": classpath,
                "message": "layer_justification is required to explain why this layer is appropriate"
            })
            continue

        validated_carriers.append({
            "classpath": classpath,
            "target_family": target_family,
            "target_layer": target_layer,
            "layer_justification": layer_justification
        })

    if validation_issues:
        return {
            "status": "FAIL",
            "reason": "layer_validation_failed",
            "issues": validation_issues,
            "validated_count": len(validated_carriers),
            "total_count": len(selected_carriers)
        }

    return {
        "status": "PASS",
        "validated_carriers": len(validated_carriers),
        "carriers": validated_carriers
    }


def extract_carriers_from_markdown(content: str) -> Dict:
    """Extract selected_carriers from markdown IMPLEMENTATION_CONTRACT.md."""
    carriers = []

    # Try to find selected_carriers in JSON format
    json_match = re.search(r'selected_carriers\s*=\s*(\[.*?\])', content, re.DOTALL)
    if json_match:
        try:
            carriers = json.loads(json_match.group(1))
        except:
            pass

    # Try table format
    if not carriers:
        table_match = re.search(
            r'\|\s*classpath\s*\|\s*target_family\s*\|\s*target_layer.*?\n((?:\|.*?\|.*?\|.*?\|.*?\n)+)',
            content,
            re.MULTILINE
        )
        if table_match:
            for row in table_match.group(1).strip().split('\n'):
                if '|' not in row:
                    continue
                parts = [p.strip() for p in row.split('|')[1:-1]]  # Skip empty first/last
                if len(parts) >= 3:
                    carriers.append({
                        "classpath": parts[0],
                        "target_family": parts[1],
                        "target_layer": parts[2],
                        "layer_justification": parts[3] if len(parts) > 3 else ""
                    })

    return {"selected_carriers": carriers}


def validate_phase0_before_phase1(
    plan_result_path: Path,
    worktree: Path
) -> Dict:
    """
    Validate plan contract before allowing Phase 1 to proceed.

    This is called during Phase 0 preflight to fail fast on layer violations.
    """
    # Try to find IMPLEMENTATION_CONTRACT.md
    contract_path = plan_result_path.parent / "IMPLEMENTATION_CONTRACT.md"

    if not contract_path.exists():
        contract_path = plan_result_path.parent / "IMPLEMENTATION_CONTRACT.json"

    if not contract_path.exists():
        return {
            "status": "WARN",
            "reason": "contract_not_found",
            "message": "IMPLEMENTATION_CONTRACT.md not found, skipping layer validation"
        }

    # Read plan to extract families
    families = []
    try:
        if plan_result_path.suffix == '.json':
            with open(plan_result_path, 'r', encoding='utf-8') as f:
                plan = json.load(f)
        else:
            with open(plan_result_path, 'r', encoding='utf-8') as f:
                content = f.read()

            # Extract families from markdown
            families_match = re.search(r'target_families.*?[:=]\s*(\[.*?\])', content, re.DOTALL)
            if families_match:
                try:
                    families = json.loads(families_match.group(1))
                except:
                    pass

    except Exception as e:
        families = []

    # Validate contract
    return validate_plan_contract(contract_path, families)


def main():
    if len(sys.argv) < 2:
        print("Usage: plan_layer_binding.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  validate <contract_path> <families_json>", file=sys.stderr)
        print("  validate-phase0 <plan_result_path> <worktree>", file=sys.stderr)
        print("  classify <classpath>", file=sys.stderr)
        print("  check-family <family_id>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "validate":
        if len(sys.argv) < 4:
            print("Usage: plan_layer_binding.py validate <contract_path> <families_json>", file=sys.stderr)
            sys.exit(1)

        contract_path = Path(sys.argv[2])
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            families = json.load(f)

        result = validate_plan_contract(contract_path, families)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if result.get("status") == "FAIL":
            sys.exit(1)

    elif command == "validate-phase0":
        if len(sys.argv) < 4:
            print("Usage: plan_layer_binding.py validate-phase0 <plan_result_path> <worktree>", file=sys.stderr)
            sys.exit(1)

        plan_result_path = Path(sys.argv[2])
        worktree = Path(sys.argv[3])

        result = validate_phase0_before_phase1(plan_result_path, worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if result.get("status") == "FAIL":
            sys.exit(1)

    elif command == "classify":
        if len(sys.argv) < 3:
            print("Usage: plan_layer_binding.py classify <classpath>", file=sys.stderr)
            sys.exit(1)

        classpath = sys.argv[2]
        layer = classify_layer(classpath)
        print(json.dumps({"classpath": classpath, "layer": layer}, ensure_ascii=False))

    elif command == "check-family":
        if len(sys.argv) < 3:
            print("Usage: plan_layer_binding.py check-family <family_id>", file=sys.stderr)
            sys.exit(1)

        family_id = sys.argv[2]
        allowed_layers = FAMILY_LAYER_REQUIREMENTS.get(family_id, ["Facade", "Controller", "Service"])
        print(json.dumps({
            "family": family_id,
            "allowed_layers": allowed_layers
        }, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
