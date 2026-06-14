param(
    [string]$EvidenceRoot = 'D:\opt\replay-evidence',
    [string]$OutputPath = '',
    [int]$MaxRoots = 40,
    [switch]$Quiet
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
        $decorated = "(?:\*\*)?${bt}?${escaped}${bt}?(?:\*\*)?"
        $separator = if ($name -match '[_-]') { '[:=]' } else { ':' }
        $patterns = @(
            "(?m)^\s*-?\s*${decorated}\s*${separator}\s*${bt}?([0-9]+)${bt}?\s*(?:/100)?\s*%?",
            "(?m)^\s*\|\s*${decorated}\s*\|\s*(?:\*\*)?${bt}?([0-9]+)${bt}?(?:\*\*)?\s*(?:/100)?\s*%?\s*\|"
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

function Get-StatusValue {
    param(
        [string]$Text,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $decorated = "(?:\*\*)?`?${escaped}`?(?:\*\*)?"
        $patterns = @(
            "(?m)^\s*-?\s*${decorated}\s*[:=]\s*(?:\*\*)?`?([A-Z][A-Z_ ]*)`?(?:\*\*)?",
            "(?m)^\s*${decorated}\s*[:=]\s*(?:\*\*)?`?([A-Z][A-Z_ ]*)`?(?:\*\*)?"
        )
        $value = Get-FirstText -Text $Text -Patterns $patterns
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    return ''
}

function Get-FinalStatusValue {
    param(
        [string]$FinalText,
        [string]$RoundText,
        [string]$SummaryText
    )

    $value = Get-StatusValue -Text $FinalText -Names @('final_replay_status', 'final post-hoc status', 'final_status', 'final status')
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    $value = Get-StatusValue -Text $RoundText -Names @('final_replay_status', 'final post-hoc status', 'final_status', 'final status', 'Round Status')
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    $value = Get-FirstText -Text $RoundText -Patterns @(
        '(?ms)^#{2,4}\s*Final Status\s*\r?\n\s*(?:-\s*)?(?:\*\*)?([A-Z][A-Z_ ]*)(?:\*\*)?',
        '(?ms)^#{2,4}\s*Round Status\s*\r?\n\s*(?:-\s*)?(?:\*\*)?([A-Z][A-Z_ ]*)(?:\*\*)?'
    )
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }

    return Get-StatusValue -Text $SummaryText -Names @('final_status', 'status')
}

function Get-ReplayRoots {
    param([string]$Root)

    $roots = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    $directRoots = @(Get-ChildItem -LiteralPath $Root -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue)
    foreach ($item in $directRoots) {
        $roots.Add($item) | Out-Null
    }

    $featureDirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notlike '_*' -and $_.Name -notlike 'claim-codex-replay-*'
    })
    foreach ($featureDir in $featureDirs) {
        $childRoots = @(Get-ChildItem -LiteralPath $featureDir.FullName -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue)
        foreach ($item in $childRoots) {
            $roots.Add($item) | Out-Null
        }
    }

    return @($roots.ToArray())
}

function Get-FeatureName {
    param(
        [string]$EvidenceRootFull,
        [string]$ReplayRoot
    )

    $parent = Split-Path -Parent $ReplayRoot
    if ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq $EvidenceRootFull.TrimEnd('\')) {
        return '(direct)'
    }
    return Split-Path -Leaf $parent
}

function Get-StopLossDecision {
    param([string]$ReplayRoot)

    $path = Join-Path $ReplayRoot 'STOP_LOSS_DECISION.json'
    if (-not (Test-Path -LiteralPath $path)) {
        return ''
    }

    try {
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $decision = [string]$json.decision
        $shouldStop = [string]$json.should_stop
        if ([string]::IsNullOrWhiteSpace($decision)) {
            return 'present'
        }
        return "$decision stop=$shouldStop"
    } catch {
        return 'present-unparsed'
    }
}

function Get-EvolutionSummary {
    param([string]$ReplayRoot)

    $path = Join-Path $ReplayRoot 'EVOLUTION_RESULT.md'
    if (-not (Test-Path -LiteralPath $path)) {
        return ''
    }

    $text = Read-TextIfExists $path
    $status = Get-StatusValue -Text $text -Names @('status', 'final_status', 'evolution_status')
    $version = Get-FirstText -Text $text -Patterns @(
        '(?m)^\s*-?\s*`?knowledge_version`?\s*[:=]\s*`?([^`\r\n]+)`?',
        '(?m)^\s*-?\s*`?actual_knowledge_version`?\s*[:=]\s*`?([^`\r\n]+)`?',
        '(?m)^\s*-?\s*`?version`?\s*[:=]\s*`?(v[0-9]+[^`\r\n]*)`?'
    )
    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'present' }
    if ([string]::IsNullOrWhiteSpace($version)) { return $status }
    return "$status $version"
}

function Convert-ToCell {
    param([object]$Value)
    if ($null -eq $Value) { return '-' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '-' }
    return $s.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $evidenceRootFull 'REPLAY_AUTOPILOT_SESSION_SUMMARY.md'
} else {
    $OutputPath = Resolve-AbsolutePath $OutputPath
}

$rootItems = @(Get-ReplayRoots -Root $evidenceRootFull | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxRoots)
$records = New-Object System.Collections.Generic.List[object]

foreach ($item in $rootItems) {
    $root = $item.FullName
    $phase0Text = Read-TextIfExists (Join-Path $root 'PHASE0_RESULT.md')
    $planText = Read-TextIfExists (Join-Path $root 'PLAN_RESULT.md')
    $roundText = Read-TextIfExists (Join-Path $root 'ROUND_RESULT.md')
    $finalText = Read-TextIfExists (Join-Path $root 'FINAL_REPLAY_REPORT.md')
    $decisionText = Read-TextIfExists (Join-Path $root 'AUTOPILOT_DECISION.md')
    $summaryText = Read-TextIfExists (Join-Path $root 'AUTOPILOT_SUMMARY.md')
    $combined = "$phase0Text`n$planText`n$roundText`n$finalText`n$decisionText`n$summaryText"

    $phase0Status = Get-StatusValue -Text $phase0Text -Names @('phase0_status', 'status')
    $planStatus = Get-StatusValue -Text $planText -Names @('plan_status', 'final_status', 'status')
    $finalStatus = Get-FinalStatusValue -FinalText $finalText -RoundText $roundText -SummaryText $summaryText
    $decision = Get-StatusValue -Text $decisionText -Names @('decision', 'circuit_breaker')
    $blocker = if (Test-Path -LiteralPath (Join-Path $root 'AUTOPILOT_BLOCKER.md')) { 'yes' } else { '' }

    $records.Add([pscustomobject]@{
        Feature = Get-FeatureName -EvidenceRootFull $evidenceRootFull -ReplayRoot $root
        ReplayRoot = $root
        RootName = $item.Name
        Updated = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        Phase0Status = $phase0Status
        PlanStatus = $planStatus
        FinalStatus = $finalStatus
        BlindCoverage = Get-MetricNumber -Text $combined -Names @('blind_self_assessed_coverage', 'blind coverage', 'Blind Self-Assessed Coverage', 'Phase 1 Blind Coverage', 'Final Coverage')
        VerificationCoverage = Get-MetricNumber -Text $combined -Names @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage', 'Verification Capped Coverage')
        OracleCoverage = Get-MetricNumber -Text $combined -Names @('oracle_adjusted_coverage', 'oracle-adjusted coverage', 'Oracle Adjusted Coverage')
        Decision = $decision
        StopLoss = Get-StopLossDecision -ReplayRoot $root
        Evolution = Get-EvolutionSummary -ReplayRoot $root
        Blocker = $blocker
    }) | Out-Null
}

$crossRoot = Join-Path $evidenceRootFull '_cross-feature'
$crossRuns = @()
if (Test-Path -LiteralPath $crossRoot) {
    $crossRuns = @(Get-ChildItem -LiteralPath $crossRoot -Directory -Filter 'cross-run-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8)
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Replay Autopilot Portable Session Summary') | Out-Null
$lines.Add('') | Out-Null
$lines.Add("- generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')") | Out-Null
$lines.Add("- evidence_root: $evidenceRootFull") | Out-Null
$lines.Add("- max_roots: $MaxRoots") | Out-Null
$lines.Add("- purpose: Session-independent replay/evolution recovery entry. Read this file before falling back to Claude/Codex conversation logs.") | Out-Null
$lines.Add("- source_policy: Generated only from replay artifacts under evidence_root; no chat JSONL or host-specific memory is required.") | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## How To Resume') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('1. Read the latest row in `Latest Replay Roots`.') | Out-Null
$lines.Add('2. Open that replay root and inspect `AUTOPILOT_DECISION.md`, `FINAL_REPLAY_REPORT.md`, `EVOLUTION_RESULT.md`, `DEEP_REVIEW_REPORT.md`, or `NEXT_EXPERIMENT_PLAN.md` if present.') | Out-Null
$lines.Add('3. Continue from artifacts and knowledge versions, not from a fixed Claude/Codex session id.') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Latest Replay Roots') | Out-Null
$lines.Add('') | Out-Null
if ($records.Count -eq 0) {
    $lines.Add('_No replay roots found._') | Out-Null
} else {
    $lines.Add('| Feature | Updated | Root | Phase0 | Plan | Final | Blind | Cap | Oracle | Decision | Stop-loss | Evolution | Blocker |') | Out-Null
    $lines.Add('| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |') | Out-Null
    foreach ($record in $records) {
        $lines.Add(('| {0} | {1} | `{2}` | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} |' -f `
            (Convert-ToCell $record.Feature),
            (Convert-ToCell $record.Updated),
            (Convert-ToCell $record.ReplayRoot),
            (Convert-ToCell $record.Phase0Status),
            (Convert-ToCell $record.PlanStatus),
            (Convert-ToCell $record.FinalStatus),
            (Convert-ToCell $record.BlindCoverage),
            (Convert-ToCell $record.VerificationCoverage),
            (Convert-ToCell $record.OracleCoverage),
            (Convert-ToCell $record.Decision),
            (Convert-ToCell $record.StopLoss),
            (Convert-ToCell $record.Evolution),
            (Convert-ToCell $record.Blocker))) | Out-Null
    }
}

$lines.Add('') | Out-Null
$lines.Add('## Cross-Feature Ledgers') | Out-Null
$lines.Add('') | Out-Null
if ($crossRuns.Count -eq 0) {
    $lines.Add('_No cross-feature ledgers found._') | Out-Null
} else {
    $lines.Add('| Updated | Ledger |') | Out-Null
    $lines.Add('| --- | --- |') | Out-Null
    foreach ($run in $crossRuns) {
        $ledger = Join-Path $run.FullName 'CROSS_FEATURE_REPLAY_LEDGER.md'
        $cell = if (Test-Path -LiteralPath $ledger) { $ledger } else { $run.FullName }
        $lines.Add(('| {0} | `{1}` |' -f $run.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), (Convert-ToCell $cell))) | Out-Null
    }
}

$lines.Add('') | Out-Null
$lines.Add('## Non-Session Rule') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('- This file replaces host-bound memory for replay recovery.') | Out-Null
$lines.Add('- Host memory files may be used as historical notes, but runner artifacts and knowledge versions are the portable source of truth.') | Out-Null
$lines.Add('- Do not paste project-specific replay details into generic skills; promote only cross-project gates after review.') | Out-Null

$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
Set-Content -LiteralPath $OutputPath -Value ($lines -join "`n") -Encoding UTF8

if (-not $Quiet) {
    Write-Host "Replay session summary written: $OutputPath"
}
