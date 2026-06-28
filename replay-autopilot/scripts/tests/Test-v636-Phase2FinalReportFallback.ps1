#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression test for deterministic Phase2 final-report fallback.

.DESCRIPTION
Validates that a Phase2 executor failure does not strand unattended replay
without FINAL_REPLAY_REPORT.md. When ROUND_RESULT.md and Phase2 exec evidence
exist, the fallback must generate a parseable final report that preserves
verification caps, records phase2_executor_blocker, and requires evolution.
#>

param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { throw "FAIL: $Message" }
    Write-Host "  PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Write-JsonFile {
    param([string]$Path, $Value, [int]$Depth = 10)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('replay-v636-phase2-final-fallback-' + [guid]::NewGuid().ToString('N'))

try {
    $replayRoot = Join-Path $tempRoot 'replay'
    $worktree = Join-Path $replayRoot 'worktree'
    $phase2Logs = Join-Path $replayRoot 'logs\phase2'
    New-Item -ItemType Directory -Force -Path $worktree, $phase2Logs | Out-Null

    git -C $worktree init 2>&1 | Out-Null
    Write-Utf8 (Join-Path $worktree 'README.md') '# fixture'
    git -C $worktree add -A 2>&1 | Out-Null
    git -C $worktree commit -m 'fixture' --allow-empty 2>&1 | Out-Null
    Write-Utf8 (Join-Path $worktree 'src.txt') 'changed'

    Write-Utf8 (Join-Path $replayRoot 'ROUND_RESULT.md') @'
# Round Result Report

- final_status: BLOCKED
- blind_self_assessed_coverage: 12
- verification_capped_coverage: 0
- oracle_used: false

## Gap Flags
- wrong_test_surface
- core_entry_unclosed
- side_effect_ledger_gap
- executable_surface_slice_gap
- exact_contract_gap
## Final Status: BLOCKED
'@

    Write-JsonFile (Join-Path $replayRoot 'SLICE_VERIFY_01.json') ([ordered]@{
        slice_index = 1
        verification_status = 'FAIL'
        slice_status = 'GREEN_PASS'
        adjusted_coverage_delta = 0
        coverage_cap = 10
        authorized_for_next_slice = $false
        authorized_for_synthesis = $false
        authorization_blockers = @('tooling_enforcement_stop', 'side_effect_ledger_gap')
        gap_flags = @('wrong_test_surface', 'exact_contract_gap')
    })

    Write-JsonFile (Join-Path $phase2Logs 'phase2.exec.json') ([ordered]@{
        stage = 'phase2'
        exit_code = 1
        executor_exit_code = 1
        failure_category = 'executor'
        completion_path = (Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md')
    })
    Write-JsonFile (Join-Path $phase2Logs 'phase2.proofspec.json') ([ordered]@{
        stage = 'phase2'
        status = 'FAIL'
        completion_ready = $false
    })
    Write-Utf8 (Join-Path $phase2Logs 'phase2.stdout.log') 'API Error: 503 No available channel for requested model'

    $assertionCount = 0

    Write-Host '[Scenario 1] Fallback script validates and writes final report...'
    $validate = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\Write-FinalReplayReportFallback.ps1') -ReplayRoot $replayRoot -ValidateOnly 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "ValidateOnly must pass. Output: $validate"
    Assert-True ($validate -match '"status"\s*:\s*"VALID"') 'ValidateOnly must emit VALID status'
    $assertionCount += 2

    $fallbackOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\Write-FinalReplayReportFallback.ps1') `
        -ReplayRoot $replayRoot `
        -Worktree $worktree `
        -Reason 'executor_failed_without_result:exit_code=1' `
        -Phase2ExitCode 1 `
        -Phase2LogDir $phase2Logs 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "Fallback must exit 0. Output: $fallbackOutput"
    $finalPath = Join-Path $replayRoot 'FINAL_REPLAY_REPORT.md'
    Assert-True (Test-Path -LiteralPath $finalPath) 'FINAL_REPLAY_REPORT.md must be created'
    $finalText = Get-Content -LiteralPath $finalPath -Raw -Encoding UTF8
    Assert-True ($finalText -match 'phase2_fallback_used:\s*true') 'final report must disclose phase2 fallback'
    Assert-True ($finalText -match 'phase2_status:\s*EXECUTOR_FAILED') 'final report must classify phase2 executor failure'
    Assert-True ($finalText -match 'final_status:\s*BLOCKED') 'final report must remain BLOCKED'
    Assert-True ($finalText -match 'oracle_adjusted_coverage:\s*0') 'final report must block oracle credit'
    Assert-True ($finalText -match 'requires_evolution:\s*true') 'final report must require evolution'
    Assert-True ($finalText -match 'phase2_executor_blocker:\s*1') 'final report must expose phase2_executor_blocker flag'
    $assertionCount += 8

    Write-Host '[Scenario 2] Parse and proposal consume fallback final report...'
    $parseOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\Parse-ReplayReport.ps1') -ReplayRoot $replayRoot 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "Parse-ReplayReport must consume fallback report. Output: $parseOutput"
    $summaryPath = Join-Path $replayRoot 'AUTOPILOT_SUMMARY.md'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'Parse-ReplayReport must write AUTOPILOT_SUMMARY.md'
    $summaryText = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8
    Assert-True ($summaryText -match 'oracle_adjusted_coverage:\s*0') 'summary must preserve enforced oracle coverage 0'
    Assert-True ($summaryText -match 'requires_evolution:\s*True') 'summary must require evolution'
    $proposalOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot '..\New-EvolutionProposal.ps1') -ReplayRoot $replayRoot 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 0) "New-EvolutionProposal must consume fallback report. Output: $proposalOutput"
    Assert-True (Test-Path -LiteralPath (Join-Path $replayRoot 'EVOLUTION_PROPOSAL.md')) 'New-EvolutionProposal must write EVOLUTION_PROPOSAL.md'
    $assertionCount += 6

    Write-Host '[Scenario 3] Run-ReplayLoop invokes fallback before blocking...'
    $runnerText = Get-Content -LiteralPath (Join-Path $scriptRoot '..\Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($runnerText.Contains('Write-FinalReplayReportFallback.ps1')) 'Run-ReplayLoop must invoke final-report fallback'
    Assert-True ($runnerText.Contains('Recovered deterministic FINAL_REPLAY_REPORT.md after Phase 2 executor failure')) 'Run-ReplayLoop must continue after executor-failure fallback success'
    Assert-True ($runnerText.Contains('Recovered deterministic FINAL_REPLAY_REPORT.md after missing Phase 2 completion artifact')) 'Run-ReplayLoop must recover missing completion artifact'
    $assertionCount += 3

    Write-Host ''
    Write-Host "=== v636 PHASE2 FINAL REPORT FALLBACK: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "TEST FAILED: $_" -ForegroundColor Red
    Write-Host "Call stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
