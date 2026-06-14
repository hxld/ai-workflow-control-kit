param(
    [string]$EvidenceRoot = '',
    [string]$ReplayRootBase = '',
    [int]$Lookback = 3,
    [int]$RepeatThreshold = 3,
    [int]$MinimumVerificationProgress = 5,
    [switch]$AllowRecentToolingChange,
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

function Add-UniqueString {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Get-StringArray {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text -split '\s*,\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
                if ($_.Name -notmatch '(?i)-aborted(?:-|$)|-archive(?:-|$)|-stale(?:-|$)') {
                    $items.Add($_) | Out-Null
                }
            }
        }
    } elseif (Test-Path -LiteralPath $EvidenceRootFull) {
        Get-ChildItem -LiteralPath $EvidenceRootFull -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notmatch '(?i)-aborted(?:-|$)|-archive(?:-|$)|-stale(?:-|$)'
        } | ForEach-Object {
            $items.Add($_) | Out-Null
        }
        Get-ChildItem -LiteralPath $EvidenceRootFull -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notlike '_*' -and $_.Name -notlike 'claim-codex-replay-*'
        } | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'claim-codex-replay-*' -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -notmatch '(?i)-aborted(?:-|$)|-archive(?:-|$)|-stale(?:-|$)'
            } | ForEach-Object {
                $items.Add($_) | Out-Null
            }
        }
    }

    return @($items.ToArray() | Sort-Object LastWriteTime -Descending | Select-Object -First $Limit)
}

function Get-RootCombinedText {
    param([string]$Root)

    $names = @(
        'ROUND_RESULT.md',
        'FINAL_REPLAY_REPORT.md',
        'STOP_OR_CONTINUE_DECISION.md',
        'STOP_LOSS_DECISION.md',
        'SLICE_VERIFY_01.json',
        'SLICE_AUTHORIZATION_01.json',
        'SLICE_RESULT_01.json',
        'PLAN_TEST_COMPILE_EVIDENCE_POLICY_GATE.json',
        'PLAN_SCHEMA_FAILFAST.json',
        'PLAN_CONTRACT_VERIFY.json',
        'PLAN_VERDICT.json',
        'BLOCKER_FINGERPRINTS.json',
        'RUN_CONTROL_SUMMARY.json',
        'STAGNATION_DECISION.json',
        'FAILURE_AUDIT_PACK.json',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'AUTOPILOT_BLOCKER.md',
        'EVOLUTION_PROPOSAL.md',
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
            "(?m)^\s*\|\s*${decorated}\s*\|\s*(?:\*\*)?${bt}?([0-9]+)${bt}?(?:\*\*)?\s*(?:/100)?\s*%?\s*\|",
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
    if ($Text -match 'plan_contract_verification_failed|Plan machine contract failed|PLAN_SCHEMA_INCOMPLETE|first_slice_proof_missing|schema_missing') {
        Add-UniqueString -List $fps -Value 'plan_format_drift'
    }
    if ($Text -match 'evolution_validation_fail|EVOLUTION_RESULT_VERIFY|FAIL_AFTER_REPAIR') {
        Add-UniqueString -List $fps -Value 'evolution_validation_fail'
    }

    return @($fps.ToArray())
}

function Get-RootStage {
    param([string]$Root)

    if (
        (Test-Path -LiteralPath (Join-Path $Root 'ROUND_RESULT.md')) -or
        (Test-Path -LiteralPath (Join-Path $Root 'FINAL_REPLAY_REPORT.md')) -or
        (Test-Path -LiteralPath (Join-Path $Root 'SLICE_VERIFY_01.json')) -or
        (Test-Path -LiteralPath (Join-Path $Root 'SLICE_AUTHORIZATION_01.json'))
    ) {
        return 'Phase1'
    }

    $schema = Read-JsonIfExists (Join-Path $Root 'PLAN_SCHEMA_FAILFAST.json')
    if ($null -ne $schema -and [string]$schema.status -eq 'FAIL') {
        return 'PlanSchemaFailFast'
    }

    $contract = Read-JsonIfExists (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')
    if ($null -ne $contract -and [string]$contract.verification_status -eq 'FAIL') {
        return 'PlanContract'
    }
    if ($null -ne $contract -and [string]$contract.verification_status -eq 'PASS') {
        return 'PlanReady'
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'PLAN_VERDICT.json')) {
        return 'Plan'
    }

    return 'Unknown'
}

function Get-RootDecisionTimestamp {
    param([string]$Root)

    $terminalDecisionArtifacts = @(
        'ROUND_RESULT.md',
        'PLAN_VERDICT.json',
        'AUTOPILOT_SUMMARY.md',
        'AUTOPILOT_DECISION.md',
        'AUTOPILOT_BLOCKER.md',
        'BLOCKER_FINGERPRINTS.json',
        'FAILURE_AUDIT_PACK.json'
    )

    $diagnosticArtifacts = @(
        'PLAN_SCHEMA_FAILFAST.json',
        'PLAN_CONTRACT_VERIFY.json'
    )

    $items = @()
    foreach ($name in $terminalDecisionArtifacts) {
        $path = Join-Path $Root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $items += Get-Item -LiteralPath $path
        }
    }
    if ($items.Count -gt 0) {
        return ($items | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }

    $diagnosticItems = @()
    foreach ($name in $diagnosticArtifacts) {
        $path = Join-Path $Root $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $diagnosticItems += Get-Item -LiteralPath $path
        }
    }
    if ($diagnosticItems.Count -gt 0) {
        return ($diagnosticItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }

    return (Get-Item -LiteralPath $Root).LastWriteTime
}

function Test-NoProgressRoot {
    param(
        [string]$Root,
        [string]$CombinedText,
        [string]$Stage,
        [int]$MinimumProgress
    )

    if ($Stage -eq 'PlanReady') {
        return $false
    }
    if ($Stage -in @('PlanSchemaFailFast', 'PlanContract', 'Plan')) {
        return $true
    }

    $verificationCap = Get-MetricNumber -Text $CombinedText -Names @(
        'verification_capped_coverage',
        'verification-capped coverage',
        'verification capped coverage',
        'Replay Coverage (Verification Capped)'
    )
    if ($null -ne $verificationCap -and [int]$verificationCap -lt $MinimumProgress) {
        return $true
    }

    $oracleAdjusted = Get-MetricNumber -Text $CombinedText -Names @(
        'oracle_adjusted_coverage',
        'oracle-adjusted coverage',
        'oracle adjusted coverage',
        'Oracle Coverage (Post-Hoc)'
    )
    $terminalBlocked = $CombinedText -match '(?i)STOP_AND_EVOLVE|STOP_BLOCKED|STOP_DEEP_REVIEW_REQUIRED|verification_status"?\s*:\s*"?(?:FAIL|PARTIAL)|authorization_blockers|AUTOPILOT_BLOCKER'
    if ($null -ne $oracleAdjusted -and [int]$oracleAdjusted -lt $MinimumProgress -and $terminalBlocked) {
        return $true
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'ROUND_RESULT.md')) {
        return $false
    }
    if ($CombinedText -match 'final_status\s*[:=]\s*BLOCKED|decision\s*:\s*STOP_BLOCKED|verification_capped_coverage\s*[:=]\s*0') {
        return $true
    }
    return $false
}

function Get-NewestToolingChange {
    $toolPaths = @(
        (Join-Path $PSScriptRoot 'Run-ReplayLoop.ps1'),
        (Join-Path $PSScriptRoot 'Run-SliceLoop.ps1'),
        (Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'),
        (Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1'),
        (Join-Path $PSScriptRoot 'SliceVerifier.ps1'),
        (Join-Path $PSScriptRoot 'FamilyRouterAndCap.ps1'),
        (Join-Path $PSScriptRoot 'phase0-precheck.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-EconomyCheckpoint.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-RedPhaseHardGate.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-ContractVerification.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-IncrementalVerification.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-TodoDetector.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-CarrierSearch.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-Phase0ContractReconciliation.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-ReflectionSufficiencyGate.ps1'),
        (Join-Path $PSScriptRoot 'Prepare-SliceEvidenceContracts.ps1'),
        (Join-Path $PSScriptRoot 'Build-NextSliceExactContract.ps1'),
        (Join-Path $PSScriptRoot 'Authorize-PreSliceEvidence.ps1'),
        (Join-Path $PSScriptRoot 'Validate-ExecutableEvidenceGate.ps1'),
        (Join-Path $PSScriptRoot 'v348_slice_quality_gate.ps1'),
        (Join-Path $PSScriptRoot 'verify-slice.ps1'),
        (Join-Path $PSScriptRoot 'verify-horizontal-slice.ps1'),
        (Join-Path $PSScriptRoot 'verify-test-charter.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-TodoPlaceholderCheck.ps1'),
        (Join-Path $PSScriptRoot 'Resolve-PythonLauncher.ps1'),
        (Join-Path $PSScriptRoot 'Write-ControlPlaneSummary.ps1'),
        (Join-Path $PSScriptRoot 'Write-FailureAuditPack.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-ReplayStoplineGate.ps1'),
        (Join-Path $PSScriptRoot 'Invoke-PlanSchemaFailFast.ps1')
    )

    $items = @($toolPaths | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ })
    if ($items.Count -eq 0) {
        return $null
    }
    return ($items | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        script = $PSCommandPath
        default_lookback = $Lookback
        default_repeat_threshold = $RepeatThreshold
        default_minimum_verification_progress = $MinimumVerificationProgress
    } | ConvertTo-Json -Depth 6
    exit 0
}

if ($Lookback -lt 1) { $Lookback = 3 }
if ($RepeatThreshold -lt 1) { $RepeatThreshold = 3 }
if ($MinimumVerificationProgress -lt 0) { $MinimumVerificationProgress = 5 }

$evidenceRootFull = if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) { Resolve-AbsolutePath $EvidenceRoot } else { '' }
$replayRootBaseFull = if (-not [string]::IsNullOrWhiteSpace($ReplayRootBase)) { Resolve-AbsolutePath $ReplayRootBase } else { '' }
if ([string]::IsNullOrWhiteSpace($evidenceRootFull) -and -not [string]::IsNullOrWhiteSpace($replayRootBaseFull)) {
    $evidenceRootFull = Split-Path -Parent $replayRootBaseFull
}
if ([string]::IsNullOrWhiteSpace($evidenceRootFull)) {
    throw 'EvidenceRoot or ReplayRootBase is required.'
}

$controlRoot = Join-Path $evidenceRootFull '_control'
New-Item -ItemType Directory -Force -Path $controlRoot | Out-Null

$roots = @(Get-ReplayRoots -EvidenceRootFull $evidenceRootFull -ReplayRootBaseFull $replayRootBaseFull -Limit $Lookback)
$records = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
    $combined = Get-RootCombinedText -Root $root.FullName
    $stage = Get-RootStage -Root $root.FullName
    $fps = @(Get-RootFingerprints -Text $combined)
    $decisionUpdated = Get-RootDecisionTimestamp -Root $root.FullName
    $noProgress = Test-NoProgressRoot -Root $root.FullName -CombinedText $combined -Stage $stage -MinimumProgress $MinimumVerificationProgress
    $records.Add([pscustomobject]@{
        root = $root.FullName
        name = $root.Name
        updated = $root.LastWriteTime
        updated_text = $root.LastWriteTime.ToString('s')
        decision_updated = $decisionUpdated
        decision_updated_text = $decisionUpdated.ToString('s')
        stage = $stage
        no_progress = $noProgress
        substantive_progress = (-not $noProgress)
        fingerprints = @($fps)
    }) | Out-Null
}

$fingerprintCounts = [ordered]@{}
foreach ($record in @($records.ToArray())) {
    foreach ($fp in @($record.fingerprints)) {
        if (-not $fingerprintCounts.Contains($fp)) {
            $fingerprintCounts[$fp] = 0
        }
        $fingerprintCounts[$fp] = [int]$fingerprintCounts[$fp] + 1
    }
}

$repeated = New-Object System.Collections.Generic.List[string]
foreach ($key in $fingerprintCounts.Keys) {
    if ([int]$fingerprintCounts[$key] -ge $RepeatThreshold) {
        Add-UniqueString -List $repeated -Value $key
    }
}

$allRecentNoProgress = $records.Count -ge $RepeatThreshold -and (@($records.ToArray() | Where-Object { -not [bool]$_.no_progress }).Count -eq 0)
if ($allRecentNoProgress -and $repeated.Count -eq 0) {
    Add-UniqueString -List $repeated -Value 'no_phase_advancement'
}

$triggered = $records.Count -ge $RepeatThreshold -and $allRecentNoProgress -and $repeated.Count -gt 0
$latest = if ($records.Count -gt 0) { $records[0] } else { $null }
$newestTool = Get-NewestToolingChange
$allowAfterToolingChange = $false
if ($triggered -and [bool]$AllowRecentToolingChange -and $null -ne $latest -and $null -ne $newestTool -and $newestTool.LastWriteTime -gt ([datetime]$latest.decision_updated)) {
    $allowAfterToolingChange = $true
}

$decision = if ($triggered -and -not $allowAfterToolingChange) {
    'STOPLINE_REPEATED_NO_PROGRESS'
} elseif ($triggered -and $allowAfterToolingChange) {
    'ALLOW_AFTER_TOOLING_CHANGE'
} else {
    'PASS'
}

$analysis = [ordered]@{
    schema = 'replay_stopline_gate.v1'
    generated_at = (Get-Date).ToString('s')
    evidence_root = $evidenceRootFull
    replay_root_base = $replayRootBaseFull
    lookback = $Lookback
    repeat_threshold = $RepeatThreshold
    minimum_verification_progress = $MinimumVerificationProgress
    decision = $decision
    triggered = $triggered
    allow_after_tooling_change = $allowAfterToolingChange
    newest_tooling_change = if ($newestTool) { $newestTool.FullName } else { '' }
    newest_tooling_change_time = if ($newestTool) { $newestTool.LastWriteTime.ToString('s') } else { '' }
    repeated_blockers = @($repeated.ToArray())
    latest_replay_root = if ($latest) { $latest.root } else { '' }
    records = @($records.ToArray())
}

$jsonPath = Join-Path $controlRoot 'STOPLINE_ANALYSIS.json'
$mdPath = Join-Path $controlRoot 'STOPLINE_ANALYSIS.md'
$analysis | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Replay Stopline Analysis') | Out-Null
$md.Add('') | Out-Null
$md.Add("- generated_at: $($analysis.generated_at)") | Out-Null
$md.Add("- decision: $decision") | Out-Null
$md.Add("- triggered: $triggered") | Out-Null
$md.Add("- repeated_blockers: $(@($repeated.ToArray()) -join ', ')") | Out-Null
$md.Add("- latest_replay_root: $($analysis.latest_replay_root)") | Out-Null
$md.Add("- minimum_verification_progress: $MinimumVerificationProgress") | Out-Null
$md.Add("- allow_after_tooling_change: $allowAfterToolingChange") | Out-Null
if ($newestTool) {
    $md.Add("- newest_tooling_change: $($newestTool.FullName)") | Out-Null
    $md.Add("- newest_tooling_change_time: $($newestTool.LastWriteTime.ToString('s'))") | Out-Null
}
$md.Add('') | Out-Null
$md.Add('## Recent Rounds') | Out-Null
$md.Add('') | Out-Null
$md.Add('| Root | Stage | No Progress | Substantive Progress | Fingerprints | Decision Updated | Root Updated |') | Out-Null
$md.Add('| --- | --- | --- | --- | --- | --- | --- |') | Out-Null
foreach ($record in @($records.ToArray())) {
    $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $record.name, $record.stage, $record.no_progress, $record.substantive_progress, ((@($record.fingerprints) -join ', ').Replace('|', '\|')), $record.decision_updated_text, $record.updated_text)) | Out-Null
}
$md.Add('') | Out-Null
$md.Add('## Rule') | Out-Null
$md.Add('') | Out-Null
$md.Add('After three no-substantive-progress rounds, unattended replay must stop unless a newer invoked runner/verifier/tooling change exists after the latest failure-decision artifact and will be validated before the next replay. A completed round with verification-capped coverage below the minimum progress threshold still counts as no progress. Directory LastWriteTime alone is not a failure timestamp because later control summaries can refresh it.') | Out-Null
Set-Content -LiteralPath $mdPath -Encoding UTF8 -Value ($md -join "`n")

if (-not $Quiet) {
    Write-Host "STOPLINE_GATE: $decision"
    Write-Host "Analysis: $mdPath"
}

if ($decision -eq 'STOPLINE_REPEATED_NO_PROGRESS') {
    exit 94
}

exit 0
