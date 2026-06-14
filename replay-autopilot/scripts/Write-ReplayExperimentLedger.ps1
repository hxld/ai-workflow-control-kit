param(
    [string]$EvidenceRoot = '',
    [string]$ReplayRootBase = '',
    [string]$OutputRoot = '',
    [int]$MaxRoots = 120,
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Read-JsonIfExists {
    param([string]$Path)
    $text = Read-TextIfExists $Path
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    try {
        return $text | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-FirstText {
    param(
        [string]$Text,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
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
        $patterns = @(
            "(?m)^\s*-?\s*${decorated}\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*(?:/100)?\s*%?",
            "(?m)\|\s*${decorated}\s*\|\s*(?:\*\*)?${bt}?([0-9]+)${bt}?(?:\*\*)?\s*(?:/100)?\s*%?\s*\|",
            "(?m)${decorated}\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*(?:/100)?\s*%?"
        )
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($match.Success) {
                return [int]$match.Groups[1].Value
            }
        }
    }
    return $null
}

function Resolve-EvidenceRootFromReplayBase {
    param([string]$ReplayRootBaseFull)

    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($ReplayRootBaseFull))
    if ([string]::IsNullOrWhiteSpace($parent)) {
        return ''
    }
    return $parent
}

function Get-ReplayRoots {
    param(
        [string]$EvidenceRootFull,
        [string]$ReplayRootBaseFull,
        [int]$Limit
    )

    $items = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($ReplayRootBaseFull)) {
        $parent = Split-Path -Parent $ReplayRootBaseFull
        $leaf = Split-Path -Leaf $ReplayRootBaseFull
        if (Test-Path -LiteralPath $parent) {
            Get-ChildItem -LiteralPath $parent -Directory -Filter "$leaf-r*" -ErrorAction SilentlyContinue | ForEach-Object {
                $items.Add($_) | Out-Null
            }
        }
    } elseif (Test-Path -LiteralPath $EvidenceRootFull) {
        Get-ChildItem -LiteralPath $EvidenceRootFull -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue | ForEach-Object {
            $items.Add($_) | Out-Null
        }
        Get-ChildItem -LiteralPath $EvidenceRootFull -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notlike '_*' -and $_.Name -notlike 'claim-codex-replay-*'
        } | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue | ForEach-Object {
                $items.Add($_) | Out-Null
            }
        }
    }

    return @($items.ToArray() | Sort-Object `
            @{ Expression = {
                    $match = [regex]::Match($_.Name, '-r([0-9]+)$')
                    if ($match.Success) { [int]$match.Groups[1].Value } else { [int]::MaxValue }
                } },
            LastWriteTime |
            Select-Object -Last $Limit)
}

function Get-RootCombinedText {
    param([string]$Root)

    $names = @(
        'PLAN_TEST_COMPILE_EVIDENCE_POLICY_GATE.json',
        'PLAN_SCHEMA_FAILFAST.json',
        'PLAN_CONTRACT_VERIFY.json',
        'PLAN_VERDICT.json',
        'BLOCKER_FINGERPRINTS.json',
        'STAGNATION_DECISION.json',
        'FAILURE_AUDIT_PACK.json',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'AUTOPILOT_BLOCKER.md',
        'EVOLUTION_PROPOSAL.md',
        'ROUND_RESULT.md',
        'FINAL_REPLAY_REPORT.md',
        'PLAN_RESULT.json',
        'PLAN_RESULT.md'
    )

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        $text = Read-TextIfExists (Join-Path $Root $name)
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $parts.Add($text) | Out-Null
        }
    }
    return ($parts -join "`n")
}

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Get-RootFingerprints {
    param([string]$Text)

    $fps = New-Object System.Collections.Generic.List[string]
    $hasPolicyRebuildIssue = $Text -match 'policy_rebuild_(?:test_module_must_be_claim_server|expected_test_class_must_use_claim_server_harness|compile_dry_run_must_use_claim_server_am_test_compile|plan_invalid:test_harness_claim_core)'
    $hasPolicyContext = $Text -match 'policyNum|insureNum|rebuildTaskData|AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor'
    $hasClaimCoreHarness = $Text -match 'test_module_for_target["''\s:=]+claim-core|-pl\s+claim-core\s+-am\s+test-compile'
    if ($hasPolicyRebuildIssue -or ($hasPolicyContext -and $hasClaimCoreHarness)) {
        Add-UniqueString -List $fps -Value 'policy_rebuild_claim_core_harness'
    }
    if ($Text -match 'verification_capped_coverage\s*[:=]\s*0|low_verification_cap') {
        Add-UniqueString -List $fps -Value 'low_verification_cap'
    }
    if ($Text -match 'side_effect_ledger_gap|side effect') {
        Add-UniqueString -List $fps -Value 'side_effect_ledger_gap'
    }
    if ($Text -match 'plan_contract_verification_failed|Plan machine contract failed|PLAN_SCHEMA_INCOMPLETE|first_slice_proof_missing|schema_missing|policy_rebuild_plan_') {
        Add-UniqueString -List $fps -Value 'plan_format_drift'
    }
    if ($Text -match 'evolution_validation_fail|EVOLUTION_RESULT_VERIFY|FAIL_AFTER_REPAIR') {
        Add-UniqueString -List $fps -Value 'evolution_validation_fail'
    }
    if ($Text -match 'executor timed out|timeout after|timed out after') {
        Add-UniqueString -List $fps -Value 'executor_timeout'
    }
    if ($Text -match 'BUILD FAILURE|COMPILATION ERROR|test-compile.*FAIL') {
        Add-UniqueString -List $fps -Value 'build_or_compile_failure'
    }

    return @($fps.ToArray())
}

function Get-RootStage {
    param([string]$Root)

    $schema = Read-JsonIfExists (Join-Path $Root 'PLAN_SCHEMA_FAILFAST.json')
    if ($null -ne $schema -and [string]$schema.status -eq 'FAIL') {
        return 'PlanSchemaFailFast'
    }

    $contract = Read-JsonIfExists (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')
    if ($null -ne $contract -and [string]$contract.verification_status -eq 'FAIL') {
        return 'PlanContract'
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'FINAL_REPLAY_REPORT.md')) {
        return 'Phase2'
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'ROUND_RESULT.md')) {
        return 'Phase1'
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'PLAN_VERDICT.json')) {
        return 'Plan'
    }

    return 'Unknown'
}

function Get-RootRound {
    param([string]$Name)

    $match = [regex]::Match($Name, '-r([0-9]+)$')
    if ($match.Success) {
        return [int]$match.Groups[1].Value
    }
    return $null
}

function Get-WorktreeHead {
    param([string]$Root)

    $audit = Read-JsonIfExists (Join-Path $Root 'WORKTREE_HEAD_AUDIT.json')
    if ($null -eq $audit) {
        return ''
    }

    $head = ''
    if ($audit.PSObject.Properties.Name -contains 'events') {
        $events = @($audit.events)
        if ($events.Count -gt 0) {
            $lastEvent = @($events | Where-Object { $_.PSObject.Properties.Name -contains 'head' -and -not [string]::IsNullOrWhiteSpace([string]$_.head) } | Select-Object -Last 1)
            if ($lastEvent.Count -gt 0) {
                $head = [string]$lastEvent[0].head
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($head) -and $audit.PSObject.Properties.Name -contains 'initial_after_start_replay_round') {
        $head = [string]$audit.initial_after_start_replay_round
    }

    if (-not [string]::IsNullOrWhiteSpace($head)) {
        $head = $head.Trim()
        if ($head.Length -gt 12) {
            return $head.Substring(0, 12)
        }
        return $head
    }
    return ''
}

function Get-RootDescription {
    param(
        [string]$Root,
        [string]$CombinedText,
        [string]$Stage,
        [string[]]$Fingerprints
    )

    $contract = Read-JsonIfExists (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')
    if ($null -ne $contract -and $null -ne $contract.issues) {
        return (@($contract.issues | Select-Object -First 4) -join '; ')
    }

    $schema = Read-JsonIfExists (Join-Path $Root 'PLAN_SCHEMA_FAILFAST.json')
    if ($null -ne $schema) {
        $reason = if ($schema.PSObject.Properties.Name -contains 'reason') { [string]$schema.reason } else { '' }
        $status = if ($schema.PSObject.Properties.Name -contains 'status') { [string]$schema.status } else { '' }
        $fp = if ($schema.PSObject.Properties.Name -contains 'fingerprint') { [string]$schema.fingerprint } else { '' }
        return (@($status, $fp, $reason) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '; '
    }

    $finalStatus = Get-FirstText -Text $CombinedText -Patterns @(
        '(?m)^\s*-?\s*final_status\s*[:=]\s*([A-Z_]+)',
        '(?m)^\s*-?\s*final\s+status\s*[:=]\s*([A-Z_]+)',
        '(?m)^\s*-?\s*decision\s*[:=]\s*([A-Z_]+)'
    )
    if (-not [string]::IsNullOrWhiteSpace($finalStatus)) {
        return "final_status=$finalStatus"
    }

    if ($Fingerprints.Count -gt 0) {
        return (@($Fingerprints) -join '; ')
    }
    return $Stage
}

function Convert-ToTsvCell {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ').Trim()
}

function Convert-ToMarkdownCell {
    param([object]$Value)
    if ($null -eq $Value) { return '-' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '-' }
    return $text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

if ($ValidateOnly) {
    [pscustomobject]@{
        status = 'VALID'
        script = $PSCommandPath
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -and -not [string]::IsNullOrWhiteSpace($ReplayRootBase)) {
    $EvidenceRoot = Resolve-EvidenceRootFromReplayBase -ReplayRootBaseFull $ReplayRootBase
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    throw 'EvidenceRoot or ReplayRootBase is required.'
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
$replayRootBaseFull = if ([string]::IsNullOrWhiteSpace($ReplayRootBase)) { '' } else { Resolve-AbsolutePath $ReplayRootBase }
$outputRootFull = if ([string]::IsNullOrWhiteSpace($OutputRoot)) { Join-Path $evidenceRootFull '_control' } else { Resolve-AbsolutePath $OutputRoot }
New-Item -ItemType Directory -Force -Path $outputRootFull | Out-Null

$roots = @(Get-ReplayRoots -EvidenceRootFull $evidenceRootFull -ReplayRootBaseFull $replayRootBaseFull -Limit $MaxRoots)
$records = New-Object System.Collections.Generic.List[object]
$bestVerificationCap = $null

foreach ($root in $roots) {
    $combined = Get-RootCombinedText -Root $root.FullName
    $stage = Get-RootStage -Root $root.FullName
    $fingerprints = @(Get-RootFingerprints -Text $combined)
    $verificationCap = Get-MetricNumber -Text $combined -Names @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage', 'Verification Capped Coverage')
    $oracleCoverage = Get-MetricNumber -Text $combined -Names @('oracle_adjusted_coverage', 'oracle-adjusted coverage', 'Oracle Adjusted Coverage')
    $hasRoundResult = Test-Path -LiteralPath (Join-Path $root.FullName 'ROUND_RESULT.md')
    $isCrash = $combined -match '(?i)(executor timed out|timeout after|timed out after|outofmemory|oom|exception|stack trace|BUILD FAILURE|COMPILATION ERROR)'

    $status = 'discard'
    $statusReason = ''
    if ($isCrash) {
        $status = 'crash'
        $statusReason = 'executor_or_build_failure'
    } elseif ($hasRoundResult -and $verificationCap -ne $null) {
        if ($bestVerificationCap -eq $null -or [int]$verificationCap -gt [int]$bestVerificationCap) {
            $status = 'keep'
            $statusReason = 'verification_cap_improved'
            $bestVerificationCap = [int]$verificationCap
        } else {
            $status = 'discard'
            $statusReason = 'verification_cap_not_improved'
        }
    } elseif ($hasRoundResult) {
        $status = 'discard'
        $statusReason = 'round_result_missing_metric'
    } else {
        $status = 'discard'
        $statusReason = 'no_round_result'
    }

    $description = Get-RootDescription -Root $root.FullName -CombinedText $combined -Stage $stage -Fingerprints $fingerprints
    $records.Add([ordered]@{
            round = Get-RootRound -Name $root.Name
            root_name = $root.Name
            updated_at = $root.LastWriteTime.ToString('s')
            status = $status
            status_reason = $statusReason
            stage = $stage
            verification_capped_coverage = $verificationCap
            oracle_adjusted_coverage = $oracleCoverage
            fingerprints = @($fingerprints)
            worktree_head = Get-WorktreeHead -Root $root.FullName
            description = $description
            replay_root = $root.FullName
        }) | Out-Null
}

$jsonPath = Join-Path $outputRootFull 'REPLAY_EXPERIMENT_LEDGER.json'
$tsvPath = Join-Path $outputRootFull 'REPLAY_EXPERIMENT_LEDGER.tsv'
$mdPath = Join-Path $outputRootFull 'REPLAY_EXPERIMENT_LEDGER.md'

$summary = [ordered]@{
    schema = 'replay_experiment_ledger.v1'
    generated_at = (Get-Date).ToString('s')
    source_pattern = 'autoresearch_results_tsv_keep_discard'
    evidence_root = $evidenceRootFull
    replay_root_base = $replayRootBaseFull
    record_count = $records.Count
    latest = if ($records.Count -gt 0) { $records[$records.Count - 1] } else { $null }
    records = @($records.ToArray())
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$tsvLines = New-Object System.Collections.Generic.List[string]
$tsvLines.Add('round	updated_at	status	status_reason	stage	verification_capped_coverage	oracle_adjusted_coverage	fingerprints	worktree_head	description	replay_root') | Out-Null
foreach ($record in $records) {
    $tsvLines.Add((@(
                $record.round,
                $record.updated_at,
                $record.status,
                $record.status_reason,
                $record.stage,
                $record.verification_capped_coverage,
                $record.oracle_adjusted_coverage,
                (@($record.fingerprints) -join ','),
                $record.worktree_head,
                $record.description,
                $record.replay_root
            ) | ForEach-Object { Convert-ToTsvCell $_ }) -join "`t") | Out-Null
}
Set-Content -LiteralPath $tsvPath -Value ($tsvLines -join "`n") -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Replay Experiment Ledger') | Out-Null
$md.Add('') | Out-Null
$md.Add("- generated_at: $($summary.generated_at)") | Out-Null
$md.Add("- evidence_root: $evidenceRootFull") | Out-Null
$md.Add("- source_pattern: autoresearch results.tsv keep/discard loop") | Out-Null
$md.Add('') | Out-Null
$md.Add('| round | status | reason | stage | cap | oracle | fingerprints | description |') | Out-Null
$md.Add('|---|---|---|---|---:|---:|---|---|') | Out-Null
foreach ($record in @($records.ToArray() | Select-Object -Last 20)) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f `
                (Convert-ToMarkdownCell $record.round),
                (Convert-ToMarkdownCell $record.status),
                (Convert-ToMarkdownCell $record.status_reason),
                (Convert-ToMarkdownCell $record.stage),
                (Convert-ToMarkdownCell $record.verification_capped_coverage),
                (Convert-ToMarkdownCell $record.oracle_adjusted_coverage),
                (Convert-ToMarkdownCell (@($record.fingerprints) -join ', ')),
                (Convert-ToMarkdownCell $record.description))) | Out-Null
}
Set-Content -LiteralPath $mdPath -Value ($md -join "`n") -Encoding UTF8

if (-not $Quiet) {
    [pscustomobject]@{
        status = 'WROTE_LEDGER'
        json = $jsonPath
        tsv = $tsvPath
        markdown = $mdPath
        records = $records.Count
    }
}
