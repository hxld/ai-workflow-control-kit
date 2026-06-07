#!/usr/bin/env python3
"""
Contract Fingerprinting Gate (Experiment 1 from NEXT_EXPERIMENT_PLAN.md).

Verify that implemented carrier matches planned signature exactly.
This prevents carrier mismatch gaps where agents create methods with wrong signatures.
"""

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def run_command(cmd: List[str], cwd: str, timeout: int = 60) -> Tuple[int, str, str]:
    """Run command and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=False
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"Command timed out after {timeout}s"
    except Exception as e:
        return -1, "", str(e)


class MethodSignature:
    """Represents a Java method signature."""

    def __init__(self, class_name: str, method_name: str, parameters: List[str], return_type: str = "void"):
        self.class_name = class_name
        self.method_name = method_name
        self.parameters = parameters
        self.return_type = return_type

    def __str__(self):
        params = ", ".join(self.parameters)
        return f"{self.return_type} {self.class_name}.{self.method_name}({params})"

    def __eq__(self, other):
        if not isinstance(other, MethodSignature):
            return False
        return (
            self.class_name == other.class_name and
            self.method_name == other.method_name and
            self.parameters == other.parameters and
            self.return_type == other.return_type
        )

    def to_dict(self):
        return {
            "class_name": self.class_name,
            "method_name": self.method_name,
            "parameters": self.parameters,
            "return_type": self.return_type,
            "formatted": str(self)
        }


def parse_carrier_string(carrier_str: str) -> Optional[MethodSignature]:
    """
    Parse a carrier string into MethodSignature.

    Handles formats like:
    - "ServiceClass.methodName"
    - "ServiceClass.methodName(ParamType)"
    - "ServiceClass.methodName(ParamType1, ParamType2): ReturnType"
    """
    if not carrier_str:
        return None

    # Remove common artifacts
    carrier_str = carrier_str.strip()
    if carrier_str.startswith("new ") or carrier_str.startswith("call "):
        carrier_str = carrier_str.split(" ", 1)[1].strip()

    # Extract return type if present
    return_type = "void"
    if ":" in carrier_str and not carrier_str.endswith(":"):
        parts = carrier_str.rsplit(":", 1)
        carrier_str = parts[0].strip()
        return_type = parts[1].strip()

    # Extract parameters
    parameters = []
    if "(" in carrier_str:
        method_part = carrier_str.split("(", 1)
        carrier_str = method_part[0].strip()

        if ")" in method_part[1]:
            params_str = method_part[1].rsplit(")", 1)[0].strip()
            if params_str:
                parameters = [p.strip() for p in params_str.split(",") if p.strip()]

    # Extract class and method name
    if "." in carrier_str:
        parts = carrier_str.split(".")
        method_name = parts[-1]
        class_name = ".".join(parts[:-1])
    else:
        # Only class name provided
        class_name = carrier_str
        method_name = "handle"  # Default carrier method name

    return MethodSignature(class_name, method_name, parameters, return_type)


def extract_method_signature_from_source(source: str, class_name: str, method_name: str) -> Optional[MethodSignature]:
    """
    Extract method signature from Java source code.
    """
    lines = source.split("\n")

    # Pattern for method declaration
    # Matches: public/private/protected/package-private [static] [final] ReturnType methodName(params) [throws ...]
    pattern = re.compile(
        r'^(?:public|private|protected|)?\s*(?:static\s+)?(?:final\s+)?([^\s]+)\s+' +
        re.escape(method_name) +
        r'\s*\(([^)]*)\)\s*(?:throws\s+[^{]+)?',
        re.MULTILINE
    )

    for i, line in enumerate(lines):
        match = pattern.search(line)
        if match:
            return_type = match.group(1).strip()
            params_str = match.group(2).strip()

            # Parse parameters
            parameters = []
            if params_str:
                # Split by comma but handle generics
                param_parts = [p.strip() for p in params_str.split(",")]
                for param in param_parts:
                    if param:
                        # Extract type from "Type name" or just "Type"
                        type_match = re.match(r'^([A-Za-z][A-Za-z0-9_<>, ?\[\]\.]*)', param)
                        if type_match:
                            parameters.append(type_match.group(1))

            return MethodSignature(class_name, method_name, parameters, return_type)

    return None


def search_method_in_worktree(worktree: str, class_name: str, method_name: str) -> Optional[Dict]:
    """
    Search for method implementation in worktree.

    Returns dict with 'file_path' and 'source' if found.
    """
    # Search for the class file
    search_cmd = ["rg", "--type", "java", f"class {class_name}"]

    returncode, stdout, stderr = run_command(search_cmd, worktree, timeout=30)
    if returncode != 0 or not stdout.strip():
        return None

    # Get file path from first match
    for line in stdout.strip().split("\n")[:5]:
        if line.strip():
            file_path = line.split(":")[0]
            break
    else:
        return None

    # Read the file to extract method signature
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            source = f.read()
    except:
        return None

    # Verify method exists in class
    if method_name not in source:
        return None

    return {
        "file_path": file_path,
        "source": source
    }


def signatures_match(plan_sig: MethodSignature, impl_sig: MethodSignature) -> bool:
    """
    Compare two method signatures.

    Returns True if they match exactly (parameters and return type).
    """
    if not plan_sig or not impl_sig:
        return False

    # Class name must match
    if plan_sig.class_name != impl_sig.class_name:
        return False

    # Method name must match
    if plan_sig.method_name != impl_sig.method_name:
        return False

    # Parameter count must match
    if len(plan_sig.parameters) != len(impl_sig.parameters):
        return False

    # Parameter types must match (order matters)
    for p1, p2 in zip(plan_sig.parameters, impl_sig.parameters):
        # Normalize for comparison (remove generics for basic check)
        p1_clean = re.sub(r'<[^>]+>', '', p1).strip()
        p2_clean = re.sub(r'<[^>]+>', '', p2).strip()
        if p1_clean != p2_clean:
            return False

    # Return type must match
    plan_return_clean = re.sub(r'<[^>]+>', '', plan_sig.return_type).strip()
    impl_return_clean = re.sub(r'<[^>]+>', '', impl_sig.return_type).strip()
    if plan_return_clean != impl_return_clean:
        return False

    return True


def signature_diff(plan_sig: MethodSignature, impl_sig: MethodSignature) -> List[str]:
    """
    Generate diff description between two signatures.
    """
    diffs = []

    if plan_sig.class_name != impl_sig.class_name:
        diffs.append(f"class_name: {plan_sig.class_name} != {impl_sig.class_name}")

    if plan_sig.method_name != impl_sig.method_name:
        diffs.append(f"method_name: {plan_sig.method_name} != {impl_sig.method_name}")

    if len(plan_sig.parameters) != len(impl_sig.parameters):
        diffs.append(f"parameter_count: {len(plan_sig.parameters)} != {len(impl_sig.parameters)}")
    else:
        for i, (p1, p2) in enumerate(zip(plan_sig.parameters, impl_sig.parameters)):
            p1_clean = re.sub(r'<[^>]+>', '', p1).strip()
            p2_clean = re.sub(r'<[^>]+>', '', p2).strip()
            if p1_clean != p2_clean:
                diffs.append(f"parameter_{i}: {p1} != {p2}")

    plan_return_clean = re.sub(r'<[^>]+>', '', plan_sig.return_type).strip()
    impl_return_clean = re.sub(r'<[^>]+>', '', impl_sig.return_type).strip()
    if plan_return_clean != impl_return_clean:
        diffs.append(f"return_type: {plan_sig.return_type} != {impl_sig.return_type}")

    return diffs


def verify_carrier_signature(
    plan_carrier: str,
    worktree_path: str,
    baseline_commit: Optional[str] = None
) -> Dict:
    """
    Verify that implemented carrier matches planned signature.

    Args:
        plan_carrier: Planned carrier string (e.g., "ServiceClass.methodName(Type)")
        worktree_path: Path to worktree
        baseline_commit: Optional baseline commit for comparison

    Returns:
        Dict with verification result
    """
    # Parse planned carrier
    plan_sig = parse_carrier_string(plan_carrier)
    if not plan_sig:
        return {
            "status": "FAIL",
            "error": "carrier_parse_failed",
            "message": f"Failed to parse carrier string: {plan_carrier}",
            "carrier_provided": plan_carrier
        }

    # Search for implementation in worktree
    impl_match = search_method_in_worktree(
        worktree_path,
        plan_sig.class_name,
        plan_sig.method_name
    )

    if not impl_match:
        return {
            "status": "FAIL",
            "error": "carrier_not_found",
            "message": f"No implementation found for {plan_sig.class_name}.{plan_sig.method_name}",
            "planned_signature": plan_sig.to_dict(),
            "search_query": f"class {plan_sig.class_name} method {plan_sig.method_name}"
        }

    # Extract implementation signature
    impl_sig = extract_method_signature_from_source(
        impl_match["source"],
        plan_sig.class_name,
        plan_sig.method_name
    )

    if not impl_sig:
        return {
            "status": "FAIL",
            "error": "method_signature_not_found",
            "message": f"Method {plan_sig.method_name} not found in class {plan_sig.class_name}",
            "planned_signature": plan_sig.to_dict(),
            "file_path": impl_match["file_path"]
        }

    # Compare signatures
    if not signatures_match(plan_sig, impl_sig):
        diffs = signature_diff(plan_sig, impl_sig)
        return {
            "status": "FAIL",
            "error": "carrier_signature_mismatch",
            "message": "Signature mismatch between planned and implemented carrier",
            "planned_signature": plan_sig.to_dict(),
            "implemented_signature": impl_sig.to_dict(),
            "differences": diffs,
            "file_path": impl_match["file_path"]
        }

    return {
        "status": "PASS",
        "message": "Carrier signature matches exactly",
        "planned_signature": plan_sig.to_dict(),
        "implemented_signature": impl_sig.to_dict(),
        "file_path": impl_match["file_path"]
    }


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python verify_carrier_signature.py --input <input.json>")
        print("  echo '{...}' | python verify_carrier_signature.py")
        print("\nInput JSON keys: plan_carrier, worktree_path, baseline_commit (optional)")
        sys.exit(0)

    if len(sys.argv) > 2 and sys.argv[1] == "--input":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            input_data = json.load(f)
    else:
        # Read from stdin
        input_data = json.loads(sys.stdin.read())

    result = verify_carrier_signature(
        plan_carrier=input_data.get("plan_carrier", ""),
        worktree_path=input_data.get("worktree_path", ""),
        baseline_commit=input_data.get("baseline_commit")
    )

    print(json.dumps(result, indent=2, ensure_ascii=False))
    sys.exit(1 if result["status"] == "FAIL" else 0)


if __name__ == "__main__":
    main()
