# Test v416: Blocker Markdown Format Support

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Get-FirstText {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($Pattern in $Patterns) {
        $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            if ($match.Groups.Count -gt 1) {
                return $match.Groups[1].Value.Trim()
            }
        }
    }
    return ''
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

# Test the blocker regex patterns directly
$planText1 = @'
# Plan Result

plan_status: BLOCKED

## Blocker

**Blocker**: oracle_overlap_below_threshold

**Reason**: Current oracle overlap is below threshold.
'@

$planText2 = @'
# Plan Result

- plan_status: BLOCKED
- blocker: oracle_overlap_below_threshold
'@

$planText3 = @'
# Plan Result

plan_status: BLOCKED
blocker: oracle_high_weight_overlap_below_threshold
'@

$planText4 = @'
# Plan Result

plan_status: BLOCKED

**Blocker**: oracle_high_weight_overlap_below_threshold
'@

# Test the regex patterns
$blockerPatterns = @(
    '(?m)^\s*-?\s*blocker\s*[:=]\s*(.+?)\s*$',
    '(?m)^\s*blocker\s*:\s*(.+?)\s*$',
    '(?m)\*?\*?Blocker\*?\*?\s*:\s*(.+?)\s*$',
    '(?i)\*\*?blocker\*?\*?\s*[:=]\s*(.+?)\s*$'
)

# Test 1: Markdown format with bold
$blocker1 = Get-FirstText -Text $planText1 -Patterns $blockerPatterns
Assert-True ($blocker1 -eq 'oracle_overlap_below_threshold') "Markdown format blocker should be extracted: got '$blocker1'"

# Test 2: YAML list format
$blocker2 = Get-FirstText -Text $planText2 -Patterns $blockerPatterns
Assert-True ($blocker2 -eq 'oracle_overlap_below_threshold') "YAML list format blocker should be extracted: got '$blocker2'"

# Test 3: Plain YAML format
$blocker3 = Get-FirstText -Text $planText3 -Patterns $blockerPatterns
Assert-True ($blocker3 -eq 'oracle_high_weight_overlap_below_threshold') "Plain YAML format blocker should be extracted: got '$blocker3'"

# Test 4: Markdown format with high-weight blocker
$blocker4 = Get-FirstText -Text $planText4 -Patterns $blockerPatterns
Assert-True ($blocker4 -eq 'oracle_high_weight_overlap_below_threshold') "Markdown format high-weight blocker should be extracted: got '$blocker4'"

# Test stale blocker detection conditions
$planStatus = 'BLOCKED'
$isStale1 = ($planStatus -eq 'BLOCKED') -and ($blocker1 -match 'oracle_overlap_below_threshold')
Assert-True $isStale1 "Stale blocker should be detected for markdown format"

$isStale2 = ($planStatus -eq 'BLOCKED') -and ($blocker4 -match 'oracle_high_weight_overlap_below_threshold')
Assert-True $isStale2 "Stale high-weight blocker should be detected for markdown format"

[ordered]@{
    status = 'PASS'
    assertions = 6
    cases = @(
        'markdown_bold_blocker_extraction',
        'yaml_list_blocker_extraction',
        'plain_yaml_blocker_extraction',
        'markdown_high_weight_blocker_extraction',
        'stale_blocker_detection_markdown',
        'stale_high_weight_blocker_detection_markdown'
    )
} | ConvertTo-Json -Depth 5
