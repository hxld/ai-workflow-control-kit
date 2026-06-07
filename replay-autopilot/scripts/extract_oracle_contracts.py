#!/usr/bin/env python3
"""
Extract oracle method contracts from a given commit.
Used for Exact Contract Pre-Binding gate (Priority 1 experiment).
"""

import json
import subprocess
import sys
from typing import Dict, List, Set
from dataclasses import dataclass, asdict
from collections import defaultdict


@dataclass
class MethodContract:
    """Java method contract signature."""
    class_name: str
    method_name: str
    parameter_types: List[str]
    return_type: str
    file_path: str
    line_number: int
    full_signature: str

    def to_key(self) -> str:
        """Unique key for this method."""
        params = ",".join(self.parameter_types)
        return f"{self.class_name}.{self.method_name}({params})"


@dataclass
class ClassContract:
    """Java class contract."""
    class_name: str
    file_path: str
    methods: List[MethodContract]


def extract_java_methods(file_content: str, file_path: str) -> List[MethodContract]:
    """Extract method signatures from Java source."""
    methods = []
    lines = file_content.split("\n")

    # Track class context
    current_class = None
    package = ""

    for i, line in enumerate(lines, 1):
        # Extract package
        if line.strip().startswith("package "):
            package = line.strip().replace("package ", "").replace(";", "").strip()
            continue

        # Extract class name
        if " class " in line or " interface " in line:
            tokens = line.strip().split()
            for j, token in enumerate(tokens):
                if token == "class" or token == "interface":
                    if j + 1 < len(tokens):
                        current_class = tokens[j + 1].split("<")[0].split("{")[0].strip()
                        break

        # Extract method signatures (public/protected/private)
        if current_class and any(line.strip().startswith(p) for p in ["public ", "protected ", "private "]):
            # Skip if it's not a method declaration
            if "(" in line and ")" in line and not line.strip().startswith("//") and ";" not in line:
                method = parse_method_line(line, current_class, package, file_path, i)
                if method:
                    methods.append(method)

    return methods


def parse_method_line(line: str, class_name: str, package: str, file_path: str, line_number: int) -> MethodContract:
    """Parse a method declaration line."""
    try:
        line = line.strip()

        # Skip if not a method
        if "(" not in line or ")" not in line:
            return None

        # Extract return type and method name
        # Pattern: return_type method_name(params)
        before_paren = line.split("(")[0].strip()
        parts = before_paren.split()

        if len(parts) < 2:
            return None

        # Handle annotations
        method_parts = []
        return_type = None
        for i, part in enumerate(parts):
            if part.startswith("@"):
                continue
            if return_type is None:
                return_type = part
            else:
                method_parts.append(part)

        if not return_type or not method_parts:
            return None

        method_name = method_parts[0].split("<")[0].split("{")[0].strip()

        # Extract parameters
        params_part = line.split("(")[1].split(")")[0]
        parameter_types = []

        if params_part.strip():
            for param in params_part.split(","):
                param = param.strip()
                if param:
                    # Extract type from "Type name" or "final Type name"
                    param_parts = param.split()
                    if len(param_parts) >= 2:
                        param_type = param_parts[-2]  # Second to last is type
                    elif len(param_parts) == 1:
                        param_type = param_parts[0]
                    else:
                        continue

                    # Clean generic parameters
                    param_type = param_type.split("<")[0].strip()
                    if param_type:
                        parameter_types.append(param_type)

        # Clean return type
        return_type_clean = return_type.split("<")[0].strip()

        # Build full signature
        full_sig = f"{class_name}.{method_name}({', '.join(parameter_types)}):{return_type_clean}"

        return MethodContract(
            class_name=class_name,
            method_name=method_name,
            parameter_types=parameter_types,
            return_type=return_type_clean,
            file_path=file_path,
            line_number=line_number,
            full_signature=full_sig
        )
    except Exception as e:
        # Don't fail on parse errors
        return None


def extract_contracts_from_commit(repo_path: str, commit: str) -> Dict[str, List[MethodContract]]:
    """Extract all method contracts from a commit."""
    contracts = defaultdict(list)

    try:
        # Get list of Java files in the commit
        result = subprocess.run(
            ["git", "-C", repo_path, "diff-tree", "--no-commit-id", "--name-only", "-r", commit],
            capture_output=True, text=True, check=True
        )

        files = [f for f in result.stdout.strip().split("\n") if f.endswith(".java")]

        for file_path in files:
            # Get file content at commit
            file_result = subprocess.run(
                ["git", "-C", repo_path, "show", f"{commit}:{file_path}"],
                capture_output=True, text=True, check=True
            )

            methods = extract_java_methods(file_result.stdout, file_path)

            for method in methods:
                contracts[method.class_name].append(method)

    except subprocess.CalledProcessError as e:
        print(f"Error extracting from commit: {e}", file=sys.stderr)

    return dict(contracts)


def compare_signatures(plan_contracts: Dict, oracle_contracts: Dict) -> Dict:
    """Compare plan signatures against oracle signatures."""
    comparison = {
        "exact_matches": [],
        "parameter_mismatches": [],
        "return_type_mismatches": [],
        "missing_in_oracle": [],
        "synthetic_carriers": [],
        "summary": {}
    }

    plan_methods = {}
    for class_name, methods in oracle_contracts.items():
        for method in methods:
            plan_methods[method.to_key()] = method

    # Check each plan method against oracle
    for method_key, method in plan_methods.items():
        found_in_oracle = False

        # Search in oracle contracts
        for oracle_class, oracle_methods in oracle_contracts.items():
            for oracle_method in oracle_methods:
                if method.method_name == oracle_method.method_name and method.class_name == oracle_class:
                    found_in_oracle = True

                    # Check parameter match
                    if method.parameter_types != oracle_method.parameter_types:
                        comparison["parameter_mismatches"].append({
                            "plan": method.to_key(),
                            "oracle": oracle_method.to_key(),
                            "plan_params": method.parameter_types,
                            "oracle_params": oracle_method.parameter_types
                        })

                    # Check return type match
                    if method.return_type != oracle_method.return_type:
                        comparison["return_type_mismatches"].append({
                            "plan": method.to_key(),
                            "oracle": oracle_method.to_key(),
                            "plan_return": method.return_type,
                            "oracle_return": oracle_method.return_type
                        })

                    # Exact match
                    if (method.parameter_types == oracle_method.parameter_types and
                        method.return_type == oracle_method.return_type):
                        comparison["exact_matches"].append(method.to_key())

                    break

        if not found_in_oracle:
            comparison["synthetic_carriers"].append({
                "signature": method.to_key(),
                "file": method.file_path,
                "line": method.line_number
            })

    # Calculate summary
    total_methods = sum(len(methods) for methods in plan_methods.values())
    synthetic_count = len(comparison["synthetic_carriers"])
    exact_match_count = len(comparison["exact_matches"])

    comparison["summary"] = {
        "total_plan_methods": total_methods,
        "exact_match_count": exact_match_count,
        "synthetic_carrier_count": synthetic_count,
        "synthetic_carrier_rate": round(synthetic_count / total_methods * 100, 1) if total_methods > 0 else 0,
        "exact_match_rate": round(exact_match_count / total_methods * 100, 1) if total_methods > 0 else 0
    }

    return comparison


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: extract_oracle_contracts.py <repo_path> <commit> [--compare <plan_contracts.json>]", file=sys.stderr)
        sys.exit(1)

    repo_path = sys.argv[1]
    commit = sys.argv[2]

    # Extract contracts from oracle commit
    oracle_contracts = extract_contracts_from_commit(repo_path, commit)

    output = {
        "commit": commit,
        "repo_path": repo_path,
        "contracts": {k: [asdict(m) for m in v] for k, v in oracle_contracts.items()},
        "summary": {
            "total_classes": len(oracle_contracts),
            "total_methods": sum(len(v) for v in oracle_contracts.values())
        }
    }

    # If comparing against plan
    if "--compare" in sys.argv:
        compare_idx = sys.argv.index("--compare")
        if compare_idx + 1 < len(sys.argv):
            plan_file = sys.argv[compare_idx + 1]
            with open(plan_file) as f:
                plan_data = json.load(f)

            comparison = compare_signatures(plan_data, oracle_contracts)
            output["comparison"] = comparison

            # Exit with error if high synthetic carrier rate
            synthetic_rate = comparison["summary"]["synthetic_carrier_rate"]
            if synthetic_rate > 40:
                print(f"FAIL: Synthetic carrier rate {synthetic_rate}% exceeds 40% threshold", file=sys.stderr)
                sys.exit(1)

    print(json.dumps(output, indent=2))
