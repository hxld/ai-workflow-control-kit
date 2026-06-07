# Verify Test Charter - Behavioral Assertions
# Experiment 3: Behavioral Test Charter Enforcement
#
# This script verifies that RED tests contain behavioral assertions,
# not structural placeholders like fail() or assertTrue(true).

param(
    [Parameter(Mandatory = $true)]
    [string]$TestFile
)

$ErrorActionPreference = 'Stop'

# Blocked patterns (non-behavioral assertions)
$blockedPatterns = @(
    @{ Pattern = "fail\(\s*\)"; Description = "fail() with no message" },
    @{ Pattern = "fail\(\s*""\s*not implemented"; Description = "fail('not implemented')" },
    @{ Pattern = "assertTrue\s*\(\s*true\s*\)"; Description = "assertTrue(true)" },
    @{ Pattern = "assertFalse\s*\(\s*false\s*\)"; Description = "assertFalse(false)" },
    @{ Pattern = "// TODO|//TODO|# TODO"; Description = "TODO comments in test" },
    @{ Pattern = "// FIXME|//FIXME"; Description = "FIXME comments in test" },
    @{ Pattern = "\/\/\s*implementation|\/\*\s*implementation"; Description = "Implementation placeholder comments" }
)

# Behavioral assertion patterns
$behavioralPatterns = @(
    @{ Pattern = "assertThat\("; Description = "AssertJ assertThat" },
    @{ Pattern = "assertEquals\("; Description = "JUnit assertEquals" },
    @{ Pattern = "assertNotEquals\("; Description = "JUnit assertNotEquals" },
    @{ Pattern = "assertSame\("; Description = "JUnit assertSame" },
    @{ Pattern = "assertNotSame\("; Description = "JUnit assertNotSame" },
    @{ Pattern = "assertNull\("; Description = "JUnit assertNull" },
    @{ Pattern = "assertNotNull\("; Description = "JUnit assertNotNull" },
    @{ Pattern = "assertTrue\([^)]+[^true]\)"; Description = "JUnit assertTrue with condition" },
    @{ Pattern = "assertFalse\([^)]+[^false]\)"; Description = "JUnit assertFalse with condition" },
    @{ Pattern = "verify\("; Description = "Mockito verify" },
    @{ Pattern = "@?Mock\s+.*Mapper"; Description = "Mocked mapper interaction" }
)

# Side effect verification patterns
$sideEffectPatterns = @(
    @{ Pattern = "verify.*\.insert"; Description = "DB insert verification" },
    @{ Pattern = "verify.*\.update"; Description = "DB update verification" },
    @{ Pattern = "verify.*\.delete"; Description = "DB delete verification" },
    @{ Pattern = "verify.*Status"; Description = "Status update verification" }
)

# Read test file content
if (-not (Test-Path -LiteralPath $TestFile)) {
    Write-Host "ERROR: Test file not found: $TestFile"
    exit 1
}

$content = Get-Content -LiteralPath $TestFile -Raw -Encoding UTF8

# Check for blocked patterns
$foundBlocked = @()
foreach ($blocked in $blockedPatterns) {
    if ($content -match $blocked.Pattern) {
        $foundBlocked += $blocked.Description
    }
}

# Check for behavioral patterns
$foundBehavioral = [System.Collections.Generic.HashSet[string]]::new()
foreach ($behavioral in $behavioralPatterns) {
    if ($content -match $behavioral.Pattern) {
        [void]$foundBehavioral.Add($behavioral.Description)
    }
}

# Check for side effect patterns
$foundSideEffects = [System.Collections.Generic.HashSet[string]]::new()
foreach ($sideEffect in $sideEffectPatterns) {
    if ($content -match $sideEffect.Pattern) {
        [void]$foundSideEffects.Add($sideEffect.Description)
    }
}

# Count behavioral assertions
$behavioralAssertionCount = 0
$behavioralAssertionCount += [regex]::Matches($content, "assertThat\(").Count
$behavioralAssertionCount += [regex]::Matches($content, "assertEquals\(").Count
$behavioralAssertionCount += [regex]::Matches($content, "verify\(").Count

# Build result
$result = [ordered]@{
    verification_status = if ($foundBlocked.Count -gt 0 -or $foundBehavioral.Count -eq 0) { "FAIL" } else { "PASS" }
    test_file = $TestFile
    blocked_patterns_found = @($foundBlocked)
    behavioral_patterns_found = @($foundBehavioral)
    side_effect_patterns_found = @($foundSideEffects)
    behavioral_assertion_count = $behavioralAssertionCount
    has_behavioral_assertion = ($foundBehavioral.Count -gt 0)
    has_side_effect_verification = ($foundSideEffects.Count -gt 0)
}

if ($foundBlocked.Count -gt 0) {
    Write-Host "Test Charter Verification: FAIL - Test contains non-behavioral assertions"
    foreach ($blocked in $foundBlocked) {
        Write-Host "  BLOCKED: $blocked"
    }
    Write-Host "  RED test must fail with business assertion (e.g., assertThat on domain value)"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 1
}

if ($foundBehavioral.Count -eq 0) {
    Write-Host "Test Charter Verification: FAIL - Test lacks behavioral assertion"
    Write-Host "  Required patterns: assertThat(), assertEquals(), verify()"
    Write-Host "  RED test must fail with business assertion, not structural error"
    $result | ConvertTo-Json -Depth 4 | Write-Host
    exit 1
}

Write-Host "Test Charter Verification: PASS - Test contains behavioral assertions"
Write-Host "  Behavioral patterns: $($foundBehavioral -join ', ')"
if ($foundSideEffects.Count -gt 0) {
    Write-Host "  Side effect patterns: $($foundSideEffects -join ', ')"
}
Write-Host "  Assertion count: $behavioralAssertionCount"
$result | ConvertTo-Json -Depth 4 | Write-Host
exit 0
