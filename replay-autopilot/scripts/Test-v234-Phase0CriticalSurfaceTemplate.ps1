$ErrorActionPreference = 'Stop'

$promptPath = Join-Path $PSScriptRoot '..\prompts\phase0-contract-gate.prompt.md'
$prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8

foreach ($required in @(
    '## Critical Surface Allocation Plan',
    '| Surface / family | Why required | First executable slice | Carrier / entry | Proof required | Deferred blocker / coverage cap |',
    'Supporting Surface Executable Slices',
    'Requirement Family Ledger',
    'deferred + blocker/cap'
)) {
    if (-not $prompt.Contains($required)) {
        throw "phase0 prompt missing required critical-surface template token: $required"
    }
}

Write-Host 'PASS Test-v234-Phase0CriticalSurfaceTemplate'
