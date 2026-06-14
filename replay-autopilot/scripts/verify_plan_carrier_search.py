#!/usr/bin/env python3
"""
Verify plan includes carrier search documentation and validates against existing carriers.

This script implements Experiment 3 from the evolution plan:
- Carrier Search Requirement Before New Service Creation
"""

import subprocess
import json
import sys
import re
from pathlib import Path
from typing import Dict, List, Tuple


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


def search_codebase(worktree: str, search_terms: List[str], file_pattern: str = "*.java") -> Dict:
    """Search codebase for existing carriers using provided terms."""
    results = {}

    # Search directories for service/facade classes
    search_paths = [
        f"{worktree}/claim-core/src/main/java",
        f"{worktree}/claim-api/src/main/java",
        f"{worktree}/claim-server/src/main/java"
    ]

    for term in search_terms:
        found = False
        matches = []

        for search_path in search_paths:
            if not Path(search_path).exists():
                continue

            # Use ripgrep if available, otherwise grep
            try:
                cmd = ["rg", "-i", f"class.*{term}", "-t", "java", search_path]
                returncode, stdout, stderr = run_command(cmd, worktree, timeout=30)
                if returncode == 0 and stdout:
                    found = True
                    for line in stdout.strip().split('\n')[:20]:  # Limit to 20 matches
                        if line.strip():
                            matches.append(line.strip())
            except:
                # Fallback to grep
                try:
                    cmd = ["grep", "-r", "-i", f"class.*{term}", "--include=file_pattern", search_path]
                    returncode, stdout, stderr = run_command(cmd, worktree, timeout=30)
                    if returncode == 0 and stdout:
                        found = True
                        for line in stdout.strip().split('\n')[:20]:
                            if line.strip():
                                matches.append(line.strip())
                except:
                    pass

        results[term] = {
            "found": found,
            "matches": matches
        }

    return results


def search_oracle_diff(worktree: str, oracle_commit: str, search_terms: List[str]) -> Dict:
    """Search oracle diff for similar carriers."""
    results = {}

    for term in search_terms:
        found = False
        files = []

        try:
            # Get list of changed files
            cmd = ["git", "-C", worktree, "diff", "--name-only", f"{oracle_commit}^..{oracle_commit}"]
            returncode, stdout, stderr = run_command(cmd, worktree, timeout=30)

            if returncode == 0:
                # Filter files matching the search term
                for file_path in stdout.strip().split('\n'):
                    if file_path and term.lower() in file_path.lower():
                        found = True
                        files.append(file_path)

            # Also search for the term in the diff content
            cmd = ["git", "-C", worktree, "diff", f"{oracle_commit}^..{oracle_commit}"]
            returncode, stdout, stderr = run_command(cmd, worktree, timeout=60)
            if returncode == 0 and term.lower() in stdout.lower():
                found = True

        except Exception as e:
            pass

        results[term] = {
            "found": found,
            "files": files
        }

    return results


def verify_plan_carrier_search(
    plan_result: Dict,
    oracle_diff: Dict,
    worktree: str,
    oracle_commit: str
) -> Dict:
    """
    Verify plan includes carrier search and validates against existing carriers.

    Returns:
        Dict with verification status and issues
    """
    issues = []
    warnings = []

    # Check if plan creates new service
    new_service_created = plan_result.get("new_service_created", False)
    if not new_service_created:
        return {"status": "PASS", "reason": "No new service created"}

    # Extract carrier search queries from plan
    carrier_search_queries = plan_result.get("carrier_search_queries", [])

    # Check 1: Are search queries documented?
    if not carrier_search_queries or len(carrier_search_queries) == 0:
        issues.append({
            "code": "carrier_search_queries_missing",
            "message": "Plan creates new service but has no documented carrier search queries",
            "severity": "critical"
        })
        return {"status": "FAIL", "issues": issues, "warnings": warnings}

    # Check 2: Search codebase for existing carriers
    codebase_results = search_codebase(worktree, carrier_search_queries)

    # Check 3: Search oracle diff for similar carriers
    oracle_results = search_oracle_diff(worktree, oracle_commit, carrier_search_queries)

    # Analyze results
    for term, result in codebase_results.items():
        if result.get("found") and len(result.get("matches", [])) > 0:
            # Found existing carrier - why create new one?
            existing_carriers = result["matches"][:5]  # Limit to 5 examples
            issues.append({
                "code": "carrier_search_existing_carrier_not_used",
                "message": f"Existing carriers found for '{term}': {len(existing_carriers)} matches. Justification required for new service.",
                "examples": existing_carriers,
                "severity": "critical"
            })

    for term, result in oracle_results.items():
        if result.get("found") and len(result.get("files", [])) > 0:
            # Oracle has similar carrier
            oracle_carriers = result["files"][:5]
            warnings.append({
                "code": "oracle_has_similar_carrier",
                "message": f"Oracle has similar carriers for '{term}': {len(oracle_carriers)} files. Check if reuse is possible.",
                "examples": oracle_carriers,
                "severity": "warning"
            })

    # Check 4: Is new service justified?
    new_service_justification = plan_result.get("new_service_justification", "")
    critical_issues = [i for i in issues if i.get("severity") == "critical"]

    if critical_issues and not new_service_justification:
        issues.append({
            "code": "new_service_justification_missing",
            "message": "New service creation requires justification when existing carriers found",
            "severity": "critical"
        })

    # Final verdict
    if len(critical_issues) > 0:
        return {"status": "FAIL", "issues": issues, "warnings": warnings}
    elif len(warnings) > 0:
        return {"status": "WARN", "issues": issues, "warnings": warnings}
    else:
        return {"status": "PASS", "reason": "Carrier search documented and validated"}


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python verify_plan_carrier_search.py --input <input.json>")
        print("  echo '{...}' | python verify_plan_carrier_search.py")
        print("\nInput JSON keys: plan_result, oracle_diff, worktree, oracle_commit")
        sys.exit(0)

    if len(sys.argv) > 2 and sys.argv[1] == "--input":
        with open(sys.argv[2], "r", encoding="utf-8-sig") as f:
            input_data = json.load(f)
    else:
        # Read from stdin
        input_data = json.loads(sys.stdin.read())
    result = verify_plan_carrier_search(**input_data)
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit codes: 0 for PASS/WARN, 1 for FAIL
    sys.exit(1 if result["status"] == "FAIL" else 0)
