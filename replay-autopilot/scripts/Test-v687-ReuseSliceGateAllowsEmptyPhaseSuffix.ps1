#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$sliceLoop = Join-Path $scriptRoot 'Run-SliceLoop.ps1'
$text = Get-Content -LiteralPath $sliceLoop -Raw -Encoding UTF8

Assert-True 'reuse_path_passes_empty_phase_suffix' ($text -match "-PhaseSuffix\s+''") 'The existing-slice reuse path must keep the canonical no-suffix stop reason.'
Assert-True 'phase_suffix_allows_empty_string' ($text -match '\[AllowEmptyString\(\)\]\s*\r?\n\s*\[string\]\$PhaseSuffix') 'Invoke-AllSliceGates must accept the reuse path empty suffix.'

$probe = @'
function Invoke-Probe {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$PhaseSuffix
    )
    if ([string]::IsNullOrWhiteSpace($PhaseSuffix)) { return 'root' }
    return $PhaseSuffix
}
Invoke-Probe -PhaseSuffix ''
'@
$result = powershell -NoProfile -ExecutionPolicy Bypass -Command $probe
Assert-True 'powershell_binding_accepts_empty_phase_suffix' ($LASTEXITCODE -eq 0 -and (($result | Out-String).Trim()) -eq 'root') (($result | Out-String).Trim())

Write-Host 'PASS: v687 reuse slice gate allows empty phase suffix'
