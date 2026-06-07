<#
.SYNOPSIS
    Test v319 Contract Reconciliation Pipeline integration.

.DESCRIPTION
    Validates that the Phase 0 contract reconciliation tool works correctly
    and is integrated into Run-ReplayLoop.ps1.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== v319 Contract Reconciliation Test ===" -ForegroundColor Cyan

# Test 1: Python script syntax
Write-Host "`n[Test 1] Python script syntax check..."
$scriptPath = Join-Path $PSScriptRoot "reconcile_phase0_artifacts.py"
if (-not (Test-Path $scriptPath)) {
    Write-Host "FAIL: reconcile_phase0_artifacts.py not found" -ForegroundColor Red
    exit 1
}

$output = python3 -m py_compile $scriptPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL: Python syntax error in reconcile_phase0_artifacts.py" -ForegroundColor Red
    Write-Host $output
    exit 1
}
Write-Host "PASS: Python script compiles successfully" -ForegroundColor Green

# Test 2: PowerShell wrapper exists and is valid
Write-Host "`n[Test 2] PowerShell wrapper validation..."
$wrapperPath = Join-Path $PSScriptRoot "Invoke-Phase0ContractReconciliation.ps1"
if (-not (Test-Path $wrapperPath)) {
    Write-Host "FAIL: Invoke-Phase0ContractReconciliation.ps1 not found" -ForegroundColor Red
    exit 1
}

try {
    $null = Get-Command -Syntax $wrapperPath -ErrorAction Stop
    Write-Host "PASS: PowerShell wrapper is valid" -ForegroundColor Green
} catch {
    Write-Host "FAIL: PowerShell wrapper has syntax errors" -ForegroundColor Red
    exit 1
}

# Test 3: Runner integration check
Write-Host "`n[Test 3] Runner integration check..."
$runnerPath = Join-Path $PSScriptRoot "Run-ReplayLoop.ps1"
if (-not (Test-Path $runnerPath)) {
    Write-Host "FAIL: Run-ReplayLoop.ps1 not found" -ForegroundColor Red
    exit 1
}

$runnerContent = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
if ($runnerContent -notmatch 'Invoke-Phase0ContractReconciliation') {
    Write-Host "FAIL: Run-ReplayLoop.ps1 does not call Invoke-Phase0ContractReconciliation" -ForegroundColor Red
    exit 1
}
if ($runnerContent -notmatch 'v319.*Contract Reconciliation') {
    Write-Host "FAIL: Run-ReplayLoop.ps1 does not have v319 comment for reconciliation" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Runner integration verified" -ForegroundColor Green

# Test 4: TDD cycle prompt exists
Write-Host "`n[Test 4] TDD cycle prompt check..."
$tddPromptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "prompts\tdd-cycle.md"
if (-not (Test-Path $tddPromptPath)) {
    Write-Host "FAIL: tdd-cycle.md not found" -ForegroundColor Red
    exit 1
}

$tddContent = Get-Content -LiteralPath $tddPromptPath -Raw -Encoding UTF8
if ($tddContent -notmatch 'RED.*GREEN.*REFACTOR') {
    Write-Host "FAIL: tdd-cycle.md missing RED-GREEN-REFACTOR content" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: TDD cycle prompt exists and contains required content" -ForegroundColor Green

# Test 5: BOM-safe JSON loading
Write-Host "`n[Test 5] BOM-safe JSON loading..."
$tempRoot = Join-Path (Split-Path $PSScriptRoot -Parent) (".tmp\reconciliation-bom-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$ledgerPath = Join-Path $tempRoot 'REQUIREMENT_FAMILY_LEDGER.json'
$contractPath = Join-Path $tempRoot 'FAMILY_CONTRACT.json'
$outputPath = Join-Path $tempRoot 'RECONCILIATION_RESULT.json'
try {
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($ledgerPath, '{"families":[{"name":"core_entry","required":true,"status":"OPEN","weight":100}]}', $utf8Bom)
    [System.IO.File]::WriteAllText($contractPath, '{"families":{"core_entry":{"blocker":""}}}', $utf8Bom)

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $bomOutput = & python3 $scriptPath $ledgerPath $contractPath --output $outputPath 2>&1
    $bomExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference
    if ($bomExitCode -ne 0) {
        Write-Host "FAIL: Reconciliation script rejected UTF-8 BOM JSON" -ForegroundColor Red
        Write-Host $bomOutput
        exit 1
    }
    $result = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.status -ne 'PASS') {
        Write-Host "FAIL: Expected PASS for BOM JSON fixture, got $($result.status)" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS: Reconciliation script accepts UTF-8 BOM JSON" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 6: list-shaped family artifacts and wrapper stderr handling
Write-Host "`n[Test 6] List-shaped family artifacts via wrapper..."
$tempRoot = Join-Path (Split-Path $PSScriptRoot -Parent) (".tmp\reconciliation-list-shape-{0}" -f $PID)
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$ledgerPath = Join-Path $tempRoot 'REQUIREMENT_FAMILY_LEDGER.json'
$contractPath = Join-Path $tempRoot 'FAMILY_CONTRACT.json'
$outputPath = Join-Path $tempRoot 'RECONCILIATION_RESULT.json'
try {
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($ledgerPath, '{"families":[{"id":"core_entry","required":true,"status":"OPEN","weight":100}]}', $utf8Bom)
    [System.IO.File]::WriteAllText($contractPath, '{"families":[{"id":"core_entry","blocker":""}]}', $utf8Bom)

    $result = & $wrapperPath -ReplayRoot $tempRoot
    if ($result.status -ne 'PASS') {
        Write-Host "FAIL: Expected PASS for list-shaped family fixture, got $($result.status)" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $outputPath)) {
        Write-Host "FAIL: Wrapper did not write RECONCILIATION_RESULT.json" -ForegroundColor Red
        exit 1
    }
    Write-Host "PASS: Wrapper accepts list-shaped family artifacts" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
