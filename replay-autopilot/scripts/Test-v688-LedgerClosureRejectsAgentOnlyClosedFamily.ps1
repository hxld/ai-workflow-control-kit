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
    param([string]$Path, $Value, [int]$Depth = 16)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v688-ledger-agent-only-closure-' + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    Write-JsonFile (Join-Path $replayRoot 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        classification = 'backend'
        verifier_adjustments = [ordered]@{ non_applicable_families = @() }
    })

    $ledgerPath = Join-Path $replayRoot 'REQUIREMENT_FAMILY_LEDGER.json'
    Write-JsonFile $ledgerPath ([ordered]@{
        schema_version = 1
        replay_root = $replayRoot
        max_slices = 3
        created_at = '2026-06-28T00:00:00'
        updated_at = '2026-06-28T00:00:00'
        coverage_cap = 100
        no_progress_slices = @()
        open_required_after_max = @()
        families = @(
            [ordered]@{
                id = 'stateful_side_effect'
                title = 'Stateful side effects'
                weight = 95
                recommended_slice_type = 'stateful_success_slice'
                required = $true
                status = 'OPEN'
                touched_count = 0
                first_slice = $null
                last_slice = $null
                slices = @()
                first_executable_carrier = 'TaskProcessor'
                planned_slice = 'S1'
                proof_required = @('db_assertion')
                forbidden_proof = @('helper_only')
                coverage_cap_if_open = 60
                open_sibling_surfaces = @()
                open_sibling_count = 0
                last_next_recommended_slice_type = ''
                last_gap_flags = @()
                evidence_keywords = @('stateful_side_effect', 'state', 'db')
                last_reason = 'fixture'
            }
        )
    })

    Write-JsonFile (Join-Path $replayRoot 'SLICE_RESULT_01.json') ([ordered]@{
        slice_index = 1
        slice_status = 'DONE'
        slice_type = 'stateful_success_slice'
        coverage_delta = 15
        target_subsurface_or_carrier = 'TaskProcessor'
        production_boundary = 'TaskProcessor'
        proof_kind = 'stateful_side_effect'
        red_expectation = 'state not written before fix'
        implemented_files = @('example-core/src/main/java/acme/TaskProcessor.java')
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @('stateful_side_effect')
        gap_flags = @()
        tests = @([ordered]@{ phase = 'GREEN'; result = 'pass'; command = 'mvn test'; evidence = 'BUILD SUCCESS' })
    })
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'FAIL'
        adjusted_coverage_delta = 0
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @()
        authorization_blockers = @('verification_failed_or_blocked')
        gap_flags = @('side_effect_ledger_gap')
        warnings = @('side_effect_ledger_depth_incomplete')
        proof_type_mismatch_families = @()
    })

    Import-RunSliceLoopFunctions
    Update-FamilyLedgerFromSlice -Path $ledgerPath -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceVerifyPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -SliceIndex 1 -MaxSlices 3

    $ledger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $stateful = @($ledger.families | Where-Object { [string]$_.id -eq 'stateful_side_effect' } | Select-Object -First 1)[0]
    Assert-True 'agent_only_closed_family_is_not_executable_closed' ([string]$stateful.status -ne 'EXECUTABLE_CLOSED') ($ledger | ConvertTo-Json -Depth 16)
    Assert-True 'agent_only_closed_family_remains_partial_after_touch' ([string]$stateful.status -eq 'PARTIAL') ($stateful | ConvertTo-Json -Depth 12)

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify-family-ledger-from-slice-verify.ps1') -ReplayRoot $replayRoot | Out-Null
    Assert-True 'family_ledger_verifier_accepts_non_closed_touched_family' ($LASTEXITCODE -eq 0)
    $check = Get-Content -LiteralPath (Join-Path $replayRoot 'FAMILY_LEDGER_FROM_SLICE_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True 'verifier_records_touched_not_closed_without_failure' ([string]$check.status -eq 'PASS' -and @($check.verified_closed_families).Count -eq 0) ($check | ConvertTo-Json -Depth 12)

    foreach ($family in @($ledger.families)) {
        if ([string]$family.id -eq 'stateful_side_effect') {
            $family.status = 'EXECUTABLE_CLOSED'
            $family.last_reason = 'stale closure from prior runner version'
        }
    }
    $ledger | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8
    Update-FamilyLedgerFromSliceIfPresent -Path $ledgerPath -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceVerifyPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -SliceIndex 1 -MaxSlices 3
    $ledgerAfterRefresh = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $statefulAfterRefresh = @($ledgerAfterRefresh.families | Where-Object { [string]$_.id -eq 'stateful_side_effect' } | Select-Object -First 1)[0]
    Assert-True 'failed_reuse_refresh_clears_stale_executable_closed' ([string]$statefulAfterRefresh.status -eq 'PARTIAL') ($ledgerAfterRefresh | ConvertTo-Json -Depth 16)

    foreach ($family in @($ledgerAfterRefresh.families)) {
        if ([string]$family.id -eq 'stateful_side_effect') {
            $family.status = 'PARTIAL'
            $family.last_reason = 'reset before verifier-authoritative partial closure fixture'
        }
    }
    $ledgerAfterRefresh | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8
    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'PARTIAL'
        adjusted_coverage_delta = 3
        should_continue = $true
        authorized_for_next_slice = $true
        authorized_for_synthesis = $false
        touched_requirement_families = @('stateful_side_effect')
        closed_requirement_families = @('stateful_side_effect')
        authorization_blockers = @()
        gap_flags = @('family_sibling_gap')
        warnings = @('family_sibling_surface_open')
        proof_type_mismatch_families = @()
    })
    Update-FamilyLedgerFromSliceIfPresent -Path $ledgerPath -SliceResultPath (Join-Path $replayRoot 'SLICE_RESULT_01.json') -SliceVerifyPath (Join-Path $replayRoot 'SLICE_VERIFY_01.json') -SliceIndex 1 -MaxSlices 3
    $ledgerAfterPartialClosure = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $statefulAfterPartialClosure = @($ledgerAfterPartialClosure.families | Where-Object { [string]$_.id -eq 'stateful_side_effect' } | Select-Object -First 1)[0]
    Assert-True 'verifier_closed_partial_slice_keeps_ledger_closed' ([string]$statefulAfterPartialClosure.status -eq 'EXECUTABLE_CLOSED') ($ledgerAfterPartialClosure | ConvertTo-Json -Depth 16)

    Write-Host 'PASS: v688 ledger closure rejects agent-only closed family'
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
