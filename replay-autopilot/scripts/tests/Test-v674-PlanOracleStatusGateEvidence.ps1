#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = 'condition was false' }
        throw "FAIL: $Message - $Detail"
    }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-OracleBlockedPlanFixture {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $worktree = Join-Path $Root 'worktree'
    Write-Utf8 (Join-Path $worktree 'module\src\main\java\com\example\ai\ExampleCoreService.java') 'package com.example.ai; public class ExampleCoreService { public void save() {} }'

    $oracleFiles = @(
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleCoreService.java'; weight = 'HIGH'; is_production = $true; additions = 10; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleFlowFacade.java'; weight = 'HIGH'; is_production = $true; additions = 20; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleRouteService.java'; weight = 'HIGH'; is_production = $true; additions = 15; deletions = 0 },
        [pscustomobject]@{ path = 'module/src/main/java/com/example/ai/ExampleController.java'; weight = 'MEDIUM'; is_production = $true; additions = 8; deletions = 0 }
    )
    Write-JsonFile (Join-Path $Root 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{ files = $oracleFiles })

    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: BLOCKED
- blocker: oracle_overlap_below_threshold
- selected_strategy: exact-contract-first
- oracle_primary_domain: ai
- requirement_primary_domain: ai
- oracle_production_file_overlap: 25%
- oracle_high_weight_coverage: 33% (1/3)
- oracle_missing_high_weight_files: documented by verifier output
- oracle_expansion_plan: missing high-weight production files are not yet mapped to executable carriers or tests
- golden_slice_binding: oracle_overlap -> ExampleCoreService -> RED: ExampleCoreServiceTest.failsBeforeMapping -> GREEN: service maps and persists field -> executable side effect mapper capture
- carrier_search: performed
- carrier_search_queries: rg "class ExampleCoreService" --type java; rg "save" --type java; rg "ExampleFlowFacade" --type java
- existing_production_carriers: ExampleCoreService
- selected_carrier_from_search: ExampleCoreService
- new_service_proposed: false
- first_slice: S1 - exact contract
- first_red_test: ExampleCoreServiceTest.failsBeforeMapping
'@
    Write-Utf8 (Join-Path $Root 'REPLAY_PLAN.md') 'S1 covers ExampleCoreService only.'
    Write-Utf8 (Join-Path $Root 'EXPECTED_DIFF_MATRIX.md') 'ExampleCoreService.java -> LOGIC_ADD.'
    Write-Utf8 (Join-Path $Root 'IMPLEMENTATION_CONTRACT.md') 'selected_real_entry: ExampleCoreService.save()'
    Write-Utf8 (Join-Path $Root 'FIRST_SLICE_PROOF_PLAN.md') @'
first_slice: S1
golden_slice_binding: oracle_overlap -> ExampleCoreService -> RED -> GREEN -> side effect
highest_weight_open_gate: core_entry
first_slice_family: core_entry
selected_real_entry: ExampleCoreService.save()
selected_carrier: ExampleCoreService.save()
first_red_test: ExampleCoreServiceTest.failsBeforeMapping
'@
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$verifier = Join-Path $scriptsRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v674-plan-gate-evidence-" + [guid]::NewGuid().ToString('N'))

try {
    New-OracleBlockedPlanFixture -Root $tempRoot
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $tempRoot -Stage Plan 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'plan verifier fails closed for low oracle overlap and blocked plan status'

    $verify = Get-Content -LiteralPath (Join-Path $tempRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $evidence = @($verify.issue_evidence)

    $issuesText = @($verify.issues) -join ';'
    $evidenceText = ($evidence | ConvertTo-Json -Depth 8)

    Assert-True (@($evidence | Where-Object { [string]$_.machine_gate -eq 'plan_oracle_overlap_enforced' }).Count -eq 1) 'overall oracle overlap issue has machine-gate evidence' "issues=$issuesText evidence=$evidenceText"
    Assert-True (@($evidence | Where-Object { [string]$_.machine_gate -eq 'plan_high_weight_oracle_overlap_enforced' }).Count -eq 1) 'high-weight oracle overlap issue has machine-gate evidence' "issues=$issuesText evidence=$evidenceText"
    Assert-True (@($evidence | Where-Object { [string]$_.machine_gate -eq 'blocked_plan_status_stops_replay' }).Count -eq 1) 'blocked plan status issue has machine-gate evidence' "issues=$issuesText evidence=$evidenceText"
    Assert-True ($issuesText -match 'oracle_overlap_below_threshold') 'overall oracle overlap issue remains machine-readable' $issuesText
    Assert-True ((@($verify.issues) -join ';') -match 'oracle_high_weight_overlap_below_threshold') 'high-weight oracle overlap issue remains machine-readable'
    Assert-True ((@($verify.issues) -join ';') -match 'plan_status_not_proceed:BLOCKED') 'blocked plan status issue remains machine-readable'

    Write-Host 'v674 Plan Oracle Status Gate Evidence: PASS'
    exit 0
} catch {
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
