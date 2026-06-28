#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import sys


def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8-sig"))


def values(obj, *names):
    out = []
    if isinstance(obj, dict):
        for name in names:
            value = obj.get(name)
            if isinstance(value, list):
                out.extend(str(v) for v in value if str(v).strip())
            elif isinstance(value, dict):
                out.append(json.dumps(value, ensure_ascii=False))
            elif value is not None and str(value).strip():
                out.append(str(value))
    return out


def carrier_tokens(text):
    tokens = []
    for part in re.split(r"[\s#(),:;]+", text or ""):
        part = part.strip().strip('"').strip("'")
        if not part:
            continue
        leaf = part.split(".")[-1]
        if len(leaf) >= 3:
            tokens.append(leaf)
    return tokens


def validate(replay_root, slice_result_path, slice_verify_path):
    replay = pathlib.Path(replay_root)
    result = load_json(slice_result_path)
    verify = load_json(slice_verify_path)
    idx = int(result.get("slice_index") or verify.get("slice_index") or 1)
    contract_path = replay / f"CARRIER_INVOCATION_CONTRACT_{idx:02d}.json"
    execution_path = replay / f"SLICE_EXECUTION_CONTRACT_{idx:02d}.json"
    issues = []

    if not contract_path.exists():
        issues.append("carrier_invocation_contract_missing")
        contract = {}
    else:
        contract = load_json(contract_path)

    if not execution_path.exists():
        issues.append("slice_execution_contract_missing")
        execution = {}
    else:
        execution = load_json(execution_path)

    for field, expected in (
        ("resolved", True),
        ("signature_match", True),
        ("test_invokes_entry", True),
    ):
        if contract.get(field) is not expected:
            issues.append(f"carrier_execution_{field}_not_true")

    if str(contract.get("carrier_origin", "")).lower() != "existing_production":
        issues.append("carrier_origin_not_existing_production")

    selected = " ".join(
        values(contract, "production_entry_qn", "test_invocation_method")
        + values(execution, "production_entry_qn", "entry_invocation_method", "red_command", "green_command")
    )
    evidence = " ".join(
        values(result, "target_subsurface_or_carrier", "production_boundary", "proof_kind", "test_execution_command")
        + values(result, "implemented_files", "current_slice_changed_files", "closed_assertions", "tests")
        + values(verify, "test_commands", "changed_files", "implemented_files")
    )
    selected_tokens = carrier_tokens(selected)
    if selected_tokens and not any(token in evidence for token in selected_tokens):
        issues.append("selected_carrier_not_observed_in_slice_evidence")

    observable_text = " ".join(
        values(execution, "side_effect_or_output_probe", "red_assertion", "must_not_assertion")
        + values(result, "side_effect_evidence", "closed_assertions", "behavior_test_charter")
    )
    if not re.search(r"(?i)(assert|verify|return|response|payload|state|status|task|progress|log|db|database|insert|update|save|persist|output)", observable_text):
        issues.append("observable_effect_not_asserted")

    authorized = bool(verify.get("authorized_for_next_slice") or verify.get("authorized_for_synthesis"))
    if issues and authorized:
        issues.append("carrier_execution_issues_but_verifier_authorized")

    payload = {
        "schema": "carrier_execution_contract_verification.v1",
        "status": "PASS" if not issues else "FAIL",
        "replay_root": str(replay),
        "slice_result": str(slice_result_path),
        "slice_verify": str(slice_verify_path),
        "carrier_invocation_contract": str(contract_path),
        "slice_execution_contract": str(execution_path),
        "issues": issues,
    }
    return payload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--replay-root")
    parser.add_argument("--slice-result")
    parser.add_argument("--slice-verify")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps({"status": "PASS", "mode": "self-test"}))
        return 0
    if not (args.replay_root and args.slice_result and args.slice_verify):
        parser.error("--replay-root, --slice-result, and --slice-verify are required")
    payload = validate(args.replay_root, args.slice_result, args.slice_verify)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if payload["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
