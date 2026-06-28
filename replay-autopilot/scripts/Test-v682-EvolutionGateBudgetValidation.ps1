#!/usr/bin/env pwsh
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if (-not $Condition) {
        if ([string]::IsNullOrWhiteSpace($Detail)) { throw "FAIL: $Name" }
        throw "FAIL: $Name :: $Detail"
    }
    Write-Host "PASS: $Name"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-StopRoot {
    param([string]$Name)
    $root = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Write-Utf8 (Join-Path $root 'STOP_OR_CONTINUE_DECISION.md') @'
# Stop Decision

- decision: STOP_AND_EVOLVE
- reason: repeated no-progress slice
'@
    return $root
}

function Invoke-Validator {
    param([string]$ReplayRoot)
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ReplayRoot $ReplayRoot 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
        Verify = Get-Content -LiteralPath (Join-Path $ReplayRoot 'EVOLUTION_RESULT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$validator = Join-Path $scriptRoot 'Validate-EvolutionResult.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v682-evolution-gate-budget-' + [guid]::NewGuid().ToString('N'))

try {
    $missingRoot = New-StopRoot 'missing-budget'
    Write-Utf8 (Join-Path $missingRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1
- pushed_commit: abcdef1234567890
- actual_knowledge_version_after_push: v682
'@
    $missing = Invoke-Validator -ReplayRoot $missingRoot
    Assert-True 'missing_gate_budget_decision_fails' ($missing.ExitCode -ne 0)
    Assert-True 'missing_gate_budget_issue_reported' (@($missing.Verify.issues) -contains 'gate_budget_decision_missing') (@($missing.Verify.issues) -join ',')
    Assert-True 'missing_new_gate_artifacts_issue_reported' (@($missing.Verify.issues) -contains 'new_gate_artifacts_missing') (@($missing.Verify.issues) -join ',')

    $badNewGateRoot = New-StopRoot 'bad-new-gate'
    Write-Utf8 (Join-Path $badNewGateRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: replay-autopilot/scripts/Test-v682-EvolutionGateBudgetValidation.ps1
- verification_results: PASS
- changed_files: replay-autopilot/scripts/verify-new-proof-policy.ps1; replay-autopilot/scripts/Validate-EvolutionResult.ps1
- pushed_commit: abcdef1234567890
- actual_knowledge_version_after_push: v682
'@
    $badNewGate = Invoke-Validator -ReplayRoot $badNewGateRoot
    Assert-True 'new_gate_without_exception_fails' ($badNewGate.ExitCode -ne 0)
    Assert-True 'new_gate_requires_exception_issue_reported' (@($badNewGate.Verify.issues) -contains 'new_gate_artifacts_require_new_gate_exception_decision') (@($badNewGate.Verify.issues) -join ',')

    $exceptionRoot = New-StopRoot 'new-gate-exception'
    Write-Utf8 (Join-Path $exceptionRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: new_gate_exception
- new_gate_artifacts: replay-autopilot/scripts/verify-new-proof-policy.ps1
- new_gate_exception_rationale: existing_gate coverage gap proven; regression Test-v682 covers the new failure class; runner integration uses Run-SliceLoop verifier invocation.
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Run-SliceLoop.ps1; replay-autopilot/scripts/Test-v682-EvolutionGateBudgetValidation.ps1
- pushed_commit: abcdef1234567890
- actual_knowledge_version_after_push: v682
'@
    $exception = Invoke-Validator -ReplayRoot $exceptionRoot
    Assert-True 'new_gate_exception_with_evidence_passes' ($exception.ExitCode -eq 0) $exception.Output
    Assert-True 'new_gate_exception_verify_pass' ([string]$exception.Verify.status -eq 'PASS') (@($exception.Verify.issues) -join ',')

    $prompt = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $scriptRoot) 'prompts\skill-evolution.prompt.md') -Raw -Encoding UTF8
    Assert-True 'prompt_requires_gate_budget_decision' ($prompt.Contains('gate_budget_decision'))
    Assert-True 'prompt_requires_new_gate_artifacts' ($prompt.Contains('new_gate_artifacts'))

    Write-Host ''
    Write-Host 'v682 Evolution Gate Budget Validation: ALL PASSED'
    exit 0
} catch {
    Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}
