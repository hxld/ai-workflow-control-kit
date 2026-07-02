#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
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

function Write-PlanFixture {
    param(
        [string]$Root,
        [string]$Carriers,
        [string]$ExtraPlanText
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-Utf8 (Join-Path $Root 'PLAN_RESULT.md') @"
# Plan Result

plan_status: PROCEED
carrier_search: performed
carrier_search_queries: rg -n "rebuildTaskData" example-core/src/main/java --glob "*.java"; rg -n "policyNum" example-core/src/main/java --glob "*.java"; rg -n "insureNum" example-core/src/main/java --glob "*.java"
existing_production_carriers: $Carriers
selected_carrier_from_search: ExampleApplyClaimApiTaskProcessor.rebuildTaskData
new_service_proposed: false
oracle_production_file_overlap: 100%
oracle_missing_high_weight_files: none
first_slice: S1_source_chain
first_red_test: PolicyRebuildSourceChainTest#propagatesPolicyAndInsureNum

Required source-chain contract:
- ExampleDataAssemblyHelper.buildRequestCommon
- ExampleDataAssemblyHelper.RequestBuildFunction
- RequestBuildContext
- policyNum and insureNum must flow through RequestBuildFunction
- example-server/src/test/java contains the no-Spring test harness
- mvn --% -f worktree/pom.xml -pl example-server -am -Dtest=PolicyRebuildSourceChainTest#propagatesPolicyAndInsureNum -Dsurefire.failIfNoSpecifiedTests=false test
- req.setPolicyNum(buildContext.getPolicyNum())
- req.setInsureNum(buildContext.getInsureNum())
$ExtraPlanText
"@

    @{
        expected_test_class = 'PolicyRebuildSourceChainTest'
        test_infrastructure_check = @{
            test_module_for_target = 'example-server'
            compilation_dry_run_command = 'mvn --% -f worktree/pom.xml -pl example-server -am test-compile'
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root 'PLAN_RESULT.json') -Encoding UTF8
}

$scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$verifier = Join-Path $scriptsRoot 'Verify-PlanContract.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v673-policy-siblings-" + [guid]::NewGuid().ToString('N'))

try {
    $missingCalculateRoot = Join-Path $tempRoot 'missing-calculate'
    Write-PlanFixture -Root $missingCalculateRoot -Carriers 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData' -ExtraPlanText @'
- ExampleApplyClaimApiTaskProcessor.rebuildTaskData
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $missingCalculateRoot -Stage Plan 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'plan verifier fails closed when calculate sibling is missing'
    $missingVerify = Get-Content -LiteralPath (Join-Path $missingCalculateRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($missingVerify.issues) -contains 'policy_rebuild_plan_missing:apply_and_calculate_siblings') 'missing sibling issue is machine-readable'
    $siblingEvidence = @($missingVerify.issue_evidence | Where-Object { [string]$_.issue -eq 'policy_rebuild_plan_missing:apply_and_calculate_siblings' })[0]
    Assert-True ($null -ne $siblingEvidence) 'missing sibling issue includes evidence row'
    Assert-True ([string]$siblingEvidence.machine_gate -eq 'Surface Coverage Gate') 'evidence row names Surface Coverage Gate'
    Assert-True ([string]$siblingEvidence.snippet -match 'ExampleCalculatorApiTaskProcessor\.rebuildTaskData') 'evidence row names missing calculate sibling'

    $completeRoot = Join-Path $tempRoot 'complete-siblings'
    Write-PlanFixture -Root $completeRoot -Carriers 'ExampleApplyClaimApiTaskProcessor.rebuildTaskData; ExampleCalculatorApiTaskProcessor.rebuildTaskData' -ExtraPlanText @'
- ExampleApplyClaimApiTaskProcessor.rebuildTaskData
- ExampleCalculatorApiTaskProcessor.rebuildTaskData
'@
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $completeRoot -Stage Plan | Out-Null
    $completeVerify = Get-Content -LiteralPath (Join-Path $completeRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($completeVerify.issues) -notcontains 'policy_rebuild_plan_missing:apply_and_calculate_siblings') 'complete sibling plan clears the sibling-specific issue'

    Write-Host 'v673 Policy Rebuild Sibling Evidence: PASS'
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
