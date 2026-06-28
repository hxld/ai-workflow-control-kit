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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v696-forced-slice-contracts-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\examine\service') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\examine\service\CaseExamineLogService.java') @'
package com.huize.claim.core.examine.service;
public class CaseExamineLogService {
    public void saveExamineLog() {
    }
}
'@
    Write-Utf8 (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\task\AiApplyClaimApiTaskProcessor.java') @'
package com.huize.claim.core.ai.task;
public class AiApplyClaimApiTaskProcessor {
    public void handleTaskResponse() {
    }
}
'@
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_red_test: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessorAutoFlowTest#handleTaskResponse_shouldPreserveExactContractForAiApplyClaimApiTaskProcessor
selected_real_entry: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
selected_carrier: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
red_command: mvn --% -f "FIRST_SLICE_ONLY/pom.xml" -pl claim-server -am -Dtest=com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessorAutoFlowTest#handleTaskResponse_shouldPreserveExactContractForAiApplyClaimApiTaskProcessor test
green_command: mvn --% -f "FIRST_SLICE_ONLY/pom.xml" -pl claim-server -am -Dtest=com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessorAutoFlowTest#handleTaskResponse_shouldPreserveExactContractForAiApplyClaimApiTaskProcessor test
downstream_output_or_side_effect: first_slice_ai_log_row
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') ''
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
                first_executable_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
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
                first_executable_carrier = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
                proof_required = @('ai_log_row', 'system_operator', 'task_completion_rows')
                forbidden_proof = @('log_message_constant_only', 'mock_only', 'helper_only')
            }
        )
    })

    $forcedFamily = 'lifecycle_cleanup_retention'
    $forcedCarrier = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
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

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'validate-family-proof-router.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -Slice 5 | Out-Null
    Assert-True 'forced_non_highest_family_router_validation_passes' ($LASTEXITCODE -eq 0)

    $carrier = Get-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $callable = Get-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $runnable = Get-Content -LiteralPath (Join-Path $replayRoot 'RUNNABLE_SLICE_AUTHORIZATION_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $charter = Get-Content -LiteralPath (Join-Path $replayRoot 'TEST_CHARTER_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $slicePlan = Get-Content -LiteralPath (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-True 'carrier_authorization_uses_forced_carrier' ([string]$carrier.selected_carrier -eq $forcedCarrier) ($carrier | ConvertTo-Json -Depth 12)
    Assert-True 'callable_authorization_does_not_reuse_first_slice_carrier' ([string]$callable.selected_carrier -eq $forcedCarrier) ($callable | ConvertTo-Json -Depth 12)
    Assert-True 'runnable_authorization_real_carrier_is_forced_carrier' ([string]$runnable.execution_authorization_fields.real_production_carrier -eq $forcedCarrier) ($runnable | ConvertTo-Json -Depth 12)
    Assert-True 'test_charter_real_entry_is_forced_carrier' ([string]$charter.real_entry_method -eq $forcedCarrier) ($charter | ConvertTo-Json -Depth 12)
    Assert-True 'slice_plan_selected_carrier_is_forced_carrier' ([string]$slicePlan.selected_carrier -eq $forcedCarrier -and [string]$slicePlan.real_entry_method -eq $forcedCarrier) ($slicePlan | ConvertTo-Json -Depth 12)
    Assert-True 'slice_plan_forced_router_status_passes' ([string]$slicePlan.router_status -eq 'PASS' -and [string]$slicePlan.authorization -eq 'ALLOW') ($slicePlan | ConvertTo-Json -Depth 12)
    Assert-True 'first_slice_carrier_not_in_per_slice_artifacts' (-not ((@(
        [string]$callable.selected_carrier,
        [string]$runnable.real_entry_fqn,
        [string]$charter.real_entry_method,
        [string]$slicePlan.selected_carrier
    ) -join "`n") -match 'AiApplyClaimApiTaskProcessor')) ($slicePlan | ConvertTo-Json -Depth 12)

    Write-Host ''
    Write-Host 'v696 Forced Slice Contracts Ignore First Slice Carrier: ALL PASSED'
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
