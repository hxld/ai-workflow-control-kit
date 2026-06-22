param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Details)) { throw "ASSERT FAILED: $Name" }
        throw "ASSERT FAILED: $Name - $Details"
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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Initialize-MinimalWorktree {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    git -C $Path init 2>&1 | Out-Null
    $testDir = Join-Path $Path 'claim-server/src/test/java/com/huize/claim/test'
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    'package com.huize.claim.test; class SliceAuthTest {}' | Set-Content -LiteralPath (Join-Path $testDir 'SliceAuthTest.java') -Encoding UTF8
    $prodDir = Join-Path $Path 'claim-core/src/main/java/com/huize/claim/core'
    New-Item -ItemType Directory -Force -Path $prodDir | Out-Null
    'package com.huize.claim.core; class TestProcessor {}' | Set-Content -LiteralPath (Join-Path $prodDir 'TestProcessor.java') -Encoding UTF8
    git -C $Path add -A 2>&1 | Out-Null
    git -C $Path commit -m 'initial' --allow-empty 2>&1 | Out-Null
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v597-wrong-surface-enforcement-" + [guid]::NewGuid().ToString('N'))

try {
    # ============================================================
    # Scenario 1: Mixed blocker + warning gap flags
    # wrong_test_surface is in warning_only_gap_flags alongside
    # a blocking flag in blocking_gap_flags.
    #
    # Regression: before v597, wrong_test_surface was excluded from
    # mustFailClosed when a severity split existed (blocking flags +
    # warning flags). The SliceVerifier's mustFailClosed loop checked
    # only $metaAuthorizingFlags (which = $blockingGapFlags), so
    # warning-classified behavioral flags were silently dropped.
    #
    # v597 fix: check both $metaAuthorizingFlags AND $gapFlags in
    # the mustFailClosed loop.
    # ============================================================
    Write-Host "`n=== Scenario 1: Mixed blocker + warning flags — wrong_test_surface must trigger mustFailClosed ==="

    $replayRoot1 = Join-Path $tempRoot 'scenario1'
    $worktree1 = Join-Path $replayRoot1 'worktree'
    Initialize-MinimalWorktree -Path $worktree1

    Write-JsonFile (Join-Path $replayRoot1 'FEATURE_CLASSIFICATION.json') ([ordered]@{
        schema_version = 1
        classification = 'backend_service'
        read_only = $false
    })

    Write-JsonFile (Join-Path $replayRoot1 'CARRIER_AUTHORIZATION_01.json') ([ordered]@{
        schema_version = 1
        slice_index = 1
        authorization = 'BLOCKED'
        issues = @()
    })

    Write-JsonFile (Join-Path $replayRoot1 'SLICE_RESULT_01.json') ([ordered]@{
        schema_version = 1
        slice_index = 1
        slice_status = 'BLOCKED'
        slice_type = 'blocker'
        gap_flags = @(
            'side_effect_evidence_missing',
            'wrong_test_surface',
            'tooling_enforcement_stop',
            'no_progress_slice'
        )
        tests = @()
        implemented_files = @()
        current_slice_changed_files = @()
        round_changed_files_snapshot = @()
        touched_requirement_families = @()
        closed_requirement_families = @()
        coverage_delta = 0
        next_recommended_slice_type = ''
        target_subsurface_or_carrier = ''
        production_boundary = ''
        proof_kind = ''
    })

    Write-JsonFile (Join-Path $replayRoot1 'SOURCE_CHAIN_CONTRACT.json') ([ordered]@{
        slice_index = 1
        rows = @()
    })

    # Run Verify-SliceClosure.ps1 first
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-SliceClosure.ps1') `
        -ReplayRoot $replayRoot1 `
        -Worktree $worktree1 `
        -SliceResult (Join-Path $replayRoot1 'SLICE_RESULT_01.json') `
        -SliceIndex 1 2>&1 | Out-Null

    $verify1 = Read-JsonFile (Join-Path $replayRoot1 'SLICE_VERIFY_01.json')
    $blockingFlags1 = @($verify1.blocking_gap_flags | ForEach-Object { [string]$_ })
    $warningFlags1 = @($verify1.warning_only_gap_flags | ForEach-Object { [string]$_ })

    Write-Host "  blocking_gap_flags: $($blockingFlags1 -join ', ')"
    Write-Host "  warning_only_gap_flags: $($warningFlags1 -join ', ')"

    # Verify the setup: wrong_test_surface is warning-only, and there IS a blocking flag
    Assert-True 'wrong_test_surface is warning-only (diagnostic)' `
        ($warningFlags1 -contains 'wrong_test_surface') `
        "warning_only=$($warningFlags1 -join '; ')"

    Assert-True 'a blocking flag exists (severity split is active)' `
        ($blockingFlags1.Count -gt 0) `
        "blocking=$($blockingFlags1 -join '; ')"

    # The critical pre-fix condition: wrong_test_surface is NOT in blocking_gap_flags
    # (this confirms the severity split excludes it from metaAuthorizingFlags)
    Assert-True 'wrong_test_surface is NOT in blocking_gap_flags (confirm severity split)' `
        ($blockingFlags1 -notcontains 'wrong_test_surface') `
        "blocking contains wrong_test_surface unexpectedly"

    # Run SliceVerifier.ps1
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'SliceVerifier.ps1') `
        -ReplayRoot $replayRoot1 `
        -Worktree $worktree1 `
        -SliceResult (Join-Path $replayRoot1 'SLICE_RESULT_01.json') `
        -SliceIndex 1 2>&1 | Out-Null

    $auth1 = Read-JsonFile (Join-Path $replayRoot1 'SLICE_AUTHORIZATION_01.json')
    $mustFailReasons1 = @($auth1.must_fail_reasons | ForEach-Object { [string]$_ })

    Write-Host "  must_fail_closed: $($auth1.must_fail_closed)"
    Write-Host "  must_fail_reasons: $($mustFailReasons1 -join ', ')"
    Write-Host "  authorized_for_next_slice: $($auth1.authorized_for_next_slice)"

    # The key v597 assertions: wrong_test_surface must independently trigger mustFailClosed
    Assert-True 'must_fail_closed is true' `
        ([bool]$auth1.must_fail_closed) `
        "must_fail_closed=$($auth1.must_fail_closed)"

    Assert-True 'wrong_test_surface is in must_fail_reasons (v597 fix)' `
        ($mustFailReasons1 -contains 'wrong_test_surface') `
        "must_fail_reasons=$($mustFailReasons1 -join '; ')"

    Assert-True 'side_effect_evidence_missing is in must_fail_reasons' `
        ($mustFailReasons1 -contains 'side_effect_evidence_missing') `
        "must_fail_reasons=$($mustFailReasons1 -join '; ')"

    Assert-True 'authorized_for_next_slice is false' `
        (-not [bool]$auth1.authorized_for_next_slice) `
        "authorized_for_next_slice=$($auth1.authorized_for_next_slice)"

    Write-Host "Scenario 1 PASS: wrong_test_surface correctly triggers mustFailClosed alongside blocker flags"

    # ============================================================
    # Summary
    # ============================================================
    Write-Host "`n=== All Scenarios Passed ==="
    $result = [ordered]@{
        status = 'PASS'
        script = $PSCommandPath
        version = 'v597'
        evolution_type = 'slice_verifier_wrong_surface_enforcement'
        tooling_changes = @(
            'SliceVerifier.ps1: mustFailClosed flag check extended to $gapFlags directly'
        )
        scenarios = @(
            'mixed_blocker_warning_wrong_test_surface_in_must_fail_reasons'
        )
        closed_machine_gates = @(
            'wrong_test_surface_independent_enforcement'
        )
    }
    $result | ConvertTo-Json -Depth 6
}
finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
