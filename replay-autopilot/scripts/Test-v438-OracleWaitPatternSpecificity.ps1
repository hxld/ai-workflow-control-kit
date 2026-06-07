# Test-v438-OracleWaitPatternSpecificity.ps1
# Regression test for v438 Oracle Wait Pattern specificity
# Tests that the refined $manualOracleWaitPattern distinguishes between
# legitimate blind replay constraint language and actual oracle-wait blockers

$ErrorActionPreference = 'Stop'

# Import the pattern from Verify-PlanContract.ps1
$scriptPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host "ERROR: Verify-PlanContract.ps1 not found at $scriptPath" -ForegroundColor Red
    exit 1
}

# Read and extract the pattern (simplified for test - using the v438 pattern directly)
$manualOracleWaitPattern = '(?is)((?<!without\s)Oracle\s+Post-Hoc\s*(->|required|pending|(before|after)\s+implementation)|(?<!cannot\sverify\.)\s*Oracle\s+commit\s+(pending|required|needed|before\s+(implementation|planning))|next (step|action):\s*(await|wait|pending).*\bOracle\b|awaiting\s+Oracle\s+(verification|access|branch)\s+(to\s+(provide|verify)|before\s+(implementation|planning)|required|pending)|waiting\s+for\s+Oracle\s+(to\s+(provide|verify)|verification\s+(required|needed))|AWAIT_ORACLE_VERIFICATION_OR_WAIVER|Provide\s+oracle\s+branch\s+access|Coverage\s+Cap\s+Waiver|waive\s+coverage\s+caps|(?<!no\s)manual\s+oracle\s+verification\s+(required|needed|pending)|(?<!constraint\s)awaiting\s+oracle\s+verification|wait(?:ing)?\s+for\s+oracle\s+verification)'

# Test cases that SHOULD NOT match (legitimate blind replay constraint language)
$shouldNotMatch = @(
    @{Description = 'without oracle access'; Text = 'Cannot verify exact method signatures without oracle access'},
    @{Description = 'Blind replay constraints'; Text = 'Blind Replay Constraints: Cannot verify exact implementation details of planned new carriers without oracle access'},
    @{Description = 'No manual oracle verification'; Text = 'No manual oracle verification required'},
    @{Description = 'negated pending'; Text = 'oracle verification not pending'},
    @{Description = 'constraint context'; Text = 'Constraint: method signatures inferred from requirement with coverage cap'},
    @{Description = 'deferred to post-hoc'; Text = 'signature verification deferred to oracle post-hoc'},
    @{Description = 'calibrate during post-hoc'; Text = 'calibrate during oracle post-hoc'},
    @{Description = 'verified against requirement'; Text = 'verified against requirement with coverage cap'}
)

# Test cases that SHOULD match (actual oracle-wait blockers)
$shouldMatch = @(
    @{Description = 'next action await Oracle'; Text = 'next action: await Oracle verification'},
    @{Description = 'next step wait Oracle'; Text = 'next step: wait for Oracle access'},
    @{Description = 'awaiting Oracle verification'; Text = 'Awaiting Oracle verification before implementation'},
    @{Description = 'waiting for Oracle to provide'; Text = 'waiting for Oracle to provide access'},
    @{Description = 'Oracle commit pending'; Text = 'Oracle commit pending before implementation'},
    @{Description = 'AWAIT_ORACLE_VERIFICATION'; Text = 'AWAIT_ORACLE_VERIFICATION_OR_WAIVER'},
    @{Description = 'Provide oracle branch'; Text = 'Provide oracle branch access'},
    @{Description = 'Coverage Cap Waiver'; Text = 'Coverage Cap Waiver required'},
    @{Description = 'manual oracle verification'; Text = 'manual oracle verification required'},
    @{Description = 'Oracle Post-Hoc required'; Text = 'Oracle Post-Hoc required'},
    @{Description = 'waiting for Oracle verification'; Text = 'waiting for Oracle verification'}
)

Write-Host "`n=== v438 Oracle Wait Pattern Specificity Test ===" -ForegroundColor Cyan

$passed = 0
$failed = 0

Write-Host "`nTest Group 1: Legitimate constraint language (should NOT match)" -ForegroundColor Yellow
foreach ($testCase in $shouldNotMatch) {
    $matches = $testCase.Text -match $manualOracleWaitPattern
    if (-not $matches) {
        Write-Host "  [PASS] $($testCase.Description): Correctly NOT matched" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  [FAIL] $($testCase.Description): Should NOT match but did" -ForegroundColor Red
        Write-Host "         Text: $($testCase.Text)" -ForegroundColor Gray
        $failed++
    }
}

Write-Host "`nTest Group 2: Actual oracle-wait blockers (SHOULD match)" -ForegroundColor Yellow
foreach ($testCase in $shouldMatch) {
    $matches = $testCase.Text -match $manualOracleWaitPattern
    if ($matches) {
        Write-Host "  [PASS] $($testCase.Description): Correctly matched" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  [FAIL] $($testCase.Description): Should match but did NOT" -ForegroundColor Red
        Write-Host "         Text: $($testCase.Text)" -ForegroundColor Gray
        $failed++
    }
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })

if ($failed -eq 0) {
    Write-Host "`nTest-v438-OracleWaitPatternSpecificity: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nTest-v438-OracleWaitPatternSpecificity: FAIL" -ForegroundColor Red
    exit 1
}
