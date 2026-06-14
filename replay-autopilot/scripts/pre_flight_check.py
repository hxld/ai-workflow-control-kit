#!/usr/bin/env python3
"""
Pre-flight validation before replay execution.
Checks test environment health to prevent environment-blocked rounds.

This script implements Experiment 1 from the evolution plan:
- Pre-Flight Test Environment Validation
"""

import subprocess
import json
import sys
from pathlib import Path
from typing import Dict, List


def run_command(cmd: List[str], workdir: str, timeout: int = 300) -> Dict:
    """Run command and return result with status and output."""
    try:
        result = subprocess.run(
            cmd,
            cwd=workdir,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return {
            "status": "success" if result.returncode == 0 else "failed",
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "error": f"Command timed out after {timeout}s"}
    except Exception as e:
        return {"status": "error", "error": str(e)}


def build_maven_command(maven_settings: str, *args: str) -> List[str]:
    cmd = ["mvn"]
    if maven_settings:
        cmd.extend(["-s", maven_settings])
    cmd.extend(args)
    return cmd


def check_test_compilation(worktree: str, maven_settings: str, root_pom: str) -> Dict:
    """Check whether the existing claim-server test harness compiles."""
    cmd = build_maven_command(
        maven_settings,
        "-f", root_pom, "test-compile", "-pl", "claim-server", "-am", "-q", "-DskipTests"
    )
    result = run_command(cmd, worktree)
    return {
        "check": "test_compilation",
        "result": result["status"],
        "details": "Compilation succeeded" if result["status"] == "success" else f"Compilation failed: {result['stderr'][:200] if 'stderr' in result else result.get('error', 'Unknown')}"
    }


def check_test_harness_dependencies(worktree: str, maven_settings: str, root_pom: str) -> Dict:
    """Check that the allowed test harness module has test dependencies.

    claim-core intentionally lacks JUnit/Mockito/Spring Test in this project.
    That must not be treated as an instruction to modify any pom.xml.
    """
    cmd = build_maven_command(maven_settings, "-f", root_pom, "dependency:tree", "-pl", "claim-server")
    result = run_command(cmd, worktree)
    output = (result.get("stdout", "") + result.get("stderr", "")).lower()
    has_test_harness = "junit" in output and "mockito" in output
    return {
        "check": "test_harness_dependency",
        "result": "success" if has_test_harness else "failed",
        "details": (
            "claim-server test harness has JUnit/Mockito dependencies"
            if has_test_harness
            else "claim-server test harness dependency check failed; do not add test dependencies to claim-core"
        )
    }


def check_existing_test_errors(worktree: str, maven_settings: str, root_pom: str) -> Dict:
    """Check for existing test compilation or execution errors."""
    cmd = build_maven_command(
        maven_settings,
        "-f", root_pom, "test-compile", "-pl", "claim-server", "-am", "-q", "-DskipTests"
    )
    result = run_command(cmd, worktree, timeout=180)
    combined_output = result.get("stdout", "") + result.get("stderr", "")
    has_errors = "error:" in combined_output.lower() or "compilation failure" in combined_output.lower() or "BUILD FAILURE" in combined_output
    return {
        "check": "existing_test_errors",
        "result": "success" if not has_errors else "failed",
        "details": "No existing test errors" if not has_errors else f"Existing test errors found: {combined_output[:200]}"
    }


def validate_oracle_accessibility(worktree: str, oracle_branch: str) -> Dict:
    """Check if oracle branch is accessible."""
    cmd = ["git", "branch", "-r", "--list", f"*{oracle_branch}*"]
    result = run_command(cmd, worktree, timeout=30)
    has_oracle = oracle_branch in result.get("stdout", "")
    return {
        "check": "oracle_accessibility",
        "result": "success" if has_oracle else "warning",
        "details": f"Oracle branch {oracle_branch} accessible" if has_oracle else f"Oracle branch {oracle_branch} not found"
    }


def run_pre_flight_checks(config: Dict) -> Dict:
    """Run all pre-flight checks and return summary."""
    worktree = config["worktree"]
    maven_settings = config.get("maven_settings", "") or ""
    root_pom = config.get("root_pom", f"{worktree}\\pom.xml")
    oracle_branch = config.get("oracle_branch", "")

    checks = [
        check_test_compilation(worktree, maven_settings, root_pom),
        check_test_harness_dependencies(worktree, maven_settings, root_pom),
        check_existing_test_errors(worktree, maven_settings, root_pom),
        validate_oracle_accessibility(worktree, oracle_branch)
    ]

    failed_checks = [c for c in checks if c["result"] == "failed"]
    warning_checks = [c for c in checks if c["result"] == "warning"]

    overall_status = "success" if not failed_checks else "failed"

    return {
        "overall_status": overall_status,
        "checks": checks,
        "failed_count": len(failed_checks),
        "warning_count": len(warning_checks),
        "recommendation": "PROCEED" if overall_status == "success" else "STOP_AND_FIX_ENVIRONMENT",
        "phase0_status": "BLOCKED_PRE_FLIGHT" if failed_checks else "PROCEED"
    }


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--config":
        # Read from file
        with open(sys.argv[2], 'r', encoding='utf-8-sig') as f:
            config = json.load(f)
    elif len(sys.argv) > 1 and sys.argv[1] == "--help":
        print(__doc__)
        print("\nUsage:")
        print("  python pre_flight_check.py --config <config.json>")
        print("  echo '{...}' | python pre_flight_check.py")
        print("\nConfig keys: worktree, maven_settings (optional), root_pom (optional), oracle_branch (optional)")
        sys.exit(0)
    else:
        # Read from stdin
        config = json.loads(sys.stdin.read())

    result = run_pre_flight_checks(config)
    print(json.dumps(result, indent=2, ensure_ascii=False))

    # Exit with error code if failed
    sys.exit(1 if result["overall_status"] == "failed" else 0)
