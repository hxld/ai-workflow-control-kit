#!/usr/bin/env python3
"""
Test Charter Pre-Validation Gate (Hypothesis 1 from NEXT_EXPERIMENT_PLAN.md)

Validates TEST_CHARTER.md completeness BEFORE RED phase starts.
Prevents wrong_test_surface failures by requiring complete test charters.

Required sections:
1. Entry Point: Exact Facade/Controller method to test
2. Test Surface: Test class at Facade/Controller layer, NOT Service layer
3. DB Verification: SELECT queries for each side effect
4. Transaction Test: Rollback scenario for stateful operations
5. Side Effects: List with verification method
"""

import re
import sys
import json
from pathlib import Path
from typing import List, Dict, Tuple


class TestCharterValidator:
    """Validates TEST_CHARTER.md completeness before RED phase."""

    # Patterns to identify test layer
    SERVICE_LAYER_PATTERNS = [r'\w+Service', r'\w+ServiceImpl']
    FACADE_LAYER_PATTERNS = [r'\w+Facade', r'\w+FacadeImpl', r'\w+Controller']

    # Required section patterns
    ENTRY_POINT_PATTERNS = [
        r'Entry Point:|Target Entry:|Testing Entry:|测试入口:',
        r'Method to Test:|Target Method:',
    ]
    DB_VERIFICATION_PATTERNS = [
        r'SELECT\s+',
        r'DB Query:|数据库查询:',
        r'Verification Query:|验证查询:',
    ]
    SIDE_EFFECT_PATTERNS = [
        r'Side Effects?:|副作用:',
        r'Expected DB Changes:|预期数据库变更:',
        r'DB State Change:|数据库状态变更:',
    ]
    TRANSACTION_TEST_PATTERNS = [
        r'@Transactional',
        r'transaction.*rollback',
        r'事务.*回滚',
    ]

    def __init__(self, charter_path: Path):
        self.charter_path = charter_path
        self.content = charter_path.read_text(encoding='utf-8', errors='ignore') if charter_path.exists() else ""
        self.failures = []
        self.warnings = []

    def validate(self) -> bool:
        """Run all validation checks."""
        if not self.content:
            self.failures.append({
                'code': 'TEST_CHARTER_EMPTY',
                'message': 'Test charter file is empty or missing'
            })
            return False

        # Required section validations
        self._validate_entry_point()
        self._validate_test_surface()
        self._validate_db_verifications()
        self._validate_transaction_tests()
        self._validate_side_effects()

        return len(self.failures) == 0

    def _validate_entry_point(self):
        """Check if entry point is specified."""
        has_entry = any(
            re.search(pattern, self.content, re.IGNORECASE | re.MULTILINE)
            for pattern in self.ENTRY_POINT_PATTERNS
        )

        if not has_entry:
            self.failures.append({
                'code': 'MISSING_ENTRY_POINT',
                'message': 'Entry point not specified in test charter',
                'detail': 'Required: Add "Entry Point: YourFacade.yourMethod()" or similar'
            })

    def _validate_test_surface(self):
        """Check if test surface is at correct layer (Facade/Controller, not Service)."""
        # Extract test class pattern
        test_class_match = re.search(
            r'Test Class:|测试类:|Target Test:|test class:',
            self.content,
            re.IGNORECASE
        )

        if not test_class_match:
            self.warnings.append({
                'code': 'TEST_CLASS_NOT_SPECIFIED',
                'message': 'Test class not explicitly specified'
            })
            return

        # Get surrounding context (next 200 chars)
        match_end = test_class_match.end()
        context = self.content[match_end:match_end + 200].lower()

        # Check if testing Service layer (wrong)
        has_service = any(re.search(p, context) for p in self.SERVICE_LAYER_PATTERNS)
        has_facade = any(re.search(p, context) for p in self.FACADE_LAYER_PATTERNS)

        if has_service and not has_facade:
            self.failures.append({
                'code': 'WRONG_TEST_SURFACE',
                'message': 'Testing Service layer instead of Facade/Controller layer',
                'detail': 'Service layer tests cannot verify full request/response flow. Move test to Facade or Controller layer.'
            })

    def _validate_db_verifications(self):
        """Check if DB verification queries are documented."""
        has_select = 'SELECT' in self.content.upper()
        has_query = any(
            re.search(pattern, self.content, re.IGNORECASE)
            for pattern in self.DB_VERIFICATION_PATTERNS
        )
        has_assertion = 'assertThat' in self.content or 'Assert' in self.content
        has_atomic_reference = 'AtomicReference' in self.content

        if not (has_select or has_query or has_atomic_reference):
            self.warnings.append({
                'code': 'MISSING_DB_VERIFICATION',
                'message': 'No DB verification queries found',
                'detail': 'Required: Add SELECT queries or AtomicReference capture patterns for side effects'
            })

    def _validate_transaction_tests(self):
        """Check if transaction test is specified for stateful operations."""
        has_transaction = any(
            re.search(pattern, self.content, re.IGNORECASE)
            for pattern in self.TRANSACTION_TEST_PATTERNS
        )

        # Check if side effects are documented (would require transaction test)
        has_side_effects = any(
            re.search(pattern, self.content, re.IGNORECASE)
            for pattern in self.SIDE_EFFECT_PATTERNS
        )

        if has_side_effects and not has_transaction:
            self.warnings.append({
                'code': 'MISSING_TRANSACTION_TEST',
                'message': 'Stateful operations should include transaction rollback test',
                'detail': 'For operations with DB side effects, add @Transactional test with expected rollback'
            })

    def _validate_side_effects(self):
        """Check if side effects are listed with verification method."""
        side_effect_match = re.search(
            r'Side Effects?:|副作用:|Expected DB Changes:|预期数据库变更:',
            self.content,
            re.IGNORECASE
        )

        if not side_effect_match:
            self.warnings.append({
                'code': 'MISSING_SIDE_EFFECTS_LIST',
                'message': 'Side effects not explicitly listed'
            })
            return

        # Extract side effects section (next 20 lines)
        se_section = self.content[side_effect_match.end():]
        se_lines = [line.strip() for line in se_section.split('\n')[:20] if line.strip()]

        verified_count = sum(1 for line in se_lines if any(
            keyword in line.lower()
            for keyword in ['verify', 'assert', '验证', 'SELECT', 'query']
        ))
        total_count = len(se_lines)

        if total_count > 0 and verified_count == 0:
            self.failures.append({
                'code': 'SIDE_EFFECTS_NOT_VERIFIED',
                'message': 'Side effects listed but no verification method specified',
                'detail': 'Each side effect must have verification (assert, verify, SELECT query, or AtomicReference)'
            })

    def report(self) -> Dict:
        """Generate validation report."""
        result = {
            'valid': len(self.failures) == 0,
            'status': 'PASS' if len(self.failures) == 0 else 'FAIL',
            'charter_file': str(self.charter_path),
            'failures': self.failures,
            'warnings': self.warnings,
            'failure_count': len(self.failures),
            'warning_count': len(self.warnings),
        }

        # Add remediation guidance
        if self.failures:
            result['remediation'] = self._generate_remediation()

        return result

    def _generate_remediation(self) -> str:
        """Generate remediation guidance for failures."""
        lines = ["ACTION REQUIRED:"]
        lines.append("  1. Fix all failures listed above")
        lines.append("  2. Re-run validation")
        lines.append("  3. Only proceed to RED phase after validation passes")

        # Specific guidance per failure code
        codes = {f['code'] for f in self.failures}
        if 'WRONG_TEST_SURFACE' in codes:
            lines.append("")
            lines.append("For WRONG_TEST_SURFACE:")
            lines.append("  - Change test class from Service to Facade/Controller")
            lines.append("  - Example: AiAutoClaimFlowServiceTest → AiAutoClaimFlowFacadeTest")

        if 'MISSING_ENTRY_POINT' in codes:
            lines.append("")
            lines.append("For MISSING_ENTRY_POINT:")
            lines.append("  - Add 'Entry Point: YourFacade.yourMethod(paramTypes)' section")

        if 'SIDE_EFFECTS_NOT_VERIFIED' in codes:
            lines.append("")
            lines.append("For SIDE_EFFECTS_NOT_VERIFIED:")
            lines.append("  - Add verification method for each side effect")
            lines.append("  - Example: 'SELECT * FROM t_compensate_detail WHERE case_id = ?'")

        return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: test_charter_prevalidator.py <TEST_CHARTER.md> [--output json]", file=sys.stderr)
        sys.exit(1)

    charter_path = Path(sys.argv[1])
    output_mode = 'json' if '--output' in sys.argv and 'json' in sys.argv else 'text'

    validator = TestCharterValidator(charter_path)
    validator.validate()
    report = validator.report()

    if output_mode == 'json':
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        # Text output
        print("=== TEST CHARTER VALIDATION ===")
        print(f"File: {charter_path}")
        print()

        if report['valid']:
            print("Status: PASSED")
            print()
            print("Test charter is complete and ready for RED phase.")
        else:
            print("Status: FAILED")
            print()

            if report['failures']:
                print("FAILURES (must fix):")
                for f in report['failures']:
                    print(f"  ❌ [{f['code']}] {f['message']}")
                    if 'detail' in f:
                        print(f"     {f['detail']}")

            if report['warnings']:
                print()
                print("WARNINGS (recommended):")
                for w in report['warnings']:
                    print(f"  ⚠️  [{w['code']}] {w['message']}")

            print()
            print(report.get('remediation', ''))

    sys.exit(0 if report['valid'] else 1)


if __name__ == '__main__':
    main()
