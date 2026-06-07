$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$runLoopPath = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$runLoopText = Get-Content -LiteralPath $runLoopPath -Raw -Encoding UTF8

Write-Host "=== v335 Carrier Search Oracle Commit Binding Test ===" -ForegroundColor Cyan

Write-Host "`n[Test 1] Carrier search uses configured oracle_commit, not undefined baseCommit..."
Assert-True ($runLoopText.Contains('$oracleCommitForCarrierSearch = Require-Key $config ''oracle_commit''')) `
    'Run-ReplayLoop must bind oracleCommitForCarrierSearch from config oracle_commit'
Assert-True (-not ($runLoopText -match '-OracleCommit\s+\$baseCommit')) `
    'Run-ReplayLoop must not pass undefined $baseCommit to Invoke-PlanCarrierSearchVerification'
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 2] Both carrier-search verification calls pass the same non-empty variable..."
$matches = [regex]::Matches($runLoopText, '-OracleCommit\s+\$oracleCommitForCarrierSearch')
Assert-True ($matches.Count -eq 2) "Expected two -OracleCommit oracleCommitForCarrierSearch calls, got $($matches.Count)"
Write-Host "PASS" -ForegroundColor Green

Write-Host "`n[Test 3] ValidateOnly accepts Claude-only config after binding fix..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Run-ReplayLoop.ps1') -ValidateOnly -UseLatestKnowledgeVersion -RequireExecutor claude | Out-Null
Assert-True ($LASTEXITCODE -eq 0) 'Run-ReplayLoop ValidateOnly must pass after carrier-search binding fix'
Write-Host "PASS" -ForegroundColor Green

[ordered]@{
    status = 'PASS'
    assertions = 4
    cases = @(
        'carrier_search_binds_oracle_commit_from_config',
        'carrier_search_does_not_use_undefined_baseCommit',
        'both_carrier_search_invocations_use_bound_oracle_commit',
        'claude_only_validate_only_passes'
    )
} | ConvertTo-Json -Depth 5
