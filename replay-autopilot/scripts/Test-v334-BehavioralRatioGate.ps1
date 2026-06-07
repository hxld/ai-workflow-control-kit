# Test-v334-BehavioralRatioGate.ps1
# Tests the v334 behavioral ratio enforcement in RED phase hard gate

param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'scripts'

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )
    if ($Text -notmatch $Pattern) {
        throw "Assertion failed: $Name"
    }
    return $Name
}

$cases = New-Object System.Collections.Generic.List[string]

# Read the enhanced RED phase gate script
$redGateScript = Get-Content -LiteralPath (Join-Path $scripts 'Invoke-RedPhaseHardGate.ps1') -Raw -Encoding UTF8

# Test 1: Verify Test-BehavioralTestCharter function exists
$cases.Add((Assert-Contains 'function_exists' $redGateScript 'function Test-BehavioralTestCharter')) | Out-Null

# Test 2: Verify structural patterns are defined
$cases.Add((Assert-Contains 'structural_patterns' $redGateScript 'assertFalse.*isInterface')) | Out-Null
$cases.Add((Assert-Contains 'structural_patterns_class' $redGateScript 'forName')) | Out-Null

# Test 3: Verify behavioral patterns are defined
$cases.Add((Assert-Contains 'behavioral_patterns_insert' $redGateScript 'verify.*Mapper.*insert')) | Out-Null
$cases.Add((Assert-Contains 'behavioral_patterns_update' $redGateScript 'verify.*Mapper.*update')) | Out-Null
$cases.Add((Assert-Contains 'behavioral_patterns_status' $redGateScript 'assertEquals.*status')) | Out-Null

# Test 4: Verify ratio calculation logic
$cases.Add((Assert-Contains 'ratio_calculation' $redGateScript 'behavioralRatio.*behavioralCount.*totalAssertions')) | Out-Null
$cases.Add((Assert-Contains 'ratio_threshold_check' $redGateScript 'behavioralRatio.*lt.*0')) | Out-Null

# Test 5: Verify integration in VerifyOnly mode
$cases.Add((Assert-Contains 'behavioral_charter_validation_comment' $redGateScript '# Behavioral test charter validation')) | Out-Null
$cases.Add((Assert-Contains 'behavioral_ratio_result_field' $redGateScript 'result.*behavioral_ratio')) | Out-Null
$cases.Add((Assert-Contains 'structural_count_result_field' $redGateScript 'result.*structural_count')) | Out-Null
$cases.Add((Assert-Contains 'behavioral_count_result_field' $redGateScript 'result.*behavioral_count')) | Out-Null

# Test 6: Verify blocking when behavioral ratio < 0.5
$cases.Add((Assert-Contains 'block_on_low_ratio' $redGateScript 'IsValid.*false')) | Out-Null
$cases.Add((Assert-Contains 'set_block_green_on_invalid' $redGateScript 'block_green.*true')) | Out-Null
$cases.Add((Assert-Contains 'add_issue_on_invalid' $redGateScript 'issues.*New-GateIssue')) | Out-Null

# Test 7: Verify test file search logic
$cases.Add((Assert-Contains 'test_file_search' $redGateScript 'Get-ChildItem -LiteralPath \$searchPath -Recurse -Filter')) | Out-Null

# Test 8: Verify function returns proper structure
$cases.Add((Assert-Contains 'returns_isvalid' $redGateScript 'IsValid = \$false')) | Out-Null
$cases.Add((Assert-Contains 'returns_ratio' $redGateScript 'BehavioralRatio = \$behavioralRatio')) | Out-Null
$cases.Add((Assert-Contains 'returns_reason' $redGateScript 'Reason = ')) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
    version = 'v334'
    enhancement = 'behavioral_ratio_enforcement'
} | ConvertTo-Json -Depth 6
