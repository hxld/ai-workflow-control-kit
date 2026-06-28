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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v703-family-exact-proof-scope-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null
    $facadeDir = Join-Path $worktree 'claim-core\src\main\java\com\huize\claim\core\ai\facade'
    New-Item -ItemType Directory -Force -Path $facadeDir | Out-Null
    Write-Utf8 (Join-Path $facadeDir 'AiClaimModuleConfigFacadeImpl.java') @'
package com.huize.claim.core.ai.facade;

public class AiClaimModuleConfigFacadeImpl {
    public Object save(Object aiClaimModuleConfigDto) {
        return null;
    }

    public Boolean checkReviewModuleEnabled(Long caseId) {
        return Boolean.TRUE;
    }
}
'@

    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
The global feature still mentions `AiApplyClaimApiTaskProcessor.handleTaskResponse`,
`AiCalculateLossApiTaskProcessor.handleTaskResponse`, `ClaimAgentFacadeImpl.batchQueryCaseDetail`,
and `理算明细.png`; these belong to other families and must not be imposed on the config slice.
'@
    Write-Utf8 (Join-Path $replayRoot 'ROUND_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') ''
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl'
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        schema_version = 1
        families = @(
            [ordered]@{
                id = 'external_integration'
                required = $true
                status = 'OPEN'
                rank = 1
                first_executable_carrier = 'com.huize.claim.core.dock.facade.InsureCompanyPushFacadeImpl'
                proof_required = @('insurer_push_task_or_status')
            },
            [ordered]@{
                id = 'config_policy_threshold'
                required = $true
                status = 'PARTIAL'
                rank = 2
                first_executable_carrier = 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl'
                proof_required = @('persist_free_review_amount', 'clear_updates_database', 'reject_invalid_amounts', 'auto_flow_gate_reads_config')
                forbidden_proof = @('front_end_only', 'constant_only', 'mock_only')
            }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_05.json') ([ordered]@{
        slice_index = 5
        verification_status = 'PASS'
        slice_status = 'PARTIAL'
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        should_continue = $true
        adjusted_coverage_delta = 3
        closed_requirement_families = @('lifecycle_cleanup_retention')
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -RequirementFamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceIndex 6 `
        -ForcedRequirementFamily config_policy_threshold `
        -ForcedSliceType exact_contract_slice `
        -ForcedSiblingSurface 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl' | Out-Null
    Assert-True 'prepare_contracts_exit_zero' ($LASTEXITCODE -eq 0)

    $carrier = Get-Content -LiteralPath (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_06.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'facade_impl_default_test_name_inferred' `
        ([string]$carrier.red_expectation -match 'AiClaimModuleConfigFacadeImplTest#shouldCoverConfigPolicyThreshold') `
        ($carrier | ConvertTo-Json -Depth 16)
    Assert-True 'carrier_authorization_allows_config_family' ([string]$carrier.authorization -eq 'ALLOW') ($carrier | ConvertTo-Json -Depth 16)
    Assert-True 'class_only_facade_resolves_to_callable_save_method' `
        ([string]$carrier.selected_carrier -eq 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save' -and [string]$carrier.real_entry -eq 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl.save') `
        ($carrier | ConvertTo-Json -Depth 16)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Invoke-CallableCarrierAuthorization.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -SliceIndex 6 | Out-Null
    Assert-True 'callable_authorization_exit_zero' ($LASTEXITCODE -eq 0)
    $callable = Get-Content -LiteralPath (Join-Path $replayRoot 'CALLABLE_CARRIER_AUTHORIZATION_06.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'callable_authorization_allows_resolved_save_method' `
        ([string]$callable.authorization -eq 'ALLOW' -and [bool]$callable.can_proceed) `
        ($callable | ConvertTo-Json -Depth 16)

    $matrix = Get-Content -LiteralPath (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_06.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrixLiterals = @($matrix.rows | ForEach-Object { [string]$_.literal })
    $expected = @('persist_free_review_amount', 'clear_updates_database', 'reject_invalid_amounts', 'auto_flow_gate_reads_config')
    Assert-True 'matrix_scope_is_family_proof_required' ([string]$matrix.row_scope -eq 'family_proof_required') ($matrix | ConvertTo-Json -Depth 16)
    Assert-True 'matrix_contains_current_config_proofs_only' (
        ($matrixLiterals.Count -eq $expected.Count) -and
        (($expected | Where-Object { $matrixLiterals -notcontains $_ }).Count -eq 0)
    ) ($matrixLiterals -join ',')
    Assert-True 'matrix_excludes_global_exact_contract_debt' (
        ($matrixLiterals -join ',') -notmatch 'AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor|ClaimAgentFacadeImpl|理算明细'
    ) ($matrixLiterals -join ',')
    Assert-True 'matrix_rows_have_red_command' (
        (@($matrix.rows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.red_command) }).Count -eq 0)
    ) ($matrix | ConvertTo-Json -Depth 16)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 6 `
        -MaxRows 5 `
        -FailOnBroadRows | Out-Null
    Assert-True 'build_subset_exit_zero' ($LASTEXITCODE -eq 0)
    $subset = Get-Content -LiteralPath (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_06.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $subsetLiterals = @($subset.rows | ForEach-Object { [string]$_.literal })
    Assert-True 'subset_allows_current_config_proofs' ([string]$subset.decision -eq 'ALLOW') ($subset | ConvertTo-Json -Depth 16)
    Assert-True 'subset_scope_preserves_family_proof_required' ([string]$subset.row_scope -eq 'family_proof_required') ($subset | ConvertTo-Json -Depth 16)
    Assert-True 'subset_contains_current_config_proofs_only' (
        ($subsetLiterals.Count -eq $expected.Count) -and
        (($expected | Where-Object { $subsetLiterals -notcontains $_ }).Count -eq 0)
    ) ($subsetLiterals -join ',')

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 6 `
        -ForcedRequirementFamily config_policy_threshold `
        -ForcedSliceType exact_contract_slice `
        -ForcedSiblingSurface 'com.huize.claim.core.ai.facade.AiClaimModuleConfigFacadeImpl' | Out-Null
    Assert-True 'pre_slice_authorization_exit_zero' ($LASTEXITCODE -eq 0)
    $auth = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_06.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($auth.issues | ForEach-Object { [string]$_ })
    Assert-True 'pre_slice_authorization_allows_config_exact_contract' ([string]$auth.decision -eq 'ALLOW') ($auth | ConvertTo-Json -Depth 16)
    Assert-True 'pre_slice_no_missing_red_or_test_or_next_exact' (
        (($issues -join ',') -notmatch 'carrier_authorization_field_not_ready:red_expectation|test_name_missing|next_slice_exact_contract_not_ready|red_command')
    ) ($auth | ConvertTo-Json -Depth 16)

    Write-Host ''
    Write-Host 'v703 Family Exact Contract Uses Current Proof Scope: ALL PASSED'
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
