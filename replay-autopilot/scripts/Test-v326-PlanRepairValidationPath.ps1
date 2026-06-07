<#
.SYNOPSIS
    Regression tests for v326 plan repair parsing and early evolution validation.

.DESCRIPTION
    Covers the two failures seen in v325:
    1. PLAN_RESULT repair wrote **oracle_production_file_overlap:** 51%, which
       the verifier did not parse.
    2. early-stop evolution validation was skipped because Run-ReplayLoop passed
       the autopilot root while the helper expected the scripts directory.
#>

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$verifyPath = Join-Path $scriptRoot 'Verify-PlanContract.ps1'
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'

Write-Host "=== v326 Plan Repair / Evolution Validation Path Test ===" -ForegroundColor Cyan

Write-Host "`n[Test 1] Verify-PlanContract parses bold oracle overlap repair field..."
$verifyText = Get-Content -LiteralPath $verifyPath -Raw -Encoding UTF8
$declaredOverlapBlock = [regex]::Match(
    $verifyText,
    '(?s)\$declaredOverlap\s*=\s*Get-FirstText\s+\$planText\s+@\((.*?)\)\s*\r?\n\s*\$oracleHighWeightFiles'
)
Assert-True $declaredOverlapBlock.Success 'declaredOverlap regex block not found'
$patterns = @([regex]::Matches($declaredOverlapBlock.Groups[1].Value, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
Assert-True ($patterns.Count -ge 4) 'expected declaredOverlap regex patterns'
$sample = '**oracle_production_file_overlap:** 51%'
$matched = $false
foreach ($pattern in $patterns) {
    if ([regex]::Match($sample, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Success) {
        $matched = $true
        break
    }
}
Assert-True $matched 'bold key-with-colon overlap field must be accepted'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 2] Evolution validation helper resolves autopilot root to scripts directory..."
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8
Assert-True ($runLoopText.Contains('$scriptDirCandidate = Join-Path $ScriptRoot ''scripts''')) `
    'Invoke-EvolutionResultValidationOrRepair must probe ScriptRoot\scripts'
Assert-True ($runLoopText.Contains('$evolutionValidationScript = $validationCandidate')) `
    'Invoke-EvolutionResultValidationOrRepair must use validationCandidate'
Assert-True ($runLoopText.Contains('-File'', (Join-Path $scriptDir ''Invoke-AgentPrompt.ps1'')')) `
    'evolution repair must invoke Invoke-AgentPrompt.ps1 from resolved scriptDir'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 3] Missing evolution validator is fail-closed, not implicit success..."
Assert-True ($runLoopText.Contains('Evolution validation script is missing')) `
    'missing validator blocker message must exist'
Assert-True ($runLoopText.Contains('return $false')) `
    'missing validator branch must return false'
Assert-True (-not ($runLoopText -match 'if \(-not \(Test-Path -LiteralPath \$evolutionValidationScript\)\)\s*\{\s*return \$true\s*\}')) `
    'missing validator must not return true'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
exit 0
