param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$Worktree = '',
    [string]$Reason = 'phase2_missing_final_report',
    [int]$Phase2ExitCode = 0,
    [string]$Phase2LogDir = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-FirstNumber {
    param([string]$Text, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return $null
}

function Get-MetricNumber {
    param([string]$Text, [string[]]$Names)
    $bt = [string][char]96
    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $patterns.Add("(?m)^\s*-?\s*${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?")
        $patterns.Add("(?m)^\s*\|\s*${bt}?${escaped}${bt}?\s*\|\s*${bt}?([0-9]+)${bt}?\s*%?\s*\|")
        $patterns.Add("(?m)${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?")
    }
    return Get-FirstNumber -Text $Text -Patterns $patterns.ToArray()
}

function Get-FirstText {
    param([string]$Text, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return ''
}

function Add-Line {
    param([System.Collections.Generic.List[string]]$Lines, [string]$Text = '')
    $Lines.Add($Text) | Out-Null
}

$root = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Replay root not found: $root"
}

$finalPath = Join-Path $root 'FINAL_REPLAY_REPORT.md'
if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        final_replay_report = $finalPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$roundPath = Join-Path $root 'ROUND_RESULT.md'
$roundText = Read-TextIfExists $roundPath
if ([string]::IsNullOrWhiteSpace($roundText)) {
    throw "ROUND_RESULT.md is required for deterministic final fallback: $roundPath"
}

$phase2Exec = if (-not [string]::IsNullOrWhiteSpace($Phase2LogDir)) { Read-JsonIfExists (Join-Path $Phase2LogDir 'phase2.exec.json') } else { $null }
$phase2Proof = if (-not [string]::IsNullOrWhiteSpace($Phase2LogDir)) { Read-JsonIfExists (Join-Path $Phase2LogDir 'phase2.proofspec.json') } else { $null }
$phase2Stdout = if (-not [string]::IsNullOrWhiteSpace($Phase2LogDir)) { Read-TextIfExists (Join-Path $Phase2LogDir 'phase2.stdout.log') } else { '' }
$phase2FailureCategory = if ($null -ne $phase2Exec) { [string]$phase2Exec.failure_category } else { '' }
$phase2ExecutorExit = if ($null -ne $phase2Exec -and $phase2Exec.PSObject.Properties.Name -contains 'executor_exit_code') { [string]$phase2Exec.executor_exit_code } else { [string]$Phase2ExitCode }

$blind = Get-MetricNumber $roundText @('blind_self_assessed_coverage', 'blind coverage')
if ($null -eq $blind) { $blind = 0 }
$capped = Get-MetricNumber $roundText @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage')
if ($null -eq $capped) { $capped = 0 }
$roundFinalStatus = Get-FirstText $roundText @(
    '(?m)^\s*-?\s*`?final_status`?\s*[:=]\s*`?([A-Z_]+)`?',
    '(?m)^\s*-?\s*`?final status`?\s*[:=]\s*`?([A-Z_]+)`?',
    '(?m)^\s*##\s*Final Status:\s*([A-Z_]+)\s*$'
)
if ([string]::IsNullOrWhiteSpace($roundFinalStatus)) { $roundFinalStatus = 'BLOCKED' }

$flagNames = @(
    'invalid_plan',
    'invalid_replay',
    'supporting_slice_first',
    'core_first_plan_invalid',
    'exact_contract_gap',
    'core_entry_unclosed',
    'side_effect_ledger_gap',
    'executable_surface_slice_gap',
    'wrong_test_surface',
    'shallow_module',
    'feedback_loop_blocker',
    'surface_budget_gap',
    'real_entry_gap',
    'needs_transaction_test',
    'mock_behavior_gap',
    'helper_only_surface_gap',
    'implementation_after_blocked_red',
    'behavior_test_charter_gap',
    'tooling_authorization_stop',
    'tooling_enforcement_stop',
    'phase2_executor_blocker'
)
$flagCounts = [ordered]@{}
foreach ($flag in $flagNames) {
    $count = ([regex]::Matches($roundText, [regex]::Escape($flag))).Count
    if ($flag -eq 'phase2_executor_blocker' -and ($Phase2ExitCode -ne 0 -or $null -ne $phase2Exec -or $Reason -match '(?i)phase2')) {
        $count = [Math]::Max($count, 1)
    }
    if ($count -gt 0) { $flagCounts[$flag] = $count }
}

$sliceSummaries = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-ChildItem -LiteralPath $root -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue | Sort-Object Name) {
    $verify = Read-JsonIfExists $file.FullName
    if ($null -eq $verify) { continue }
    $sliceSummaries.Add(("- {0}: verification={1}; status={2}; adjusted_delta={3}; cap={4}; next_authorized={5}; synthesis_authorized={6}; blockers={7}" -f $file.Name, $verify.verification_status, $verify.slice_status, $verify.adjusted_coverage_delta, $verify.coverage_cap, $verify.authorized_for_next_slice, $verify.authorized_for_synthesis, ((Get-StringArray $verify.authorization_blockers) -join ','))) | Out-Null
}

$changedFiles = @()
if (-not [string]::IsNullOrWhiteSpace($Worktree) -and (Test-Path -LiteralPath $Worktree -PathType Container)) {
    try {
        $changedFiles = @(& git -C $Worktree status --short --untracked-files=all)
    } catch {
        $changedFiles = @("git status failed: $($_.Exception.Message)")
    }
}

$stdoutLine = ''
if (-not [string]::IsNullOrWhiteSpace($phase2Stdout)) {
    $stdoutLine = (($phase2Stdout -split "\r?\n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($stdoutLine.Length -gt 240) { $stdoutLine = $stdoutLine.Substring(0, 240) }
}

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines '# Final Replay Report'
Add-Line $lines ''
Add-Line $lines '- schema: final_replay_report_fallback.v1'
Add-Line $lines "- generated_at: $(Get-Date -Format s)"
Add-Line $lines "- replay_root: $root"
Add-Line $lines "- worktree: $Worktree"
Add-Line $lines "- final_status: BLOCKED"
Add-Line $lines "- final_replay_status: BLOCKED"
Add-Line $lines "- phase2_status: EXECUTOR_FAILED"
Add-Line $lines "- phase2_fallback_used: true"
Add-Line $lines "- phase2_failure_category: $phase2FailureCategory"
Add-Line $lines "- phase2_exit_code: $Phase2ExitCode"
Add-Line $lines "- phase2_executor_exit_code: $phase2ExecutorExit"
Add-Line $lines "- phase2_failure_reason: $Reason"
Add-Line $lines '- oracle_used: false'
Add-Line $lines "- blind_self_assessed_coverage: $blind"
Add-Line $lines "- verification_capped_coverage: $capped"
Add-Line $lines '- oracle_adjusted_coverage: 0'
Add-Line $lines '- reported_oracle_adjusted_coverage:'
Add-Line $lines '- oracle_coverage_enforced: true'
Add-Line $lines '- oracle_coverage_enforcement_rule: phase2_executor_failure_blocks_oracle_credit'
Add-Line $lines '- requires_evolution: true'
Add-Line $lines '- evolution_type: phase2_executor_fallback_and_verifiable_rule_evolution'
Add-Line $lines '- production_match: 0'
Add-Line $lines "- round_final_status: $roundFinalStatus"
Add-Line $lines ''
Add-Line $lines '## Phase2 Executor Evidence'
Add-Line $lines "- phase2_log_dir: $Phase2LogDir"
Add-Line $lines "- phase2_exec_exists: $($null -ne $phase2Exec)"
Add-Line $lines "- phase2_proofspec_exists: $($null -ne $phase2Proof)"
Add-Line $lines "- phase2_stdout_head: $stdoutLine"
Add-Line $lines ''
Add-Line $lines '## Slice Verification Summary'
if ($sliceSummaries.Count -eq 0) {
    Add-Line $lines '- none'
} else {
    foreach ($summary in $sliceSummaries) { Add-Line $lines $summary }
}
Add-Line $lines ''
Add-Line $lines '## Changed Files'
if ($changedFiles.Count -eq 0) {
    Add-Line $lines '- none'
} else {
    foreach ($file in $changedFiles) { Add-Line $lines "- $file" }
}
Add-Line $lines ''
Add-Line $lines '## Gap Flags'
if ($flagCounts.Count -eq 0) {
    Add-Line $lines '- phase2_executor_blocker: 1'
} else {
    foreach ($key in $flagCounts.Keys) { Add-Line $lines "- ${key}: $($flagCounts[$key])" }
}
Add-Line $lines ''
Add-Line $lines '## Oracle Calibration Rubric'
Add-Line $lines '- exact_file_family_overlap: not_run_phase2_executor_failed'
Add-Line $lines '- conceptual_role_overlap: not_run_phase2_executor_failed'
Add-Line $lines '- missing_deploy_facing_family_penalty: retained_from_round_result'
Add-Line $lines '- exact_contract_penalty: retained_from_round_result'
Add-Line $lines ''
Add-Line $lines '## Final Decision'
Add-Line $lines '- decision: STOP_AND_EVOLVE'
Add-Line $lines '- stop_reason: phase2_executor_failed_without_final_report'
Add-Line $lines '- next_required_action: deterministic final fallback allowed evolution proposal generation; run validated tooling evolution before the next replay cycle.'

Set-Content -LiteralPath $finalPath -Value ($lines -join "`n") -Encoding UTF8
[ordered]@{
    status = 'WROTE_FINAL_REPLAY_REPORT'
    final_replay_report = $finalPath
    final_status = 'BLOCKED'
    phase2_fallback_used = $true
    verification_capped_coverage = $capped
    oracle_adjusted_coverage = 0
    requires_evolution = $true
} | ConvertTo-Json -Depth 8
