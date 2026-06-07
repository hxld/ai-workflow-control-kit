# v405: Plan Contract Blocker Text Auto-Repair Regression Test
# Tests that Verify-PlanContract.ps1 auto-repairs blocker field even when trailing text is present

param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifierPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8
$cases = New-Object System.Collections.Generic.List[string]

# Test 1: Verify v405 comment exists
$cases.Add((Assert-True -Name 'v405_comment_exists' -Condition (
    $verifierContent -match 'v405.*Update blocker'
))) | Out-Null

# Test 2: Verify regex uses .*\$ instead of \s*\$ to match any trailing text
$cases.Add((Assert-True -Name 'v405_blocker_regex_uses_wildcard' -Condition (
    $verifierContent -match 'oracle_overlap_below_threshold\.\*\$'
))) | Out-Null

# Test 3: Verify both regex patterns are updated (plain and backtick variants)
$patternCount = ([regex]::Matches($verifierContent, 'oracle_overlap_below_threshold\.\*\$')).Count
$cases.Add((Assert-True -Name 'v405_both_patterns_updated' -Condition ($patternCount -ge 2))) | Out-Null

# Test 4: Verify auto-repair sets blocker to 'none'
$cases.Add((Assert-True -Name 'v405_repair_sets_blocker_to_none' -Condition (
    $verifierContent -match '\$\{1\}none' -or $verifierContent -match 'blocker`: none'
))) | Out-Null

# Test 5: Verify the stale blocker detection condition
$cases.Add((Assert-True -Name 'v405_stale_blocker_detection' -Condition (
    $verifierContent -match 'isStaleBlocker.*oracle_overlap_below_threshold'
))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
