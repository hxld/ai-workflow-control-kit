$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$searchScript = Join-Path $scriptRoot 'Start-ExternalPracticeSearch.ps1'
if (-not (Test-Path -LiteralPath $searchScript)) {
    throw "Missing external practice search script: $searchScript"
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("external-practice-test-{0}" -f ([guid]::NewGuid().ToString('N')))
$evidenceRoot = Join-Path $tempRoot 'evidence'
$replayRoot = Join-Path $evidenceRoot 'feature-a\claim-codex-replay-v001-r01'
$outputRoot = Join-Path $evidenceRoot '_external-practice'
$configPath = Join-Path $tempRoot 'config.yaml'

try {
    New-Item -ItemType Directory -Force -Path $replayRoot | Out-Null
    @"
project_root: /path/to/project
replay_root_base: $($replayRoot -replace '\\claim-codex-replay-v001-r01$', '\claim-codex-replay-v001')
executor: claude
external_practice_seed_urls: https://example.com/a,https://example.com/b
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $replayRoot 'DEEP_REVIEW_REPORT.md') -Value '# Deep Review' -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $searchScript -ConfigPath $configPath -EvidenceRoot $evidenceRoot -ReplayRoot $replayRoot -OutputRoot $outputRoot -Reason 'test_stagnation' -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Start-ExternalPracticeSearch exited with $LASTEXITCODE"
    }

    $promptPath = Join-Path $outputRoot 'EXTERNAL_PRACTICE_RESEARCH_PROMPT.md'
    $decisionPath = Join-Path $outputRoot 'EXTERNAL_PRACTICE_DECISION.json'
    Assert-True (Test-Path -LiteralPath $promptPath) 'prompt was not generated'
    Assert-True (Test-Path -LiteralPath $decisionPath) 'decision was not generated'
    Assert-True (Test-Path -LiteralPath (Join-Path $replayRoot 'EXTERNAL_PRACTICE_RESEARCH_PROMPT.md')) 'prompt was not copied to replay root'

    $prompt = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
    Assert-True ($prompt -match 'External Practice Search Trigger') 'prompt missing title'
    Assert-True ($prompt -match 'https://example.com/a') 'prompt missing seed URL'
    Assert-True ($prompt -match 'golden slice') 'prompt missing positive sample language'

    $decision = Get-Content -LiteralPath $decisionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($decision.final_status -eq 'QUEUED_AGENT_NOT_RUN') "unexpected decision: $($decision.final_status)"
    Assert-True ($decision.safe_for_auto_apply -eq $false) 'queued decision must not auto apply'

    $fallbackOutput = Join-Path $evidenceRoot '_external-practice-fallback'
    @"
project_root: /path/to/project
replay_root_base: $($replayRoot -replace '\\claim-codex-replay-v001-r01$', '\claim-codex-replay-v001')
executor: claude
external_practice_primary_executor: claude
external_practice_fallback_executor: codex
external_practice_allow_fallback: true
external_practice_seed_urls: https://example.com/a
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8
    $env:REPLAY_AUTOPILOT_SIMULATE_EXTERNAL_AGENT_FAILURE = '1'
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $searchScript -ConfigPath $configPath -EvidenceRoot $evidenceRoot -ReplayRoot $replayRoot -OutputRoot $fallbackOutput -Reason 'test_fallback' -RunAgent -Quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Start-ExternalPracticeSearch fallback test exited with $LASTEXITCODE"
        }
    } finally {
        Remove-Item Env:\REPLAY_AUTOPILOT_SIMULATE_EXTERNAL_AGENT_FAILURE -ErrorAction SilentlyContinue
    }
    $fallbackDecision = Get-Content -LiteralPath (Join-Path $fallbackOutput 'EXTERNAL_PRACTICE_DECISION.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($fallbackDecision.final_status -eq 'BLOCKED_ALL_EXECUTORS_FAILED') "unexpected fallback final_status: $($fallbackDecision.final_status)"
    Assert-True (@($fallbackDecision.attempts).Count -eq 2) "expected 2 fallback attempts, got $(@($fallbackDecision.attempts).Count)"
    Assert-True (@($fallbackDecision.attempts | Where-Object { $_.executor -eq 'claude' }).Count -eq 1) 'missing primary claude attempt'
    Assert-True (@($fallbackDecision.attempts | Where-Object { $_.executor -eq 'codex' }).Count -eq 1) 'missing fallback codex attempt'
    Assert-True ($fallbackDecision.next_replay_executor -eq 'claude') 'next replay executor should remain claude'

    Write-Host 'Test-ExternalPracticeSearch: PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
