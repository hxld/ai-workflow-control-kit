param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.yaml'),
    [string]$EvidenceRoot = '',
    [string]$OutputRoot = '',
    [int]$MaxRoots = 160,
    [int]$MinOracleCoverage = 30,
    [switch]$RunAgent,
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-SimpleYaml {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^([^:]+):\s*(.*)$') { throw "Unsupported config line: $line" }
        $result[$matches[1].Trim()] = $matches[2].Trim().Trim('"').Trim("'")
    }
    return $result
}

function Get-ConfigValueOrDefault {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$DefaultValue = ''
    )
    if ($Config.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($Config[$Key])) {
        return $Config[$Key]
    }
    return $DefaultValue
}

function Convert-ToBool {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1', 'true', 'yes', 'y', 'on') -contains $Value.Trim().ToLowerInvariant()
}

function Resolve-EvidenceRootFromReplayBase {
    param([string]$ReplayRootBase)
    if ([string]::IsNullOrWhiteSpace($ReplayRootBase)) { return '' }
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($ReplayRootBase))
    $grandParent = Split-Path -Parent $parent
    if (-not [string]::IsNullOrWhiteSpace($grandParent) -and (Split-Path -Leaf $grandParent) -ieq 'replay-evidence') {
        return $grandParent
    }
    if ((Split-Path -Leaf $parent) -ieq 'replay-evidence') {
        return $parent
    }
    return $parent
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Convert-ToMetricNumber {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $clean = $Value.Trim().Trim('*').Trim('%').Trim()
    $number = 0.0
    if ([double]::TryParse($clean, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [math]::Round($number, 2)
    }
    return $null
}

function Get-FirstMetric {
    param(
        [string]$Text,
        [string[]]$LabelPatterns
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    foreach ($label in $LabelPatterns) {
        $patterns = @(
            "(?im)^\s*[-*]?\s*`?\**(?:$label)\**`?\s*(?:\([^)]*\))?\s*[:=]\s*\**([0-9]+(?:\.[0-9]+)?)\s*%?",
            "(?im)^\s*\|\s*[^|]*(?:$label)[^|]*\|\s*\**([0-9]+(?:\.[0-9]+)?)\s*%?\**\s*\|",
            "(?im)^\s*[-*]?\s*[^`r`n]*(?:$label)[^0-9`r`n]{0,80}\**([0-9]+(?:\.[0-9]+)?)\s*%?"
        )
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($Text, $pattern)
            if ($match.Success) {
                $value = Convert-ToMetricNumber $match.Groups[1].Value
                if ($null -ne $value) { return $value }
            }
        }
    }
    return $null
}

function Get-FirstTextValue {
    param(
        [string]$Text,
        [string[]]$LabelPatterns
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    foreach ($label in $LabelPatterns) {
        $patterns = @(
            "(?im)^\s*[-*]?\s*`?\**(?:$label)\**`?\s*[:=]\s*(.+?)\s*$",
            "(?im)^\s*\|\s*[^|]*(?:$label)[^|]*\|\s*(.+?)\s*\|"
        )
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($Text, $pattern)
            if ($match.Success) {
                return $match.Groups[1].Value.Trim().Trim('*').Trim()
            }
        }
    }
    return ''
}

function Get-FeatureNameFromRoot {
    param(
        [string]$EvidenceRoot,
        [string]$ReplayRoot
    )
    $evidenceFull = Resolve-AbsolutePath $EvidenceRoot
    $rootFull = Resolve-AbsolutePath $ReplayRoot
    if ($rootFull.Length -le $evidenceFull.Length) { return (Split-Path -Leaf $rootFull) }
    $relative = $rootFull.Substring($evidenceFull.Length).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($relative)) { return (Split-Path -Leaf $rootFull) }
    $first = ($relative -split '\\')[0]
    if ([string]::IsNullOrWhiteSpace($first)) { return (Split-Path -Leaf $rootFull) }
    return $first
}

function Find-ReplayRoots {
    param(
        [string]$EvidenceRoot,
        [int]$MaxRoots
    )
    $includeNames = @(
        'ROUND_RESULT.md',
        'FINAL_REPLAY_REPORT.md',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'DEEP_REVIEW_REPORT.md',
        'ROOT_CAUSE_LEDGER.json',
        'NEXT_EXPERIMENT_PLAN.md'
    )
    $files = New-Object System.Collections.Generic.List[string]
    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        $args = @('--files', $EvidenceRoot)
        foreach ($name in $includeNames) { $args += @('-g', $name) }
        $args += @(
            '-g', '!**/worktree/**',
            '-g', '!**/logs/**',
            '-g', '!**/.git/**',
            '-g', '!**/.tmp/**',
            '-g', '!**/_golden-samples/**'
        )
        $rgFiles = & rg @args
        if ($LASTEXITCODE -le 1 -and $rgFiles) {
            foreach ($path in $rgFiles) {
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                if ([System.IO.Path]::IsPathRooted($path)) {
                    $files.Add((Resolve-AbsolutePath $path)) | Out-Null
                } else {
                    $files.Add((Resolve-AbsolutePath (Join-Path $EvidenceRoot $path))) | Out-Null
                }
            }
        }
    } else {
        Get-ChildItem -Path $EvidenceRoot -Recurse -File -Force | Where-Object {
            $includeNames -contains $_.Name -and
            $_.FullName -notmatch '\\(worktree|logs|\.git|\.tmp|_golden-samples)\\'
        } | ForEach-Object { $files.Add($_.FullName) | Out-Null }
    }

    $byRoot = @{}
    foreach ($file in ($files | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $root = Split-Path -Parent $file
        if (-not $byRoot.ContainsKey($root)) {
            $byRoot[$root] = [pscustomobject]@{
                Root = $root
                LastWriteTime = (Get-Item -LiteralPath $file).LastWriteTime
            }
        } else {
            $last = (Get-Item -LiteralPath $file).LastWriteTime
            if ($last -gt $byRoot[$root].LastWriteTime) {
                $byRoot[$root].LastWriteTime = $last
            }
        }
    }

    return @($byRoot.Values | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxRoots)
}

function Get-GapFlags {
    return @(
        'wrong_test_surface',
        'core_entry_unclosed',
        'side_effect_ledger_gap',
        'executable_surface_slice_gap',
        'exact_contract_gap',
        'behavior_test_charter_gap',
        'static_only',
        'mock_only',
        'helper_only',
        'carrier_search_missing',
        'horizontal_slice_minimum_not_met',
        'non_authorizing_evidence',
        'red_phase_missing',
        'green_phase_missing',
        'oracle_first_planning',
        'selected_real_entry_missing',
        'first_slice_proof_missing'
    )
}

function Analyze-ReplayRoot {
    param(
        [string]$EvidenceRoot,
        [string]$ReplayRoot
    )
    $names = @(
        'ROUND_RESULT.md',
        'FINAL_REPLAY_REPORT.md',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'DEEP_REVIEW_REPORT.md',
        'ROOT_CAUSE_LEDGER.json',
        'NEXT_EXPERIMENT_PLAN.md'
    )
    $textParts = New-Object System.Collections.Generic.List[string]
    $present = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        $path = Join-Path $ReplayRoot $name
        if (Test-Path -LiteralPath $path) {
            $present.Add($name) | Out-Null
            $textParts.Add((Read-TextIfExists $path)) | Out-Null
        }
    }
    $text = ($textParts -join "`n`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $oracle = Get-FirstMetric -Text $text -LabelPatterns @(
        'oracle[_ -]*adjusted[_ -]*coverage',
        'oracle[_ -]*coverage',
        'Oracle Coverage \(Post-Hoc\)'
    )
    $verification = Get-FirstMetric -Text $text -LabelPatterns @(
        'verification[_ -]*capped[_ -]*coverage',
        'Replay Coverage \(Verification Capped\)',
        'verification capped',
        '验证上限'
    )
    $blind = Get-FirstMetric -Text $text -LabelPatterns @(
        'blind[_ -]*self[_ -]*assessed[_ -]*coverage',
        'Replay Coverage \(Self-Assessed\)',
        'blind coverage',
        '盲目'
    )
    $finalStatus = Get-FirstTextValue -Text $text -LabelPatterns @(
        'final[_ -]*status',
        'final post-hoc status',
        'final status'
    )
    $decision = Get-FirstTextValue -Text $text -LabelPatterns @(
        'AUTOPILOT_DECISION',
        'decision'
    )

    $gapObjects = New-Object System.Collections.Generic.List[object]
    foreach ($flag in Get-GapFlags) {
        $pattern = [regex]::Escape($flag)
        $count = [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
        if ($count -gt 0) {
            $gapObjects.Add([ordered]@{ flag = $flag; count = $count }) | Out-Null
        }
    }
    $gapCount = $gapObjects.Count
    $oracleValue = if ($null -ne $oracle) { [double]$oracle } else { 0.0 }
    $verificationValue = if ($null -ne $verification) { [double]$verification } else { 0.0 }
    $blindValue = if ($null -ne $blind) { [double]$blind } else { 0.0 }
    $hasFinal = $present -contains 'FINAL_REPLAY_REPORT.md'
    $hasDeepReview = $present -contains 'DEEP_REVIEW_REPORT.md'
    $divergencePenalty = [math]::Max(0, $blindValue - [math]::Max($verificationValue, $oracleValue))
    $score = ($oracleValue * 3.0) + ($verificationValue * 2.0) + ($blindValue * 0.25)
    if ($hasFinal) { $score += 10 }
    if ($hasDeepReview) { $score += 5 }
    $score = $score - ($gapCount * 2.0) - $divergencePenalty
    $antiScore = $gapCount * 8.0
    if ($blindValue -ge 60 -and [math]::Max($verificationValue, $oracleValue) -le 30) {
        $antiScore += ($blindValue - [math]::Max($verificationValue, $oracleValue))
    }
    if ($decision -match '(?i)STOP|BLOCKED|DEEP_REVIEW') { $antiScore += 12 }

    return [pscustomobject]@{
        feature = (Get-FeatureNameFromRoot -EvidenceRoot $EvidenceRoot -ReplayRoot $ReplayRoot)
        replay_root = $ReplayRoot
        last_write_time = (Get-Item -LiteralPath $ReplayRoot).LastWriteTime.ToString('s')
        oracle_adjusted_coverage = $oracle
        verification_capped_coverage = $verification
        blind_self_assessed_coverage = $blind
        final_status = $finalStatus
        decision = $decision
        present_artifacts = $present.ToArray()
        gap_flags = $gapObjects.ToArray()
        gap_flag_count = $gapCount
        candidate_score = [math]::Round($score, 2)
        anti_pattern_score = [math]::Round($antiScore, 2)
        has_final_report = $hasFinal
        has_deep_review = $hasDeepReview
    }
}

function New-GapSummary {
    param([object[]]$Items)
    $counts = @{}
    foreach ($item in $Items) {
        foreach ($gap in @($item.gap_flags)) {
            if (-not $counts.ContainsKey($gap.flag)) { $counts[$gap.flag] = 0 }
            $counts[$gap.flag] += [int]$gap.count
        }
    }
    return @($counts.Keys | Sort-Object { $counts[$_] } -Descending | ForEach-Object {
        [pscustomobject]@{ flag = $_; count = $counts[$_] }
    })
}

function New-FeatureSummary {
    param([object[]]$Items)
    return @($Items | Group-Object feature | Sort-Object Name | ForEach-Object {
        $groupItems = @($_.Group)
        $bestOracle = @($groupItems | Where-Object { $null -ne $_.oracle_adjusted_coverage } | Sort-Object oracle_adjusted_coverage -Descending | Select-Object -First 1)
        $bestVerification = @($groupItems | Where-Object { $null -ne $_.verification_capped_coverage } | Sort-Object verification_capped_coverage -Descending | Select-Object -First 1)
        [pscustomobject]@{
            feature = $_.Name
            replay_roots = $groupItems.Count
            best_oracle_adjusted_coverage = if ($bestOracle.Count -gt 0) { $bestOracle[0].oracle_adjusted_coverage } else { $null }
            best_verification_capped_coverage = if ($bestVerification.Count -gt 0) { $bestVerification[0].verification_capped_coverage } else { $null }
        }
    })
}

function Write-GoldenSampleMarkdown {
    param(
        [string]$OutputRoot,
        [object[]]$Candidates,
        [object[]]$AntiPatterns,
        [object[]]$GapSummary,
        [object[]]$FeatureSummary,
        [int]$ScannedCount
    )
    $sop = New-Object System.Collections.Generic.List[string]
    $sop.Add('# Golden Sample SOP')
    $sop.Add('')
    $sop.Add("- generated_at: $((Get-Date).ToString('s'))")
    $sop.Add("- source: deterministic replay evidence mining")
    $sop.Add("- scanned_replay_roots: $ScannedCount")
    $sop.Add('')
    $sop.Add('## Machine-Readable Rules')
    $sop.Add('')
    $sop.Add('- requirement_type: infer from current requirement and code surface only; do not copy feature-specific oracle facts from past replay.')
    $sop.Add('- first_carrier_selection: select the real production entry/orchestrator that owns the highest-weight behavior; DTO/entity/mapper/config/helper files cannot be the first carrier unless the requirement is purely schema-only.')
    $sop.Add('- forbidden_first_slice: helper-only, mock-only, static-only, file-presence-only, getter/setter-only, DTO-only, mapper-only, config-only, log-text-only.')
    $sop.Add('- required_red_test_shape: the first RED must fail on externally observable business behavior through a real entry or stateful carrier, not on missing scaffolding.')
    $sop.Add('- side_effect_evidence: coverage credit requires an assertion over DB/state/file/API/payload/export/page/task/log side effect that the requirement actually needs.')
    $sop.Add('- coverage_credit_rule: blind score cannot exceed verification-capped evidence; if oracle later contradicts the slice, lower score and evolve the gate.')
    $sop.Add('- stop_conditions: stop and evolve after repeated wrong_test_surface, core_entry_unclosed, side_effect_ledger_gap, exact_contract_gap, or executor/schema blocker recurrence.')
    $sop.Add('')
    $sop.Add('## Top Gap Signals')
    if ($GapSummary.Count -eq 0) {
        $sop.Add('- none observed')
    } else {
        foreach ($gap in @($GapSummary | Select-Object -First 12)) {
            $sop.Add(("- {0}: {1}" -f $gap.flag, $gap.count))
        }
    }
    $sop.Add('')
    $sop.Add('## Candidate Evidence')
    if ($Candidates.Count -eq 0) {
        $sop.Add('- no positive candidate found yet')
    } else {
        foreach ($item in @($Candidates | Select-Object -First 8)) {
            $sop.Add(("- {0} | oracle={1} | verification={2} | score={3} | root={4}" -f $item.feature, $item.oracle_adjusted_coverage, $item.verification_capped_coverage, $item.candidate_score, $item.replay_root))
        }
    }
    $sop.Add('')
    $sop.Add('## Anti-Pattern Evidence')
    if ($AntiPatterns.Count -eq 0) {
        $sop.Add('- no anti-pattern found yet')
    } else {
        foreach ($item in @($AntiPatterns | Select-Object -First 8)) {
            $flags = (@($item.gap_flags | Select-Object -First 5 | ForEach-Object { $_.flag }) -join ', ')
            $sop.Add(("- {0} | blind={1} | verification={2} | oracle={3} | flags={4} | root={5}" -f $item.feature, $item.blind_self_assessed_coverage, $item.verification_capped_coverage, $item.oracle_adjusted_coverage, $flags, $item.replay_root))
        }
    }
    Set-Content -LiteralPath (Join-Path $OutputRoot 'GOLDEN_SAMPLE_SOP.md') -Value ($sop -join "`n") -Encoding UTF8

    $prompt = New-Object System.Collections.Generic.List[string]
    $prompt.Add('# Golden Sample Control Prompt')
    $prompt.Add('')
    $prompt.Add('Use this as generic workflow control only. It is not oracle evidence and must not supply feature-specific implementation facts.')
    $prompt.Add('')
    $prompt.Add('## Mandatory Behavior')
    $prompt.Add('')
    $prompt.Add('1. Start from the highest-weight real production behavior, not from easy carriers.')
    $prompt.Add('2. The first slice must bind: requirement literal -> real entry/carrier -> failing behavioral test -> side-effect proof -> verification cap.')
    $prompt.Add('3. Reject first slices that only prove helper, DTO, mapper, config, static text, file presence, or mocks.')
    $prompt.Add('4. If public/deploy-facing behavior exists, the carrier and test must exercise that public/deploy-facing route or explicitly cap coverage.')
    $prompt.Add('5. If state changes, tasks, logs, exports, payloads, or generated artifacts are required, score only the part backed by executable evidence.')
    $prompt.Add('6. When the plan cannot name a real entry and executable first proof, stop with BLOCKED/INVALID_PLAN; do not fill the gap with prose.')
    $prompt.Add('')
    $prompt.Add('## Recurring Anti-Patterns To Avoid')
    foreach ($gap in @($GapSummary | Select-Object -First 10)) {
        $prompt.Add(("- {0}" -f $gap.flag))
    }
    if ($GapSummary.Count -eq 0) {
        $prompt.Add('- No mined gap signal yet; keep strict evidence gates.')
    }
    $prompt.Add('')
    $prompt.Add('## Coverage Honesty')
    $prompt.Add('')
    $prompt.Add('- Self-assessed coverage must be capped by executable verification evidence.')
    $prompt.Add('- Oracle post-hoc may only lower or calibrate confidence after blind implementation completes.')
    $prompt.Add('- A high blind score with low verification/oracle score is an anti-pattern, not progress.')
    Set-Content -LiteralPath (Join-Path $OutputRoot 'GOLDEN_SAMPLE_PROMPT.md') -Value ($prompt -join "`n") -Encoding UTF8

    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add('# Golden Sample Mining Summary')
    $summary.Add('')
    $summary.Add("- generated_at: $((Get-Date).ToString('s'))")
    $summary.Add("- scanned_replay_roots: $ScannedCount")
    $summary.Add("- candidate_count: $($Candidates.Count)")
    $summary.Add("- anti_pattern_count: $($AntiPatterns.Count)")
    $summary.Add('')
    $summary.Add('## Feature Coverage Snapshot')
    foreach ($feature in @($FeatureSummary | Select-Object -First 20)) {
        $summary.Add(("- {0}: roots={1}, best_oracle={2}, best_verification={3}" -f $feature.feature, $feature.replay_roots, $feature.best_oracle_adjusted_coverage, $feature.best_verification_capped_coverage))
    }
    $summary.Add('')
    $summary.Add('## Next Automatic Use')
    $summary.Add('')
    $summary.Add('- `Start-ReplayRound.ps1` may snapshot `GOLDEN_SAMPLE_PROMPT.md` and `GOLDEN_DELIVERY_SLICE_PROMPT.md` into the next replay root and append them to Phase0/Plan/Phase1 prompts.')
    $summary.Add('- `Run-ReplayLoop.ps1` refreshes this mining output, then generates the Golden Delivery Slice, after each run when `golden_sample_auto_mine: true`.')
    Set-Content -LiteralPath (Join-Path $OutputRoot 'GOLDEN_SAMPLE_SUMMARY.md') -Value ($summary -join "`n") -Encoding UTF8
}

$configPathFull = Resolve-AbsolutePath $ConfigPath
$config = Read-SimpleYaml -Path $configPathFull

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $configuredEvidenceRoot = Get-ConfigValueOrDefault -Config $config -Key 'evidence_root' -DefaultValue ''
    if (-not [string]::IsNullOrWhiteSpace($configuredEvidenceRoot)) {
        $EvidenceRoot = $configuredEvidenceRoot
    } else {
        $EvidenceRoot = Resolve-EvidenceRootFromReplayBase (Get-ConfigValueOrDefault -Config $config -Key 'replay_root_base' -DefaultValue '')
    }
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    throw "EvidenceRoot is required. Pass -EvidenceRoot or set replay_root_base/evidence_root in config."
}
$EvidenceRoot = Resolve-AbsolutePath $EvidenceRoot
if (-not (Test-Path -LiteralPath $EvidenceRoot)) {
    throw "EvidenceRoot not found: $EvidenceRoot"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $EvidenceRoot '_golden-samples'
}
$OutputRoot = Resolve-AbsolutePath $OutputRoot

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        ConfigPath = $configPathFull
        EvidenceRoot = $EvidenceRoot
        OutputRoot = $OutputRoot
        MaxRoots = $MaxRoots
        RunAgent = [bool]$RunAgent
    } | Format-List
    exit 0
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$roots = @(Find-ReplayRoots -EvidenceRoot $EvidenceRoot -MaxRoots $MaxRoots)
$items = New-Object System.Collections.Generic.List[object]
foreach ($rootInfo in $roots) {
    $item = Analyze-ReplayRoot -EvidenceRoot $EvidenceRoot -ReplayRoot $rootInfo.Root
    if ($null -ne $item) { $items.Add($item) | Out-Null }
}

$candidates = @($items | Where-Object {
    (($_.oracle_adjusted_coverage -ne $null) -and ([double]$_.oracle_adjusted_coverage -ge $MinOracleCoverage) -and
     ($_.verification_capped_coverage -ne $null) -and ([double]$_.verification_capped_coverage -ge 30)) -and
    $_.candidate_score -gt 0
} | Sort-Object candidate_score -Descending | Select-Object -First 30)

$antiPatterns = @($items | Where-Object {
    $_.anti_pattern_score -gt 0 -and (
        (($_.blind_self_assessed_coverage -ne $null) -and ([double]$_.blind_self_assessed_coverage -ge 60) -and
         ((($_.verification_capped_coverage -eq $null) -or ([double]$_.verification_capped_coverage -le 30) -or ($_.oracle_adjusted_coverage -eq $null) -or ([double]$_.oracle_adjusted_coverage -le 30)))) -or
        $_.gap_flag_count -ge 3
    )
} | Sort-Object anti_pattern_score -Descending | Select-Object -First 30)

$itemArray = $items.ToArray()
$gapSummary = @(New-GapSummary -Items $itemArray)
$featureSummary = @(New-FeatureSummary -Items $itemArray)

$ledger = [ordered]@{
    schema = 'golden_sample_mining.v1'
    generated_at = (Get-Date).ToString('s')
    evidence_root = $EvidenceRoot
    output_root = $OutputRoot
    scanned_replay_roots = $items.Count
    max_roots = $MaxRoots
    min_oracle_coverage = $MinOracleCoverage
    candidates = @($candidates)
    anti_patterns = @($antiPatterns)
    gap_summary = @($gapSummary)
    feature_summary = @($featureSummary)
}
$ledgerPath = Join-Path $OutputRoot 'GOLDEN_SAMPLE_LEDGER.json'
$ledger | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ledgerPath -Encoding UTF8
Write-GoldenSampleMarkdown -OutputRoot $OutputRoot -Candidates @($candidates) -AntiPatterns @($antiPatterns) -GapSummary @($gapSummary) -FeatureSummary @($featureSummary) -ScannedCount $items.Count

if ($RunAgent) {
    $promptTemplate = Join-Path (Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')) 'prompts\golden-sample-mining.prompt.md'
    if (-not (Test-Path -LiteralPath $promptTemplate)) {
        throw "Golden sample mining prompt template missing: $promptTemplate"
    }
    $agentPrompt = Join-Path $OutputRoot 'GOLDEN_SAMPLE_AI_REVIEW_PROMPT.md'
    $promptText = (Get-Content -LiteralPath $promptTemplate -Raw -Encoding UTF8).
        Replace('{{GOLDEN_SAMPLE_LEDGER}}', $ledgerPath).
        Replace('{{GOLDEN_SAMPLE_SOP}}', (Join-Path $OutputRoot 'GOLDEN_SAMPLE_SOP.md')).
        Replace('{{GOLDEN_SAMPLE_PROMPT}}', (Join-Path $OutputRoot 'GOLDEN_SAMPLE_PROMPT.md')).
        Replace('{{OUTPUT_PATH}}', (Join-Path $OutputRoot 'GOLDEN_SAMPLE_AI_REVIEW.md'))
    Set-Content -LiteralPath $agentPrompt -Value $promptText -Encoding UTF8
    $executor = Get-ConfigValueOrDefault -Config $config -Key 'executor' -DefaultValue 'codex'
    $timeoutMinutes = [int](Get-ConfigValueOrDefault -Config $config -Key 'executor_timeout_minutes' -DefaultValue '120')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-AgentPrompt.ps1') `
        -PromptPath $agentPrompt `
        -WorkDir (Resolve-AbsolutePath (Join-Path $PSScriptRoot '..')) `
        -LogDir (Join-Path $OutputRoot 'logs\golden-sample-ai-review') `
        -Executor $executor `
        -TimeoutMinutes $timeoutMinutes `
        -Name 'golden-sample-ai-review' `
        -CompletionPath (Join-Path $OutputRoot 'GOLDEN_SAMPLE_AI_REVIEW.md') `
        -CompletionQuietSeconds 60
    if ($LASTEXITCODE -ne 0) {
        throw "Golden sample AI review failed with exit code $LASTEXITCODE"
    }
}

if (-not $Quiet) {
    Write-Host "Golden sample mining completed."
    Write-Host "Evidence root: $EvidenceRoot"
    Write-Host "Output root: $OutputRoot"
    Write-Host "Scanned replay roots: $($items.Count)"
    Write-Host "Candidates: $($candidates.Count)"
    Write-Host "Anti-patterns: $($antiPatterns.Count)"
    Write-Host "Ledger: $ledgerPath"
}
