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

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
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

function Get-RunnerAuthorizationState {
    param([string]$Root)

    $router = Read-JsonIfExists (Join-Path $Root 'FAMILY_ROUTER_AND_CAP.json')
    $ledgerCap = $null
    $finalPassAllowed = $true
    if ($null -ne $router) {
        if ($router.PSObject.Properties.Name -contains 'coverage_cap_from_ledger' -and "$($router.coverage_cap_from_ledger)" -match '^\d+$') {
            $ledgerCap = [int]$router.coverage_cap_from_ledger
        }
        if ($router.PSObject.Properties.Name -contains 'final_pass_allowed') {
            $finalPassAllowed = [bool]$router.final_pass_allowed
        }
    }

    $signals = New-Object System.Collections.Generic.List[string]
    if (-not $finalPassAllowed) {
        $signals.Add('router_final_pass_allowed=false') | Out-Null
    }

    if (Test-Path -LiteralPath $Root) {
        foreach ($file in Get-ChildItem -LiteralPath $Root -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue | Sort-Object Name) {
            $verify = Read-JsonIfExists $file.FullName
            if ($null -eq $verify) { continue }
            if ($verify.PSObject.Properties.Name -contains 'authorized_for_next_slice' -and -not [bool]$verify.authorized_for_next_slice) {
                $signals.Add("authorized_for_next_slice=false:$($file.Name)") | Out-Null
            }
            if ($verify.PSObject.Properties.Name -contains 'authorized_for_synthesis' -and -not [bool]$verify.authorized_for_synthesis) {
                $signals.Add("authorized_for_synthesis=false:$($file.Name)") | Out-Null
            }
            foreach ($blocker in Get-StringArray $verify.authorization_blockers) {
                if (-not [string]::IsNullOrWhiteSpace($blocker)) {
                    $signals.Add("blocker:$blocker") | Out-Null
                }
            }
        }
    }

    $uniqueSignals = @($signals | Select-Object -Unique)
    return [pscustomobject]@{
        coverage_cap_from_ledger = $ledgerCap
        final_pass_allowed = $finalPassAllowed
        non_authorizing_signals = $uniqueSignals
        has_non_authorizing_evidence = (-not $finalPassAllowed) -or $uniqueSignals.Count -gt 0
    }
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
    # Backward-compatible observed variants covered by the generic rules:
    # CAVEATS|CAVIETS|CAVETS and GREEN_PROCEED / READY_PROCEED style values.
    if ($status -match '^PROCEED_WITH_[A-Z_]+$') {
        return 'PROCEED'
    }
    if ($status -match '^[A-Z_]+_PROCEED$') {
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
        '(?m)^\s*\|\s*\*{0,2}Final Status\*{0,2}\s*\|\s*\*{0,2}`?([A-Z_]+)`?\*{0,2}\s*\|',
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
        'behavior_test_charter_gap',
        'phase2_executor_blocker'
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
    $runnerAuthorization = Get-RunnerAuthorizationState -Root $Root

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
    $blindCoverage = Get-MetricNumber $roundText @('blind_self_assessed_coverage', 'blind coverage')
    $runnerCoverageEnforced = $false
    if ($null -ne $runnerAuthorization.coverage_cap_from_ledger) {
        $ledgerCap = [int]$runnerAuthorization.coverage_cap_from_ledger
        if ($null -eq $verificationCappedCoverage -or [int]$verificationCappedCoverage -gt $ledgerCap) {
            $verificationCappedCoverage = $ledgerCap
            $runnerCoverageEnforced = $true
        }
        if ($null -eq $blindCoverage -and [bool]$runnerAuthorization.has_non_authorizing_evidence) {
            $blindCoverage = $ledgerCap
            $runnerCoverageEnforced = $true
        } elseif ($null -ne $blindCoverage -and [int]$blindCoverage -gt $ledgerCap) {
            $blindCoverage = $ledgerCap
            $runnerCoverageEnforced = $true
        }
    }

    $reportedOracleAdjustedCoverage = $oracleAdjustedCoverage
    $oracleCoverageEnforced = $false
    $oracleCoverageEnforcementRule = 'none'
    $oracleDecisionCap = $null
    if ($null -ne $verificationCappedCoverage -and [bool]$runnerAuthorization.has_non_authorizing_evidence) {
        $oracleDecisionCap = [int]$verificationCappedCoverage
        $oracleCoverageEnforcementRule = 'runner_non_authorizing_cap_blocks_oracle_credit'
    } elseif ($null -ne $verificationCappedCoverage -and [int]$verificationCappedCoverage -le 0) {
        $oracleDecisionCap = 0
        $oracleCoverageEnforcementRule = 'verification_capped_zero_blocks_oracle_credit'
    }
    if ($null -ne $oracleAdjustedCoverage -and $null -ne $oracleDecisionCap -and [int]$oracleAdjustedCoverage -gt [int]$oracleDecisionCap) {
        $oracleCoverageEnforced = $true
        $enforcementPath = Join-Path $Root 'ORACLE_COVERAGE_ENFORCEMENT.md'
        @(
            '# Oracle Coverage Enforcement',
            '',
            "- rule: $oracleCoverageEnforcementRule",
            "- reported_oracle_adjusted_coverage: $reportedOracleAdjustedCoverage",
            "- enforced_oracle_adjusted_coverage: $oracleDecisionCap",
            "- verification_capped_coverage: $verificationCappedCoverage",
            "- runner_final_pass_allowed: $($runnerAuthorization.final_pass_allowed)",
            "- runner_non_authorizing_signals: $(@($runnerAuthorization.non_authorizing_signals) -join '; ')",
            '',
            'Reason: oracle-adjusted coverage is replay implementation overlap, not oracle completeness. Runner-owned authorization and verification caps must control autopilot summaries and decisions.'
        ) | Set-Content -LiteralPath $enforcementPath -Encoding UTF8
        $oracleAdjustedCoverage = [int]$oracleDecisionCap
    }

    if ([bool]$runnerAuthorization.has_non_authorizing_evidence) {
        $status = 'BLOCKED'
    }

    $productionMatch = Get-MetricNumber $combined @('production_match', 'Production Match', 'production code match', 'production match')
    $oracleTestCoverageZero = $combined -match '(?i)(Oracle\s+Test\s+Coverage[^\r\n]*(NONE|0\s*%)|Oracle\s+has\s+(ZERO|NO)\s+test\s+coverage|oracle\s+coverage[^\r\n]*production\s+match\s+only)'
    $replayClassification = 'full_replay'
    $requiresEvolution = $false
    $evolutionType = 'none'
    if ($null -ne $productionMatch -and [int]$productionMatch -ge 100 -and $oracleTestCoverageZero -and
        (($null -ne $oracleAdjustedCoverage -and [int]$oracleAdjustedCoverage -le 0) -or
         ($null -ne $verificationCappedCoverage -and [int]$verificationCappedCoverage -le 0))) {
        $replayClassification = 'production_match_only'
        $requiresEvolution = $true
        $evolutionType = if ($combined -match '(?i)(test infrastructure|wrong_test_surface|shallow_module|test_compilation|cannot find symbol|missing dependency|no executable evidence)') {
            'test_infrastructure'
        } else {
            'behavior_test_coverage'
        }
    }
    $explicitRequiresEvolution = Get-FirstText $combined @(
        '(?m)^\s*-?\s*`?requires_evolution`?\s*[:=]\s*`?([A-Za-z0-9_+-]+)`?',
        '(?m)^\s*-?\s*requires evolution\s*[:=]\s*`?([A-Za-z0-9_+-]+)`?'
    )
    $explicitEvolutionType = Get-FirstText $combined @(
        '(?m)^\s*-?\s*`?evolution_type`?\s*[:=]\s*`?([A-Za-z0-9_-]+)`?',
        '(?m)^\s*-?\s*evolution type\s*[:=]\s*`?([A-Za-z0-9_-]+)`?'
    )
    if ($explicitRequiresEvolution -and $explicitRequiresEvolution.Trim() -match '^(?i:true|yes|1)$') {
        $requiresEvolution = $true
    }
    if ($combined -match '(?m)^\s*-?\s*`?phase2_fallback_used`?\s*[:=]\s*`?(?i:true|yes|1)`?' -or $flagCounts['phase2_executor_blocker'] -gt 0) {
        $requiresEvolution = $true
        if ($evolutionType -eq 'none') {
            $evolutionType = 'phase2_executor_fallback'
        }
    }
    if ($explicitEvolutionType) {
        $evolutionType = $explicitEvolutionType
    }

    return [pscustomobject]@{
        ReplayRoot = $Root
        Phase0ResultExists = (Test-Path -LiteralPath $phase0ResultPath)
        RoundResultExists = (Test-Path -LiteralPath $roundResultPath)
        FinalReportExists = (Test-Path -LiteralPath $finalReportPath)
        Phase0Status = $phase0Status
        OracleUsed = $oracleUsed
        BlindCoverage = $blindCoverage
        VerificationCappedCoverage = $verificationCappedCoverage
        OracleAdjustedCoverage = $oracleAdjustedCoverage
        ReportedOracleAdjustedCoverage = $reportedOracleAdjustedCoverage
        OracleCoverageEnforced = $oracleCoverageEnforced
        OracleCoverageEnforcementRule = $oracleCoverageEnforcementRule
        ProductionMatch = $productionMatch
        ReplayClassification = $replayClassification
        RequiresEvolution = $requiresEvolution
        EvolutionType = $evolutionType
        FinalStatus = $status
        FlagCounts = $flagCounts
        RunnerCoverageCapFromLedger = $runnerAuthorization.coverage_cap_from_ledger
        RunnerFinalPassAllowed = $runnerAuthorization.final_pass_allowed
        RunnerCoverageEnforced = $runnerCoverageEnforced
        RunnerNonAuthorizingSignals = @($runnerAuthorization.non_authorizing_signals)
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
    phase2_executor_blocker = 'Evolution Abstraction Gate'
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
- oracle_coverage_enforcement_rule: $($result.OracleCoverageEnforcementRule)
- production_match: $($result.ProductionMatch)
- replay_classification: $($result.ReplayClassification)
- requires_evolution: $($result.RequiresEvolution)
- evolution_type: $($result.EvolutionType)
- final_status: $($result.FinalStatus)
- runner_coverage_cap_from_ledger: $($result.RunnerCoverageCapFromLedger)
- runner_final_pass_allowed: $($result.RunnerFinalPassAllowed)
- runner_coverage_enforced: $($result.RunnerCoverageEnforced)
- runner_non_authorizing_signals: $(@($result.RunnerNonAuthorizingSignals) -join '; ')

## Gap Flags

$($flagLines -join "`n")

## Productized Gate Hits

$($gateLines -join "`n")
"@
    Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8
    Write-Host "Wrote summary: $summaryPath"
}
