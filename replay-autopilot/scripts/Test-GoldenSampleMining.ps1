$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$miner = Join-Path $scriptRoot 'Start-GoldenSampleMining.ps1'
if (-not (Test-Path -LiteralPath $miner)) {
    throw "Missing miner script: $miner"
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function New-TestFile {
    param(
        [string]$Path,
        [string]$Content
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("golden-sample-mining-test-{0}" -f ([guid]::NewGuid().ToString('N')))
$evidence = Join-Path $tempRoot 'evidence'
$output = Join-Path $tempRoot 'out'

try {
    New-TestFile -Path (Join-Path $evidence 'feature-good\claim-codex-replay-v999-cross-r01\ROUND_RESULT.md') -Content @"
# Round Result

blind_self_assessed_coverage: 88%
verification_capped_coverage: 82%
final_status: CLOSED
"@
    New-TestFile -Path (Join-Path $evidence 'feature-good\claim-codex-replay-v999-cross-r01\FINAL_REPLAY_REPORT.md') -Content @"
# Final Replay Report

oracle_adjusted_coverage: 86%
AUTOPILOT_DECISION: CONTINUE_IMPROVED
"@
    New-TestFile -Path (Join-Path $evidence 'feature-bad\claim-codex-replay-v998-cross-r01\ROUND_RESULT.md') -Content @"
# Round Result

blind_self_assessed_coverage: 96%
verification_capped_coverage: 0%
final_status: PARTIAL

Gaps: wrong_test_surface, core_entry_unclosed, side_effect_ledger_gap, mock_only, helper_only.
"@
    New-TestFile -Path (Join-Path $evidence 'feature-bad\claim-codex-replay-v998-cross-r01\FINAL_REPLAY_REPORT.md') -Content @"
# Final Replay Report

oracle_adjusted_coverage: 8%
AUTOPILOT_DECISION: STOP_DEEP_REVIEW_REQUIRED
"@
    New-TestFile -Path (Join-Path $evidence 'feature-ignore\claim-codex-replay-v000-r01\logs\ROUND_RESULT.md') -Content "blind_self_assessed_coverage: 100%"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $miner -EvidenceRoot $evidence -OutputRoot $output -MaxRoots 20 -Quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Start-GoldenSampleMining exited with $LASTEXITCODE"
    }

    $ledgerPath = Join-Path $output 'GOLDEN_SAMPLE_LEDGER.json'
    $sopPath = Join-Path $output 'GOLDEN_SAMPLE_SOP.md'
    $promptPath = Join-Path $output 'GOLDEN_SAMPLE_PROMPT.md'
    $summaryPath = Join-Path $output 'GOLDEN_SAMPLE_SUMMARY.md'
    Assert-True (Test-Path -LiteralPath $ledgerPath) 'ledger was not generated'
    Assert-True (Test-Path -LiteralPath $sopPath) 'SOP was not generated'
    Assert-True (Test-Path -LiteralPath $promptPath) 'prompt was not generated'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'summary was not generated'

    $ledger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($ledger.scanned_replay_roots -eq 2) "expected 2 scanned roots, got $($ledger.scanned_replay_roots)"
    Assert-True (@($ledger.candidates | Where-Object { $_.feature -eq 'feature-good' }).Count -eq 1) 'good feature was not selected as candidate'
    Assert-True (@($ledger.anti_patterns | Where-Object { $_.feature -eq 'feature-bad' }).Count -eq 1) 'bad feature was not selected as anti-pattern'
    Assert-True ((Get-Content -LiteralPath $sopPath -Raw -Encoding UTF8) -match 'forbidden_first_slice') 'SOP missing forbidden_first_slice rule'
    Assert-True ((Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8) -match 'Coverage Honesty') 'prompt missing coverage honesty section'

    Write-Host 'Test-GoldenSampleMining: PASS'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
