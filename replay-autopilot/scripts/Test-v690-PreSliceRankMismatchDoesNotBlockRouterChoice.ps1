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
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v690-preauth-rank-mismatch-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'FIRST_SLICE_PROOF_PLAN.md') @'
first_red_test: sample-harness/src/test/java/com/example/workflow/StatefulFlowTest.java#shouldPersistStatefulSideEffects
selected_real_entry: com.example.workflow.TaskProcessor.handleTaskResponse
selected_carrier: com.example.workflow.TaskProcessor.handleTaskResponse
proof_kind: stateful_behavior
'@
    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'BASELINE_INDEX.md') ''
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'ORACLE_DIFF_ANALYSIS.json') ([ordered]@{
        files = @(
            [ordered]@{
                path = 'claim-core/src/main/java/com/huize/claim/core/ai/task/AiApplyClaimApiTaskProcessor.java'
                is_production = $true
                weight = 'HIGH'
                layer = 'Service'
            }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'FAMILY_CONTRACT.json') ([ordered]@{
        families = @(
            [ordered]@{ id = 'stateful_side_effect'; required = $true },
            [ordered]@{ id = 'external_integration'; required = $true }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'CARRIER_RANK_02.json') ([ordered]@{
        schema_version = 1
        slice_index = 2
        families = @(
            [ordered]@{
                family = 'external_integration'
                required = $true
                status = 'OPEN'
                rank = 1
                production_carrier = 'com.huize.claim.core.dock.facade.InsureCompanyPushFacadeImpl.push'
            },
            [ordered]@{
                family = 'stateful_side_effect'
                required = $true
                status = 'PARTIAL'
                rank = 4
                production_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
            }
        )
        missing_required_rank1 = @()
        gate = 'carrier_ranking_hard_stop'
    })
    Write-JsonFile (Join-Path $replayRoot 'CARRIER_AUTHORIZATION_02.json') ([ordered]@{
        schema_version = 1
        slice_index = 2
        forced_requirement_family = 'stateful_side_effect'
        authorization = 'ALLOW'
        real_entry = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        selected_carrier = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        production_boundary = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        downstream_side_effect_or_output = 'compensate_info_row; compensate_detail_row; route_status_change'
        red_expectation = 'business assertion should fail before production change'
        requires_side_effect_evidence = $true
        requires_exact_contract_assertions = $false
        forbidden_synthetic_carrier = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'SIDE_EFFECT_EVIDENCE_02.json') ([ordered]@{
        schema_version = 1
        slice_index = 2
        forced_requirement_family = 'stateful_side_effect'
        required_for_this_slice = $true
        entry_call = 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse'
        expected_writes_or_outputs = @('compensate_info_row', 'compensate_detail_row', 'route_status_change')
        red_result = 'PENDING_BUSINESS_ASSERTION'
        green_result = 'PENDING'
        test_name = 'sample-harness/src/test/java/com/example/workflow/StatefulFlowTest.java#shouldPersistStatefulSideEffects'
        status = 'READY'
    })
    Write-JsonFile (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_02.json') ([ordered]@{
        rows = @(
            [ordered]@{
                literal = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                symbol_or_field = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                test_assertion = 'should invoke selected task processor entry'
            }
        )
    })
    Write-JsonFile (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_02.json') ([ordered]@{
        decision = 'ALLOW'
        rows = @(
            [ordered]@{
                literal = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                symbol_or_field = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                test_assertion = 'should invoke selected task processor entry'
            }
        )
        issues = @()
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Authorize-PreSliceEvidence.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 2 `
        -ForcedRequirementFamily stateful_side_effect `
        -ForcedSliceType stateful_success_slice `
        -ForcedSiblingSurface 'com.huize.claim.core.ai.task.AiApplyClaimApiTaskProcessor.handleTaskResponse' | Out-Null
    Assert-True 'pre_slice_authorization_exit_zero' ($LASTEXITCODE -eq 0)

    $auth = Get-Content -LiteralPath (Join-Path $replayRoot 'PRE_SLICE_AUTHORIZATION_02.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = @($auth.issues | ForEach-Object { [string]$_ })
    $warnings = @($auth.warnings | ForEach-Object { [string]$_ })
    Assert-True 'rank_mismatch_does_not_block_router_selected_family' ([string]$auth.decision -eq 'ALLOW') ($auth | ConvertTo-Json -Depth 12)
    Assert-True 'rank_mismatch_not_in_issues' (-not (($issues -join ',') -match 'forced_family_not_highest_weight_open|forced_family_not_rank1')) ($issues -join ',')
    Assert-True 'rank_mismatch_disclosed_as_warning' (($warnings -join ',') -match 'forced_family_not_rank1:stateful_side_effect!=rank1:external_integration') ($warnings -join ',')

    Write-Host ''
    Write-Host 'v690 PreSlice Rank Mismatch Does Not Block Router Choice: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
