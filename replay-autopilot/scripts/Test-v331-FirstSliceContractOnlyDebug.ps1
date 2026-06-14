# Debug script for first_slice_proof_invalid:contract_only_first_slice issue

param(
    [string]$ReplayRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\aiClaimV2\claim-codex-replay-v330-autopilot-20260517-r01"
)

$ErrorActionPreference = 'Stop'

function Get-KeyValueField {
    param([string]$Text, [string]$Field)
    $escapedField = [regex]::Escape($Field)
    foreach ($line in ($Text -split "\r?\n")) {
        $lineMatch = [regex]::Match($line.Trim(), '^(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*(.+?)\s*$')
        if ($lineMatch.Success) {
            return $lineMatch.Groups[1].Value.Trim()
        }
    }
    $patterns = @(
        '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*([^\r\n]+?)\s*$',
        '(?im)^\s*(?:\*{0,2}\s*)?(?:[-*]\s*)?' + $escapedField + '\s*\*{0,2}\s*[:=|][ \t]*\r?\n\s*:\s*([^\r\n]+?)\s*$',
        '(?im)\|\s*\*{0,2}' + $escapedField + '\*{0,2}\s*\|\s*`?([^\r\n|]+?)`?\s*\|'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

$firstSliceProofPath = Join-Path $ReplayRoot 'FIRST_SLICE_PROOF_PLAN.md'
$planResultPath = Join-Path $ReplayRoot 'PLAN_RESULT.md'

if (-not (Test-Path -LiteralPath $firstSliceProofPath)) {
    Write-Host "FIRST_SLICE_PROOF_PLAN.md not found: $firstSliceProofPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $planResultPath)) {
    Write-Host "PLAN_RESULT.md not found: $planResultPath"
    exit 1
}

$firstSliceProofText = Get-Content -LiteralPath $firstSliceProofPath -Raw -Encoding UTF8
$planResultText = Get-Content -LiteralPath $planResultPath -Raw -Encoding UTF8

$contractOnlyPattern = '(?i)(CONTRACT_ONLY|contract\s*(?:&|and)\s*RED(?!\s*(?:&|and)\s*GREEN)|contract\s+definition|contract\s+classes?|tests?\s+only|RED[-\s]*only|no\s+production\s+code|does\s+not\s+touch\s+production|produces\s+no\s+production|defer(?:red)?\s+to\s+S\d|to\s+be\s+implemented\s+in\s+Slice\s+\d)'
$noneLikePattern = '(?i)^\s*(NONE|N/A|NOT_APPLICABLE|none_with_reason|PLAN_BLOCKED_[A-Z0-9_]+)\b'

# Get plan status
$planStatusMatch = [regex]::Match($planResultText, '(?im)^\s*-?\s*plan_status\s*[:=]\s*[`*]*([A-Z_]+)[`*]*')
if (-not $planStatusMatch.Success) {
    $planStatusMatch = [regex]::Match($planResultText, '(?im)\*\*plan_status\*\*\s*[:=]\s*[`*]*([A-Z_]+)[`*]*')
}
if (-not $planStatusMatch.Success) {
    $planStatusMatch = [regex]::Match($planResultText, '(?mi)^##\s*Plan\s*Status\s*\r?\n\s*\*{0,2}\s*([A-Z_]+)')
}
$planStatus = if ($planStatusMatch.Success) { $planStatusMatch.Groups[1].Value.Trim() } else { 'UNKNOWN' }

Write-Host "=== Debug Info ===" -ForegroundColor Cyan
Write-Host "plan_status: $planStatus"
Write-Host ""

# Get key fields
$fields = @('first_slice', 'minimum_side_effect_or_blocker', 'production_boundary', 'expected_production_diff', 'green_minimum_implementation')
$fieldValues = @{}
foreach ($field in $fields) {
    $value = Get-KeyValueField -Text $firstSliceProofText -Field $field
    $fieldValues[$field] = $value
    Write-Host "$field`: $value" -ForegroundColor Yellow

    # Check if value matches patterns
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        if ($value -match $noneLikePattern) {
            Write-Host "  -> Matches noneLikePattern!" -ForegroundColor Red
        }
        if ($value -match $contractOnlyPattern) {
            Write-Host "  -> Matches contractOnlyPattern!" -ForegroundColor Red
        }
    } else {
        Write-Host "  -> Empty/NULL" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "=== Pattern Check ===" -ForegroundColor Cyan
Write-Host "contractOnlyPattern: $contractOnlyPattern"
Write-Host "noneLikePattern: $noneLikePattern"
Write-Host ""

Write-Host "=== Verdict ===" -ForegroundColor Cyan
if ($planStatus -eq 'PROCEED') {
    $issues = @()
    if ([string]::IsNullOrWhiteSpace($fieldValues['minimum_side_effect_or_blocker']) -or
        $fieldValues['minimum_side_effect_or_blocker'] -match $noneLikePattern -or
        $fieldValues['minimum_side_effect_or_blocker'] -match $contractOnlyPattern) {
        $issues += 'first_slice_proof_invalid:minimum_side_effect_or_blocker'
    }
    if ([string]::IsNullOrWhiteSpace($fieldValues['production_boundary']) -or
        $fieldValues['production_boundary'] -match $noneLikePattern -or
        $fieldValues['production_boundary'] -match $contractOnlyPattern) {
        $issues += 'first_slice_proof_invalid:contract_only_first_slice (from production_boundary)'
    }
    if ([string]::IsNullOrWhiteSpace($fieldValues['expected_production_diff']) -or
        $fieldValues['expected_production_diff'] -match $noneLikePattern -or
        $fieldValues['expected_production_diff'] -match $contractOnlyPattern) {
        $issues += 'first_slice_proof_invalid:expected_production_diff_none'
    }
    if ($fieldValues['first_slice'] -match $contractOnlyPattern) {
        $issues += 'first_slice_proof_invalid:contract_only_first_slice (from first_slice)'
    }

    if ($issues.Count -gt 0) {
        Write-Host "Issues found:" -ForegroundColor Red
        foreach ($issue in $issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
    } else {
        Write-Host "No issues found (verifier should PASS)" -ForegroundColor Green
    }
} else {
    Write-Host "plan_status is not PROCEED, skipping contract-only checks" -ForegroundColor Yellow
}
