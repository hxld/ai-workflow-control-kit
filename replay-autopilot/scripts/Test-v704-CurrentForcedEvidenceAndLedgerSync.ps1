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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Import-RunSliceLoopFunctions {
    $runSliceLoop = Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($runSliceLoop, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Run-SliceLoop.ps1 parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"
    }

    $functionAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($functionAst in @($functionAsts)) {
        Invoke-Expression ("function script:$($functionAst.Name) " + $functionAst.Body.Extent.Text)
    }
}

function New-FamilyRow {
    param(
        [string]$Id,
        [int]$Weight,
        [string]$Status,
        [string]$SliceType,
        [string]$Carrier,
        [string[]]$ProofRequired,
        [int]$CoverageCap
    )
    return [ordered]@{
        id = $Id
        title = $Id
        weight = $Weight
        recommended_slice_type = $SliceType
        required = $true
        status = $Status
        touched_count = 0
        first_slice = $null
        last_slice = $null
        slices = @()
        first_executable_carrier = $Carrier
        planned_slice = ''
        proof_required = @($ProofRequired)
        forbidden_proof = @('helper_only', 'mock_only', 'static_only')
        coverage_cap_if_open = $CoverageCap
        open_sibling_surfaces = @($Carrier)
        open_sibling_count = 1
        last_next_recommended_slice_type = ''
        last_gap_flags = @()
        evidence_keywords = @($Id)
        last_reason = 'fixture'
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v704-current-forced-ledger-sync-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $worktree 'claim-server\src\test\java'), (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\facade') | Out-Null
    Write-Utf8 (Join-Path $worktree 'pom.xml') '<project><modelVersion>4.0.0</modelVersion><groupId>demo</groupId><artifactId>root</artifactId><version>1</version></project>'
    Write-Utf8 (Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\facade\AiClaimModuleConfigFacadeImpl.java') @'
package com.huize.claim.core.ai.facade;

public class AiClaimModuleConfigFacadeImpl {
    public Object save(Object dto) {
        return null;
    }
}
'@
    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
selected_carrier: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
selected_real_entry: com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse
downstream_output_or_side_effect: first_slice_payload_contract
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') 'global exact contract text mentions AiApplyClaimApiTaskProcessor and must not override current config evidence.'
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl'
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{ required_source_chain = $false })
    Write-JsonFile (Join-Path $replayRoot 'REPLAY_CONTEXT_INDEX_VALIDATION.json') ([ordered]@{ status = 'PASS' })

    $configCarrier = 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save'
    $ledgerPath = Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-JsonFile $ledgerPath ([ordered]@{
        schema_version = 1
        replay_root = $replayRoot
        max_slices = 8
        created_at = '2026-06-28T00:00:00'
        updated_at = '2026-06-28T00:00:00'
        coverage_cap = 65
        no_progress_slices = @()
        open_required_after_max = @()
        families = @(
            (New-FamilyRow -Id 'wire_payload_api_contract' -Weight 88 -Status 'OPEN' -SliceType 'exact_contract_slice' -Carrier 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse' -ProofRequired @('wire_payload_payload_assertion') -CoverageCap 70),
            (New-FamilyRow -Id 'config_policy_threshold' -Weight 87 -Status 'PARTIAL' -SliceType 'exact_contract_slice' -Carrier $configCarrier -ProofRequired @('persist_free_review_amount', 'clear_updates_database', 'reject_invalid_amounts', 'auto_flow_gate_reads_config') -CoverageCap 65),
            (New-FamilyRow -Id 'external_integration' -Weight 82 -Status 'OPEN' -SliceType 'deploy_surface_first_slice' -Carrier 'com.huize.claim.core.dock.facade.InsureCompanyPushFacadeImpl.push' -ProofRequired @('partner_push_status') -CoverageCap 65)
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -RequirementFamilyLedger $ledgerPath `
        -SliceIndex 6 `
        -ForcedRequirementFamily config_policy_threshold `
        -ForcedSliceType exact_contract_slice `
        -ForcedSiblingSurface $configCarrier | Out-Null
    Assert-True 'prepare_current_forced_config_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-CallableCarrierAuthorization.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 6 | Out-Null
    Assert-True 'callable_current_forced_config_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 6 `
        -MaxRows 5 `
        -FailOnBroadRows | Out-Null
    Assert-True 'next_slice_exact_contract_current_forced_config_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 6 `
        -ForcedRequirementFamily config_policy_threshold `
        -ForcedSliceType exact_contract_slice `
        -ForcedSiblingSurface $configCarrier | Out-Null
    Assert-True 'pre_slice_authorization_current_forced_config_exit_zero' ($LASTEXITCODE -eq 0)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-PreSliceExperimentContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 6 | Out-Null
    Assert-True 'pre_slice_experiment_uses_current_evidence_exit_zero' ($LASTEXITCODE -eq 0)

    $slicePlan = Read-JsonFile (Join-Path $replayRoot 'SLICE_PLAN_CONTRACT_06.json')
    $sliceExecution = Read-JsonFile (Join-Path $replayRoot 'SLICE_EXECUTION_CONTRACT_06.json')
    Assert-True 'pre_slice_contract_prefers_current_forced_family_over_highest_open_ledger' `
        ([string]$slicePlan.selected_family -eq 'config_policy_threshold' -and [string]$slicePlan.forced_requirement_family -eq 'config_policy_threshold' -and [string]$slicePlan.highest_weight_open_family -eq 'wire_payload_api_contract') `
        ($slicePlan | ConvertTo-Json -Depth 16)
    Assert-True 'slice_execution_contract_family_matches_current_forced_evidence' `
        ([string]$sliceExecution.family_id -eq 'config_policy_threshold') `
        ($sliceExecution | ConvertTo-Json -Depth 16)

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_05.json') ([ordered]@{
        slice_index = 5
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        coverage_delta = 10
        production_boundary = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
        proof_kind = 'lifecycle_cleanup_retention'
        implemented_files = @('claim-core/src/main/java/com/huize/claim/core/examine/service/CaseExamineLogService.java')
        touched_requirement_families = @('lifecycle_cleanup_retention')
        closed_requirement_families = @('lifecycle_cleanup_retention')
        gap_flags = @('exact_contract_gap', 'exact_contract_minimum_coverage_gap', 'tooling_enforcement_stop')
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_05.json') ([ordered]@{
        slice_index = 5
        verification_status = 'PARTIAL'
        slice_status = 'DONE'
        adjusted_coverage_delta = 3
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
        touched_requirement_families = @('lifecycle_cleanup_retention')
        closed_requirement_families = @('lifecycle_cleanup_retention')
        proof_type_mismatch_families = @()
        gap_flags = @('family_sibling_gap')
        warnings = @('family_sibling_surface_open')
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_06.json') ([ordered]@{
        slice_index = 6
        slice_status = 'DONE'
        slice_type = 'exact_contract_slice'
        coverage_delta = 10
        production_boundary = $configCarrier
        proof_kind = 'config_policy_threshold'
        implemented_files = @(
            'claim-core/src/main/java/com/huize/claim/core/ai/service/AiClaimModuleConfigService.java',
            'claim-core/src/main/resources/mybatis/mapper/ai/TAiClaimModuleConfigMapper.xml'
        )
        touched_requirement_families = @('config_policy_threshold')
        closed_requirement_families = @('config_policy_threshold')
        gap_flags = @()
        side_effect_evidence = [ordered]@{
            entry_call = $configCarrier
            expected_writes_or_outputs = @('persist_free_review_amount', 'clear_updates_database', 'auto_flow_gate_reads_config')
        }
        must_not_assertions = @('reject_invalid_amounts')
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_06.json') ([ordered]@{
        slice_index = 6
        verification_status = 'PARTIAL'
        slice_status = 'DONE'
        adjusted_coverage_delta = 3
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        authorization_blockers = @()
        touched_requirement_families = @('config_policy_threshold')
        closed_requirement_families = @('config_policy_threshold')
        proof_type_mismatch_families = @()
        gap_flags = @('family_sibling_gap')
        warnings = @('family_sibling_surface_open')
    })

    $ledger = Read-JsonFile $ledgerPath
    $ledger.families += (New-FamilyRow -Id 'lifecycle_cleanup_retention' -Weight 76 -Status 'PARTIAL' -SliceType 'stateful_success_slice' -Carrier 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog' -ProofRequired @('same_status_cleanup', 'system_operator') -CoverageCap 60)
    $ledger | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $replayRoot -Ledger $ledgerPath -ValidateOnly | Out-Null
    Assert-True 'router_reports_stale_ledger_before_authorizing_sync' ($LASTEXITCODE -ne 0)
    $staleRouter = Read-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json')
    Assert-True 'stale_router_reason_is_metadata_inconsistency' ([string]$staleRouter.status -eq 'METADATA_INCONSISTENCY') ($staleRouter | ConvertTo-Json -Depth 16)

    Import-RunSliceLoopFunctions
    $synced = Sync-FamilyLedgerFromAuthorizingSliceEvidence -Path $ledgerPath -ReplayRoot $replayRoot -MaxSlices 8 -RunnerContractPath (Join-Path $replayRoot 'RUNNER_CONTRACT.md')
    Assert-True 'authorizing_verifier_closures_are_synced' ([int]$synced -ge 2) "synced=$synced"

    $syncedLedger = Read-JsonFile $ledgerPath
    $configFamily = @($syncedLedger.families | Where-Object { [string]$_.id -eq 'config_policy_threshold' } | Select-Object -First 1)[0]
    $cleanupFamily = @($syncedLedger.families | Where-Object { [string]$_.id -eq 'lifecycle_cleanup_retention' } | Select-Object -First 1)[0]
    Assert-True 'config_family_closed_after_authorizing_sync' ([string]$configFamily.status -eq 'EXECUTABLE_CLOSED') ($configFamily | ConvertTo-Json -Depth 12)
    Assert-True 'cleanup_family_closed_after_authorizing_sync' ([string]$cleanupFamily.status -eq 'EXECUTABLE_CLOSED') ($cleanupFamily | ConvertTo-Json -Depth 12)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'FamilyRouterAndCap.ps1') -ReplayRoot $replayRoot -Ledger $ledgerPath -ValidateOnly | Out-Null
    Assert-True 'router_no_longer_reports_stale_ledger_after_authorizing_sync' ($LASTEXITCODE -eq 0)
    $router = Read-JsonFile (Join-Path $replayRoot 'FAMILY_ROUTER_AND_CAP.json')
    Assert-True 'router_selects_remaining_highest_open_family_after_sync' ([string]$router.selected_family -eq 'wire_payload_api_contract') ($router | ConvertTo-Json -Depth 16)

    Write-Host ''
    Write-Host 'v704 Current Forced Evidence And Ledger Sync: ALL PASSED'
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
