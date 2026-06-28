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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v699-side-effect-exact-subset-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $tempRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $replayRoot, $worktree | Out-Null

    Write-Utf8 (Join-Path $replayRoot 'IMPLEMENTATION_CONTRACT.md') @'
The global feature still mentions `AiApplyClaimApiTaskProcessor.handleTaskResponse`,
`AiCalculateLossApiTaskProcessor.handleTaskResponse`, `ClaimAgentFacadeImpl.batchQueryCaseDetail`,
and `理算明细.png`; these belong to other families and must not be imposed on the lifecycle slice.
'@
    Write-Utf8 (Join-Path $replayRoot 'ROUND_CONTRACT.md') ''
    Write-Utf8 (Join-Path $replayRoot 'EXPECTED_DIFF_MATRIX.md') ''
    Write-Utf8 (Join-Path $replayRoot 'TEST_CHARTER.md') ''
    Write-JsonFile (Join-Path $replayRoot 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        required_source_chain = $false
    })
    Write-JsonFile (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') ([ordered]@{
        schema_version = 1
        families = @(
            [ordered]@{
                id = 'lifecycle_cleanup_retention'
                required = $true
                status = 'OPEN'
                first_executable_carrier = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
                proof_required = @('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log')
                forbidden_proof = @('log_message_constant_only', 'mock_only', 'helper_only')
            }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Prepare-SliceEvidenceContracts.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -RequirementFamilyLedger (Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json') `
        -SliceIndex 5 `
        -ForcedRequirementFamily lifecycle_cleanup_retention `
        -ForcedSliceType stateful_success_slice `
        -ForcedSiblingSurface 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog' | Out-Null
    Assert-True 'prepare_contracts_exit_zero' ($LASTEXITCODE -eq 0)

    $matrix = Get-Content -LiteralPath (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $matrixLiterals = @($matrix.rows | ForEach-Object { [string]$_.literal })
    Assert-True 'matrix_scope_is_side_effect_proof_required' ([string]$matrix.row_scope -eq 'side_effect_proof_required') ($matrix | ConvertTo-Json -Depth 16)
    Assert-True 'matrix_contains_only_current_lifecycle_outputs' (
        ($matrixLiterals.Count -eq 4) -and
        (@('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log') | Where-Object { $matrixLiterals -notcontains $_ }).Count -eq 0
    ) ($matrixLiterals -join ',')
    Assert-True 'matrix_excludes_global_exact_contract_debt' (
        ($matrixLiterals -join ',') -notmatch 'AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor|ClaimAgentFacadeImpl|理算明细'
    ) ($matrixLiterals -join ',')

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 5 `
        -MaxRows 5 `
        -FailOnBroadRows | Out-Null
    Assert-True 'build_subset_exit_zero' ($LASTEXITCODE -eq 0)
    $subset = Get-Content -LiteralPath (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $subsetLiterals = @($subset.rows | ForEach-Object { [string]$_.literal })
    Assert-True 'subset_allows_lifecycle_outputs' ([string]$subset.decision -eq 'ALLOW') ($subset | ConvertTo-Json -Depth 16)
    Assert-True 'subset_scope_is_side_effect_expected_outputs' ([string]$subset.row_scope -eq 'side_effect_expected_outputs') ($subset | ConvertTo-Json -Depth 16)
    Assert-True 'subset_contains_current_lifecycle_outputs_only' (
        ($subsetLiterals.Count -eq 4) -and
        (@('ai_log_row', 'system_operator', 'task_completion_rows', 'negative_gate_failure_log') | Where-Object { $subsetLiterals -notcontains $_ }).Count -eq 0
    ) ($subsetLiterals -join ',')

    Write-JsonFile (Join-Path $replayRoot 'EXACT_CONTRACT_ASSERTION_MATRIX_05.json') ([ordered]@{
        schema_version = 1
        slice_index = 5
        forced_requirement_family = 'lifecycle_cleanup_retention'
        required_for_this_slice = $true
        rows = @(
            [ordered]@{
                literal = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                symbol_or_field = 'AiApplyClaimApiTaskProcessor.handleTaskResponse'
                db_or_wire_or_display = 'behavior'
                boundary_type = 'behavior'
                production_boundary = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
                test_assertion = 'global row must wait for its own slice'
                status = 'OPEN'
            },
            [ordered]@{
                literal = 'ai_log_row'
                symbol_or_field = 'ai_log_row'
                db_or_wire_or_display = 'db'
                boundary_type = 'db'
                production_boundary = 'com.huize.claim.core.examine.service.CaseExamineLogService.saveExamineLog'
                test_assertion = 'assert ai log row through lifecycle carrier'
                status = 'OPEN'
            }
        )
    })

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Build-NextSliceExactContract.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 5 `
        -MaxRows 5 `
        -FailOnBroadRows | Out-Null
    Assert-True 'build_subset_with_stale_matrix_exit_zero' ($LASTEXITCODE -eq 0)
    $filtered = Get-Content -LiteralPath (Join-Path $replayRoot 'NEXT_SLICE_EXACT_CONTRACT_05.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $filteredLiterals = @($filtered.rows | ForEach-Object { [string]$_.literal })
    $warnings = @($filtered.warnings | ForEach-Object { [string]$_ })
    Assert-True 'stale_global_row_skipped_from_subset' (
        ($filteredLiterals.Count -eq 1) -and
        ($filteredLiterals[0] -eq 'ai_log_row') -and
        (($warnings -join ',') -match 'out_of_slice_exact_row_skipped:AiApplyClaimApiTaskProcessor.handleTaskResponse')
    ) ($filtered | ConvertTo-Json -Depth 16)

    Write-Host ''
    Write-Host 'v699 Side-Effect Exact Subset Uses Current Slice Scope: ALL PASSED'
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
