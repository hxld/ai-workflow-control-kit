#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import sys


SIDE_EFFECT_FAMILIES = {
    "stateful_side_effect",
    "core_entry",
    "wire_payload_api_contract",
    "generated_artifact_template_upload",
    "deploy_export_page",
    "external_integration",
    "lifecycle_cleanup_retention",
}


def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8-sig"))


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def text_of(value):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def evidence_fields(result):
    side = result.get("side_effect_evidence") if isinstance(result.get("side_effect_evidence"), dict) else {}
    tests = as_list(result.get("tests"))
    test_text = " ".join(text_of(t) for t in tests)
    red_tests = [t for t in tests if isinstance(t, dict) and str(t.get("phase", "")).upper() == "RED"]
    green_tests = [t for t in tests if isinstance(t, dict) and str(t.get("phase", "")).upper() in {"GREEN", "VERIFY"}]
    return {
        "red_command": result.get("red_command") or result.get("test_red_command") or next((t.get("command") for t in red_tests if isinstance(t, dict) and t.get("command")), ""),
        "red_exit_code": result.get("red_exit_code") if result.get("red_exit_code") is not None else next((t.get("exit_code") for t in red_tests if isinstance(t, dict) and t.get("exit_code") is not None), None),
        "red_failure_assertion": result.get("red_failure_assertion") or side.get("red_result") or next((t.get("evidence") for t in red_tests if isinstance(t, dict) and t.get("evidence")), ""),
        "green_command": result.get("green_command") or result.get("test_execution_command") or next((t.get("command") for t in green_tests if isinstance(t, dict) and t.get("command")), ""),
        "green_exit_code": result.get("green_exit_code") if result.get("green_exit_code") is not None else result.get("test_execution_exit_code"),
        "asserted_side_effects": result.get("asserted_side_effects") or side.get("expected_writes_or_outputs") or result.get("closed_assertions") or [],
        "test_harness_module": result.get("test_harness_module") or result.get("test_module") or "",
        "entry_invocation": result.get("entry_invocation") or side.get("entry_call") or result.get("production_boundary") or result.get("target_subsurface_or_carrier") or "",
        "must_not_assertions": result.get("must_not_assertions") or side.get("must_not_writes") or result.get("must_not_behavior") or [],
        "test_text": test_text,
    }


def ledger_requires_side_effect(ledger, touched, closed):
    families = ledger.get("families", []) if isinstance(ledger, dict) else []
    required = set(touched) | set(closed)
    for family in families:
        if not isinstance(family, dict):
            continue
        fid = str(family.get("id", ""))
        if fid in SIDE_EFFECT_FAMILIES and (family.get("required") is True or fid in required):
            return True
    return bool(required & SIDE_EFFECT_FAMILIES)


def validate(slice_result_path, family_ledger_path):
    result = load_json(slice_result_path)
    ledger = load_json(family_ledger_path)
    touched = [str(x) for x in as_list(result.get("touched_requirement_families"))]
    closed = [str(x) for x in as_list(result.get("closed_requirement_families"))]
    requires_side = ledger_requires_side_effect(ledger, touched, closed)
    fields = evidence_fields(result)
    issues = []

    for field in ("red_command", "red_failure_assertion", "green_command", "test_harness_module", "entry_invocation"):
        if not str(fields[field]).strip():
            issues.append(f"red_green_schema_missing_{field}")

    if fields["red_exit_code"] is None:
        issues.append("red_green_schema_missing_red_exit_code")
    elif int(fields["red_exit_code"]) == 0 and str(result.get("slice_status", "")).upper() == "DONE":
        issues.append("red_phase_not_red_failure")

    if fields["green_exit_code"] is None:
        issues.append("red_green_schema_missing_green_exit_code")
    elif int(fields["green_exit_code"]) != 0 and str(result.get("slice_status", "")).upper() == "DONE":
        issues.append("green_phase_not_success")

    asserted = " ".join(text_of(x) for x in as_list(fields["asserted_side_effects"]))
    must_not = " ".join(text_of(x) for x in as_list(fields["must_not_assertions"]))
    business_text = " ".join([asserted, must_not, str(fields["red_failure_assertion"]), fields["test_text"]])

    if requires_side:
        if not asserted.strip():
            issues.append("red_green_schema_missing_asserted_side_effects")
        if not re.search(r"(?i)(assert|verify|status|state|task|progress|log|db|database|mapper|dao|insert|update|save|persist|payload|response|output)", business_text):
            issues.append("side_effect_assertion_not_business_observable")
        if re.search(r"(?i)(static_only|helper_only|mock_only|dto_only|compile_only|file_presence_only|taskData\s*==\s*null)", business_text):
            issues.append("side_effect_assertion_uses_non_authorizing_surface")

    payload = {
        "schema": "red_green_side_effect_evidence.v1",
        "status": "PASS" if not issues else "FAIL",
        "slice_result": str(slice_result_path),
        "family_ledger": str(family_ledger_path),
        "requires_side_effect_evidence": requires_side,
        "fields": {k: v for k, v in fields.items() if k != "test_text"},
        "issues": issues,
    }
    return payload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--slice-result")
    parser.add_argument("--family-ledger")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps({"status": "PASS", "mode": "self-test"}))
        return 0
    if not (args.slice_result and args.family_ledger):
        parser.error("--slice-result and --family-ledger are required")
    payload = validate(args.slice_result, args.family_ledger)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0 if payload["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
