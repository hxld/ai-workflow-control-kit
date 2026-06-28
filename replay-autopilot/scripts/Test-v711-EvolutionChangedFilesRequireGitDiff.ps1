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
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('v711-evolution-git-diff-' + [guid]::NewGuid().ToString('N'))

try {
    $unchangedRoot = New-StopRoot 'unchanged-existing-file'
    Write-Utf8 (Join-Path $unchangedRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: regression_test
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/README.md
- closed_machine_gates: stop_and_evolve_result_contract
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v711
'@
    $unchanged = Invoke-Validator -ReplayRoot $unchangedRoot
    Assert-True ($unchanged.ExitCode -ne 0) 'validator fails when changed_files lists only an existing unchanged file'
    Assert-True (@($unchanged.Verify.issues) -contains 'tooling_changed_files_no_git_diff_entry') 'unchanged fixture reports no git diff entry'
    Assert-True (@($unchanged.Verify.issues) -contains 'tooling_changed_file_not_in_git_diff:replay-autopilot/README.md') 'unchanged file path is reported exactly'

    $changedRoot = New-StopRoot 'changed-file'
    Write-Utf8 (Join-Path $changedRoot 'EVOLUTION_RESULT.md') @'
# Evolution Result

- final_status: VALIDATED_TOOLING_EVOLUTION
- tooling_changes_applied: true
- stop_and_evolve_satisfied: true
- gate_budget_decision: regression_test
- new_gate_artifacts: none
- verification_results: PASS
- changed_files: replay-autopilot/scripts/Validate-EvolutionResult.ps1; replay-autopilot/scripts/Test-v711-EvolutionChangedFilesRequireGitDiff.ps1
- closed_machine_gates: stop_and_evolve_result_contract
- pushed_commit: 0123456789abcdef
- actual_knowledge_version_after_push: v711
'@
    $changed = Invoke-Validator -ReplayRoot $changedRoot
    Assert-True ($changed.ExitCode -eq 0) "validator passes when changed_files names real files in the current git diff. Output: $($changed.Output)"
    Assert-True ([string]$changed.Verify.status -eq 'PASS') 'changed fixture writes PASS verification status'

    Write-Host ''
    Write-Host 'v711 Evolution Changed Files Git Diff Guard: ALL PASSED'
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
