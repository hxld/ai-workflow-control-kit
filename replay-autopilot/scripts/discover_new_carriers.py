#!/usr/bin/env python3
"""
Discover NEW carrier signatures from oracle diff.

Usage: discover_new_carriers.py <base_commit> <oracle_commit> <target_carrier>

Output: CARRIER_SIGNATURES.json with class names and method signatures only.
NO implementation logic is copied.
"""

import subprocess
import json
import sys
from pathlib import Path

def carrier_exists_in_base(carrier_name, base_commit):
    """Check if carrier exists in base commit."""
    result = subprocess.run(
        ["git", "grep", "--quiet", f"class {carrier_name}", base_commit],
        capture_output=True
    )
    return result.returncode == 0

def get_new_carrier_files(base_commit, oracle_commit, carrier_name):
    """Get files added/modified in oracle that contain the carrier."""
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{base_commit}..{oracle_commit}"],
        capture_output=True,
        text=True
    )

    all_diff_files = result.stdout.strip().split('\n')
    carrier_files = [f for f in all_diff_files if carrier_name in f or 'Service' in f]
    return carrier_files

def extract_signatures_only(oracle_commit, file_path):
    """Extract ONLY signatures, not implementations."""
    result = subprocess.run(
        ["git", "show", f"{oracle_commit}:{file_path}"],
        capture_output=True,
        text=True
    )

    lines = result.stdout.split('\n')
    signatures = []

    for line in lines:
        # Extract ONLY signatures (public/protected/private + return type + method + params)
        # Skip body/implementation
        if line.strip().startswith(('public', 'protected', 'private')):
            if '(' in line and ')' in line and '{' not in line:
                signatures.append(line.strip())
            elif '{' in line:
                # Signature on same line as opening brace - extract just signature
                sig_part = line.split('{')[0].strip()
                if sig_part:
                    signatures.append(sig_part)

    return signatures

def main():
    base_commit = sys.argv[1]
    oracle_commit = sys.argv[2]
    target_carrier = sys.argv[3]

    # Check if carrier exists in base
    if carrier_exists_in_base(target_carrier, base_commit):
        print(f"Carrier {target_carrier} exists in base, no scan needed")
        return

    # Get NEW carrier files from oracle diff
    carrier_files = get_new_carrier_files(base_commit, oracle_commit, target_carrier)

    # Extract signatures ONLY
    signatures = {}
    for file_path in carrier_files:
        sigs = extract_signatures_only(oracle_commit, file_path)
        if sigs:
            signatures[file_path] = sigs

    # Output CARRIER_SIGNATURES.json
    output = {
        "carrier": target_carrier,
        "base_commit": base_commit,
        "oracle_commit": oracle_commit,
        "exists_in_base": False,
        "signatures": signatures
    }

    with open("CARRIER_SIGNATURES.json", "w") as f:
        json.dump(output, f, indent=2)

    print(f"Discovered {len(signatures)} files with signatures for {target_carrier}")
    print("Output: CARRIER_SIGNATURES.json")

if __name__ == "__main__":
    main()
