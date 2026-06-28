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
$runLoop = Join-Path $scriptRoot 'Run-ReplayLoop.ps1'
$phase0Prompt = Join-Path (Split-Path -Parent $scriptRoot) 'prompts\phase0-contract-gate.prompt.md'

$runLoopText = Get-Content -LiteralPath $runLoop -Raw -Encoding UTF8
$promptText = Get-Content -LiteralPath $phase0Prompt -Raw -Encoding UTF8

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runLoop, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True 'run_loop_parse_clean' (-not $parseErrors -or $parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')

$invokeWithRetryBlock = [regex]::Match(
    $runLoopText,
    '(?s)function Invoke-WithRetry\s*\{.+?(?=function Invoke-EvolutionWithRetry)'
).Value
Assert-True 'invoke_with_retry_extractable' (-not [string]::IsNullOrWhiteSpace($invokeWithRetryBlock))
Invoke-Expression $invokeWithRetryBlock

$script:FixtureExitCode = $null
$result = Invoke-WithRetry -Label 'stdout exit fixture' -Action {
    Write-Output 'agent stdout before failure'
    & powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Output 'native stdout before failure'; exit 93"
    $script:FixtureExitCode = $LASTEXITCODE
} -MaxRetries 2 -DelaySeconds 0 -NonRetryExitCodes @(93)

Assert-True 'invoke_with_retry_returns_scalar_bool' ($result -is [bool]) ("type=$($result.GetType().FullName)")
Assert-True 'invoke_with_retry_preserves_non_retry_false' ($result -eq $false)
Assert-True 'fixture_exit_code_is_93' ($script:FixtureExitCode -eq 93) "exit=$script:FixtureExitCode"
Assert-True 'invoke_with_retry_captures_action_output' ($runLoopText.Contains('$actionOutput = @(& $Action)'))

Assert-True 'phase0_guard_repair_forbids_protected_root_commands' (
    $runLoopText.Contains('Do not run any command line containing the protected project root') -and
    $runLoopText.Contains('pom.xml path outside the isolated worktree')
)
Assert-True 'phase0_guard_repair_uses_read_only_command_whitelist' (
    $runLoopText.Contains('Use only read-only source discovery commands such as rg, Get-Content, Select-String, Get-ChildItem, and Test-Path') -and
    $runLoopText.Contains('Do not run git diff, git log, git show, or any build tool in this repair pass')
)
Assert-True 'phase0_contract_repair_requires_schema_exact_ledger' (
    $runLoopText.Contains('EXPLORATION_REPORT.md must contain the exact heading ## Schema and Exact Contract Discovery Ledger after repair') -and
    $runLoopText.Contains('Do not put schema, signature, field, enum, or payload discovery content only under ## Uncertainty Ledger') -and
    $runLoopText.Contains('The Schema and Exact Contract Discovery Ledger must include current-worktree search evidence')
)

Assert-True 'phase0_prompt_has_shell_whitelist' (
    $promptText.Contains('Phase 0 shell command whitelist') -and
    $promptText.Contains('`rg`') -and
    $promptText.Contains('`Get-Content`') -and
    $promptText.Contains('`Test-Path`')
)
Assert-True 'phase0_prompt_forbids_protected_root_pom_compile' (
    $promptText.Contains('protected/original project root') -and
    $promptText.Contains('pom.xml') -and
    $promptText.Contains('{{WORKTREE}}') -and
    $promptText.Contains('Phase 0') -and
    $promptText.Contains('Maven')
)

[ordered]@{
    status = 'PASS'
    version = 'v612'
    assertions = @(
        'Invoke-WithRetry returns scalar false when child emits stdout and exits 93',
        'Phase0 command-guard repair narrows commands to read-only discovery',
        'Phase0 contract repair requires Schema and Exact Contract Discovery Ledger',
        'Phase0 prompt forbids protected-root pom compile commands'
    )
} | ConvertTo-Json -Depth 4
