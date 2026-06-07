param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "Assertion failed: $Name" }
    return $Name
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$runLoop = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1')
$untilRunner = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'Run-UntilKnowledgeVersion.ps1')

$cases = New-Object System.Collections.Generic.List[string]
$cases.Add((Assert-True -Name 'run_loop_has_evolution_retry_helper' -Condition ($runLoop -match 'function\s+Invoke-EvolutionWithRetry'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_retries_evolution_calls' -Condition (($runLoop | Select-String -Pattern 'Invoke-EvolutionWithRetry' -AllMatches).Matches.Count -ge 6))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_has_no_direct_evolution_native_invocation' -Condition ($runLoop -notmatch '&\s+powershell\s+@evolutionArgs'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_preserves_evolution_exit_code' -Condition ($runLoop -match 'LastEvolutionExitCode'))) | Out-Null
$cases.Add((Assert-True -Name 'run_loop_documents_claude_api_400_retry' -Condition ($runLoop -match 'API Error:\s*400\s*/\s*1210'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_has_process_retry_helper' -Condition ($untilRunner -match 'function\s+Invoke-ProcessWithRetry'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_retries_evolution_process' -Condition ($untilRunner -match 'Invoke-ProcessWithRetry[\s\S]+-Label\s+''evolution''[\s\S]+-MaxRetries\s+2'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_records_attempt_count' -Condition ($untilRunner -match 'evolution_attempts'))) | Out-Null
$cases.Add((Assert-True -Name 'until_runner_documents_claude_api_400_retry' -Condition ($untilRunner -match 'API Error:\s*400\s*/\s*1210'))) | Out-Null

[ordered]@{
    status = 'PASS'
    assertions = $cases.Count
    cases = @($cases)
} | ConvertTo-Json -Depth 5
