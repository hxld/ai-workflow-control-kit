param(
    [string]$TestRoot = (Join-Path $PSScriptRoot '.tmp\v395-carrier-oracle-fallback'),
    [switch]$ValidateOnly
)

<#
.SYNOPSIS
    Regression test for v395 carrier oracle path fallback enhancement

.DESCRIPTION
    Tests that Verify-PlanContract.ps1 correctly checks carrier existence:
    1. In ORACLE_DIFF_ANALYSIS.json (oracle additions)
    2. In worktree (if not in oracle)
    3. In project root as fallback (if not in worktree)

    This prevents false "carrier_search_selected_carrier_not_found_in_codebase"
    errors when the carrier is a real oracle addition that exists in the
    current project codebase (<PROJECT_ROOT>) but not in the replay worktree.
#>

$ErrorActionPreference = 'Stop'
$testDir = $PSScriptRoot
$scriptsDir = Join-Path $testDir '..\..'

function New-MinimalOracleDiff {
    param([string]$Path, [string]$CarrierName)
    $oracleDiff = @{
        schema_version = 1
        generated_at = (Get-Date).ToString('s')
        base_commit = 'e19c16c5a8096c8d36938f2c4697980deea71d4'
        oracle_commit = '07d37b6c30d42f0737a2629f051b9d7b76baf78e'
        total_files = 1
        production_files = 1
        test_files = 0
        high_weight_files = 1
        total_additions = 1502
        total_deletions = 0
        files = @(
            @{
                path = "example-core/src/main/java/com/example/project/core/ai/service/$CarrierName.java"
                layer = 'Service'
                weight = 'HIGH'
                is_test = $false
                is_production = $true
                additions = 1502
                deletions = 0
            }
        )
    }
    $oracleDiff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-MinimalPlanResult {
    param([string]$Path, [string]$CarrierName)
    $planContent = @"
# Plan Result

- generated_at: $(Get-Date -Format 's')
- run_label: v395-test
- carrier_search: performed
- carrier_search_queries: rg "class.*AutoFlow.*Service" --type java
- existing_production_carriers: $CarrierName.java (1502)
- selected_carrier_from_search: $CarrierName (highest-weight oracle file with 1502 additions)
- new_service_proposed: false
- new_service_justification: N/A - using existing oracle carrier
- oracle_production_file_overlap: 100%
- oracle_missing_high_weight_files: none
- plan_status: PROCEED
- selected_carrier: $CarrierName
"@
    Set-Content -LiteralPath $Path -Value $planContent -Encoding UTF8
}

function Invoke-CarrierOracleCheck {
    param(
        [string]$TestDir,
        [string]$CarrierName,
        [bool]$CreateOracleDiff = $true,
        [bool]$UseEnvProjectRoot = $false
    )

    New-Item -ItemType Directory -Force -Path $TestDir | Out-Null

    # Create oracle diff
    if ($CreateOracleDiff) {
        New-MinimalOracleDiff -Path (Join-Path $TestDir 'ORACLE_DIFF_ANALYSIS.json') -CarrierName $CarrierName
    }

    # Create plan result
    New-MinimalPlanResult -Path (Join-Path $TestDir 'PLAN_RESULT.md') -CarrierName $CarrierName

    # Create worktree (empty - carrier not present)
    $worktree = Join-Path $TestDir 'worktree'
    New-Item -ItemType Directory -Force -Path $worktree | Out-Null

    # For test 3, create an isolated PROJECT_ROOT that contains the carrier.
    # Do not depend on a specific project root; the main worktree branch may not contain this oracle-added class.
    $originalEnv = $null
    if ($UseEnvProjectRoot) {
        $originalEnv = $env:PROJECT_ROOT
        $projectRoot = Join-Path $TestDir 'project-root'
        $projectSourceDir = Join-Path $projectRoot 'example-core\src\main\java\com\example\project\core\ai\service'
        New-Item -ItemType Directory -Force -Path $projectSourceDir | Out-Null
        Set-Content -LiteralPath (Join-Path $projectSourceDir "$CarrierName.java") -Value @"
package com.example.project.core.ai.service;

public class $CarrierName {
}
"@ -Encoding UTF8
        $env:PROJECT_ROOT = $projectRoot
    }

    try {
        # Run verification
        $verifyScript = Join-Path $scriptsDir 'Verify-PlanContract.ps1'
        $verifyResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ReplayRoot $TestDir -Stage Plan 2>&1
        $verifyExit = $LASTEXITCODE
    } finally {
        if ($null -ne $originalEnv) {
            $env:PROJECT_ROOT = $originalEnv
        } elseif ($UseEnvProjectRoot) {
            Remove-Item Env:\PROJECT_ROOT -ErrorAction SilentlyContinue
        }
    }

    # Read verification result
    $verifyJson = Join-Path $TestDir 'PLAN_CONTRACT_VERIFY.json'
    if (Test-Path -LiteralPath $verifyJson) {
        $verifyData = Get-Content -LiteralPath $verifyJson -Raw -Encoding UTF8 | ConvertFrom-Json
        return @{
            ExitCode = $verifyExit
            VerificationStatus = $verifyData.verification_status
            Issues = $verifyData.issues
            Warnings = $verifyData.warnings
        }
    }

    return @{
        ExitCode = $verifyExit
        VerificationStatus = 'UNKNOWN'
        Issues = @()
        Warnings = @()
    }
}

if ($ValidateOnly) {
    $d = Join-Path $TestRoot 'validate-only'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    New-MinimalOracleDiff -Path (Join-Path $d 'ORACLE_DIFF_ANALYSIS.json') -CarrierName 'ValidateOnlyService'
    New-MinimalPlanResult -Path (Join-Path $d 'PLAN_RESULT.md') -CarrierName 'ValidateOnlyService'
    [ordered]@{ status = 'VALID'; test_root = $TestRoot } | ConvertTo-Json -Depth 4
    exit 0
}

# Clean up and recreate test root
if (Test-Path -LiteralPath $TestRoot) {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$passCount = 0
$failCount = 0
$testCount = 0

Write-Host "=== v395 Carrier Oracle Path Fallback Tests ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Carrier in ORACLE_DIFF_ANALYSIS.json => PASS
Write-Host 'Test 1: Carrier in ORACLE_DIFF_ANALYSIS.json => PASS'
$testCount++
$result1 = Invoke-CarrierOracleCheck -TestDir (Join-Path $TestRoot 'test1-oracle-diff') -CarrierName 'ExampleFlowService' -CreateOracleDiff $true
$hasNotFoundError = $result1.Issues -contains 'carrier_search_selected_carrier_not_found_in_codebase'
$hasOracleWarning = $result1.Warnings | Where-Object { $_ -like '*ORACLE_DIFF_ANALYSIS.json*' }
if (-not $hasNotFoundError -and $hasOracleWarning) {
    Write-Host "  PASS (issues=$($result1.Issues.Count), oracle warning present)" -ForegroundColor Green
    $passCount++
} else {
    Write-Host "  FAIL (issues=$($result1.Issues.Count), expected oracle warning)" -ForegroundColor Red
    $failCount++
}

# Test 2: Carrier not in oracle, not in worktree, not in project root => FAIL
Write-Host 'Test 2: Carrier not in oracle, not in worktree, not in project root => FAIL'
$testCount++
$result2 = Invoke-CarrierOracleCheck -TestDir (Join-Path $TestRoot 'test2-not-found') -CarrierName 'NonExistentService' -CreateOracleDiff $false
$hasNotFoundError2 = $result2.Issues -contains 'carrier_search_selected_carrier_not_found_in_codebase'
if ($hasNotFoundError2) {
    Write-Host "  PASS (correctly reports carrier not found)" -ForegroundColor Green
    $passCount++
} else {
    Write-Host "  FAIL (should report carrier not found)" -ForegroundColor Red
    $failCount++
}

# Test 3: Carrier not in oracle, but in project root (via env var) => PASS
Write-Host 'Test 3: Carrier not in oracle, but in project root (via PROJECT_ROOT env var) => PASS'
$testCount++
$result3 = Invoke-CarrierOracleCheck -TestDir (Join-Path $TestRoot 'test3-project-root-fallback') -CarrierName 'ExampleFlowService' -CreateOracleDiff $false -UseEnvProjectRoot $true
$hasNotFoundError3 = $result3.Issues -contains 'carrier_search_selected_carrier_not_found_in_codebase'
$hasProjectRootWarning = $result3.Warnings | Where-Object { $_ -like '*project root*' }
if (-not $hasNotFoundError3 -and $hasProjectRootWarning) {
    Write-Host "  PASS (found in project root fallback)" -ForegroundColor Green
    $passCount++
} else {
    Write-Host "  FAIL (should find in project root fallback, warnings: $($result3.Warnings -join ', '))" -ForegroundColor Red
    $failCount++
}

Write-Host ""
Write-Host "=== Results: $passCount/$testCount passed ===" -ForegroundColor $(if ($passCount -eq $testCount) { 'Green' } else { 'Yellow' })

if ($failCount -gt 0) {
    Write-Host "Some tests failed. Temp directory preserved at: $TestRoot" -ForegroundColor Red
    [ordered]@{
        status = 'FAIL'
        passed = $passCount
        failed = $failCount
        total = $testCount
        test_root = $TestRoot
    } | ConvertTo-Json -Depth 4
    exit 1
}

# Clean up on success
Remove-Item -LiteralPath $TestRoot -Recurse -Force

[ordered]@{
    status = 'PASS'
    assertions = 3
    cases = @(
        'carrier_in_oracle_diff_passes',
        'carrier_not_found_anywhere_fails',
        'carrier_in_project_root_fallback_passes'
    )
} | ConvertTo-Json -Depth 5
exit 0
