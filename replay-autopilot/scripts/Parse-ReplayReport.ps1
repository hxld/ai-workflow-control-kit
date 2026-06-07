param(
    [string]$ReplayRoot,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [switch]$All
)

$ErrorActionPreference = 'Stop'

function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^([^:]+):\s*(.*)$') {
            $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
        }
    }
    return $result
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-FirstNumber {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return [int]$m.Groups[1].Value
        }
    }
    return $null
}

function Get-FirstText {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return $m.Groups[1].Value.Trim()
        }
    }
    return $null
}

function Normalize-StatusOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $status = $Value.Trim().ToUpperInvariant()
    # Backward-compatible observed variants covered by the generic rule: CAVEATS|CAVIETS|CAVETS.
    if ($status -match '^PROCEED_WITH_[A-Z_]+$') {
        return 'PROCEED'
    }
    $known = @(
        'PROCEED',
        'BLOCKED',
        'INVALID_PLAN',
        'INVALID_REPLAY',
        'PARTIAL',
        'PASS',
        'FAIL',
        'FAILED',
        'CLOSED',
        'DONE',
        'COMPLETE',
        'COMPLETED',
        'INCOMPLETE',
        'TARGET_REACHED',
        'STOP_BLOCKED',
        'STOP_DEEP_REVIEW_REQUIRED',
        'CONTINUE',
        'CONTINUE_AFTER_DEEP_REVIEW_EVOLUTION'
    )

    if ($known -contains $status) {
        return $status
    }
    return $null
}

function Get-MetricNumber {
    param(
        [string]$Text,
        [string[]]$Names
    )

    $bt = [string][char]96
    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $decorated = "(?:\*\*)?${bt}?${escaped}${bt}?(?:\*\*)?"
        $separator = if ($name -match '[_-]') { '[:=]' } else { ':' }
        $patterns.Add("(?m)^\s*-?\s*${decorated}\s*${separator}\s*${bt}?([0-9]+)${bt}?\s*(?:/100)?\s*%?(?:\s+[^\r\n]*)?\s*$")
        $patterns.Add("(?m)^\s*\|\s*${decorated}\s*\|\s*(?:\*\*)?${bt}?([0-9]+)${bt}?(?:\*\*)?\s*(?:/100)?\s*%?\s*\|")
    }
    return Get-FirstNumber $Text $patterns.ToArray()
}

function Get-FinalStatus {
    param(
        [string]$FinalText,
        [string]$RoundText,
        [string]$Phase0Status
    )

    $finalPatterns = @(
        '(?m)^\s*-?\s*`?final_replay_status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*Final replay status\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*\*{0,2}Final Status\*{0,2}\s*[:=]\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?m)^\s*-?\s*`?final post-hoc status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*`?final_status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*`?final status`?\s*[:=]\s*`?([A-Z_]+)`?'
    )
    $status = Get-FirstText $FinalText $finalPatterns
    $status = Normalize-StatusOrNull $status
    if ($status) { return $status }

    $roundPatterns = @(
        '(?m)^\s*-?\s*`?final_status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*`?final status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*`?status`?\s*[:=]\s*`?([A-Z_]+)`?'
    )
    $status = Get-FirstText $RoundText $roundPatterns
    $status = Normalize-StatusOrNull $status
    if ($status) { return $status }

    return (Normalize-StatusOrNull $Phase0Status)
}

function Parse-OneReplay {
    param([string]$Root)
    $phase0ResultPath = Join-Path $Root 'PHASE0_RESULT.md'
    $roundResultPath = Join-Path $Root 'ROUND_RESULT.md'
    $finalReportPath = Join-Path $Root 'FINAL_REPLAY_REPORT.md'
    $phase0Text = Read-TextIfExists $phase0ResultPath
    $roundText = Read-TextIfExists $roundResultPath
    $finalText = Read-TextIfExists $finalReportPath
    $combined = "$phase0Text`n$roundText`n$finalText"

    $flags = @(
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
        'behavior_test_charter_gap'
    )

    $flagCounts = [ordered]@{}
    foreach ($flag in $flags) {
        $flagCounts[$flag] = ([regex]::Matches($combined, [regex]::Escape($flag))).Count
    }

    $phase0Status = Get-FirstText $phase0Text @(
        '(?m)^\s*-?\s*phase0_status\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)\*\*phase0_status\*\*\s*[:=]\s*[`*]*([A-Z_]+)',
        '(?mi)^##\s*Decision\s*[:=]\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s+0\s+Decision\s*[:=]\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s*0\s*Status\s*[:=]\s*[^A-Z_\r\n]*([A-Z_]+)',
        '(?mi)^##\s*Phase\s*0\s*Status\s*\r?\n\s*\*{0,2}\s*([A-Z_]+)',
        '(?m)^\s*-?\s*status\s*[:=]\s*`?([A-Z_]+)`?'
    )
    $phase0Status = Normalize-StatusOrNull $phase0Status

    $status = Get-FinalStatus -FinalText $finalText -RoundText $roundText -Phase0Status $phase0Status

    $oracleUsed = Get-FirstText $roundText @(
        'oracle_used\s*[:=]\s*[^A-Za-z\r\n]*(true|false)',
        'oracle_used\s*=\s*[^A-Za-z\r\n]*(true|false)'
    )

    $oracleAdjustedCoverage = Get-MetricNumber $finalText @('oracle_adjusted_coverage', 'oracle-adjusted coverage', 'oracle adjusted coverage', 'oracle coverage (post-hoc)', 'Oracle Coverage (Post-Hoc)')
    if ($null -eq $oracleAdjustedCoverage) {
        $oracleAdjustedCoverage = Get-MetricNumber $combined @('oracle_adjusted_coverage', 'oracle-adjusted coverage', 'oracle adjusted coverage', 'oracle coverage (post-hoc)', 'Oracle Coverage (Post-Hoc)')
    }
    if ($null -eq $oracleAdjustedCoverage) {
        $oracleAdjustedCoverage = Get-MetricNumber $combined @('replay coverage (self-assessed)', 'Replay Coverage (Self-Assessed)', 'blind_self_assessed_coverage')
    }
    $verificationCappedCoverage = Get-MetricNumber $roundText @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage')
    $reportedOracleAdjustedCoverage = $oracleAdjustedCoverage
    $oracleCoverageEnforced = $false
    if ($null -ne $oracleAdjustedCoverage -and $null -ne $verificationCappedCoverage -and [int]$verificationCappedCoverage -le 0 -and [int]$oracleAdjustedCoverage -gt 0) {
        $oracleCoverageEnforced = $true
        $enforcementPath = Join-Path $Root 'ORACLE_COVERAGE_ENFORCEMENT.md'
        @(
            '# Oracle Coverage Enforcement',
            '',
            '- rule: verification_capped_zero_blocks_oracle_credit',
            "- reported_oracle_adjusted_coverage: $reportedOracleAdjustedCoverage",
            "- enforced_oracle_adjusted_coverage: 0",
            "- verification_capped_coverage: $verificationCappedCoverage",
            '',
            'Reason: oracle-adjusted coverage is replay implementation overlap, not oracle completeness. When Phase 1 has zero executable verification credit, post-hoc oracle credit is capped at zero for autopilot summaries and decisions.'
        ) | Set-Content -LiteralPath $enforcementPath -Encoding UTF8
        $oracleAdjustedCoverage = 0
    }

    return [pscustomobject]@{
        ReplayRoot = $Root
        Phase0ResultExists = (Test-Path -LiteralPath $phase0ResultPath)
        RoundResultExists = (Test-Path -LiteralPath $roundResultPath)
        FinalReportExists = (Test-Path -LiteralPath $finalReportPath)
        Phase0Status = $phase0Status
        OracleUsed = $oracleUsed
        BlindCoverage = Get-MetricNumber $roundText @('blind_self_assessed_coverage', 'blind coverage')
        VerificationCappedCoverage = $verificationCappedCoverage
        OracleAdjustedCoverage = $oracleAdjustedCoverage
        ReportedOracleAdjustedCoverage = $reportedOracleAdjustedCoverage
        OracleCoverageEnforced = $oracleCoverageEnforced
        FinalStatus = $status
        FlagCounts = $flagCounts
    }
}

if ($All) {
    $config = Read-SimpleYaml $ConfigPath
    if (-not $config.ContainsKey('replay_root_base')) {
        throw "Config missing replay_root_base"
    }
    $base = $config['replay_root_base']
    $parent = Split-Path -Parent $base
    $leaf = Split-Path -Leaf $base
    $roots = Get-ChildItem -LiteralPath $parent -Directory -Filter "$leaf-r*" | Sort-Object Name | ForEach-Object { $_.FullName }
} else {
    if ([string]::IsNullOrWhiteSpace($ReplayRoot)) {
        throw "Pass -ReplayRoot or use -All"
    }
    $roots = @([System.IO.Path]::GetFullPath($ReplayRoot))
}

$results = foreach ($root in $roots) {
    Parse-OneReplay -Root $root
}

$results | Select-Object ReplayRoot,Phase0ResultExists,RoundResultExists,FinalReportExists,Phase0Status,OracleUsed,BlindCoverage,VerificationCappedCoverage,OracleAdjustedCoverage,FinalStatus | Format-Table -AutoSize

$productizedGateMap = @{
    invalid_plan = 'Core-First Budget Gate'
    invalid_replay = 'Core-First Budget Gate'
    supporting_slice_first = 'Core-First Budget Gate'
    core_first_plan_invalid = 'Core-First Budget Gate'
    exact_contract_gap = 'Requirement Contract Gate'
    core_entry_unclosed = 'Core-First Budget Gate'
    real_entry_gap = 'Core-First Budget Gate'
    surface_budget_gap = 'Core-First Budget Gate'
    helper_only_surface_gap = 'Core-First Budget Gate'
    side_effect_ledger_gap = 'Executable Evidence Gate'
    needs_transaction_test = 'Executable Evidence Gate'
    wrong_test_surface = 'Executable Evidence Gate'
    shallow_module = 'Executable Evidence Gate'
    feedback_loop_blocker = 'Executable Evidence Gate'
    mock_behavior_gap = 'Executable Evidence Gate'
    implementation_after_blocked_red = 'Executable Evidence Gate'
    behavior_test_charter_gap = 'Executable Evidence Gate'
    executable_surface_slice_gap = 'Surface Coverage Gate'
}

foreach ($result in $results) {
    $summaryPath = Join-Path $result.ReplayRoot 'AUTOPILOT_SUMMARY.md'
    $flagLines = foreach ($key in $result.FlagCounts.Keys) {
        "- ${key}: $($result.FlagCounts[$key])"
    }
    $gateCounts = [ordered]@{
        'Source-of-Truth Gate' = 0
        'Oracle Isolation Gate' = 0
        'Requirement Contract Gate' = 0
        'Surface Coverage Gate' = 0
        'Core-First Budget Gate' = 0
        'Executable Evidence Gate' = 0
        'Coverage Cap Gate' = 0
        'Evolution Abstraction Gate' = 0
    }
    foreach ($key in $result.FlagCounts.Keys) {
        if ($productizedGateMap.ContainsKey($key)) {
            $gate = $productizedGateMap[$key]
            $gateCounts[$gate] += $result.FlagCounts[$key]
        }
    }
    $gateLines = foreach ($gate in $gateCounts.Keys) {
        "- ${gate}: $($gateCounts[$gate])"
    }
    $summary = @"
# Replay Autopilot Summary

- Replay root: $($result.ReplayRoot)
- PHASE0_RESULT exists: $($result.Phase0ResultExists)
- ROUND_RESULT exists: $($result.RoundResultExists)
- FINAL_REPLAY_REPORT exists: $($result.FinalReportExists)
- phase0_status: $($result.Phase0Status)
- oracle_used: $($result.OracleUsed)
- blind_self_assessed_coverage: $($result.BlindCoverage)
- verification_capped_coverage: $($result.VerificationCappedCoverage)
- oracle_adjusted_coverage: $($result.OracleAdjustedCoverage)
- reported_oracle_adjusted_coverage: $($result.ReportedOracleAdjustedCoverage)
- oracle_coverage_enforced: $($result.OracleCoverageEnforced)
- final_status: $($result.FinalStatus)

## Gap Flags

$($flagLines -join "`n")

## Productized Gate Hits

$($gateLines -join "`n")
"@
    Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
    Write-Host "Wrote summary: $summaryPath"
}
