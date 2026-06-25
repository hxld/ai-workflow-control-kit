param(
    [string]$EvidenceRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT",
    [string]$ReplayRoot = '',
    [string]$OutputRoot = '',
    [int]$MaxRoots = 40,
    [int]$Lookback = 10,
    [int]$TargetCoverage = 90,
    [int]$MinOracleImprovement = 8,
    [int]$LowCapThreshold = 45,
    [int]$RepeatBlockerThreshold = 2,
    [string]$RequireExecutor = '',
    [int]$AuxiliaryTimeoutSeconds = 90,
    [switch]$SkipAuxiliaryArtifacts,
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
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Read-TextIfExists $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
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

function Convert-ToCell {
    param([object]$Value)
    if ($null -eq $Value) { return '-' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '-' }
    return $text.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-ReplayRoots {
    param(
        [string]$EvidenceRootFull,
        [string]$SingleReplayRoot,
        [int]$Limit
    )

    if (-not [string]::IsNullOrWhiteSpace($SingleReplayRoot)) {
        return @((Get-Item -LiteralPath (Resolve-AbsolutePath $SingleReplayRoot)))
    }

    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $EvidenceRootFull)) {
        return @()
    }

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

    return @($items.ToArray() | Sort-Object LastWriteTime -Descending | Select-Object -First $Limit)
}

function Get-FeatureName {
    param(
        [string]$EvidenceRootFull,
        [string]$Root
    )

    $parent = Split-Path -Parent $Root
    if ([System.IO.Path]::GetFullPath($parent).TrimEnd('\') -ieq $EvidenceRootFull.TrimEnd('\')) {
        return '(direct)'
    }
    return Split-Path -Leaf $parent
}

function Add-Fingerprint {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Add-String {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $List.Add($Value) | Out-Null
    }
}

function Invoke-ControlSummaryAuxiliary {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$Arguments,
        [string]$OutputRootFull,
        [int]$TimeoutSeconds
    )

    $timeout = [Math]::Max(1, $TimeoutSeconds)
    $safeName = ($Name -replace '[^A-Za-z0-9_-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'auxiliary' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdoutPath = Join-Path $OutputRootFull ("{0}-{1}.stdout.log" -f $safeName, $stamp)
    $stderrPath = Join-Path $OutputRootFull ("{0}-{1}.stderr.log" -f $safeName, $stamp)
    $timeoutPath = Join-Path $OutputRootFull ("{0}_AUXILIARY_TIMEOUT.json" -f $safeName.ToUpperInvariant().Replace('-', '_'))

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments
    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $argumentList `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    $completed = $process.WaitForExit($timeout * 1000)
    if (-not $completed) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [ordered]@{
            schema = 'replay_control_summary_auxiliary_timeout.v1'
            generated_at = (Get-Date).ToString('s')
            name = $Name
            script = $ScriptPath
            timeout_seconds = $timeout
            stdout = $stdoutPath
            stderr = $stderrPath
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $timeoutPath -Encoding UTF8
        return [pscustomobject]@{
            name = $Name
            completed = $false
            timed_out = $true
            exit_code = 124
            stdout = $stdoutPath
            stderr = $stderrPath
            timeout_marker = $timeoutPath
        }
    }

    $exitCode = if ($null -eq $process.ExitCode) { 1 } else { [int]$process.ExitCode }
    return [pscustomobject]@{
        name = $Name
        completed = $true
        timed_out = $false
        exit_code = $exitCode
        stdout = $stdoutPath
        stderr = $stderrPath
        timeout_marker = ''
    }
}

function Get-VerificationIssues {
    param([string]$Root)

    $issues = New-Object System.Collections.Generic.List[string]
    $verificationFiles = @(
        'PHASE0_CONTRACT_VERIFY.json',
        'PHASE0_CARRIER_EVIDENCE_VERIFY.json',
        'PLAN_TEST_COMPILE_EVIDENCE_POLICY_GATE.json',
        'PLAN_SCHEMA_FAILFAST.json',
        'PLAN_VERDICT.json',
        'PLAN_CONTRACT_VERIFY.json',
        'EVOLUTION_RESULT_VERIFY.json',
        'DRY_RUN_GATE.json'
    )

    foreach ($name in $verificationFiles) {
        $path = Join-Path $Root $name
        $json = Read-JsonIfExists $path
        if ($null -eq $json) { continue }

        Add-String -List $issues -Value "${name}:status:$($json.verification_status)"
        if (-not [string]::IsNullOrWhiteSpace([string]$json.status)) {
            Add-String -List $issues -Value "${name}:status:$($json.status)"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$json.fingerprint)) {
            Add-String -List $issues -Value "${name}:fingerprint:$($json.fingerprint)"
            Add-String -List $issues -Value ([string]$json.fingerprint)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$json.reason)) {
            Add-String -List $issues -Value "${name}:reason:$($json.reason)"
        }
        foreach ($issue in @($json.issues)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$issue)) {
                Add-String -List $issues -Value "${name}:issue:$issue"
                Add-String -List $issues -Value ([string]$issue)
            }
        }
        foreach ($warning in @($json.warnings)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
                Add-String -List $issues -Value "${name}:warning:$warning"
            }
        }
        foreach ($reason in @($json.reasons)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$reason)) {
                Add-String -List $issues -Value "${name}:reason:$reason"
            }
        }
        foreach ($gap in @($json.gap_flags)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$gap)) {
                Add-String -List $issues -Value "${name}:gap:$gap"
                Add-String -List $issues -Value ([string]$gap)
            }
        }
        if ($null -ne $json.checks) {
            foreach ($issue in @($json.checks.test_infrastructure_issues)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$issue)) {
                    Add-String -List $issues -Value "${name}:test_infrastructure_issue:$issue"
                    Add-String -List $issues -Value ([string]$issue)
                }
            }
            foreach ($issue in @($json.checks.side_effect_issues)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$issue)) {
                    Add-String -List $issues -Value "${name}:side_effect_issue:$issue"
                    Add-String -List $issues -Value ([string]$issue)
                }
            }
        }
    }

    return @($issues.ToArray())
}

function Get-FingerprintsFromText {
    param(
        [string]$Text,
        [object]$ExecutorAudit,
        [string]$RequiredExecutor
    )

    $fingerprints = New-Object System.Collections.Generic.List[string]

    $patterns = [ordered]@{
        'policy_rebuild_claim_core_harness' = 'policy_rebuild_(?:test_module_must_be_claim_server|expected_test_class_must_use_claim_server_harness|compile_dry_run_must_use_claim_server_am_test_compile|plan_invalid:test_harness_claim_core)|(?s)(?=.*(?:policyNum|insureNum|rebuildTaskData|AiApplyClaimApiTaskProcessor|AiCalculateLossApiTaskProcessor))(?=.*(?:test_module_for_target["''\s:=]+claim-core|-pl\s+claim-core\s+-am\s+test-compile))'
        'wrong_test_surface' = 'wrong_test_surface|wrong test surface|helper/static green|static-only|mock-only|test surface'
        'core_entry_unclosed' = 'core_entry_unclosed|core entry|real entry.*missing|entry.*not closed'
        'side_effect_ledger_gap' = 'side_effect_ledger_gap|side effect|DB side effect|state.*progress|transaction'
        'executable_surface_slice_gap' = 'executable_surface_slice_gap|deploy-facing|executable surface|compile-only'
        'exact_contract_gap' = 'exact_contract_gap|contract drift|field mismatch|literal drift'
        'phase0_oracle_contamination' = 'phase0_oracle_inferred_selected_entry|oracle.*selected.*entry|selected.*entry.*oracle|oracle contamination'
        'schema_contract_discovery_gap' = 'schema_verification_gap|new_table_structure_gap|schema_exact_discovery_ledger_missing|schema_exact_discovery_evidence_missing|phase0_blocked_on_oracle_or_schema_uncertainty|phase0_manual_oracle_wait'
        'phase0_carrier_evidence_gap' = 'phase0_carrier_search_commands_missing|phase0_selected_real_entry_missing|phase0_selected_real_entry_invalid_format|phase0_selected_real_entry_not_found|phase0_selected_real_entry_not_baseline_existing|phase0_carrier_claim_hallucinated'
        'plan_format_drift' = 'first_slice_proof_(?:missing|invalid|schema)|schema_missing|format drift|BLOCKED_PLAN_MISMATCH|plan_contract_verification_failed|plan_status_not_proceed'
        'phase0_format_drift' = 'phase0_status.*not found|STOP_PHASE0_PARSE_FAILURE|phase0 parse|exploration_missing|selected_real_entry_missing|requirement literal inventory'
        'protected_root_isolation_violation' = 'protected_root_pom_forbidden|protected_root_modified|protected main project root|protected root'
        'executor_credit_required' = 'executor_credit_required|402\s+Credit|required account credit|credit required|positive balance|required for this model|insufficient credits|not enough credits'
        'executor_resource_or_crash' = '429|503|rate limit|usage_limit|timeout|API 400|API 503|No available channel|server-side issue|inference gateway|executor_failed_without_result|executor crash'
        'evolution_validation_fail' = 'FAIL_AFTER_REPAIR|EVOLUTION_RESULT_VERIFY|knowledge_repo_commit_or_push_blocked|validation.*fail'
        'low_verification_cap' = 'verification_capped_coverage:\s*(?:0|[1-9]|[1-3][0-9]|4[0-5])\b'
    }

    foreach ($key in $patterns.Keys) {
        if ($Text -match $patterns[$key]) {
            Add-Fingerprint -List $fingerprints -Value $key
        }
    }

    if ($null -ne $ExecutorAudit) {
        $executor = [string]$ExecutorAudit.executor
        $policy = [string]$ExecutorAudit.policy
        $allowCodex = [string]$ExecutorAudit.allow_codex_executor
        if (-not [string]::IsNullOrWhiteSpace($RequiredExecutor) -and -not [string]::IsNullOrWhiteSpace($executor) -and $executor -ne $RequiredExecutor) {
            Add-Fingerprint -List $fingerprints -Value 'executor_policy_violation'
        }
        if ($executor -eq 'codex' -and $allowCodex -ne 'True' -and $allowCodex -ne 'true') {
            Add-Fingerprint -List $fingerprints -Value 'codex_used_as_primary_executor'
        }
        if ($policy -eq 'blocked') {
            Add-Fingerprint -List $fingerprints -Value 'executor_policy_violation'
        }
    }

    return @($fingerprints.ToArray())
}

function Get-ExecutorFailureEvidenceText {
    param([string]$Root)
    $logsRoot = Join-Path $Root 'logs'
    if (-not (Test-Path -LiteralPath $logsRoot)) { return '' }

    $evidence = New-Object System.Collections.Generic.List[string]
    $metaFiles = @(Get-ChildItem -LiteralPath $logsRoot -Recurse -File -Filter '*.exec.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 20)
    foreach ($metaFile in $metaFiles) {
        $meta = Read-JsonIfExists $metaFile.FullName
        if ($null -eq $meta) { continue }
        $category = [string]$meta.failure_category
        $executorExitCode = [string]$meta.executor_exit_code
        $stdoutLog = [string]$meta.stdout_log
        $stderrLog = [string]$meta.stderr_log
        if (-not [string]::IsNullOrWhiteSpace($category) -or -not [string]::IsNullOrWhiteSpace($executorExitCode)) {
            $evidence.Add(("executor_meta: {0}; failure_category={1}; executor_exit_code={2}" -f $metaFile.FullName, $category, $executorExitCode)) | Out-Null
        }
        foreach ($logPath in @($stdoutLog, $stderrLog)) {
            if ([string]::IsNullOrWhiteSpace($logPath) -or -not (Test-Path -LiteralPath $logPath)) { continue }
            $text = Read-TextIfExists $logPath
            if ($text -match '(?i)\b402\b|\b503\b|credit required|positive balance|required for this model|insufficient credits|not enough credits|usage limit|rate.?limit|too.?many.?requests|no available channel|server-side issue|inference gateway|gateway|authentication|unauthorized') {
                $excerpt = $text.Trim()
                if ($excerpt.Length -gt 1200) { $excerpt = $excerpt.Substring(0, 1200) }
                $evidence.Add(("executor_log: {0}`n{1}" -f $logPath, $excerpt)) | Out-Null
            }
        }
    }

    return (@($evidence.ToArray()) -join "`n")
}

function Read-ControlReplay {
    param(
        [string]$EvidenceRootFull,
        [string]$Root,
        [string]$RequiredExecutor
    )

    $summaryText = Read-TextIfExists (Join-Path $Root 'AUTOPILOT_SUMMARY.md')
    $decisionText = Read-TextIfExists (Join-Path $Root 'AUTOPILOT_DECISION.md')
    $roundText = Read-TextIfExists (Join-Path $Root 'ROUND_RESULT.md')
    $finalText = Read-TextIfExists (Join-Path $Root 'FINAL_REPLAY_REPORT.md')
    $stopLossText = Read-TextIfExists (Join-Path $Root 'STOP_LOSS_DECISION.md')
    $deepReviewText = Read-TextIfExists (Join-Path $Root 'DEEP_REVIEW_REPORT.md')
    $evolutionVerifyText = Read-TextIfExists (Join-Path $Root 'EVOLUTION_RESULT_VERIFY.json')
    $blockerText = Read-TextIfExists (Join-Path $Root 'AUTOPILOT_BLOCKER.md')
    $verificationIssues = Get-VerificationIssues -Root $Root
    $verificationIssueText = @($verificationIssues) -join "`n"
    $executorFailureText = Get-ExecutorFailureEvidenceText -Root $Root
    $combined = "$summaryText`n$decisionText`n$roundText`n$finalText`n$stopLossText`n$deepReviewText`n$evolutionVerifyText`n$blockerText`n$verificationIssueText`n$executorFailureText"
    $executorAudit = Read-JsonIfExists (Join-Path $Root 'EXECUTOR_AUDIT.json')
    $item = Get-Item -LiteralPath $Root

    $decision = Get-FirstText $decisionText @(
        '(?m)^\s*-\s*decision\s*:\s*`?([A-Z0-9_]+)`?',
        '(?m)^\s*decision\s*[:=]\s*`?([A-Z0-9_]+)`?'
    )
    $circuitBreaker = Get-FirstText $decisionText @(
        '(?m)^\s*-\s*circuit_breaker\s*:\s*`?([A-Z0-9_]+)`?'
    )
    if ([string]::IsNullOrWhiteSpace($decision) -and -not [string]::IsNullOrWhiteSpace($circuitBreaker)) {
        $decision = $circuitBreaker
    }

    $stopLossDecision = Get-FirstText $stopLossText @(
        '(?m)^\s*-\s*decision\s*:\s*`?([A-Z0-9_]+)`?'
    )

    $fingerprints = Get-FingerprintsFromText -Text $combined -ExecutorAudit $executorAudit -RequiredExecutor $RequiredExecutor
    $oracle = Get-MetricNumber $combined @('oracle_adjusted_coverage', 'oracle-adjusted coverage', 'oracle adjusted coverage', 'Oracle Coverage (Post-Hoc)')
    $cap = Get-MetricNumber $combined @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage', 'Replay Coverage (Verification Capped)')
    $blind = Get-MetricNumber $combined @('blind_self_assessed_coverage', 'blind coverage', 'Replay Coverage (Self-Assessed)')

    return [pscustomobject]@{
        feature = Get-FeatureName -EvidenceRootFull $EvidenceRootFull -Root $Root
        replay_root = $Root
        root_name = Split-Path -Leaf $Root
        updated = $item.LastWriteTime
        updated_text = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        phase0_status = Get-FirstText $summaryText @('(?m)^\s*-\s*phase0_status\s*:\s*`?([A-Z0-9_]+)`?')
        plan_status = Get-FirstText (Read-TextIfExists (Join-Path $Root 'PLAN_RESULT.md')) @('(?m)^\s*-\s*plan_status\s*:\s*`?([A-Z0-9_]+)`?', '(?m)^\s*plan_status\s*[:=]\s*`?([A-Z0-9_]+)`?')
        final_status = Get-FirstText $combined @('(?m)^\s*-\s*final_status\s*:\s*`?([A-Z0-9_]+)`?', '(?m)^\s*-\s*final(?: post-hoc)? status\s*:\s*`?([A-Z0-9_]+)`?')
        blind_self_assessed_coverage = $blind
        verification_capped_coverage = $cap
        oracle_adjusted_coverage = $oracle
        autopilot_decision = $decision
        stop_loss_decision = $stopLossDecision
        blocker_file = [bool](Test-Path -LiteralPath (Join-Path $Root 'AUTOPILOT_BLOCKER.md'))
        executor = if ($executorAudit) { [string]$executorAudit.executor } else { '' }
        require_executor = if ($executorAudit) { [string]$executorAudit.require_executor } else { '' }
        allow_codex_executor = if ($executorAudit) { [string]$executorAudit.allow_codex_executor } else { '' }
        executor_policy = if ($executorAudit) { [string]$executorAudit.policy } else { '' }
        verification_issues = @($verificationIssues)
        fingerprints = @($fingerprints)
    }
}

function New-BlockerRegistry {
    param([object[]]$Records)

    $registry = [ordered]@{}
    foreach ($record in $Records) {
        foreach ($fp in @($record.fingerprints)) {
            if (-not $registry.Contains($fp)) {
                $registry[$fp] = [ordered]@{
                    fingerprint = $fp
                    count = 0
                    features = @()
                    latest_root = ''
                    latest_updated = ''
                    roots = @()
                }
            }
            $entry = $registry[$fp]
            $entry.count = [int]$entry.count + 1
            if (@($entry.features) -notcontains $record.feature) {
                $entry.features = @($entry.features) + $record.feature
            }
            if ([string]::IsNullOrWhiteSpace($entry.latest_root) -or ([datetime]$record.updated -gt [datetime]$entry.latest_updated)) {
                $entry.latest_root = $record.replay_root
                $entry.latest_updated = $record.updated.ToString('s')
            }
            $entry.roots = @($entry.roots) + $record.replay_root
        }
    }
    return $registry
}

function New-ControlDecision {
    param(
        [object]$Latest,
        [object[]]$Records,
        [hashtable]$Registry,
        [int]$Target,
        [int]$MinImprovement,
        [int]$LowCap,
        [int]$RepeatThreshold,
        [int]$LookbackCount
    )

    $recent = @($Records | Sort-Object updated -Descending | Select-Object -First $LookbackCount)
    $prior = @($recent | Where-Object { $_.replay_root -ne $Latest.replay_root })
    $priorOracle = @($prior | Where-Object { $_.oracle_adjusted_coverage -ne $null } | ForEach-Object { [int]$_.oracle_adjusted_coverage })
    $bestPriorOracle = if ($priorOracle.Count -gt 0) { ($priorOracle | Measure-Object -Maximum).Maximum } else { $null }
    $oracleImprovement = if ($Latest.oracle_adjusted_coverage -ne $null -and $bestPriorOracle -ne $null) { [int]$Latest.oracle_adjusted_coverage - [int]$bestPriorOracle } else { $null }
    $reasons = New-Object System.Collections.Generic.List[string]
    $kind = 'CONTINUE'

    if (@($Latest.fingerprints) -contains 'executor_policy_violation' -or @($Latest.fingerprints) -contains 'codex_used_as_primary_executor') {
        $kind = 'STOPLINE'
        $reasons.Add('executor_policy_mismatch') | Out-Null
    }

    if ($Latest.blocker_file -and $Latest.autopilot_decision -notmatch 'CONTINUE|TARGET_REACHED') {
        $reasons.Add('autopilot_blocker_present') | Out-Null
    }

    if ($Latest.oracle_adjusted_coverage -ne $null -and [int]$Latest.oracle_adjusted_coverage -ge $Target) {
        if ($Latest.verification_capped_coverage -ne $null -and [int]$Latest.verification_capped_coverage -ge $Target) {
            $kind = 'STOPLINE'
            $reasons.Add('target_reached_preserve_evidence') | Out-Null
        } else {
            $kind = 'EVOLVE'
            $reasons.Add('oracle_verification_mismatch') | Out-Null
        }
    }

    if ($Latest.verification_capped_coverage -ne $null -and [int]$Latest.verification_capped_coverage -le $LowCap) {
        $reasons.Add("low_verification_cap:$($Latest.verification_capped_coverage)") | Out-Null
    }

    if ($null -ne $oracleImprovement -and $oracleImprovement -lt $MinImprovement) {
        $reasons.Add("no_substantive_oracle_improvement:$oracleImprovement") | Out-Null
    }

    $repeated = @()
    foreach ($fp in @($Latest.fingerprints)) {
        if ($Registry.Contains($fp) -and [int]$Registry[$fp].count -ge $RepeatThreshold) {
            $repeated += $fp
        }
    }
    if ($repeated.Count -gt 0) {
        $reasons.Add("repeated_blockers:$($repeated -join ',')") | Out-Null
    }

    if ($kind -ne 'STOPLINE') {
        if (@($Latest.fingerprints) -contains 'executor_credit_required') {
            $kind = 'STOPLINE'
            $reasons.Add('executor_credit_required_restore_balance_before_replay') | Out-Null
        } elseif (@($Latest.fingerprints) -contains 'executor_resource_or_crash') {
            $kind = 'UPGRADE'
            $reasons.Add('executor_retry_or_fallback_needed') | Out-Null
        } elseif ($reasons.Count -gt 0 -or $Latest.stop_loss_decision -eq 'STOP_DEEP_REVIEW_REQUIRED') {
            $kind = 'EVOLVE'
        }
    }

    $next = switch ($kind) {
        'CONTINUE' { 'Run the next bounded replay round.' }
        'STOPLINE' {
            if (@($Latest.fingerprints) -contains 'executor_credit_required') {
                'Restore Claude/executor credit or intentionally change executor policy; do not run another replay from this resource-only failure.'
            } else {
                'Stop unattended replay and preserve evidence before accepting more runs.'
            }
        }
        'UPGRADE' { 'Upgrade runner reliability or fallback handling before the next replay.' }
        'EVOLVE' { 'Run deep review / external practice / golden sample evolution before more blind replay.' }
        default { 'Inspect RUN_CONTROL_SUMMARY and AUTOPILOT_DECISION.' }
    }

    return [ordered]@{
        decision_kind = $kind
        reasons = @($reasons)
        repeated_blockers = @($repeated)
        best_prior_oracle = $bestPriorOracle
        oracle_improvement_over_prior_best = $oracleImprovement
        target_coverage = $Target
        low_cap_threshold = $LowCap
        recommended_next_step = $next
    }
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $EvidenceRoot '_control'
}

$evidenceRootFull = Resolve-AbsolutePath $EvidenceRoot
$outputRootFull = Resolve-AbsolutePath $OutputRoot

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        evidence_root = $evidenceRootFull
        replay_root = $ReplayRoot
        output_root = $outputRootFull
        max_roots = $MaxRoots
        lookback = $Lookback
        target_coverage = $TargetCoverage
        require_executor = $RequireExecutor
        auxiliary_timeout_seconds = $AuxiliaryTimeoutSeconds
        skip_auxiliary_artifacts = [bool]$SkipAuxiliaryArtifacts
    } | ConvertTo-Json -Depth 6
    exit 0
}

New-Item -ItemType Directory -Force -Path $outputRootFull | Out-Null
$rootItems = @(Get-ReplayRoots -EvidenceRootFull $evidenceRootFull -SingleReplayRoot $ReplayRoot -Limit $MaxRoots)
$records = @()
foreach ($item in $rootItems) {
    $records += Read-ControlReplay -EvidenceRootFull $evidenceRootFull -Root $item.FullName -RequiredExecutor $RequireExecutor
}

if ($records.Count -eq 0) {
    throw "No replay roots found under $evidenceRootFull"
}

$orderedRecords = @($records | Sort-Object updated -Descending)
$latest = $orderedRecords[0]
$registry = New-BlockerRegistry -Records $orderedRecords
$controlDecision = New-ControlDecision -Latest $latest -Records $orderedRecords -Registry $registry -Target $TargetCoverage -MinImprovement $MinOracleImprovement -LowCap $LowCapThreshold -RepeatThreshold $RepeatBlockerThreshold -LookbackCount $Lookback

$latestObject = [ordered]@{
    schema = 'replay_control_summary.v1'
    generated_at = (Get-Date).ToString('s')
    evidence_root = $evidenceRootFull
    latest = $latest
    control_decision = $controlDecision
    auxiliary_policy = [ordered]@{
        timeout_seconds = $AuxiliaryTimeoutSeconds
        skip_auxiliary_artifacts = [bool]$SkipAuxiliaryArtifacts
    }
    recent = @($orderedRecords | Select-Object -First $Lookback)
}

$stagnationObject = [ordered]@{
    schema = 'replay_stagnation_decision.v1'
    generated_at = (Get-Date).ToString('s')
    decision_kind = $controlDecision.decision_kind
    triggered = @('EVOLVE', 'UPGRADE', 'STOPLINE') -contains $controlDecision.decision_kind
    reasons = $controlDecision.reasons
    repeated_blockers = $controlDecision.repeated_blockers
    oracle_improvement_over_prior_best = $controlDecision.oracle_improvement_over_prior_best
    recommended_next_step = $controlDecision.recommended_next_step
}

$registryObject = [ordered]@{
    schema = 'replay_blocker_registry.v1'
    generated_at = (Get-Date).ToString('s')
    replay_count = $orderedRecords.Count
    blocker_count = $registry.Count
    blockers = $registry
}

$latestJson = Join-Path $outputRootFull 'RUN_CONTROL_LATEST.json'
$latestMd = Join-Path $outputRootFull 'RUN_CONTROL_LATEST.md'
$registryJson = Join-Path $outputRootFull 'BLOCKER_REGISTRY.json'
$briefMd = Join-Path $outputRootFull 'MORNING_BRIEF.md'

$latestObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJson -Encoding UTF8
$registryObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $registryJson -Encoding UTF8

$summaryJson = Join-Path $latest.replay_root 'RUN_CONTROL_SUMMARY.json'
$summaryMd = Join-Path $latest.replay_root 'RUN_CONTROL_SUMMARY.md'
$fingerprintsJson = Join-Path $latest.replay_root 'BLOCKER_FINGERPRINTS.json'
$stagnationJson = Join-Path $latest.replay_root 'STAGNATION_DECISION.json'
$latestObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryJson -Encoding UTF8
$stagnationObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $stagnationJson -Encoding UTF8
([ordered]@{
    schema = 'replay_blocker_fingerprints.v1'
    generated_at = (Get-Date).ToString('s')
    replay_root = $latest.replay_root
    fingerprints = @($latest.fingerprints)
    repeated_blockers = @($controlDecision.repeated_blockers)
}) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fingerprintsJson -Encoding UTF8

$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add('# Replay Control Summary') | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add("- generated_at: $($latestObject.generated_at)") | Out-Null
$mdLines.Add("- decision_kind: $($controlDecision.decision_kind)") | Out-Null
$mdLines.Add("- recommended_next_step: $($controlDecision.recommended_next_step)") | Out-Null
$mdLines.Add("- latest_replay_root: $($latest.replay_root)") | Out-Null
$mdLines.Add("- feature: $($latest.feature)") | Out-Null
$mdLines.Add("- executor: $($latest.executor)") | Out-Null
$mdLines.Add("- require_executor: $($latest.require_executor)") | Out-Null
$mdLines.Add("- executor_policy: $($latest.executor_policy)") | Out-Null
$mdLines.Add("- autopilot_decision: $($latest.autopilot_decision)") | Out-Null
$mdLines.Add("- stop_loss_decision: $($latest.stop_loss_decision)") | Out-Null
$mdLines.Add("- blind_self_assessed_coverage: $($latest.blind_self_assessed_coverage)") | Out-Null
$mdLines.Add("- verification_capped_coverage: $($latest.verification_capped_coverage)") | Out-Null
$mdLines.Add("- oracle_adjusted_coverage: $($latest.oracle_adjusted_coverage)") | Out-Null
$mdLines.Add('') | Out-Null
$mdLines.Add('## Verification Issues') | Out-Null
if (@($latest.verification_issues).Count -eq 0) {
    $mdLines.Add('- none') | Out-Null
} else {
    foreach ($issue in @($latest.verification_issues | Select-Object -First 20)) {
        $mdLines.Add("- $issue") | Out-Null
    }
}
$mdLines.Add('') | Out-Null
$mdLines.Add('## Reasons') | Out-Null
if (@($controlDecision.reasons).Count -eq 0) {
    $mdLines.Add('- none') | Out-Null
} else {
    foreach ($reason in @($controlDecision.reasons)) {
        $mdLines.Add("- $reason") | Out-Null
    }
}
$mdLines.Add('') | Out-Null
$mdLines.Add('## Blocker Fingerprints') | Out-Null
if (@($latest.fingerprints).Count -eq 0) {
    $mdLines.Add('- none') | Out-Null
} else {
    foreach ($fp in @($latest.fingerprints)) {
        $count = if ($registry.Contains($fp)) { $registry[$fp].count } else { 1 }
        $mdLines.Add("- ${fp}: count=$count") | Out-Null
    }
}
Set-Content -LiteralPath $summaryMd -Value ($mdLines -join "`n") -Encoding UTF8
Set-Content -LiteralPath $latestMd -Value ($mdLines -join "`n") -Encoding UTF8

$brief = New-Object System.Collections.Generic.List[string]
$brief.Add('# Replay Morning Brief') | Out-Null
$brief.Add('') | Out-Null
$brief.Add("- generated_at: $($latestObject.generated_at)") | Out-Null
$brief.Add("- control_decision: $($controlDecision.decision_kind)") | Out-Null
$brief.Add("- next_step: $($controlDecision.recommended_next_step)") | Out-Null
$brief.Add("- latest_replay: $($latest.replay_root)") | Out-Null
$brief.Add("- latest_coverage: blind=$($latest.blind_self_assessed_coverage), cap=$($latest.verification_capped_coverage), oracle=$($latest.oracle_adjusted_coverage)") | Out-Null
$brief.Add("- executor_policy: executor=$($latest.executor), required=$($latest.require_executor), policy=$($latest.executor_policy)") | Out-Null
$brief.Add('') | Out-Null
$brief.Add('## Recent Replay Rows') | Out-Null
$brief.Add('') | Out-Null
$brief.Add('| Updated | Feature | Root | Decision | Cap | Oracle | Fingerprints |') | Out-Null
$brief.Add('| --- | --- | --- | --- | ---: | ---: | --- |') | Out-Null
foreach ($record in @($orderedRecords | Select-Object -First ([Math]::Min($Lookback, $orderedRecords.Count)))) {
    $brief.Add(('| {0} | {1} | `{2}` | {3} | {4} | {5} | {6} |' -f `
        (Convert-ToCell $record.updated_text),
        (Convert-ToCell $record.feature),
        (Convert-ToCell $record.replay_root),
        (Convert-ToCell $record.autopilot_decision),
        (Convert-ToCell $record.verification_capped_coverage),
        (Convert-ToCell $record.oracle_adjusted_coverage),
        (Convert-ToCell (@($record.fingerprints) -join ',')))) | Out-Null
}
Set-Content -LiteralPath $briefMd -Value ($brief -join "`n") -Encoding UTF8

$failureAuditScript = Join-Path $PSScriptRoot 'Write-FailureAuditPack.ps1'
if (-not $SkipAuxiliaryArtifacts -and (Test-Path -LiteralPath $failureAuditScript)) {
    $failureAuditResult = Invoke-ControlSummaryAuxiliary `
        -Name 'failure-audit-pack' `
        -ScriptPath $failureAuditScript `
        -Arguments @(
            '-EvidenceRoot', $evidenceRootFull,
            '-ReplayRoot', $latest.replay_root,
            '-ControlSummaryPath', $latestJson,
            '-BlockerRegistryPath', $registryJson,
            '-Quiet'
        ) `
        -OutputRootFull $outputRootFull `
        -TimeoutSeconds $AuxiliaryTimeoutSeconds

    if ($failureAuditResult.timed_out) {
        Write-Warning "Failure audit pack generation timed out after $AuxiliaryTimeoutSeconds seconds; continuing control loop. Marker: $($failureAuditResult.timeout_marker)"
    } elseif ($failureAuditResult.exit_code -ne 0) {
        Write-Warning "Failure audit pack generation failed with exit code $($failureAuditResult.exit_code); continuing control loop. stderr: $($failureAuditResult.stderr)"
    } else {
        $failureAuditPath = Join-Path $latest.replay_root 'FAILURE_AUDIT_PACK.json'
        $failureAudit = Read-JsonIfExists $failureAuditPath
        if ($null -ne $failureAudit -and [bool]$failureAudit.golden_first_slice_required) {
            $goldenScript = Join-Path $PSScriptRoot 'Write-GoldenDeliverySlice.ps1'
            if (Test-Path -LiteralPath $goldenScript) {
                $goldenResult = Invoke-ControlSummaryAuxiliary `
                    -Name 'golden-delivery-slice' `
                    -ScriptPath $goldenScript `
                    -Arguments @(
                        '-EvidenceRoot', $evidenceRootFull,
                        '-ControlSummaryPath', $latestJson,
                        '-Quiet'
                    ) `
                    -OutputRootFull $outputRootFull `
                    -TimeoutSeconds $AuxiliaryTimeoutSeconds

                if ($goldenResult.timed_out) {
                    Write-Warning "Golden delivery slice generation timed out after $AuxiliaryTimeoutSeconds seconds; continuing control loop. Marker: $($goldenResult.timeout_marker)"
                } elseif ($goldenResult.exit_code -ne 0) {
                    Write-Warning "Golden delivery slice generation failed with exit code $($goldenResult.exit_code); continuing control loop. stderr: $($goldenResult.stderr)"
                }
            }
        }
    }
}

if (-not $Quiet) {
    Write-Host "Control decision: $($controlDecision.decision_kind)"
    Write-Host "Wrote $summaryMd"
    Write-Host "Wrote $latestMd"
    Write-Host "Wrote $briefMd"
}
