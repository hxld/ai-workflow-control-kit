param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
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
    param(
        [string]$Text,
        [string[]]$Names
    )

    $bt = [string][char]96
    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $patterns.Add("(?m)^\s*-?\s*${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?")
        $patterns.Add("(?m)^\s*\|\s*${bt}?${escaped}${bt}?\s*\|\s*${bt}?([0-9]+)${bt}?\s*%?\s*\|")
        $patterns.Add("(?m)${bt}?${escaped}${bt}?\s*[:=]\s*${bt}?([0-9]+)${bt}?\s*%?")
    }
    return Get-FirstNumber $Text $patterns.ToArray()
}

function Get-SummaryFlagCount {
    param([string]$Text, [string]$Flag)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $pattern = '(?m)^\s*-\s*' + [regex]::Escape($Flag) + '\s*:\s*([0-9]+)\s*$'
    $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

function New-VerifiableRuleItem {
    param(
        [string]$Id,
        [string]$Fingerprint,
        [string]$Severity = 'P0',
        [string]$OwnerLayer = 'replay-autopilot',
        [string]$MachineGate,
        [string]$PreventionGate,
        [string]$RequiredFix,
        [string]$RegressionTest,
        [string]$NextValidation
    )

    return [pscustomobject][ordered]@{
        id = $Id
        fingerprint = $Fingerprint
        severity = $Severity
        owner_layer = $OwnerLayer
        trigger = [ordered]@{
            fingerprint = $Fingerprint
            repeated = $true
            replay_count = 1
        }
        must_fix = $true
        prevention_gate = $PreventionGate
        required_fix = $RequiredFix
        regression_test = $RegressionTest
        next_validation = $NextValidation
        machine_gate = $MachineGate
        acceptance = @(
            "Invoked runner, prompt, verifier, schema, or gate change addresses machine_gate=$MachineGate.",
            "Regression evidence is present and PASS for: $RegressionTest",
            "Next validation evidence is present and PASS for: $NextValidation"
        )
        verification_status = 'PENDING'
    }
}

function Write-VerifiableRules {
    param(
        [string]$Root,
        [object[]]$Rules
    )

    if (@($Rules).Count -eq 0) {
        return
    }

    $rulesPath = Join-Path $Root 'VERIFIABLE_RULES.json'
    $rulesMdPath = Join-Path $Root 'VERIFIABLE_RULES.md'
    $generatedAt = (Get-Date).ToString('s')
    $pack = [ordered]@{
        schema = 'replay_verifiable_rule_pack.v1'
        generated_at = $generatedAt
        replay_root = $Root
        source_audit_pack = (Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')
        rules = @($Rules)
    }
    $pack | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $rulesPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Verifiable Replay Rules') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("- generated_at: $generatedAt") | Out-Null
    $lines.Add("- source_audit_pack: $(Join-Path $Root 'PLAN_CONTRACT_VERIFY.json')") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('| Rule | Fingerprint | Severity | Machine Gate | Verification Status |') | Out-Null
    $lines.Add('| --- | --- | --- | --- | --- |') | Out-Null
    foreach ($rule in @($Rules)) {
        $lines.Add("| $($rule.id) | $($rule.fingerprint) | $($rule.severity) | $($rule.machine_gate) | $($rule.verification_status) |") | Out-Null
    }
    Set-Content -LiteralPath $rulesMdPath -Encoding UTF8 -Value ($lines -join "`n")
}

$root = [System.IO.Path]::GetFullPath($ReplayRoot)
if (-not (Test-Path -LiteralPath $root)) {
    throw "Replay root not found: $root"
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $root 'EVOLUTION_PROPOSAL.md'
}

$roundResultPath = Join-Path $root 'ROUND_RESULT.md'
$finalReportPath = Join-Path $root 'FINAL_REPLAY_REPORT.md'
$summaryPath = Join-Path $root 'AUTOPILOT_SUMMARY.md'
$phase0ResultPath = Join-Path $root 'PHASE0_RESULT.md'

$phase0Text = Read-TextIfExists $phase0ResultPath
$roundText = Read-TextIfExists $roundResultPath
$finalText = Read-TextIfExists $finalReportPath
$summaryText = Read-TextIfExists $summaryPath
$combined = "$phase0Text`n$roundText`n$finalText`n$summaryText"

$blind = Get-MetricNumber $combined @('blind_self_assessed_coverage', 'blind coverage')
$capped = Get-MetricNumber $combined @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage')
$oracle = Get-MetricNumber $combined @('oracle_adjusted_coverage', 'oracle-adjusted coverage')

$flagMap = [ordered]@{
    invalid_plan = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Plan was rejected before implementation. Strengthen first-slice routing or keep the early stop as valid protection.'
    }
    invalid_replay = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Replay attempted an invalid first slice. Stop full implementation until the core path is selected.'
    }
    supporting_slice_first = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Supporting slice was selected before core path. Require core entry RED/GREEN before helper/config/log/OCR/report/export slices.'
    }
    core_first_plan_invalid = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Core-first plan is invalid. Require selected real entry, rejected alternatives, and first RED test before coding.'
    }
    core_entry_unclosed = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Core real entry is still unclosed. Route early budget to the highest-weight production entry before helper/supporting slices.'
    }
    real_entry_gap = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Implementation is not wired through the real entry. Require entry -> orchestration -> side effect -> proof closure.'
    }
    side_effect_ledger_gap = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'State/task/progress/log/persistence/transaction side effects are under-verified. Require side-effect ledger and executable proof.'
    }
    needs_transaction_test = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'Stateful behavior lacks DB/transaction/rollback verification. Require transaction-depth proof or explicit coverage cap.'
    }
    executable_surface_slice_gap = [pscustomobject]@{
        Gate = 'Surface Coverage Gate'
        Recommendation = 'High-weight deploy-facing surfaces lack executable minimum slices. Require surface -> carrier -> output -> proof closure.'
    }
    exact_contract_gap = [pscustomobject]@{
        Gate = 'Requirement Contract Gate'
        Recommendation = 'Field/column/flag/enum/payload/display contracts drifted. Require literal -> symbol -> wire/db/display -> assertion mapping.'
    }
    wrong_test_surface = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'Tests validated the wrong seam or internals. Prefer real entry/interface-level evidence over helper-only assertions.'
    }
    shallow_module = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'New abstraction may be shallow/pass-through. Require deletion test or collapse into the caller.'
    }
    feedback_loop_blocker = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'Runnable feedback loop is missing or blocked. Stop feature expansion until the blocker is classified.'
    }
    mock_behavior_gap = [pscustomobject]@{
        Gate = 'Executable Evidence Gate'
        Recommendation = 'Mock-only green is not enough for real behavior. Downgrade confidence unless real-entry or stateful proof exists.'
    }
    helper_only_surface_gap = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Helper/service exists but is not wired into real entry. Treat helper-only work as support, not completion.'
    }
    surface_budget_gap = [pscustomobject]@{
        Gate = 'Core-First Budget Gate'
        Recommendation = 'Budget still goes to low-risk helper/DTO/log slices. Route first slice to the highest-weight surface.'
    }
    plan_oracle_overlap_gap = [pscustomobject]@{
        Gate = 'Surface Coverage Gate'
        Recommendation = 'Plan oracle production file coverage is below the 50% threshold. Expand coverage by mapping missing production files to implementation slices, or document out-of-scope files with architectural separation reasons. The evolution proposal system must detect this gap to prevent no-op evolutions when the plan was BLOCKED by oracle overlap enforcement.'
    }
    plan_high_weight_oracle_overlap_gap = [pscustomobject]@{
        Gate = 'Surface Coverage Gate'
        Recommendation = 'Plan oracle high-weight production file coverage is below the 70% threshold. Core service, facade, and flow files must be covered before proceeding. The evolution proposal should flag this as tooling-evolution-needed.'
    }
    phase2_executor_blocker = [pscustomobject]@{
        Gate = 'Evolution Abstraction Gate'
        Recommendation = 'Phase2 executor failure prevented the normal final report/oracle path. Preserve deterministic fallback reporting, keep oracle credit at zero, and route the run into tooling evolution instead of stranding unattended control.'
    }
}

$detected = @(foreach ($key in $flagMap.Keys) {
    $summaryCount = Get-SummaryFlagCount -Text $summaryText -Flag $key
    $count = if ($summaryCount -ne $null) {
        $summaryCount
    } else {
        ([regex]::Matches($combined, [regex]::Escape($key))).Count
    }
    if ($count -gt 0) {
        $flagInfo = $flagMap[$key]
        $actionClass = if (@('invalid_plan', 'invalid_replay', 'supporting_slice_first', 'core_first_plan_invalid') -contains $key) {
            'workflow-gate-needs-evolution'
        } elseif (@('exact_contract_gap', 'executable_surface_slice_gap', 'core_entry_unclosed', 'real_entry_gap', 'side_effect_ledger_gap', 'needs_transaction_test', 'wrong_test_surface', 'shallow_module', 'feedback_loop_blocker', 'mock_behavior_gap', 'helper_only_surface_gap', 'surface_budget_gap') -contains $key) {
            'already-covered-but-not-enforced'
        } elseif (@('phase2_executor_blocker') -contains $key) {
            'tooling-evolution-needed'
        } else {
            'needs-more-replay-evidence'
        }
        [pscustomobject]@{
            Gate = $flagInfo.Gate
            Flag = $key
            Count = $count
            Recommendation = $flagInfo.Recommendation
            ActionClass = $actionClass
        }
    }
})

$planContractVerifyPath = Join-Path $root 'PLAN_CONTRACT_VERIFY.json'
$verifiableRules = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $planContractVerifyPath) {
    try {
        $planContract = Get-Content -LiteralPath $planContractVerifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $contractIssues = @($planContract.issues)

        if (($contractIssues | Where-Object { $_ -match 'oracle_overlap_below_threshold' } | Select-Object -First 1)) {
            $alreadyDetected = $detected | Where-Object { $_.Flag -eq 'plan_oracle_overlap_gap' }
            if (-not $alreadyDetected) {
                $detected += [pscustomobject]@{
                    Gate = 'Surface Coverage Gate'
                    Flag = 'plan_oracle_overlap_gap'
                    Count = 1
                    Recommendation = 'Plan oracle production file coverage is below the 50% threshold. Expand coverage by mapping missing production files to implementation slices, or document out-of-scope files with architectural separation reasons.'
                    ActionClass = 'tooling-evolution-needed'
                }
            }
            $verifiableRules.Add((New-VerifiableRuleItem `
                -Id 'rule_plan_oracle_overlap_enforced' `
                -Fingerprint 'oracle_overlap_below_threshold' `
                -MachineGate 'plan_oracle_overlap_enforced' `
                -PreventionGate 'Surface Coverage Gate' `
                -RequiredFix 'Make invoked plan repair and verification fail closed unless oracle production file overlap reaches the threshold or a verifier-recognized exemption is present.' `
                -RegressionTest 'scripts\Test-v600-OracleOverlapEvolutionProposalDetection.ps1' `
                -NextValidation 'scripts\Validate-VerifiableRuleClosure.ps1')) | Out-Null
        }
        if (($contractIssues | Where-Object { $_ -match 'oracle_high_weight_overlap_below_threshold' } | Select-Object -First 1)) {
            $alreadyDetected = $detected | Where-Object { $_.Flag -eq 'plan_high_weight_oracle_overlap_gap' }
            if (-not $alreadyDetected) {
                $detected += [pscustomobject]@{
                    Gate = 'Surface Coverage Gate'
                    Flag = 'plan_high_weight_oracle_overlap_gap'
                    Count = 1
                    Recommendation = 'Plan oracle high-weight production file coverage is below the 70% threshold. Core service, facade, and flow files must be covered before proceeding.'
                    ActionClass = 'tooling-evolution-needed'
                }
            }
            $verifiableRules.Add((New-VerifiableRuleItem `
                -Id 'rule_plan_high_weight_oracle_overlap_enforced' `
                -Fingerprint 'oracle_high_weight_overlap_below_threshold' `
                -MachineGate 'plan_high_weight_oracle_overlap_enforced' `
                -PreventionGate 'Surface Coverage Gate' `
                -RequiredFix 'Make invoked plan repair and verification fail closed unless high-weight oracle production file coverage reaches the threshold or a verifier-recognized exemption is present.' `
                -RegressionTest 'scripts\Test-v600-OracleOverlapEvolutionProposalDetection.ps1' `
                -NextValidation 'scripts\Validate-VerifiableRuleClosure.ps1')) | Out-Null
        }
        if (($contractIssues | Where-Object { $_ -match '(?i)_plan_missing:.*Context' } | Select-Object -First 1)) {
            $verifiableRules.Add((New-VerifiableRuleItem `
                -Id 'rule_source_chain_context_contract_enforced' `
                -Fingerprint 'source_chain_context_contract_missing' `
                -MachineGate 'source_chain_context_contract_enforced' `
                -PreventionGate 'Requirement Contract Gate' `
                -RequiredFix 'Require source-chain plans to name the upstream context carrier and the real builder path before Phase 1 can proceed.' `
                -RegressionTest 'scripts\Test-v626-PlanContractPolicyRebuildIntentGuard.ps1' `
                -NextValidation 'scripts\Verify-PlanContract.ps1')) | Out-Null
        }
        if (($contractIssues | Where-Object { $_ -match '(?i)_plan_missing:.*siblings' } | Select-Object -First 1)) {
            $verifiableRules.Add((New-VerifiableRuleItem `
                -Id 'rule_sibling_surface_coverage_enforced' `
                -Fingerprint 'sibling_surface_coverage_missing' `
                -MachineGate 'sibling_surface_coverage_enforced' `
                -PreventionGate 'Surface Coverage Gate' `
                -RequiredFix 'Require first-slice plans to cover required sibling execution surfaces, or remain blocked.' `
                -RegressionTest 'scripts\Test-v491-PolicyRebuildVerifierSiblingAndNoSpring.ps1' `
                -NextValidation 'scripts\Verify-PlanContract.ps1')) | Out-Null
        }
        if (($contractIssues | Where-Object { $_ -match 'plan_status_not_proceed' } | Select-Object -First 1)) {
            $verifiableRules.Add((New-VerifiableRuleItem `
                -Id 'rule_blocked_plan_status_stops_replay' `
                -Fingerprint 'plan_status_not_proceed' `
                -MachineGate 'blocked_plan_status_stops_replay' `
                -PreventionGate 'Core-First Budget Gate' `
                -RequiredFix 'Keep the replay stopped when the plan contract status is BLOCKED, and route to evolution with closeable machine gates.' `
                -RegressionTest 'scripts\Test-v598-VerifiableRuleClosureGate.ps1' `
                -NextValidation 'scripts\Run-ReplayLoop.ps1')) | Out-Null
        }
    } catch {
    }
}

$shouldEvolve = $false
$reason = 'No transferable gap was detected, or oracle coverage already reached the target.'
if ($oracle -ne $null -and $oracle -lt 90 -and $detected.Count -gt 0) {
    $shouldEvolve = $true
    $reason = 'oracle coverage is below 90 and transferable workflow gate gaps were detected.'
} elseif ($oracle -eq $null -and $detected.Count -gt 0) {
    $shouldEvolve = $true
    $reason = 'oracle score is missing, but transferable workflow gate gaps were detected.'
}

$oracleGapDetected = $detected | Where-Object { $_.Flag -in @('plan_oracle_overlap_gap', 'plan_high_weight_oracle_overlap_gap') } | Select-Object -First 1
if (-not $shouldEvolve -and $oracleGapDetected) {
    $shouldEvolve = $true
    $reason = 'plan oracle overlap gap detected from PLAN_CONTRACT_VERIFY.json'
}

$enforcementNeeded = @($detected | Where-Object { $_.ActionClass -in @('workflow-gate-needs-evolution', 'already-covered-but-not-enforced', 'tooling-evolution-needed') })

$detectedRows = if ($detected.Count -gt 0) {
    ($detected | Sort-Object Gate, Flag | ForEach-Object { "| $($_.Gate) | $($_.Flag) | $($_.Count) | $($_.ActionClass) | $($_.Recommendation) |" }) -join "`n"
} else {
    "| none | none | 0 | none | no workflow evolution recommended |"
}

$gateRows = if ($detected.Count -gt 0) {
    ($detected |
        Group-Object Gate |
        Sort-Object Name |
        ForEach-Object {
            $total = ($_.Group | Measure-Object Count -Sum).Sum
            $flags = ($_.Group | Sort-Object Flag | ForEach-Object { $_.Flag }) -join ', '
            "| $($_.Name) | $total | $flags |"
        }) -join "`n"
} else {
    "| none | 0 | none |"
}

$proposal = @"
# Replay Evolution Proposal

- Replay root: $root
- PHASE0_RESULT: $phase0ResultPath
- ROUND_RESULT: $roundResultPath
- FINAL_REPLAY_REPORT: $finalReportPath
- blind_self_assessed_coverage: $blind
- verification_capped_coverage: $capped
- oracle_adjusted_coverage: $oracle
- should_evolve: $shouldEvolve
- reason: $reason

## Detected Transferable Gaps

| productized gate | flag | count | action_class | recommendation |
|------------------|------|------:|--------------|----------------|
$detectedRows

## Enforcement Classification

- enforcement_needed_count: $($enforcementNeeded.Count)
- rule: if a gap maps to an existing gate but recurs in replay, classify it as already-covered-but-not-enforced, not no-op.
- no_op_version_guard: already-covered-by-existing-gate without a concrete runner/prompt/verifier/test change must not advance knowledge version; write NO_VERSION_ADVANCE_REASON.md instead.
- required_action: evolve runner/prompt/verifier enforcement before adding more synonym skill rules.

## 8-Gate Summary

| productized gate | total flag hits | flags |
|------------------|----------------:|-------|
$gateRows

## Absorption Rules

- Absorb only cross-project gates, routing rules, validation discipline, or report formats.
- Do not absorb project paths, business class names, table names, oracle filenames, commits, or concrete replay roots.
- Do not treat scoring caps as execution improvements; when the same gap repeats, evolve budget routing, real entries, and executable slices first.
- If an existing skill already covers the gate, mark already-covered-by-existing-gate instead of duplicating rules, but do not create no-source-change knowledge versions.
- Do not add new synonymous gate names. Map every candidate change to one of the eight productized gates before editing skills.

## Suggested Next Action

$(if ($shouldEvolve) { 'Run a controlled tooling/prompt enforcement evolution using EVOLUTION_PROMPT.md. Treat already-covered-but-not-enforced as tooling-evolution-needed unless concrete evidence shows the runner already enforces it.' } else { 'No automatic skill evolution. Continue replay or inspect manually.' })
"@

Set-Content -LiteralPath $OutPath -Value $proposal -Encoding UTF8
Write-VerifiableRules -Root $root -Rules @($verifiableRules.ToArray())
Write-Host "Wrote evolution proposal: $OutPath"
