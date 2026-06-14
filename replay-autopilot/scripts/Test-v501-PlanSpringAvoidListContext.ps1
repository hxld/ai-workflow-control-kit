param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifier = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$v491 = Join-Path $scriptRoot 'Test-v491-PolicyRebuildVerifierSiblingAndNoSpring.ps1'

$verifierText = Get-Content -LiteralPath $verifier -Raw -Encoding UTF8
Assert-True 'verifier_tracks_negative_spring_sections' ($verifierText.Contains('$inNegativeList') -and $verifierText.Contains('$negativeSection'))
Assert-True 'verifier_still_scans_real_spring_harness' ($verifierText.Contains('SpringJUnit4ClassRunner') -and $verifierText.Contains('return $true'))

$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $v491)
if ($KeepTemp) { $args += '-KeepTemp' }
& powershell @args
if ($LASTEXITCODE -ne 0) { throw "v491 no-spring regression failed with exit code $LASTEXITCODE" }

Write-Host 'PASS: v501 plan spring avoid-list context'
