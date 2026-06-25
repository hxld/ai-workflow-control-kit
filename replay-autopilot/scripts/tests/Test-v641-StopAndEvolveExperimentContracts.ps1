#!/usr/bin/env pwsh
<#
.SYNOPSIS
Regression coverage for v641 STOP_AND_EVOLVE experiment contracts.
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

$testRoot = Split-Path -Parent $PSCommandPath
$scriptsRoot = Split-Path -Parent $testRoot
$autopilotRoot = Split-Path -Parent $scriptsRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v641-stop-and-evolve-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $assertionCount = 0

    Write-Host '[Scenario 1] Pre-RED carrier signature authorization emits required fields...'
    $worktree = Join-Path $tempRoot 'worktree'
    $sourceDir = Join-Path $worktree 'src\main\java\demo'
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
    Write-Utf8 (Join-Path $sourceDir 'RealEntry.java') @'
package demo;

public class RealEntry {
    public String handle(String value) {
        return value;
    }
}
'@
    $carrierInput = @{
        worktree_path = $worktree
        selected_real_entry = 'demo.RealEntry.handle(String): String'
        selected_carrier = 'demo.RealEntry.handle(String): String'
        test_invocation_path = 'real_entry_public_call'
        proof_observation_point = 'returned_payload'
    } | ConvertTo-Json -Compress
    $carrierOutput = $carrierInput | python (Join-Path $scriptsRoot 'verify_carrier_signature.py')
    Assert-True ($LASTEXITCODE -eq 0) "carrier authorization must pass. Output: $carrierOutput"
    $carrierJson = $carrierOutput | ConvertFrom-Json
    Assert-True ([bool]$carrierJson.authorized) 'carrier authorization must expose authorized=true'
    Assert-True ($carrierJson.PSObject.Properties.Name -contains 'blockers') 'carrier authorization must expose blockers'
    Assert-True ($carrierJson.PSObject.Properties.Name -contains 'resolved_signature') 'carrier authorization must expose resolved_signature'
    Assert-True ($carrierJson.PSObject.Properties.Name -contains 'reachable_from_entry') 'carrier authorization must expose reachable_from_entry'
    $assertionCount += 5

    Write-Host '[Scenario 2] Blocked carrier values fail before RED...'
    $blockedInput = @{
        worktree_path = $worktree
        selected_real_entry = 'unknown'
        selected_carrier = 'helper_only'
        test_invocation_path = 'mock_only'
        proof_observation_point = 'unknown'
    } | ConvertTo-Json -Compress
    $blockedOutput = $blockedInput | python (Join-Path $scriptsRoot 'verify_carrier_signature.py') 2>&1
    Assert-True ($LASTEXITCODE -ne 0) 'blocked placeholders must fail carrier authorization'
    $blockedJson = $blockedOutput | ConvertFrom-Json
    Assert-False ([bool]$blockedJson.authorized) 'blocked placeholders must expose authorized=false'
    Assert-True (@($blockedJson.blockers).Count -gt 0) 'blocked placeholders must list blockers'
    $assertionCount += 3

    Write-Host '[Scenario 3] Coverage recomputation rejects positive coverage without synthesis authorization...'
    $coverageRoot = Join-Path $tempRoot 'coverage'
    New-Item -ItemType Directory -Force -Path $coverageRoot | Out-Null
    @{ slice_index = 1; authorized_for_synthesis = $false; adjusted_coverage_delta = 25; closed_requirement_families = @() } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $coverageRoot 'SLICE_VERIFY_01.json') -Encoding UTF8
    Write-Utf8 (Join-Path $coverageRoot 'ROUND_RESULT.md') @'
# ROUND_RESULT

- blind_self_assessed_coverage: 25
- verification_capped_coverage: 25
'@
    $coverageOutput = & python (Join-Path $scriptsRoot 'recompute_round_coverage.py') --root $coverageRoot --require-closed-family --fail-on-positive-without-synthesis 2>&1
    Assert-True ($LASTEXITCODE -ne 0) "non-authorizing positive coverage must fail. Output: $coverageOutput"
    $coverageJson = $coverageOutput | ConvertFrom-Json
    Assert-True (@($coverageJson.issues) -contains 'positive_coverage_without_synthesis_authorization') 'coverage recomputation must flag positive coverage without synthesis'
    $assertionCount += 2

    Write-Host '[Scenario 4] Replay context index freshness validation blocks stale indexes...'
    $contextRoot = Join-Path $tempRoot 'context'
    New-Item -ItemType Directory -Force -Path $contextRoot | Out-Null
    @{ initial_after_start_replay_round = 'abc1234' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $contextRoot 'WORKTREE_HEAD_AUDIT.json') -Encoding UTF8
    @{
        freshness_metadata = @{ initial_after_start_replay_round = 'def5678' }
        real_entry_candidates = @(@{ signature = 'demo.RealEntry.handle(String)' })
        allowed_test_harness_modules = @('demo-harness')
        forbidden_test_annotations = @('@SpringBootTest')
        required_family_proof_contracts = @{ core_entry = @{ proof = 'real_entry_behavior' } }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $contextRoot 'replay-context-index.json') -Encoding UTF8
    $contextOutput = & python (Join-Path $scriptsRoot 'validate_replay_context_index.py') --root $contextRoot --context replay-context-index.json --require-family core_entry --require-fresh-head 2>&1
    Assert-True ($LASTEXITCODE -ne 0) "stale context must fail. Output: $contextOutput"
    $contextJson = $contextOutput | ConvertFrom-Json
    Assert-True (@($contextJson.issues) -contains 'context_index_stale_or_incomplete') 'context validation must flag stale head'
    $assertionCount += 2

    Write-Host '[Scenario 5] Runner and prompt surfaces reference the enforced experiment contracts...'
    $runnerText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-ReplayLoop.ps1') -Raw -Encoding UTF8
    $roundSynthesisText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\phase1-round-synthesis.prompt.md') -Raw -Encoding UTF8
    $deepReviewText = Get-Content -LiteralPath (Join-Path $autopilotRoot 'prompts\deep-replay-review.prompt.md') -Raw -Encoding UTF8
    Assert-True ($runnerText -match 'verify_carrier_signature\.py') 'Run-ReplayLoop must invoke carrier signature authorization'
    Assert-True ($runnerText -match 'PRE_S1_CARRIER_SIGNATURE_AUTHORIZATION\.json') 'Run-ReplayLoop must write pre-S1 signature authorization artifact'
    Assert-True ($runnerText -match 'validate_replay_context_index\.py') 'Run-ReplayLoop must invoke replay context index validation'
    $sliceRunnerText = Get-Content -LiteralPath (Join-Path $scriptsRoot 'Run-SliceLoop.ps1') -Raw -Encoding UTF8
    Assert-True ($sliceRunnerText -match 'recompute_round_coverage\.py') 'Run-SliceLoop must invoke round coverage recomputation'
    Assert-True ($roundSynthesisText -match 'authorized_for_synthesis=false') 'round synthesis prompt must enforce non-authorizing slices'
    Assert-True ($deepReviewText -match 'replay-context-index') 'deep review prompt must route toward reusable context index'
    $assertionCount += 6

    Write-Host ''
    Write-Host "=== v641 STOP_AND_EVOLVE EXPERIMENT CONTRACTS: ALL $assertionCount ASSERTIONS PASS ===" -ForegroundColor Green
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
