#!/bin/bash
set -e

echo "=== ORACLE_CONTRACT_EXTRACTION ==="

REPLAY_ROOT="$1"
ORACLE_COMMIT="$2"
REPO_PATH="$3"

# Check required arguments
if [ -z "$REPLAY_ROOT" ] || [ -z "$ORACLE_COMMIT" ]; then
    echo "Usage: phase0-oracle-contract-extract.sh <replay_root> <oracle_commit> [repo_path]"
    exit 1
fi

# Default repo path
if [ -z "$REPO_PATH" ]; then
    REPO_PATH="$AI_WORKFLOW_PROJECT_ROOT"
fi

CONTRACTS_CACHE="$REPLAY_ROOT/../../ORACLE_CONTRACTS_CACHE.json"
OUTPUT_FILE="$REPLAY_ROOT/ORACLE_CONTRACTS.json"

# Check if oracle contracts already cached from previous rounds
if [ -f "$CONTRACTS_CACHE" ]; then
    echo "Using cached oracle contracts from previous rounds"
    cp "$CONTRACTS_CACHE" "$OUTPUT_FILE"
    echo "ORACLE_CONTRACT_EXTRACTION: COMPLETE (cached)"
    exit 0
fi

# Use Python script for extraction
EXTRACT_SCRIPT="$REPLAY_ROOT/../replay-autopilot/scripts/extract_oracle_contracts.py"

if [ -f "$EXTRACT_SCRIPT" ]; then
    echo "Extracting oracle contracts using Python script..."
    python3 "$EXTRACT_SCRIPT" "$REPO_PATH" "$ORACLE_COMMIT" > "$OUTPUT_FILE"
    echo "ORACLE_CONTRACT_EXTRACTION: COMPLETE"
    echo "Oracle contracts written to $OUTPUT_FILE"

    # Cache for future rounds
    cp "$OUTPUT_FILE" "$CONTRACTS_CACHE"
    echo "Cached for future rounds at $CONTRACTS_CACHE"

    # Show summary
    if command -v jq >/dev/null 2>&1; then
        echo "Summary:"
        jq -r '.summary' "$OUTPUT_FILE" 2>/dev/null || echo "See full output in $OUTPUT_FILE"
    fi
    exit 0
fi

# Fallback: Create placeholder for manual oracle inspection
echo "Python extraction script not found, creating placeholder for manual inspection"
cat > "$OUTPUT_FILE" <<'EOF'
{
  "extracted_at": "placeholder",
  "oracle_commit": "$ORACLE_COMMIT",
  "note": "Python extraction script not found - manual oracle inspection required",
  "contracts": {},
  "summary": {
    "total_classes": 0,
    "total_methods": 0
  }
}
EOF

echo "ORACLE_CONTRACT_EXTRACTION: INCOMPLETE (placeholder created)"
echo "Please run: python3 $AI_WORKFLOW_REPLAY_AUTOPILOT_ROOT\scripts\extract_oracle_contracts.py \"$REPO_PATH\" \"$ORACLE_COMMIT\" > \"$OUTPUT_FILE\""
exit 1
