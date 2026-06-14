#!/usr/bin/env python3
"""
Test File Auto-Generation (P0 - CRITICAL BLOCKER RESOLUTION).

Ensures test file exists before RED phase. Generates skeleton if missing.
This addresses the v365 blocker where test files don't exist, preventing RED gate execution.

From NEXT_EXPERIMENT_PLAN.md Experiment 1.
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional


def infer_package_from_source(source_path: str, worktree_path: str) -> Optional[str]:
    """
    Infer package name from source file location.

    Java package convention: src/main/java/com/example/Service.java
    Test location: src/test/java/com/example/ServiceTest.java
    """
    # Normalize paths
    source_path = os.path.normpath(source_path)
    worktree_path = os.path.normpath(worktree_path)

    # Extract relative path from worktree
    if worktree_path not in source_path:
        return None

    rel_path = source_path.replace(worktree_path, '').lstrip(os.sep)

    # Extract package from path
    # Pattern: src/main/java/com/example/project/service/MyService.java
    #          -> com.example.project.service

    if 'src/main/java' in rel_path:
        parts = rel_path.split('src/main/java')[1].lstrip(os.sep)
    elif 'src/test/java' in rel_path:
        parts = rel_path.split('src/test/java')[1].lstrip(os.sep)
    else:
        # Try to extract from any java path
        for marker in ['java/', 'java\\']:
            if marker in rel_path:
                parts = rel_path.split(marker)[1].lstrip(os.sep)
                break
        else:
            return None

    # Remove filename and convert path to package
    parts = parts.replace(os.sep, '/')
    parts = parts.rsplit('/', 1)[0] if '/' in parts else parts
    package = parts.replace('/', '.')

    return package


def find_source_file(worktree_path: str, class_name: str) -> Optional[Dict]:
    """
    Search for source file in worktree.

    Returns dict with 'file_path' and 'package' if found.
    """
    # Search for the class file
    search_cmd = ["rg", "--type", "java", f"class {class_name}", worktree_path]

    try:
        result = subprocess.run(
            search_cmd,
            capture_output=True,
            text=True,
            timeout=30,
            shell=False
        )

        if result.returncode != 0 or not result.stdout.strip():
            return None

        # Get file path from first match
        for line in result.stdout.strip().split("\n")[:5]:
            if line.strip():
                source_file = line.split(":")[0]
                break
        else:
            return None

        # Infer package from source location
        package = infer_package_from_source(source_file, worktree_path)

        return {
            "file_path": source_file,
            "package": package
        }

    except (subprocess.TimeoutExpired, Exception) as e:
        return None


import subprocess


def infer_test_path(carrier_class: str, worktree_path: str) -> str:
    """
    Infer test file path from carrier class name.

    Returns the expected test file location.
    """
    # Try to find source file first
    source_info = find_source_file(worktree_path, carrier_class)

    if source_info:
        # Convert source path to test path
        source_path = source_info["file_path"]
        package = source_info.get("package")

        # Replace src/main/java with src/test/java
        test_path = source_path.replace(
            os.path.join('src', 'main', 'java'),
            os.path.join('src', 'test', 'java')
        )

        # Add Test suffix
        test_dir = os.path.dirname(test_path)
        test_filename = os.path.basename(test_path).replace('.java', 'Test.java')
        test_path = os.path.join(test_dir, test_filename)

        return test_path, package
    else:
        # Fallback: construct from class name
        # com.example.project.service.MyService -> src/test/java/com/example/project/service/MyServiceTest.java
        package_parts = carrier_class.split('.')
        class_name = package_parts[-1]
        package = '.'.join(package_parts[:-1]) if len(package_parts) > 1 else ''

        test_path = os.path.join(
            worktree_path,
            'src', 'test', 'java',
            *package_parts[:-1],
            f'{class_name}Test.java'
        )

        return os.path.normpath(test_path), package


def generate_test_skeleton(carrier_class: str, carrier_method: str, package: str, test_file_path: str) -> str:
    """
    Generate test file skeleton content.

    The skeleton includes:
    1. Package declaration
    2. Required imports
    3. @Test method that will fail with ClassNotFoundException
    """
    simple_class_name = carrier_class.split('.')[-1]
    test_class_name = f'{simple_class_name}Test'

    skeleton = f'''package {package};

import org.junit.Test;
import static org.mockito.Mockito.*;
import static org.junit.Assert.*;

/**
 * Auto-generated test skeleton for {carrier_class}
 *
 * RED PHASE: This test should fail with ClassNotFoundException
 * because {carrier_class} does not exist yet.
 *
 * After implementing {carrier_class}.{carrier_method},
 * this test should pass in GREEN phase.
 */
public class {test_class_name} {{

    /**
     * Test {carrier_method} - RED phase
     *
     * Expected RED failure: ClassNotFoundException for {carrier_class}
     *
     * GREEN phase goal: Implement {carrier_class}.{carrier_method}
     * to make this test pass.
     */
    @Test
    public void test{carrier_method[0].upper() + carrier_method[1:]}_ThrowsClassNotFoundException() {{
        // RED: This test should fail because {carrier_class} doesn't exist
        {carrier_class} carrier = new {carrier_class}();

        // TODO: Call {carrier_method} and verify behavior
        fail("RED phase: {carrier_class}.{carrier_method} not implemented yet");
    }}

    /**
     * Test charter placeholder - add behavioral assertions here
     */
    @Test
    public void test{carrier_method[0].upper() + carrier_method[1:]}_BehavioralVerification() {{
        // GIVEN: Setup test data
        Long caseId = 12345L;

        // WHEN: Call the method
        // {carrier_class} service = new {carrier_class}();
        // service.{carrier_method}(caseId);

        // THEN: Verify behavioral outcomes
        // TODO: Add assertions for side effects, DB writes, status changes, etc.
        // Example: verify(mapper).insertCompensateDetail(any());
    }}
}}
'''

    return skeleton


def ensure_test_file_exists(carrier_class: str, carrier_method: str, worktree_path: str) -> Dict:
    """
    Ensure test file exists for target carrier.
    Generate skeleton if missing.

    Args:
        carrier_class: Fully qualified class name (e.g., com.example.project.service.MyService)
        carrier_method: Method name to test (e.g., processAutoFlow)
        worktree_path: Path to worktree

    Returns:
        Dict with status, test_file_path, and action taken.
    """
    # Infer test file path
    test_file_path, package = infer_test_path(carrier_class, worktree_path)

    if not package:
        return {
            "status": "ERROR",
            "reason": "package_inference_failed",
            "message": f"Could not infer package for {carrier_class}",
            "carrier_class": carrier_class
        }

    # Check if test file exists
    if os.path.exists(test_file_path):
        # Verify file is not empty
        if os.path.getsize(test_file_path) > 0:
            return {
                "status": "EXISTS",
                "test_file_path": test_file_path,
                "package": package,
                "message": f"Test file already exists: {test_file_path}"
            }
        else:
            # File exists but is empty - regenerate
            pass

    # Generate test file skeleton
    skeleton = generate_test_skeleton(carrier_class, carrier_method, package, test_file_path)

    # Create directory if needed
    os.makedirs(os.path.dirname(test_file_path), exist_ok=True)

    # Write test file
    try:
        with open(test_file_path, 'w', encoding='utf-8') as f:
            f.write(skeleton)

        return {
            "status": "GENERATED",
            "test_file_path": test_file_path,
            "package": package,
            "carrier_class": carrier_class,
            "carrier_method": carrier_method,
            "test_class_name": f'{carrier_class.split(".")[-1]}Test',
            "message": f"Generated test skeleton: {test_file_path}"
        }

    except Exception as e:
        return {
            "status": "ERROR",
            "reason": "write_failed",
            "message": f"Failed to write test file: {str(e)}",
            "test_file_path": test_file_path
        }


def verify_test_file_exists(slice_result: Dict) -> Dict:
    """
    Verify test file exists before RED phase.

    This is used by the workflow gate to ensure test files are present
    before attempting to run Maven tests.
    """
    if not slice_result.get("test_file_path"):
        return {
            "status": "REJECTED",
            "reason": "test_file_missing",
            "message": "Test file path not specified in slice result. Run ensure_test_file_exists() first."
        }

    test_file_path = slice_result["test_file_path"]

    if not os.path.exists(test_file_path):
        return {
            "status": "REJECTED",
            "reason": "test_file_not_found",
            "message": f"Test file not found: {test_file_path}"
        }

    # Check file is not empty
    if os.path.getsize(test_file_path) == 0:
        return {
            "status": "REJECTED",
            "reason": "test_file_empty",
            "message": f"Test file is empty: {test_file_path}"
        }

    return {
        "status": "AUTHORIZED",
        "test_file_path": test_file_path,
        "message": "Test file verified and ready for RED phase"
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: ensure_test_file_exists.py <command> [args...]", file=sys.stderr)
        print("\nCommands:", file=sys.stderr)
        print("  generate <carrier_class> <carrier_method> <worktree_path>", file=sys.stderr)
        print("  verify <test_file_path>", file=sys.stderr)
        print("\nExamples:", file=sys.stderr)
        print("  ensure_test_file_exists.py generate com.example.service.MyService processFlow /path/to/worktree", file=sys.stderr)
        print("  ensure_test_file_exists.py verify /path/to/worktree/src/test/java/com/example/service/MyServiceTest.java", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "generate":
        if len(sys.argv) < 5:
            print("Usage: ensure_test_file_exists.py generate <carrier_class> <carrier_method> <worktree_path>", file=sys.stderr)
            sys.exit(1)

        carrier_class = sys.argv[2]
        carrier_method = sys.argv[3]
        worktree_path = sys.argv[4]

        result = ensure_test_file_exists(carrier_class, carrier_method, worktree_path)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        # Exit with error if generation failed
        if result.get("status") == "ERROR":
            sys.exit(1)

    elif command == "verify":
        if len(sys.argv) < 3:
            print("Usage: ensure_test_file_exists.py verify <test_file_path>", file=sys.stderr)
            sys.exit(1)

        test_file_path = sys.argv[2]
        slice_result = {"test_file_path": test_file_path}

        result = verify_test_file_exists(slice_result)
        print(json.dumps(result, indent=2, ensure_ascii=False))

        # Exit with error if verification failed
        if result.get("status") in ["REJECTED", "ERROR"]:
            sys.exit(1)

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
