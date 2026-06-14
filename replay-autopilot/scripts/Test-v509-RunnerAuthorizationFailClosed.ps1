param(
    [switch]$KeepTemp,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-JsonFile {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    if (-not $Condition) {
        throw "FAIL: $Name $Details"
    }
}

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) {
        throw "FAIL: $Name missing pattern: $Pattern"
    }
}

$scriptRoot = Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')
$tempRoot = Join-Path $scriptRoot ('.tmp\v509-runner-authorization-{0}' -f $PID)
$enforcer = Join-Path $PSScriptRoot 'Enforce-RoundCoverageCap.ps1'
$parser = Join-Path $PSScriptRoot 'Parse-ReplayReport.ps1'
$stopLoss = Join-Path $PSScriptRoot 'Test-ReplayStopLoss.ps1'
$synthesisValidator = Join-Path $PSScriptRoot 'Validate-StopLossSynthesis.ps1'
$runner = Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        enforcer = $enforcer
        parser = $parser
        stop_loss = $stopLoss
        synthesis_validator = $synthesisValidator
        runner = $runner
        temp_root = $tempRoot
    } | ConvertTo-Json -Depth 6
    exit 0
}

foreach ($required in @($enforcer, $parser, $stopLoss, $synthesisValidator, $runner)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required script: $required"
    }
}

$runnerText = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
Assert-Contains 'runner has authorization helper' $runnerText 'Get-RunnerAuthorizationState'
Assert-Contains 'runner caps oracle on non-authorizing evidence' $runnerText 'runner_non_authorizing_cap_blocks_oracle_credit'
Assert-Contains 'runner writes non-authorizing decision evidence' $runnerText 'runner_non_authorizing_signals'

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$roundResult = Join-Path $tempRoot 'ROUND_RESULT.md'
$finalReport = Join-Path $tempRoot 'FINAL_REPLAY_REPORT.md'
$routerCap = Join-Path $tempRoot 'FAMILY_ROUTER_AND_CAP.json'
$sliceVerify = Join-Path $tempRoot 'SLICE_VERIFY_01.json'

Set-Content -LiteralPath $roundResult -Encoding UTF8 -Value (@(
    '# Round Result',
    '',
    '## Verification Capped Coverage',
    '',
    '**Capped Coverage**: 100%',
    '',
    '## Final Status',
    '',
    '**Status**: PASS'
) -join "`n")

Set-Content -LiteralPath $finalReport -Encoding UTF8 -Value (@(
    '# Final Replay Report',
    '',
    '```',
    'production_match: 100',
    'oracle_adjusted_coverage: 100',
    'replay_classification: full_replay',
    '```',
    '',
    '| Metric | Value |',
    '|--------|-------|',
    '| verification_capped_coverage | 100% |',
    '| oracle_adjusted_coverage | 100% |'
) -join "`n")

Write-JsonFile -Path $routerCap -Object ([ordered]@{
    coverage_cap_from_ledger = 0
    final_pass_allowed = $false
    open_required_family_count = 2
    open_families = @(
        [ordered]@{ id = 'stateful_side_effect'; status = 'OPEN'; weight = 95 },
        [ordered]@{ id = 'wire_payload_api_contract'; status = 'OPEN'; weight = 88 }
    )
})

Write-JsonFile -Path $sliceVerify -Object ([ordered]@{
    verification_status = 'FAIL'
    authorized_for_next_slice = $false
    authorized_for_synthesis = $false
    authorization_blockers = @(
        'test_compilation_failed',
        'behavior_test_charter_evidence_file_invalid'
    )
})

& powershell -NoProfile -ExecutionPolicy Bypass -File $enforcer `
    -RoundResultPath $roundResult `
    -RouterCapPath $routerCap `
    -ReplayRoot $tempRoot
if ($LASTEXITCODE -ne 0) {
    throw "Enforce-RoundCoverageCap.ps1 failed with exit code $LASTEXITCODE"
}

$roundText = Get-Content -LiteralPath $roundResult -Raw -Encoding UTF8
Assert-Contains 'round verification cap exact metric' $roundText '(?m)^-\s*verification_capped_coverage:\s*0\s*$'
Assert-Contains 'round final blocked exact metric' $roundText '(?m)^-\s*final_status:\s*BLOCKED\s*$'
Assert-Contains 'round non-authorizing signal' $roundText 'authorized_for_synthesis=false:SLICE_VERIFY_01\.json'

& powershell -NoProfile -ExecutionPolicy Bypass -File $parser -ReplayRoot $tempRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Parse-ReplayReport.ps1 failed with exit code $LASTEXITCODE"
}

$summaryText = Get-Content -LiteralPath (Join-Path $tempRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
Assert-Contains 'summary verification cap' $summaryText '(?m)^-\s*verification_capped_coverage:\s*0\s*$'
Assert-Contains 'summary oracle enforced to zero' $summaryText '(?m)^-\s*oracle_adjusted_coverage:\s*0\s*$'
Assert-Contains 'summary preserves reported oracle' $summaryText '(?m)^-\s*reported_oracle_adjusted_coverage:\s*100\s*$'
Assert-Contains 'summary final blocked' $summaryText '(?m)^-\s*final_status:\s*BLOCKED\s*$'
Assert-Contains 'summary runner signal' $summaryText 'runner_non_authorizing_signals: .*authorized_for_synthesis=false:SLICE_VERIFY_01\.json'

& powershell -NoProfile -ExecutionPolicy Bypass -File $stopLoss `
    -ReplayRoot $tempRoot `
    -HistoryRoot $tempRoot `
    -TargetCoverage 90 `
    -LowCapRounds 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Test-ReplayStopLoss.ps1 failed with exit code $LASTEXITCODE"
}

$stopLossJson = Get-Content -LiteralPath (Join-Path $tempRoot 'STOP_LOSS_DECISION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True 'stop-loss blocks target reached' ($stopLossJson.decision -eq 'STOP_DEEP_REVIEW_REQUIRED') ($stopLossJson | ConvertTo-Json -Depth 12)
Assert-True 'stop-loss should stop' ([bool]$stopLossJson.should_stop) ($stopLossJson | ConvertTo-Json -Depth 12)
Assert-True 'stop-loss effective oracle zero' ([int]$stopLossJson.current.oracle_adjusted_coverage -eq 0) ($stopLossJson | ConvertTo-Json -Depth 12)
Assert-True 'stop-loss effective verification zero' ([int]$stopLossJson.current.verification_capped_coverage -eq 0) ($stopLossJson | ConvertTo-Json -Depth 12)
Assert-True 'stop-loss carries runner reason' ((@($stopLossJson.reasons) -join ';') -match 'runner_non_authorizing_replay') ($stopLossJson | ConvertTo-Json -Depth 12)

$synthesisJsonText = & powershell -NoProfile -ExecutionPolicy Bypass -File $synthesisValidator -ReplayRoot $tempRoot -TargetCoverage 90
if ($LASTEXITCODE -ne 0) {
    throw "Validate-StopLossSynthesis.ps1 failed with exit code $LASTEXITCODE"
}
$synthesisJson = $synthesisJsonText | ConvertFrom-Json
Assert-True 'synthesis validation stops' ($synthesisJson.status -eq 'STOP_AND_EVOLVE') ($synthesisJson | ConvertTo-Json -Depth 12)
Assert-True 'synthesis validation oracle capped' ([int]$synthesisJson.oracle_adjusted_coverage -eq 0) ($synthesisJson | ConvertTo-Json -Depth 12)
Assert-True 'synthesis validation verification capped' ([int]$synthesisJson.verification_capped_coverage -eq 0) ($synthesisJson | ConvertTo-Json -Depth 12)

[ordered]@{
    status = 'PASS'
    assertions = 20
    temp_root = $tempRoot
} | ConvertTo-Json -Depth 6

if (-not $KeepTemp) {
    $tmpRootFull = Resolve-AbsolutePath $tempRoot
    $allowedRoot = Resolve-AbsolutePath (Join-Path $scriptRoot '.tmp')
    if ($tmpRootFull.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tmpRootFull -Recurse -Force
    }
}
