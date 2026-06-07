<#
.SYNOPSIS
    Regression test for Phase0 reconciliation invocation.

.DESCRIPTION
    Guards against calling Invoke-Phase0ContractReconciliation.ps1 through
    powershell -File with -FailOnContradiction:$false. Windows PowerShell
    passes that switch value as a string in this shape and can stop the replay
    before Phase0 repair/Plan can run.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== v323 Phase0 Reconciliation Invocation Test ===" -ForegroundColor Cyan

$runnerPath = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'
if (-not (Test-Path -LiteralPath $runnerPath)) {
    Write-Host "FAIL: Run-ReplayLoop.ps1 not found" -ForegroundColor Red
    exit 1
}

$runnerContent = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

Write-Host "`n[Test 1] Runner invokes reconciliation in-process..."
if ($runnerContent -notmatch '\$reconcileResult\s*=\s*&\s*\$reconcileScript\s+-ReplayRoot\s+\$replayRoot') {
    Write-Host "FAIL: Run-ReplayLoop.ps1 does not invoke reconciliation in-process" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: in-process invocation found" -ForegroundColor Green

Write-Host "`n[Test 2] Runner does not pass false switch through powershell -File..."
if ($runnerContent -match '-FailOnContradiction:\$false') {
    Write-Host "FAIL: Run-ReplayLoop.ps1 still passes -FailOnContradiction:`$false" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: false switch forwarding removed" -ForegroundColor Green

Write-Host "`n[Test 3] Wrapper can skip cleanly when artifacts are absent..."
$wrapperPath = Join-Path $PSScriptRoot 'Invoke-Phase0ContractReconciliation.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("phase0-reconcile-empty-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $result = & $wrapperPath -ReplayRoot $tempRoot
    if (-not $result -or $result.status -ne 'SKIP' -or $result.reason -ne 'ledger_not_found') {
        Write-Host "FAIL: Expected SKIP/ledger_not_found but got: $($result | ConvertTo-Json -Compress)" -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "PASS: wrapper skip path returns structured result" -ForegroundColor Green

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
