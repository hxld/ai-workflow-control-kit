#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-JsonFile {
    param([string]$Path, [object]$Value, [int]$Depth = 16)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Utf8 {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Value -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v697-forced-slice-selector-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-server\src\test\java') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\examine\service') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\examine\service\CaseExamineLogService.java') @'
package com.example.project.core.examine.service;
public class CaseExamineLogService {
    public void saveExamineLog() {
    }
}
'@
    Write-Utf8 (Join-Path $worktree 'example-core\src\main\java\com\example\project\core\ai\task\ExampleApplyClaimApiTaskProcessor.java') @'
package com.example.project.core.ai.task;
public class ExampleApplyClaimApiTaskProcessor {
    public void handleTaskResponse() {
    }
}
'@

    $firstSliceTest = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessorAutoFlowTest#handleTaskResponse_shouldPreserveExactContractForExampleApplyClaimApiTaskProcessor'
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @"
first_red_test: $firstSliceTest
selected_real_entry: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse
selected_carrier: com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse
red_command: mvn --% -f "FIRST_SLICE_ONLY/pom.xml" -pl example-server -am -Dtest=$firstSliceTest test
green_command: mvn --% -f "FIRST_SLICE_ONLY/pom.xml" -pl example-server -am -Dtest=$firstSliceTest test
downstream_output_or_side_effect: first_slice_ai_log_row
"@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') ''
    Write-Utf8 (Join-Path $replayRoot 'REPLAY_PLAN.md') @'
| Slice | Family | Carrier | Boundary | Proof | Tests | Extra | Test selector |
| S5 | lifecycle_cleanup_retention | com.example.project.core.examine.service.CaseExamineLogService.saveExamineLog | stateful | exact | stale | old | cap 65 until integration proof |
'@
    Write-JsonFile (Join-Path $replayRoot 'PLAN_RESULT.json') ([ordered]@{
        plan_status = 'PROCEED'
        expected_test_class = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessorAutoFlowTest'
        expected_test_method = 'handleTaskResponse_shouldPreserveExactContractForExampleApplyClaimApiTaskProcessor'
        test_infrastructure_check = [ordered]@{
            test_module_for_target = 'example-server'
        }
    })
    Write-JsonFile (Join-Path $replayRoot 'REPLAY_CONTEXT_INDEX_VALIDATION.json') ([ordered]@{ status = 'PASS' })
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{ required_source_chain = $false })
    Write-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        families = @(
            [ordered]@{
                id = 'wire_payload_api_contract'
                required = $true
                status = 'PARTIAL'
                weight = 88
                touched_count = 3
                coverage_cap_if_open = 70
                recommended_slice_type = 'exact_contract_slice'
                first_executable_carrier = 'com.example.project.core.ai.task.ExampleApplyClaimApiTaskProcessor.handleTaskResponse'
                proof_required = @('payload_contract')
                forbidden_proof = @('dto_only')
            },
            [ordered]@{
                id = 'lifecycle_cleanup_retention'
                required = $true
                status = 'OPEN'
                weight = 76
                touched_count = 0
                coverage_cap_if_open = 60
                recommended_slice_type = 'stateful_success_slice'
                first_executable_carrier = 'com.example.project.core.examine.service.CaseExamineLogService.saveExamineLog'
                proof_required = @('ai_log_row', 'system_operator', 'task_completion_rows')
                forbidden_proof = @('log_message_constant_only', 'mock_only', 'helper_only')
            }
        )
    })

    $forcedFamily = 'lifecycle_cleanup_retention'
    $forcedCarrier = 'com.example.project.core.examine.service.CaseExamineLogService.saveExamineLog'
    $expectedSelector = 'CaseExamineLogServiceTest#shouldCoverLifecycleCleanupRetention'

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -RequirementFamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceIndex 5 `
        -ForcedRequirementFamily $forcedFamily `
        -ForcedSliceType stateful_success_slice `
        -ForcedSiblingSurface $forcedCarrier | Out-Null
    Assert-True 'prepare_contracts_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-CallableCarrierAuthorization.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 5 | Out-Null
    Assert-True 'callable_authorization_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 5 `
        -ForcedRequirementFamily $forcedFamily `
        -ForcedSliceType stateful_success_slice `
        -ForcedSiblingSurface $forcedCarrier | Out-Null
    Assert-True 'pre_slice_experiment_contracts_exit_zero' ($LASTEXITCODE -eq 0)

    $side = Get-Content -LiteralPath (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runnable = Get-Content -LiteralPath (Join-Path $replayRoot 'RUNNABLE_SLICE_AUTHORIZATION_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $charter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $canonicalCharter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $slicePlan = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True 'side_effect_uses_forced_default_selector' ([string]$side.test_name -eq $expectedSelector) ($side | ConvertTo-Json -Depth 12)
    Assert-True 'runnable_uses_forced_carrier_test_class' ([string]$runnable.test_class -eq 'CaseExamineLogServiceTest') ($runnable | ConvertTo-Json -Depth 12)
    Assert-True 'runnable_uses_forced_carrier_test_method' ([string]$runnable.test_method -eq 'shouldCoverLifecycleCleanupRetention') ($runnable | ConvertTo-Json -Depth 12)
    Assert-True 'test_charter_uses_forced_carrier_test_class' ([string]$charter.test_class -eq 'CaseExamineLogServiceTest') ($charter | ConvertTo-Json -Depth 12)
    Assert-True 'canonical_charter_uses_forced_carrier_test_method' ([string]$canonicalCharter.test_method -eq 'shouldCoverLifecycleCleanupRetention') ($canonicalCharter | ConvertTo-Json -Depth 12)
    Assert-True 'slice_plan_uses_forced_selector' ([string]$slicePlan.red_test_name -eq $expectedSelector) ($slicePlan | ConvertTo-Json -Depth 12)

    $selectorText = @(
        [string]$side.test_name,
        [string]$runnable.test_class,
        [string]$runnable.test_method,
        [string]$runnable.red_command,
        [string]$runnable.green_command,
        [string]$charter.test_class,
        [string]$canonicalCharter.maven_command,
        [string]$slicePlan.red_test_name,
        [string]$slicePlan.validation_command
    ) -join "`n"
    Assert-True 'first_slice_test_selector_not_reused' (-not ($selectorText -match 'ExampleApplyClaimApiTaskProcessorAutoFlowTest|handleTaskResponse_shouldPreserveExactContractForExampleApplyClaimApiTaskProcessor|cap 65 until integration proof')) $selectorText

    Write-Host ''
    Write-Host 'v697 Forced Slice Test Selector Does Not Reuse First Slice: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
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
