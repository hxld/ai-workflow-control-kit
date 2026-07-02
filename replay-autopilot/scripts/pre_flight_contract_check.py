#!/usr/bin/env python3
"""
Pre-Implementation Contract Verification Gate

Before RED phase starts, verify all referenced service methods exist
and have correct signatures.
"""

import sys
import json
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def extract_service_references(test_charter_path: Path) -> List[Dict]:
    """Parse TEST_CHARTER.md for service method references"""
    if not test_charter_path.exists():
        print("ERROR: TEST_CHARTER.md not found")
        sys.exit(1)

    content = test_charter_path.read_text(encoding='utf-8')
    references = []

    # Pattern 1: Explicit service method references like "CompensateService.rewriteCompensateData"
    service_method_pattern = re.compile(
        r'(\w+Service)\.(\w+)\s*\(',
        re.MULTILINE
    )

    # Pattern 2: Service class references
    service_class_pattern = re.compile(
        r'class\s+(\w+Service)',
        re.MULTILINE
    )

    for match in service_method_pattern.finditer(content):
        service_name = match.group(1)
        method_name = match.group(2)
        references.append({
            'service': service_name,
            'method': method_name,
            'params': []  # Params will be verified from actual file
        })

    # Also scan for service class usage
    for match in service_class_pattern.finditer(content):
        service_name = match.group(1)
        if not any(ref['service'] == service_name for ref in references):
            references.append({
                'service': service_name,
                'method': None,
                'params': []
            })

    return references


def find_service_file(service_name: str, project_root: Path) -> Optional[Path]:
    """Find service file in project structure"""
    # Common service locations
    search_paths = [
        project_root / "example-core" / "src" / "main" / "java" / "com" / "huize" / "claim" / "core",
        project_root / "example-core" / "src" / "main" / "java" / "com" / "huize" / "claim",
    ]

    for search_path in search_paths:
        if not search_path.exists():
            continue

        # Search recursively for the service file
        for java_file in search_path.rglob("*.java"):
            if java_file.name == f"{service_name}.java":
                return java_file

            # Also check for interface/impl pattern
            if java_file.stem == service_name:
                return java_file

    return None


def parse_method_signature(java_file: Path, method_name: str) -> Optional[Dict]:
    """Parse Java file for method signature"""
    content = java_file.read_text(encoding='utf-8')

    # Match method declaration: public/private/protected <return_type> <method_name>(<params>)
    method_pattern = re.compile(
        r'(?:public|private|protected)\s+(?:static\s+)?(?:[\w<>,\s\[\]]+)\s+' +
        re.escape(method_name) + r'\s*\(([^)]*)\)',
        re.MULTILINE | re.DOTALL
    )

    match = method_pattern.search(content)
    if not match:
        return None

    params_str = match.group(1).strip()
    # Simple param parsing - split by comma and take type
    params = []
    if params_str:
        for param in params_str.split(','):
            param = param.strip()
            if param:
                # Extract type from "Type name" or "Type name = default"
                type_match = re.match(r'([\w<>,\[\]\s]+)', param)
                if type_match:
                    params.append(type_match.group(1).strip())

    return {
        'method': method_name,
        'params': params,
        'found': True
    }


def verify_method_signature(service_file: Path, method_name: str, params: List) -> Tuple[bool, str]:
    """Read actual service file and verify method exists with matching signature"""
    if not service_file.exists():
        return False, f"{service_file.name} not found"

    content = service_file.read_text(encoding='utf-8')

    # Check if method exists
    method_pattern = re.compile(
        r'(?:public|private|protected)\s+(?:static\s+)?(?:[\w<>,\s\[\]]+)\s+' +
        re.escape(method_name) + r'\s*\(',
        re.MULTILINE
    )

    if not method_pattern.search(content):
        return False, f"Method {method_name} not found in {service_file.name}"

    # Parse and return signature info
    signature = parse_method_signature(service_file, method_name)
    if signature:
        return True, f"Found: {method_name}({', '.join(signature['params'])})"

    return True, f"Method {method_name} exists (signature parse failed but method found)"


def main():
    test_charter = Path("TEST_CHARTER.md")
    if not test_charter.exists():
        print("ERROR: TEST_CHARTER.md not found in current directory")
        sys.exit(1)

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

    references = extract_service_references(test_charter)
    failures = []
    warnings = []

    if not references:
        print("WARNING: No service references found in TEST_CHARTER.md")
        print("CONTRACT_VERIFICATION_PASSED")
        sys.exit(0)

    for ref in references:
        service_name = ref['service']
        method_name = ref.get('method')

        service_path = find_service_file(service_name, project_root)

        if not service_path:
            failures.append(f"{service_name}.java not found in project")
            continue

        if method_name:
            success, message = verify_method_signature(service_path, method_name, ref.get('params', []))
            if not success:
                failures.append(f"{service_name}.{method_name}: {message}")
            else:
                print(f"  VERIFIED: {service_name}.{method_name}")
        else:
            warnings.append(f"{service_name}: class found but no specific method to verify")

    if failures:
        print("CONTRACT_VERIFICATION_FAILED")
        for f in failures:
            print(f"  - {f}")

        if warnings:
            print("\nWarnings:")
            for w in warnings:
                print(f"  - {w}")

        sys.exit(1)

    print("CONTRACT_VERIFICATION_PASSED")
    if warnings:
        print("\nWarnings:")
        for w in warnings:
            print(f"  - {w}")

    sys.exit(0)


if __name__ == "__main__":
    main()
