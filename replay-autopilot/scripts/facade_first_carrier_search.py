#!/usr/bin/env python3
"""
Facade-First Carrier Selection (Experiment 1)

Requires existing Facade carriers before allowing NEW services.
This addresses the 'wrong_test_surface' gap by enforcing architectural layer requirements.
"""

import sys
import re
import subprocess
import json
from pathlib import Path
from typing import List, Dict, Optional, Tuple, Set


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
}


def classify_layer(classpath: str) -> str:
    """Classify a Java class path into its architectural layer."""
    for layer, pattern in LAYERS.items():
        if re.search(pattern, classpath):
            return layer
    return "Unknown"


def run_rg_search(pattern: str, search_root: Path, file_pattern: str = "java") -> List[str]:
    """Run ripgrep search and return matching files"""
    try:
        result = subprocess.run(
            ['rg', '-l', pattern, str(search_root), '-t', file_pattern],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            matches = result.stdout.strip().split('\n')
            return [m for m in matches if m]

    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return []


def search_facades_for_family(
    families: List[Dict],
    worktree: Path,
    max_facades: int = 50
) -> Tuple[List[Dict], List[str]]:
    """
    Search for existing Facade carriers that can serve the requirement families.

    Returns: (matching_facades, all_facades_checked)
    """
    facade_pattern = r"class.*Facade.*java"
    service_root = worktree

    # Find all Facade files
    facade_files = run_rg_search(facade_pattern, service_root)

    if not facade_files:
        return [], []

    # Limit search to avoid excessive checking
    if len(facade_files) > max_facades:
        facade_files = facade_files[:max_facades]

    facades_checked = []
    matching_facades = []

    for facade_path in facade_files:
        try:
            facade_file = Path(facade_path)
            if not facade_file.exists():
                continue

            content = facade_file.read_text(encoding='utf-8', errors='ignore')

            # Extract class name
            class_match = re.search(r'public\s+(?:class|interface)\s+(\w+Facade)', content)
            if not class_match:
                continue

            class_name = class_match.group(1)
            facades_checked.append(class_name)

            # Check if facade matches any family requirements
            # Extract methods to check capability
            methods = extract_public_methods(content)

            facade_info = {
                "classpath": facade_path,
                "class_name": class_name,
                "layer": "Facade",
                "methods": methods[:20]  # First 20 methods
            }

            # Check if facade can serve any of the target families
            for family in families:
                family_id = family.get("id", "")
                if family_id == "core_entry":
                    # Facade is preferred for core_entry
                    matching_facades.append(facade_info)
                    break

        except Exception as e:
            continue

    return matching_facades, facades_checked


def search_controllers_for_family(
    families: List[Dict],
    worktree: Path,
    max_controllers: int = 50
) -> Tuple[List[Dict], List[str]]:
    """Search for existing Controller carriers."""
    controller_pattern = r"class.*Controller.*java"
    controller_files = run_rg_search(controller_pattern, worktree)

    if not controller_files:
        return [], []

    if len(controller_files) > max_controllers:
        controller_files = controller_files[:max_controllers]

    controllers_checked = []
    matching_controllers = []

    for controller_path in controller_files:
        try:
            controller_file = Path(controller_path)
            if not controller_file.exists():
                continue

            content = controller_file.read_text(encoding='utf-8', errors='ignore')

            class_match = re.search(r'public\s+(?:class|interface)\s+(\w+Controller)', content)
            if not class_match:
                continue

            class_name = class_match.group(1)
            controllers_checked.append(class_name)

            methods = extract_public_methods(content)

            controller_info = {
                "classpath": controller_path,
                "class_name": class_name,
                "layer": "Controller",
                "methods": methods[:20]
            }

            for family in families:
                family_id = family.get("id", "")
                if family_id == "core_entry" or family_id == "deploy_export_page":
                    matching_controllers.append(controller_info)
                    break

        except Exception:
            continue

    return matching_controllers, controllers_checked


def extract_public_methods(content: str) -> List[str]:
    """Extract public method signatures from Java class content."""
    methods = []
    method_pattern = re.compile(
        r'public\s+(?:static\s+)?(?:abstract\s+)?(?:[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)',
        re.MULTILINE
    )

    for match in method_pattern.finditer(content):
        method_name = match.group(1)
        params = match.group(2).strip()

        # Skip getters/setters and common Object methods
        if method_name.startswith('get') or method_name.startswith('set') or method_name.startswith('is'):
            continue
        if method_name in ['equals', 'hashCode', 'toString']:
            continue

        methods.append(f"{method_name}({params})")

    return methods


def generate_facade_insufficiency_justification(
    facades_checked: List[str],
    families: List[Dict],
    worktree: Path
) -> Dict:
    """
    Generate justification for why existing Facades are insufficient.

    This is required when proposing a NEW service for core_entry family.
    """
    return {
        "all_facades_checked": facades_checked,
        "total_facades_checked": len(facades_checked),
        "target_families": [f.get("id") for f in families],
        "insufficiency_reasons": [
            f"No existing Facade matches requirement for family {f.get('id')}"
            for f in families
        ],
        "orphan_feature": True
    }


def validate_facade_first_selection(
    selected_carriers: List[Dict],
    families: List[Dict],
    worktree: Path
) -> Dict:
    """
    Validate that carrier selection follows Facade-First priority.

    Rules:
    1. For core_entry family, MUST select from Facade or Controller layer
    2. NEW service selection requires explicit justification with all_facades_checked
    3. Facade/Controller carriers take priority over Service layer
    """
    issues = []

    # Check each selected carrier
    for carrier in selected_carriers:
        classpath = carrier.get("classpath", "")
        target_family = carrier.get("target_family", "")
        carrier_type = carrier.get("carrier_type", "EXISTING")  # EXISTING or NEW

        layer = classify_layer(classpath)
        required_layers = FAMILY_LAYER_REQUIREMENTS.get(target_family, ["Facade", "Controller", "Service"])

        # Rule 1: core_entry must use Facade or Controller
        if target_family == "core_entry":
            if layer not in ["Facade", "Controller"]:
                if carrier_type == "NEW":
                    # NEW service for core_entry requires justification
                    all_facades_checked = carrier.get("all_facades_checked", [])
                    if not all_facades_checked or len(all_facades_checked) == 0:
                        issues.append({
                            "code": "facade_exists_check",
                            "carrier": classpath,
                            "target_family": target_family,
                            "reason": "NEW service for core_entry without listing all existing Facades",
                            "required_evidence": [
                                "all_facades_checked: list of all *Facade.java files matching feature keywords",
                                "facade_insufficiency_reason: explanation for each Facade why insufficient"
                            ]
                        })
                else:
                    # EXISTING carrier in wrong layer
                    issues.append({
                        "code": "wrong_layer_for_family",
                        "carrier": classpath,
                        "current_layer": layer,
                        "required_layers": required_layers,
                        "target_family": target_family
                    })

    return {
        "valid": len(issues) == 0,
        "issues": issues,
        "carriers_validated": len(selected_carriers)
    }


def search_carriers_with_facade_first(
    families: List[Dict],
    worktree: Path
) -> Dict:
    """
    Search for carriers following Facade-First priority order.

    Priority:
    1. EXISTING FACADE CARRIERS (highest priority)
    2. EXISTING CONTROLLER CARRIERS
    3. NEW SERVICE (last resort, requires justification)
    """
    result = {
        "search_order_followed": True,
        "facades_found": [],
        "controllers_found": [],
        "recommendation": "",
        "selected_carriers": []
    }

    # Step 1: Search for Facade carriers
    matching_facades, all_facades = search_facades_for_family(families, worktree)
    result["facades_found"] = matching_facades
    result["all_facades_checked"] = all_facades

    if matching_facades:
        result["recommendation"] = "USE_EXISTING_FACADE"
        result["selected_carriers"] = matching_facades
        result["justification"] = f"Found {len(matching_facades)} existing Facade carriers"
        return result

    # Step 2: Search for Controller carriers
    matching_controllers, all_controllers = search_controllers_for_family(families, worktree)
    result["controllers_found"] = matching_controllers
    result["all_controllers_checked"] = all_controllers

    if matching_controllers:
        result["recommendation"] = "USE_EXISTING_CONTROLLER"
        result["selected_carriers"] = matching_controllers
        result["justification"] = f"Found {len(matching_controllers)} existing Controller carriers"
        return result

    # Step 3: Recommend NEW service with justification
    result["recommendation"] = "PROPOSE_NEW_SERVICE"
    result["justification"] = generate_facade_insufficiency_justification(
        all_facades, families, worktree
    )
    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: facade_first_carrier_search.py <command> [args...]", file=sys.stderr)
        print("Commands:", file=sys.stderr)
        print("  search <worktree> <families_json>", file=sys.stderr)
        print("  validate <selected_carriers_json> <families_json> <worktree>", file=sys.stderr)
        print("  classify <classpath>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "search":
        if len(sys.argv) < 4:
            print("Usage: facade_first_carrier_search.py search <worktree> <families_json>", file=sys.stderr)
            sys.exit(1)

        worktree = Path(sys.argv[2])
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            families = json.load(f)

        result = search_carriers_with_facade_first(families, worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

    elif command == "validate":
        if len(sys.argv) < 5:
            print("Usage: facade_first_carrier_search.py validate <selected_carriers_json> <families_json> <worktree>", file=sys.stderr)
            sys.exit(1)

        with open(sys.argv[2], 'r', encoding='utf-8') as f:
            selected_carriers = json.load(f)
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            families = json.load(f)
        worktree = Path(sys.argv[4])

        result = validate_facade_first_selection(selected_carriers, families, worktree)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        if not result.get("valid"):
            sys.exit(1)

    elif command == "classify":
        if len(sys.argv) < 3:
            print("Usage: facade_first_carrier_search.py classify <classpath>", file=sys.stderr)
            sys.exit(1)

        classpath = sys.argv[2]
        layer = classify_layer(classpath)
        print(json.dumps({"classpath": classpath, "layer": layer}, ensure_ascii=False))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
