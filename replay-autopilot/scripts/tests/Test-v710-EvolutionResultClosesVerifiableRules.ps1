param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    Write-Host "PASS: $Message"
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function New-RuleClosureRoot {
    param(
        [string]$Name,
        [string]$ClosedMachineGatesLine
    )

    $root = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Write-Utf8 (Join-Path $root 'STOP_OR_CONTINUE_DECISION.md') @'
# Stop Decision

- decision: STOP_AND_EVOLVE
- reason: required verifiable rule closure
'@
    Write-Utf8 (Join-Path $root 'VERIFIABLE_RULES.json') @'
{
  "rules": [
    {
      "id": "rule-1",
      "must_fix": true,
      "machine_gate": "blocked_plan_status_stops_replay",
      "verification_status": "PENDING"
    }
  ]
}
'@
    Write-Utf8 (Join-Path $root 'EVOLUTION_RESULT.md') @"
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1; replay-autopilot/scripts/tests/Test-v710-EvolutionResultClosesVerifiableRules.ps1
$ClosedMachineGatesLine
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v710
"@
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

$scriptRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $scriptRoot 'Validate-EvolutionResult.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v710-evolution-rule-closure-' + [guid]::NewGuid().ToString('N'))

try {
    $missingRoot = New-RuleClosureRoot -Name 'missing-closed-gate' -ClosedMachineGatesLine '- closed_machine_gates: unrelated_gate'
    $missing = Invoke-Validator -ReplayRoot $missingRoot
    Assert-True ($missing.ExitCode -ne 0) 'validator fails when must-fix machine gate is not reported closed'
    Assert-True (@($missing.Verify.issues) -contains 'closed_machine_gate_missing:blocked_plan_status_stops_replay') 'missing required machine gate is reported exactly'

    $validRoot = New-RuleClosureRoot -Name 'valid-closed-gate' -ClosedMachineGatesLine '- closed_machine_gates: blocked_plan_status_stops_replay'
    $valid = Invoke-Validator -ReplayRoot $validRoot
    Assert-True ($valid.ExitCode -eq 0) "validator passes when must-fix machine gate is reported closed. Output: $($valid.Output)"
    Assert-True ([string]$valid.Verify.status -eq 'PASS') 'valid fixture writes PASS verification status'

    Write-Host ''
    Write-Host 'v710 Evolution Result Verifiable Rule Closure: ALL PASSED'
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
