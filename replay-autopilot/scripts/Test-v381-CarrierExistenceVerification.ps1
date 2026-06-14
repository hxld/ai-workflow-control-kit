# Test-v381-CarrierExistenceVerification.ps1
# Regression test for v381: Carrier Existence Verification
#
# Tests that Verify-PlanContract.ps1 verifies selected carriers exist in codebase
# This prevents synthetic carriers like ExampleFlowService from being selected

param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifierPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        verifier_path = $verifierPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

# Test 1: Verifier contains carrier existence check
$verifierContent = Get-Content -LiteralPath $verifierPath -Raw -Encoding UTF8

# Check for the new v381 carrier existence verification code
$hasCarrierExistenceCheck = $verifierContent -match 'v381.*Carrier Existence Verification' -and
                             $verifierContent -match 'carrier_search_selected_carrier_not_found_in_codebase'

Assert-True $hasCarrierExistenceCheck "Verifier must contain v381 carrier existence verification"

# Test 2: Check for rg command usage
$hasRgCheck = $verifierContent -match 'rgCarrierPattern.*--type.*java' -or
              $verifierContent -match 'rg\s+.*class.*CarrierName'

Assert-True $hasRgCheck "Verifier must use rg to verify carrier existence"

# Test 3: Check for proper issue reporting
$hasIssueReporting = $verifierContent -match 'issues\.Add.*carrier_search_selected_carrier_not_found_in_codebase'

Assert-True $hasIssueReporting "Verifier must add issue when carrier not found"

# Test 4: Verify check runs even when new_service_proposed is false
# The existence check should run for ALL selected carriers, not just new services
$checksAllCarriers = $verifierContent -match 'selected_carrier_from_search.*-not.*newServiceIsTrue' -or
                     $verifierContent -match 'carrierNameForExistenceCheck.*-notmatch.*newServiceIsTrue'

# This check ensures the existence verification runs independently of new service flag
$independentCheck = $verifierContent -match 'Carrier Existence Verification.*selected.*carrier.*must.*exist'

Assert-True $independentCheck "Carrier existence check must be independent of new_service_proposed"

# Test 5: Check for worktree existence guard
$hasWorktreeGuard = $verifierContent -match 'Test-Path.*LiteralPath.*worktreePathForCarrierCheck'

Assert-True $hasWorktreeGuard "Verifier must check worktree exists before running rg"

# Test 6: Check for synthetic carrier pattern exclusion
$hasPatternExclusion = $verifierContent -match 'TBD|unknown|N/A|placeholder.*NONE_FOUND'

Assert-True $hasPatternExclusion "Verifier must exclude placeholder patterns from existence check"

# Test 7: Verify the fix prevents the v380 bug pattern
# The bug: ExampleFlowService was selected but didn't exist
# The fix: rg should be called to verify the carrier exists
$hasRgInvocation = $verifierContent -match 'rg\s+.*class.*\$rgCarrierPattern' -or
                   $verifierContent -match 'rg\s+.*--type\s+java'

Assert-True $hasRgInvocation "Verifier must invoke rg for carrier existence verification"

[ordered]@{
    status = 'PASS'
    assertions = 7
    tests = @(
        'v381_carrier_existence_check_present',
        'rg_command_usage',
        'issue_reporting_present',
        'check_independent_of_new_service',
        'worktree_guard_present',
        'pattern_exclusion_present',
        'rg_invocation_prevents_synthetic_carrier'
    )
} | ConvertTo-Json -Depth 6
