#!/usr/bin/env pwsh
# Test-v285-RunnerSyntaxRecovery.ps1
# v285: Test runner syntax fixes and recovery router parameter handling

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) {
        Write-Host "FAIL: $Name" -ForegroundColor Red
        return $false
    }
    Write-Host "PASS: $Name" -ForegroundColor Green
    return $true
}

$cases = [System.Collections.Generic.List[bool]]::new()

# Test 1: Run-SliceLoop.ps1 parses without syntax errors
Write-Host "`nTest 1: Run-SliceLoop.ps1 parses without syntax errors"
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw), [ref]$parseErrors)
$cases.Add((Assert-True 'run_slice_loop_parses' ($parseErrors.Count -eq 0)))

# Test 2: Run-ReplayLoop.ps1 parses without syntax errors
Write-Host "`nTest 2: Run-ReplayLoop.ps1 parses without syntax errors"
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -Raw), [ref]$parseErrors)
$cases.Add((Assert-True 'run_replay_loop_parses' ($parseErrors.Count -eq 0)))

# Test 3: Recovery router accepts 'none' sentinel for empty ForcedFamily
Write-Host "`nTest 3: Recovery router accepts 'none' sentinel for empty ForcedFamily"
$replayRoot = Join-Path $env:TEMP "replay_test_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 1 `
        -BlockerReason 'test_blocker' `
        -ForcedFamily 'none' `
        -SliceType 'test' | Out-Null
    $recoveryPath = Join-Path $replayRoot 'RECOVERY_ACTION_1.json'
    $cases.Add((Assert-True 'recovery_router_accepts_none_sentinel' (Test-Path -LiteralPath $recoveryPath)))
} finally {
    Remove-Item -LiteralPath $replayRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 4: Recovery router handles empty ForcedFamily by omission
Write-Host "`nTest 4: Recovery router handles missing ForcedFamily parameter"
$replayRoot = Join-Path $env:TEMP "replay_test_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
try {
    # Call without -ForcedFamily parameter at all
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Get-RecoveryAction.ps1') `
        -ReplayRoot $replayRoot `
        -SliceIndex 2 `
        -BlockerReason 'test_blocker' `
        -SliceType 'test' | Out-Null
    $recoveryPath = Join-Path $replayRoot 'RECOVERY_ACTION_2.json'
    $cases.Add((Assert-True 'recovery_router_handles_missing_forced_family' (Test-Path -LiteralPath $recoveryPath)))
} finally {
    Remove-Item -LiteralPath $replayRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 5: Check that $i: syntax is not present in Run-SliceLoop.ps1
Write-Host "`nTest 5: No invalid `$i: syntax in Run-SliceLoop.ps1"
$content = Get-Content -LiteralPath (Join-Path $scriptRoot 'Run-SliceLoop.ps1') -Raw
$hasInvalidSyntax = $content -match '\$i:'
$cases.Add((Assert-True 'no_invalid_variable_syntax' (-not $hasInvalidSyntax)))

# Summary
$passed = ($cases | Where-Object { $_ }).Count
$total = $cases.Count
Write-Host "`n========================================"
Write-Host "v285 Test Results: $passed/$total passed"
if ($passed -eq $total) {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests FAILED" -ForegroundColor Red
    exit 1
}
