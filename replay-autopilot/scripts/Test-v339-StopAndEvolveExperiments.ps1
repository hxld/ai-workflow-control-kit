# Test-v339-StopAndEvolveExperiments.ps1
# Tests for v339 stop-and-evolve experiment implementation
# - Experiment 1: Stateful Success Slice for high-weight, multi-surface core_entry
# - Experiment 2: RED Phase Hard Gate (already implemented in v334)
# - Experiment 3: Business Assertion Threshold (minimum 3 assertions)

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptRoot

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
        tests = @(
            'experiment1_stateful_success_slice_condition',
            'experiment3_assertion_threshold'
        )
    } | ConvertTo-Json -Depth 6
    exit 0
}

$cases = New-Object System.Collections.Generic.List[string]
$evidence = [ordered]@{}

# === Test 1: Experiment 1 - Stateful Success Slice Condition ===
Write-Host "Test 1: Experiment 1 - Stateful Success Slice Condition"

$runSliceLoopPath = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$content = Get-Content -LiteralPath $runSliceLoopPath -Raw -Encoding UTF8

# Check for the enhanced condition
$hasWeightCheck = $content -match 'weight.*-ge.*90'
$hasSiblingCountCheck = $content -match 'siblingCount.*-ge.*3'
$hasStatefulSlice = $content -match 'stateful_success_slice'

if ($hasWeightCheck -and $hasSiblingCountCheck -and $hasStatefulSlice) {
    $cases.Add('experiment1_stateful_success_slice_condition') | Out-Null
    $evidence.experiment1 = 'PASS'
    Write-Host "  Experiment 1: PASS - Stateful Success Slice condition found"
} else {
    $evidence.experiment1 = 'FAIL'
    Write-Host "  Experiment 1: FAIL - Missing required condition"
    Write-Host "    weight>=90: $hasWeightCheck"
    Write-Host "    siblingCount>=3: $hasSiblingCountCheck"
    Write-Host "    stateful_success_slice: $hasStatefulSlice"
}

# === Test 2: Experiment 3 - Business Assertion Threshold ===
Write-Host "`nTest 2: Experiment 3 - Business Assertion Threshold"

$redGatePath = Join-Path $scriptRoot 'Invoke-RedPhaseHardGate.ps1'
$redGateContent = Get-Content -LiteralPath $redGatePath -Raw -Encoding UTF8

# Check for assertion threshold implementation
$hasMinAssertions = $redGateContent -match 'minAssertions.*=.*3'
$hasInsufficientCheck = $redGateContent -match 'insufficient_business_assertions'
$hasRequiredAssertionCountField = $redGateContent -match 'required_assertion_count'
$hasLiteralTrueExclusion = $redGateContent -match 'assertTrue\(true\)'

if ($hasMinAssertions -and $hasInsufficientCheck -and $hasRequiredAssertionCountField -and $hasLiteralTrueExclusion) {
    $cases.Add('experiment3_assertion_threshold') | Out-Null
    $evidence.experiment3 = 'PASS'
    Write-Host "  Experiment 3: PASS - Business Assertion Threshold found"
} else {
    $evidence.experiment3 = 'FAIL'
    Write-Host "  Experiment 3: FAIL - Missing assertion threshold implementation"
    Write-Host "    minAssertions=3: $hasMinAssertions"
    Write-Host "    insufficient_business_assertions: $hasInsufficientCheck"
    Write-Host "    required_assertion_count field: $hasRequiredAssertionCountField"
    Write-Host "    assertTrue(true) exclusion: $hasLiteralTrueExclusion"
}

# === Test 3: Experiment 2 - RED Phase Hard Gate (Already Implemented) ===
Write-Host "`nTest 3: Experiment 2 - RED Phase Hard Gate (v334)"

# Check that RED gate already has behavioral charter validation
$hasBehavioralCharterFunc = $redGateContent -match 'function Test-BehavioralTestCharter'
$hasBehavioralRatioCheck = $redGateContent -match 'behavioral_ratio'
$hasStructuralOnlyCheck = $redGateContent -match 'structural_only_test'

if ($hasBehavioralCharterFunc -and $hasBehavioralRatioCheck -and $hasStructuralOnlyCheck) {
    $cases.Add('experiment2_red_phase_hard_gate') | Out-Null
    $evidence.experiment2 = 'PASS'
    Write-Host "  Experiment 2: PASS - RED Phase Hard Gate already implemented (v334)"
} else {
    $evidence.experiment2 = 'FAIL'
    Write-Host "  Experiment 2: FAIL - RED Phase Hard Gate implementation missing"
}

# === Summary ===
$allPass = $cases.Count -ge 2 -and $evidence.experiment1 -eq 'PASS' -and $evidence.experiment3 -eq 'PASS'

$result = [ordered]@{
    status = if ($allPass) { 'PASS' } else { 'FAIL' }
    script = $PSCommandPath
    cases = @($cases)
    evidence = $evidence
    version = 'v339'
    evolution_type = 'stop_and_evolve_experiments'
}

Write-Host "`n=== Summary ==="
Write-Host "Status: $($result.status)"
Write-Host "Passed Cases: $($cases.Count)/3"
Write-Host "  - Experiment 1: $($evidence.experiment1)"
Write-Host "  - Experiment 2: $($evidence.experiment2)"
Write-Host "  - Experiment 3: $($evidence.experiment3)"

$result | ConvertTo-Json -Depth 10

if (-not $allPass) {
    exit 1
}
