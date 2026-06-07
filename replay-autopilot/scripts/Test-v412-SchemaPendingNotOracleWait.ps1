$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

$patternMatch = [regex]::Match($content, "\`$manualOracleWaitPattern\s*=\s*'([^']+)'")
if (-not $patternMatch.Success) {
    throw 'manualOracleWaitPattern assignment not found.'
}

$manualOracleWaitPattern = $patternMatch.Groups[1].Value

if ('schema verification pending' -match $manualOracleWaitPattern) {
    throw 'schema verification pending must not be classified as phase0_manual_oracle_wait.'
}

if ('awaiting schema' -match $manualOracleWaitPattern) {
    throw 'awaiting schema must not be classified as phase0_manual_oracle_wait.'
}

if ('waiting for Oracle' -notmatch $manualOracleWaitPattern) {
    throw 'real oracle waiting text must still be classified as phase0_manual_oracle_wait.'
}

if ($content -notmatch 'schema_verification_pending_disclosed') {
    throw 'schema pending text should be retained as a non-blocking warning.'
}

Write-Host 'Test-v412-SchemaPendingNotOracleWait: PASS'
