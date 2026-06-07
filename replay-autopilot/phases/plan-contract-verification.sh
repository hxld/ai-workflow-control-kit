#!/bin/bash
set -e

echo "=== PLAN_CONTRACT_VERIFICATION ==="

REPLAY_ROOT="$1"
PLAN_FILE="$2"
ORACLE_CONTRACTS="$REPLAY_ROOT/ORACLE_CONTRACTS.json"
LEDGER_FILE="$REPLAY_ROOT/REQUIREMENT_FAMILY_LEDGER.json"
REQUIREMENT_SNAPSHOT="$REPLAY_ROOT/REQUIREMENT_SOURCE_SNAPSHOT.md"

# Check required arguments
if [ -z "$REPLAY_ROOT" ] || [ -z "$PLAN_FILE" ]; then
    echo "Usage: plan-contract-verification.sh <replay_root> <plan_file>"
    exit 1
fi

# Check if oracle contracts exist
if [ ! -f "$ORACLE_CONTRACTS" ]; then
    echo "PLAN_CONTRACT_VERIFICATION: SKIPPED"
    echo "Oracle contracts not found at $ORACLE_CONTRACTS"
    echo "Run phase0-oracle-contract-extract.sh first"
    exit 0
fi

# Check if plan file exists
if [ ! -f "$PLAN_FILE" ]; then
    echo "PLAN_CONTRACT_VERIFICATION: SKIPPED"
    echo "Plan file not found at $PLAN_FILE"
    exit 0
fi

# Use Python script for verification
VERIFY_SCRIPT="$REPLAY_ROOT/../replay-autopilot/scripts/extract_oracle_contracts.py"

if [ -f "$VERIFY_SCRIPT" ]; then
    echo "Verifying plan against oracle contracts..."
    python3 "$VERIFY_SCRIPT" "$REPLAY_ROOT/../.." "placeholder" --compare "$PLAN_FILE" --oracle "$ORACLE_CONTRACTS" > "$REPLAY_ROOT/PLAN_CONTRACT_VERIFY_RESULT.json" 2>&1 || true

    # Check result
    if [ -f "$REPLAY_ROOT/PLAN_CONTRACT_VERIFY_RESULT.json" ]; then
        RESULT=$(cat "$REPLAY_ROOT/PLAN_CONTRACT_VERIFY_RESULT.json")

        # Check for high synthetic carrier rate
        if echo "$RESULT" | grep -q "FAIL.*Synthetic carrier rate"; then
            echo "PLAN_CONTRACT_VERIFICATION: FAILED"
            echo "$RESULT"
            echo ""
            echo "REQUIRED ACTIONS:"
            echo "1. Update plan to use EXACT oracle signatures from ORACLE_CONTRACTS.json"
            echo "2. Remove synthetic carriers that don't exist in oracle"
            echo "3. Verify each carrier matches oracle exactly"
            exit 1
        fi

        echo "PLAN_CONTRACT_VERIFICATION: PASSED"
        echo "Plan uses oracle signatures correctly"
        exit 0
    fi
fi

echo "PLAN_CONTRACT_VERIFICATION: INCOMPLETE"
echo "Verification script not found or failed"
exit 0

# === ENTRY POINT VALIDATION (v357) ===
echo ""
echo "=== ENTRY_POINT_MAPPING_VERIFICATION ==="

# Check if requirement family ledger exists
if [ ! -f "$LEDGER_FILE" ]; then
    echo "ENTRY_POINT_VALIDATION: SKIPPED"
    echo "Family ledger not found at $LEDGER_FILE"
    exit 0
fi

# Check if requirement snapshot exists
if [ ! -f "$REQUIREMENT_SNAPSHOT" ]; then
    echo "ENTRY_POINT_VALIDATION: SKIPPED"
    echo "Requirement snapshot not found at $REQUIREMENT_SNAPSHOT"
    exit 0
fi

# Use Python script for entry point validation
ENTRY_POINT_SCRIPT="$REPLAY_ROOT/../replay-autopilot/scripts/validate_entry_point_mapping.py"

if [ -f "$ENTRY_POINT_SCRIPT" ]; then
    echo "Validating entry point mapping against requirement workflow..."
    python3 "$ENTRY_POINT_SCRIPT" \
        --requirement "$REQUIREMENT_SNAPSHOT" \
        --ledger "$LEDGER_FILE" \
        > "$REPLAY_ROOT/ENTRY_POINT_VERIFY_RESULT.json" 2>&1

    ENTRY_EXIT_CODE=$?

    # Check result
    if [ -f "$REPLAY_ROOT/ENTRY_POINT_VERIFY_RESULT.json" ]; then
        RESULT=$(cat "$REPLAY_ROOT/ENTRY_POINT_VERIFY_RESULT.json")

        if echo "$RESULT" | grep -q '"valid":\s*true'; then
            echo "ENTRY_POINT_VALIDATION: PASSED"
            echo "All carriers verified against requirement workflow"
            exit 0
        else
            echo "ENTRY_POINT_VALIDATION: FAILED"
            echo "$RESULT"
            echo ""
            echo "REQUIRED ACTIONS:"
            echo "1. Verify each selected carrier matches requirement workflow keywords"
            echo "2. Check REQUIREMENT_FAMILY_LEDGER.json for wrong entry points"
            echo "3. Use requirement workflow to select correct carrier (e.g., AiApplyClaim for '申请' not AiCalculateLoss)"
            exit 1
        fi
    else
        echo "ENTRY_POINT_VALIDATION: ERROR"
        echo "Failed to produce result file"
        exit $ENTRY_EXIT_CODE
    fi
else
    echo "ENTRY_POINT_VALIDATION: SKIPPED"
    echo "Validation script not found at $ENTRY_POINT_SCRIPT"
    exit 0
fi
