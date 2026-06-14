#!/usr/bin/env python3
"""
Carrier Search Requirement

Before creating new service classes, search for existing carriers
and verify they cannot serve the use case before creating new ones.
"""

import sys
import re
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Tuple


def run_rg_search(pattern: str, search_root: Path, file_pattern: str = "*.java") -> List[str]:
    """Run ripgrep search and return matching files"""
    try:
        result = subprocess.run(
            ['rg', '-l', pattern, str(search_root), '-t', 'java'],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            matches = result.stdout.strip().split('\n')
            return [m for m in matches if m]

    except (subprocess.TimeoutExpired, FileNotFoundError):
        # Fallback to manual search if rg not available
        pass

    return []


def search_service_classes(feature_name: str, project_root: Path) -> List[Path]:
    """
    Search for existing service classes related to feature

    Returns list of Java file paths
    """
    # Common search patterns
    patterns = [
        f"class.*{feature_name}Service",
        f"class.*{feature_name}Facade",
        f"interface.*{feature_name}Service",
        f"interface.*{feature_name}Facade",
    ]

    # Also search for common service patterns
    service_root = project_root / "claim-core" / "src" / "main" / "java"
    if not service_root.exists():
        return []

    found_files = []

    # Use ripgrep if available, fallback to glob
    for pattern in patterns:
        matches = run_rg_search(pattern, service_root)
        for match in matches:
            file_path = Path(match)
            if file_path.exists() and file_path not in found_files:
                found_files.append(file_path)

    # Fallback to glob search
    if not found_files:
        for java_file in service_root.rglob('*.java'):
            content = java_file.read_text(encoding='utf-8')
            for pattern in patterns:
                if re.search(pattern, content, re.IGNORECASE):
                    if java_file not in found_files:
                        found_files.append(java_file)
                    break

    return found_files


def analyze_service_capabilities(service_file: Path) -> Dict[str, str]:
    """
    Analyze service file to extract public methods and capabilities

    Returns dict with method signatures and brief descriptions
    """
    if not service_file.exists():
        return {}

    content = service_file.read_text(encoding='utf-8')

    # Extract public methods
    methods = []
    method_pattern = re.compile(
        r'public\s+(?:static\s+)?(?:[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)',
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

    return {
        'file': str(service_file),
        'class_name': service_file.stem,
        'methods': methods
    }


def check_carrier_adequacy(required_methods: List[str], existing_services: List[Dict]) -> Tuple[bool, str]:
    """
    Check if existing services can satisfy requirements

    Returns: (adequate, reason)
    """
    if not existing_services:
        return False, "No existing services found for this feature"

    required_lower = [m.lower() for m in required_methods]

    for service in existing_services:
        methods = service.get('methods', [])
        methods_lower = [m.lower() for m in methods]

        # Check if required methods are available
        matches = sum(1 for req in required_lower if any(req in meth for meth in methods_lower))

        if matches >= len(required_methods) * 0.5:  # 50% match threshold
            return True, f"Existing service {service['class_name']} has {matches}/{len(required_methods)} required methods"

    return False, f"Existing services inadequate: {[s['class_name'] for s in existing_services]}"


def main():
    if len(sys.argv) < 2:
        print("Usage: carrier_search.py <feature_name> [required_method1] [required_method2] ...")
        print("  Example: carrier_search.py Compensate rewriteData insertDetail")
        sys.exit(1)

    feature_name = sys.argv[1]
    required_methods = sys.argv[2:] if len(sys.argv) > 2 else []

    project_root = Path.cwd()
    # If in worktree, go to parent
    if (project_root / "worktree").exists():
        project_root = project_root / "worktree"
    elif project_root.name == "claim-codex-replay" or "autopilot" in project_root.name:
        # Try to find claim project root
        for parent in [project_root] + list(project_root.parents):
            if (parent / "pom.xml").exists():
                project_root = parent
                break

    print(f"Searching for existing carriers related to: {feature_name}")
    print(f"Project root: {project_root}")
    print("")

    existing_services = search_service_classes(feature_name, project_root)

    if not existing_services:
        print(f"RESULT: NO_EXISTING_CARRIER")
        print(f"No existing service classes found for feature: {feature_name}")
        print("Proceed with creating new service class.")
        sys.exit(0)

    print(f"Found {len(existing_services)} existing service(s):")
    print("")

    service_capabilities = []
    for service_file in existing_services:
        capabilities = analyze_service_capabilities(service_file)
        service_capabilities.append(capabilities)

        print(f"  File: {capabilities['file']}")
        print(f"  Class: {capabilities['class_name']}")
        print(f"  Methods ({len(capabilities['methods'])}):")
        for method in capabilities['methods'][:10]:  # First 10 methods
            print(f"    - {method}")
        if len(capabilities['methods']) > 10:
            print(f"    ... and {len(capabilities['methods']) - 10} more")
        print("")

    # Check adequacy if required methods specified
    if required_methods:
        adequate, reason = check_carrier_adequacy(required_methods, service_capabilities)

        if adequate:
            print(f"RESULT: CARRIER_ADEQUATE")
            print(f"Reason: {reason}")
            print("")
            print("Recommendation: Use existing service instead of creating new one.")
            sys.exit(1)  # Exit with error to indicate should NOT create new carrier
        else:
            print(f"RESULT: CARRIER_INADEQUATE")
            print(f"Reason: {reason}")
            print("")
            print("Proceed with creating new service class.")
            sys.exit(0)

    # If no required methods, just report findings
    print(f"RESULT: EXISTING_CARRIERS_FOUND")
    print("Review existing services above before creating new carrier.")
    sys.exit(0)


if __name__ == "__main__":
    main()
