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

function New-StopRoot {
    param([string]$Name)

    $root = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Write-Utf8 (Join-Path $root 'STOP_OR_CONTINUE_DECISION.md') @'
# Stop Decision

- decision: STOP_AND_EVOLVE
- reason: repeated machine gate drift
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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v709-evolution-changed-files-exist-' + [guid]::NewGuid().ToString('N'))

try {
    $missingRoot = New-StopRoot 'missing-file'
    Write-Utf8 (Join-Path $missingRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Does-Not-Exist.ps1
- closed_machine_gates: stop_and_evolve_result_contract
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v709
'@
    $missing = Invoke-Validator -ReplayRoot $missingRoot
    Assert-True ($missing.ExitCode -ne 0) 'validator fails when changed_files names no real tooling file'
    Assert-True (@($missing.Verify.issues) -contains 'tooling_changed_files_no_existing_replay_autopilot_file') 'missing changed file reports no existing replay-autopilot file'
    Assert-True (@($missing.Verify.issues) -contains 'tooling_changed_file_missing:replay-autopilot/scripts/Does-Not-Exist.ps1') 'missing changed file path is reported exactly'

    $validRoot = New-StopRoot 'valid-file'
    Write-Utf8 (Join-Path $validRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: existing_gate_enforcement
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1; replay-autopilot/scripts/Test-v709-EvolutionChangedFilesExist.ps1
- closed_machine_gates: stop_and_evolve_result_contract
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v709
'@
    $valid = Invoke-Validator -ReplayRoot $validRoot
    Assert-True ($valid.ExitCode -eq 0) "validator passes when changed_files names real tooling files. Output: $($valid.Output)"
    Assert-True ([string]$valid.Verify.status -eq 'PASS') 'valid fixture writes PASS verification status'

    Write-Host ''
    Write-Host 'v709 Evolution Changed Files Existence: ALL PASSED'
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
