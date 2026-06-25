param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $scriptRoot 'Validate-VerifiableRuleClosure.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('rule-closure-' + [guid]::NewGuid().ToString('N'))
$replayRoot = Join-Path $tempRoot 'replay'
$controlRoot = Join-Path $tempRoot '_control'

New-Item -ItemType Directory -Force -Path $replayRoot, $controlRoot | Out-Null

try {
    $rulesPath = Join-Path $replayRoot 'VERIFIABLE_RULES.json'
    [ordered]@{
        schema = 'replay_verifiable_rule_pack.v1'
        generated_at = (Get-Date).ToString('s')
        replay_root = $replayRoot
        rules = @(
            [ordered]@{
                id = 'rule_real_entry_test_surface_required'
                fingerprint = 'wrong_test_surface'
                must_fix = $true
                machine_gate = 'real_entry_test_surface_required'
                verification_status = 'PENDING'
                regression_test = 'fixture regression must pass'
                next_validation = 'next validation must pass'
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rulesPath -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $replayRoot -ControlRoot $controlRoot *> (Join-Path $tempRoot 'fail.out')
    $failExit = $LASTEXITCODE
    Assert-True ($failExit -ne 0) "Expected open rule to fail, got $failExit."
    $failResult = Get-Content -LiteralPath (Join-Path $replayRoot 'VERIFIABLE_RULE_CLOSURE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($failResult.status -eq 'FAIL') 'Open rule should write FAIL status.'
    Assert-True ($failResult.open_rules.Count -eq 1) 'Open rule should be listed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $controlRoot 'VERIFIABLE_RULE_CLOSURE_LATEST.json') -PathType Leaf) 'Latest closure JSON should be copied.'

    @(
        '# Evolution Result',
        '',
        '- final_status: VALIDATED_TOOLING_EVOLUTION',
        '- tooling_changes_applied: true',
        '- stop_and_evolve_satisfied: true',
        '- verification_results: PASS',
        '- closed_machine_gates: real_entry_test_surface_required',
        '- changed_files: replay-autopilot/scripts/Validate-VerifiableRuleClosure.ps1'
    ) | Set-Content -LiteralPath (Join-Path $replayRoot 'EVOLUTION_RESULT.md') -Encoding UTF8
    [ordered]@{
        status = 'PASS'
        issues = @()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $replayRoot 'EVOLUTION_RESULT_VERIFY.json') -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $replayRoot -ControlRoot $controlRoot *> (Join-Path $tempRoot 'pass.out')
    $passExit = $LASTEXITCODE
    Assert-True ($passExit -eq 0) "Expected closed rule to pass, got $passExit."
    $passResult = Get-Content -LiteralPath (Join-Path $replayRoot 'VERIFIABLE_RULE_CLOSURE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($passResult.status -eq 'PASS') 'Closed rule should write PASS status.'
    Assert-True ($passResult.closed_rules.Count -eq 1) 'Closed rule should be listed.'

    $missingRulesRoot = Join-Path $tempRoot 'missing-rules-replay'
    New-Item -ItemType Directory -Force -Path $missingRulesRoot | Out-Null
    @(
        '# Replay Evolution Proposal',
        '',
        '- should_evolve: True',
        '- reason: plan contract failed'
    ) | Set-Content -LiteralPath (Join-Path $missingRulesRoot 'EVOLUTION_PROPOSAL.md') -Encoding UTF8
    [ordered]@{
        verification_status = 'FAIL'
        issues = @('plan_status_not_proceed:BLOCKED')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $missingRulesRoot 'PLAN_CONTRACT_VERIFY.json') -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sut -ReplayRoot $missingRulesRoot -ControlRoot $controlRoot *> (Join-Path $tempRoot 'missing-rules.out')
    $missingRulesExit = $LASTEXITCODE
    Assert-True ($missingRulesExit -ne 0) "Expected missing rules to fail when evolution is required, got $missingRulesExit."
    $missingRulesResult = Get-Content -LiteralPath (Join-Path $missingRulesRoot 'VERIFIABLE_RULE_CLOSURE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($missingRulesResult.status -eq 'FAIL') 'Missing rules should write FAIL status for required evolution.'
    Assert-True (@($missingRulesResult.issues) -contains 'verifiable_rules_missing_for_required_evolution') 'Missing rules failure should be machine-readable.'

    Write-Host 'Test-v598-VerifiableRuleClosureGate PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
