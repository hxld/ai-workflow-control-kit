param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$delegate = Join-Path $scriptRoot 'Test-v495-PolicyRebuildNoChangeFalsePositiveAndSideEffectRepair.ps1'

if (-not (Test-Path -LiteralPath $delegate -PathType Leaf)) {
    throw "Missing delegated regression: $delegate"
}

if ($KeepTemp) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $delegate -KeepTemp
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $delegate
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host 'PASS: v497 policy rebuild downstream validation is allowed when upstream assignment is present'
