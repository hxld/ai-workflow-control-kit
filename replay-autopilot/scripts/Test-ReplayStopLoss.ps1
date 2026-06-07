param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$HistoryRoot = 'D:\opt',
    [int]$TargetCoverage = 90,
    [int]$Lookback = 4,
    [int]$MinOracleImprovement = 8,
    [int]$LowCapThreshold = 45,
    [int]$LowCapRounds = 2,
    [int]$RepeatGapThreshold = 2,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-MetricNumber {
    param(
        [string]$Text,
        [string[]]$Names
    )

    $bt = [string][char]96
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $patterns = @(
            "(?m)^\s*-?\s*${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?",
            "(?m)^\s*\|\s*${bt}?${escaped}${bt}?\s*\|\s*${bt}?([0-9]+)${bt}?\s*%?\s*\|",
            "(?m)${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?"
        )
        foreach ($pattern in $patterns) {
            $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) {
                return [int]$m.Groups[1].Value
            }
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

function Get-GapFlagCounts {
    param([string]$Text)

    $patterns = [ordered]@{
        wrong_test_surface = @('wrong[-_ ]test[-_ ]surface', 'helper/static green', 'static-only', 'test.*surface.*wrong')
        shallow_module = @('shallow[-_ ]module', 'shallow.*service', 'module.*shallow')
        synthetic_carrier_gap = @('synthetic[-_ ]carrier', 'Noop', 'placeholder.*carrier', 'carrier.*miss')
        core_entry_unclosed = @('core[-_ ]entry', 'real.*entry.*missing', 'entry.*not.*closed', 'entry.*missing')
        side_effect_ledger_gap = @('side[-_ ]effect', 'DB.*side.*effect', 'state.*task.*progress', 'transaction.*side.*effect')
        executable_surface_slice_gap = @('executable[-_ ]surface', 'deploy-facing.*not.*closed', 'executable.*surface', 'compile-only')
        exact_contract_gap = @('exact[-_ ]contract', 'contract.*drift', 'field.*mismatch', 'literal.*drift')
        implementation_after_blocked_red = @('implementation[-_ ]after[-_ ]blocked[-_ ]red', 'RED.*blocked.*implementation', 'implementation.*blocked.*RED')
        behavior_test_charter_gap = @('behavior[-_ ]test[-_ ]charter', 'test[-_ ]charter.*missing', 'charter.*non[-_ ]authorizing')
    }

    $result = [ordered]@{}
    foreach ($key in $patterns.Keys) {
        $count = 0
        foreach ($pattern in $patterns[$key]) {
            $count += [regex]::Matches($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
        }
        $result[$key] = $count
    }
    return $result
}

function Read-ReplaySnapshot {
    param([string]$Root)

    $summaryPath = Join-Path $Root 'AUTOPILOT_SUMMARY.md'
    $finalPath = Join-Path $Root 'FINAL_REPLAY_REPORT.md'
    $roundPath = Join-Path $Root 'ROUND_RESULT.md'
    $proposalPath = Join-Path $Root 'EVOLUTION_PROPOSAL.md'

    $summaryText = Read-TextIfExists $summaryPath
    $finalText = Read-TextIfExists $finalPath
    $roundText = Read-TextIfExists $roundPath
    $proposalText = Read-TextIfExists $proposalPath
    $combined = "$summaryText`n$finalText`n$roundText`n$proposalText"

    $summaryItem = if (Test-Path -LiteralPath $summaryPath) { Get-Item -LiteralPath $summaryPath } else { $null }
    return [pscustomobject]@{
        root = $Root
        has_summary = [bool](Test-Path -LiteralPath $summaryPath)
        has_final_report = [bool](Test-Path -LiteralPath $finalPath)
        summary_modified = if ($summaryItem) { $summaryItem.LastWriteTime.ToString('s') } else { $null }
        blind_self_assessed_coverage = Get-MetricNumber $combined @('blind_self_assessed_coverage', 'blind-self-assessed coverage')
        verification_capped_coverage = Get-MetricNumber $combined @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage')
        oracle_adjusted_coverage = Get-MetricNumber $combined @('oracle_adjusted_coverage', 'oracle-adjusted coverage')
        final_status = Get-FirstText $combined @(
            '(?m)^\s*-?\s*final(?: post-hoc)? status\s*[:=]\s*`?([A-Z_]+)`?',
            '(?m)^\s*-?\s*final_status\s*[:=]\s*`?([A-Z_]+)`?',
            '(?m)^\s*-?\s*status\s*[:=]\s*`?([A-Z_]+)`?'
        )
        gap_flags = Get-GapFlagCounts $combined
    }
}

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        ReplayRoot = (Resolve-AbsolutePath $ReplayRoot)
        HistoryRoot = (Resolve-AbsolutePath $HistoryRoot)
        TargetCoverage = $TargetCoverage
        Lookback = $Lookback
        MinOracleImprovement = $MinOracleImprovement
        LowCapThreshold = $LowCapThreshold
        LowCapRounds = $LowCapRounds
        RepeatGapThreshold = $RepeatGapThreshold
    } | Format-List
    exit 0
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$historyRootFull = Resolve-AbsolutePath $HistoryRoot
if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "Replay root not found: $replayRootFull"
}

$current = Read-ReplaySnapshot $replayRootFull
$evolutionResultText = Read-TextIfExists (Join-Path $replayRootFull 'EVOLUTION_RESULT.md')
$stopOrContinueText = Read-TextIfExists (Join-Path $replayRootFull 'STOP_OR_CONTINUE_DECISION.md')
$hasValidatedEvolution = (
    $evolutionResultText -match '(?im)^\s*-\s*final_status\s*:\s*`?[^`\r\n]*VALIDATED[^`\r\n]*`?\s*$' -and
    $evolutionResultText -match '(?im)^\s*-\s*actual_knowledge_version_after_push\s*:\s*`?v[0-9]+`?\s*$'
)
$wasStoppedForEvolution = (
    $stopOrContinueText -match '(?im)^\s*-\s*decision\s*:\s*`?STOP_AND_EVOLVE`?\s*$' -or
    (Read-TextIfExists (Join-Path $replayRootFull 'STOP_LOSS_DECISION.md')) -match '(?im)^\s*-\s*decision\s*:\s*STOP_DEEP_REVIEW_REQUIRED\s*$'
)
$candidateRoots = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $historyRootFull) {
    Get-ChildItem -LiteralPath $historyRootFull -Directory -Filter 'claim-codex-replay-v*-autopilot-*' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.FullName -ne $replayRootFull -and (Test-Path -LiteralPath (Join-Path $_.FullName 'AUTOPILOT_SUMMARY.md'))) {
            $snapshot = Read-ReplaySnapshot $_.FullName
            $candidateRoots.Add($snapshot)
        }
    }
}

$recent = @($candidateRoots | Sort-Object @{ Expression = { if ($_.summary_modified) { [datetime]$_.summary_modified } else { [datetime]::MinValue } }; Descending = $true } | Select-Object -First $Lookback)
$recentOracleValues = @($recent | Where-Object { $_.oracle_adjusted_coverage -ne $null } | ForEach-Object { [int]$_.oracle_adjusted_coverage })
$bestRecentOracle = if ($recentOracleValues.Count -gt 0) { ($recentOracleValues | Measure-Object -Maximum).Maximum } else { $null }
$oracleImprovement = if ($current.oracle_adjusted_coverage -ne $null -and $bestRecentOracle -ne $null) { [int]$current.oracle_adjusted_coverage - [int]$bestRecentOracle } else { $null }

$reasons = New-Object System.Collections.Generic.List[string]
$repeatedGaps = New-Object System.Collections.Generic.List[object]
$decision = 'CONTINUE'

if ($current.oracle_adjusted_coverage -ne $null -and [int]$current.oracle_adjusted_coverage -ge $TargetCoverage) {
    $decision = 'TARGET_REACHED'
    if ($current.verification_capped_coverage -ne $null -and [int]$current.verification_capped_coverage -le $LowCapThreshold) {
        $reasons.Add("oracle_vs_verification_mismatch: oracle=$($current.oracle_adjusted_coverage) verification_capped=$($current.verification_capped_coverage)")
        $decision = 'STOP_DEEP_REVIEW_REQUIRED'
    }
} else {
    if ($current.final_status -match 'BLOCKED|INVALID' -or ($current.oracle_adjusted_coverage -ne $null -and [int]$current.oracle_adjusted_coverage -le 10)) {
        $reasons.Add('catastrophic_or_blocked')
    }

    if ($recent.Count -ge 2 -and $current.oracle_adjusted_coverage -ne $null -and $bestRecentOracle -ne $null -and $oracleImprovement -lt $MinOracleImprovement) {
        $reasons.Add("no_substantive_oracle_improvement: improvement=$oracleImprovement best_recent=$bestRecentOracle required_delta=$MinOracleImprovement")
    }

    $lowCapSeries = @()
    if ($current.verification_capped_coverage -ne $null) {
        $lowCapSeries += [int]$current.verification_capped_coverage
    }
    $lowCapSeries += @($recent | Select-Object -First ([Math]::Max(0, $LowCapRounds - 1)) | Where-Object { $_.verification_capped_coverage -ne $null } | ForEach-Object { [int]$_.verification_capped_coverage })
    if ($lowCapSeries.Count -ge $LowCapRounds -and @($lowCapSeries | Where-Object { $_ -le $LowCapThreshold }).Count -ge $LowCapRounds) {
        $reasons.Add("low_verification_cap_streak: threshold=$LowCapThreshold rounds=$LowCapRounds values=$($lowCapSeries -join ',')")
    }

    foreach ($gap in $current.gap_flags.Keys) {
        if ([int]$current.gap_flags[$gap] -le 0) { continue }
        $priorHits = @($recent | Where-Object { $_.gap_flags.Contains($gap) -and [int]$_.gap_flags[$gap] -gt 0 }).Count
        if ($priorHits -ge $RepeatGapThreshold) {
            $item = [ordered]@{
                gap = $gap
                current_mentions = [int]$current.gap_flags[$gap]
                prior_hit_count = $priorHits
            }
            $repeatedGaps.Add([pscustomobject]$item)
        }
    }

    if ($repeatedGaps.Count -gt 0) {
        $reasons.Add("repeated_high_value_gap: $(@($repeatedGaps | ForEach-Object { $_.gap }) -join ',')")
    }

    if ($reasons.Count -gt 0 -and $hasValidatedEvolution -and $wasStoppedForEvolution) {
        $decision = 'CONTINUE_AFTER_VALIDATED_EVOLUTION'
    } elseif ($reasons.Count -gt 0) {
        $decision = 'STOP_DEEP_REVIEW_REQUIRED'
    }
}

$shouldStop = $decision -eq 'STOP_DEEP_REVIEW_REQUIRED'
$recentRootList = New-Object System.Collections.Generic.List[string]
foreach ($item in @($recent)) {
    if (-not [string]::IsNullOrWhiteSpace($item.root)) {
        $recentRootList.Add([string]$item.root)
    }
}
$repeatedGapList = @()
foreach ($item in $repeatedGaps) {
    $repeatedGapList += $item
}
$decisionObject = [ordered]@{
    should_stop = $shouldStop
    decision = $decision
    reasons = @($reasons)
    target_coverage = $TargetCoverage
    current = $current
    recent_roots = @($recentRootList)
    best_recent_oracle = $bestRecentOracle
    oracle_improvement_over_recent_best = $oracleImprovement
    repeated_gaps = $repeatedGapList
    evolution_result_validated = $hasValidatedEvolution
    stopped_for_evolution = $wasStoppedForEvolution
    recommended_action = if ($shouldStop -and $reasons -match 'oracle_vs_verification_mismatch') {
        'Oracle says target reached but executable evidence says otherwise. Run deep review to resolve the mismatch before accepting oracle verdict.'
    } elseif ($shouldStop) {
        'Run deep replay review before the next evolution; convert repeated failures into <=3 falsifiable workflow experiments.'
    } elseif ($decision -eq 'CONTINUE_AFTER_VALIDATED_EVOLUTION') {
        'Validated evolution result exists for the stopped replay; allow one bounded replay/evolution loop, then re-check stop-loss.'
    } elseif ($decision -eq 'TARGET_REACHED') {
        'Stop replay loop and preserve evidence.'
    } else {
        'Continue normal replay/evolution loop.'
    }
    generated_at = (Get-Date).ToString('s')
}

$jsonPath = Join-Path $replayRootFull 'STOP_LOSS_DECISION.json'
$mdPath = Join-Path $replayRootFull 'STOP_LOSS_DECISION.md'
$decisionObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = @(
    '# Replay Stop Loss Decision',
    '',
    "- decision: $decision",
    "- should_stop: $shouldStop",
    "- target_coverage: $TargetCoverage",
    "- current_oracle_adjusted_coverage: $($current.oracle_adjusted_coverage)",
    "- current_verification_capped_coverage: $($current.verification_capped_coverage)",
    "- best_recent_oracle: $bestRecentOracle",
    "- oracle_improvement_over_recent_best: $oracleImprovement",
    "- recent_roots: $(@($recentRootList) -join '; ')",
    '',
    '## Reasons'
)
if ($reasons.Count -eq 0) {
    $md += '- none'
} else {
    $md += @($reasons | ForEach-Object { "- $_" })
}
$md += @(
    '',
    '## Repeated Gaps'
)
if ($repeatedGaps.Count -eq 0) {
    $md += '- none'
} else {
    $md += @($repeatedGaps | ForEach-Object { "- $($_.gap): current_mentions=$($_.current_mentions), prior_hit_count=$($_.prior_hit_count)" })
}
$md += @(
    '',
    '## Recommended Action',
    '',
    $decisionObject.recommended_action
)
Set-Content -LiteralPath $mdPath -Value ($md -join "`n") -Encoding UTF8

Write-Host "Stop-loss decision: $decision (should_stop=$shouldStop)"
Write-Host "Wrote $jsonPath"
Write-Host "Wrote $mdPath"
