param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [int]$MinAddressedBlockers = 1,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-TextIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
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

function Get-UniqueStringArray {
    param([object[]]$Values)
    $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($Values)) {
        foreach ($item in @(Get-StringArray $value)) {
            if ($set.Add($item)) {
                $out.Add($item) | Out-Null
            }
        }
    }
    return @($out.ToArray())
}

function Test-TextAddressesBlocker {
    param(
        [string]$Text,
        [string]$Blocker
    )

    $lower = $Text.ToLowerInvariant()
    $blockerLower = $Blocker.ToLowerInvariant()
    if ($lower.Contains($blockerLower)) { return $true }

    switch -Regex ($blockerLower) {
        'plan_format_drift' {
            return $lower -match '(plan[_ -]?format|markdown|regex|schema|json|first[_ -]?slice[_ -]?proof|plan[_ -]?result)'
        }
        'low_verification_cap' {
            return $lower -match '(low[_ -]?verification|verification[_ -]?cap|coverage[_ -]?cap|low[_ -]?cap|zero[_ -]?cap|0\s*cap)'
        }
        'evolution_validation_fail' {
            return $lower -match '(evolution[_ -]?validation|evolution_result_verify|validated[_ -]?stop|regression[_ -]?test|verification[_ -]?results)'
        }
        'side_effect_ledger_gap' {
            return $lower -match '(side[_ -]?effect|side_effect_ledger|stateful|db|database|transaction|persist|insert|update)'
        }
        'exact_contract_gap' {
            return $lower -match '(exact[_ -]?contract|literal[_ -]?contract|schema[_ -]?contract|field|payload|wire|enum)'
        }
        'wrong_test_surface' {
            return $lower -match '(wrong[_ -]?test[_ -]?surface|test[_ -]?surface|real[_ -]?entry|helper[_ -]?only|mock[_ -]?only|static[_ -]?only)'
        }
        'core_entry_unclosed' {
            return $lower -match '(core[_ -]?entry|real[_ -]?entry|entry[_ -]?closure|selected[_ -]?entry|production[_ -]?entry)'
        }
        'executable_surface_slice_gap' {
            return $lower -match '(executable[_ -]?surface|deploy[_ -]?facing|surface[_ -]?slice|api|export|page|payload|artifact)'
        }
        'phase0_carrier_evidence_gap' {
            return $lower -match '(phase0|phase 0|carrier[_ -]?evidence|selected[_ -]?real[_ -]?entry|source[_ -]?search|baseline[_ -]?existing)'
        }
        'phase0_oracle_contamination' {
            return $lower -match '(oracle[_ -]?contamination|oracle[_ -]?used|blind[_ -]?source|source[_ -]?isolation|forbidden[_ -]?source)'
        }
        'phase0_format_drift' {
            return $lower -match '(phase0|phase 0|format[_ -]?drift|machine[_ -]?contract|exact[_ -]?heading|status[_ -]?field)'
        }
        'executor_resource_or_crash' {
            return $lower -match '(executor|retry|rate[_ -]?limit|429|capacity|timeout|api 400|crash|fallback)'
        }
        'schema_contract_discovery_gap' {
            return $lower -match '(schema[_ -]?discovery|schema[_ -]?contract|confirmed|inferred|blocked|payload[_ -]?schema)'
        }
        default {
            return $false
        }
    }
}

function Write-GateResult {
    param(
        [string]$Root,
        [object]$Result,
        [bool]$Pass
    )

    $jsonPath = Join-Path $Root 'REFLECTION_GATE.json'
    $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    if (-not $Pass) {
        $md = New-Object System.Collections.Generic.List[string]
        $md.Add('# Deep Reflection Required') | Out-Null
        $md.Add('') | Out-Null
        $md.Add("status: $($Result.status)") | Out-Null
        $md.Add("replay_root: $Root") | Out-Null
        $md.Add('') | Out-Null
        $md.Add('## Why The Loop Stopped') | Out-Null
        foreach ($issue in @($Result.issues)) {
            $md.Add("- $issue") | Out-Null
        }
        $md.Add('') | Out-Null
        $md.Add('## Required Before Next Replay') | Out-Null
        $md.Add('- Map each repeated blocker to a concrete runner, verifier, schema, prompt, or golden-slice change.') | Out-Null
        $md.Add('- Prefer machine-readable JSON/schema contracts over additional Markdown regex repairs.') | Out-Null
        $md.Add('- Add a regression fixture proving the old failure now fails closed or passes for the right reason.') | Out-Null
        $md.Add('- Re-run the reflection gate before launching the next unattended cycle.') | Out-Null
        Set-Content -LiteralPath (Join-Path $Root 'DEEP_REFLECTION_REQUIRED.md') -Encoding UTF8 -Value ($md -join "`n")
    }

    if ($Pass) { exit 0 }
    exit 1
}

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        schema = 'reflection_sufficiency_gate.v1'
        replay_root_required = $true
    } | ConvertTo-Json -Depth 4
    exit 0
}

$root = Resolve-AbsolutePath $ReplayRoot
if (-not (Test-Path -LiteralPath $root)) {
    throw "Replay root not found: $root"
}

$stagnationPath = Join-Path $root 'STAGNATION_DECISION.json'
$evolutionVerifyPath = Join-Path $root 'EVOLUTION_RESULT_VERIFY.json'
$evolutionResultPath = Join-Path $root 'EVOLUTION_RESULT.md'
$failureAuditPath = Join-Path $root 'FAILURE_AUDIT_PACK.json'
$goldenSlicePath = Join-Path $root 'NEXT_GOLDEN_DELIVERY_SLICE.json'

$stagnation = Read-JsonIfExists $stagnationPath
$failureAudit = Read-JsonIfExists $failureAuditPath
$triggered = $false
if ($null -ne $stagnation -and $stagnation.PSObject.Properties.Name -contains 'triggered') {
    $triggered = [bool]$stagnation.triggered
}

$reasons = if ($null -ne $stagnation) { @(Get-StringArray $stagnation.reasons) } else { @() }
$repeated = if ($null -ne $stagnation) { @(Get-StringArray $stagnation.repeated_blockers) } else { @() }
if ($null -ne $failureAudit) {
    $repeated = @(Get-UniqueStringArray @($repeated, $failureAudit.must_fix_before_next_replay, $failureAudit.repeated_blockers))
}
$critical = $triggered -or ($reasons -match 'low_verification_cap|repeated_blockers').Count -gt 0 -or $repeated.Count -gt 0

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not $critical) {
    Write-GateResult -Root $root -Pass $true -Result ([ordered]@{
        schema = 'reflection_sufficiency_gate.v1'
        status = 'PASS'
        required = $false
        reason = 'stagnation_not_triggered'
        repeated_blockers = @($repeated)
        issues = @()
        warnings = @()
        generated_at = (Get-Date).ToString('s')
    })
}

$evolutionVerify = Read-JsonIfExists $evolutionVerifyPath
if ($null -eq $evolutionVerify) {
    $issues.Add('evolution_result_verify_missing') | Out-Null
} elseif ([string]$evolutionVerify.status -ne 'PASS') {
    $issues.Add("evolution_result_verify_not_pass:$($evolutionVerify.status)") | Out-Null
}

if ($null -eq $failureAudit) {
    $issues.Add('failure_audit_pack_missing') | Out-Null
}

$evolutionText = Read-TextIfExists $evolutionResultPath
if ([string]::IsNullOrWhiteSpace($evolutionText)) {
    $issues.Add('evolution_result_missing') | Out-Null
}

if ($evolutionText -match '(?i)\b(no[-_ ]?source[-_ ]?change|already[-_ ]?covered[-_ ]?but[-_ ]?not[-_ ]?enforced)\b' -and
    $evolutionText -notmatch '(?i)(tooling_changes_applied\s*:\s*true|Replay-Autopilot Files Modified|Tooling Changes Applied|changed_files)') {
    $issues.Add('reflection_no_executable_tooling_or_schema_change') | Out-Null
}

if ($evolutionText -notmatch '(?i)(final_status\s*:\s*VALIDATED_|final_status:\s*VALIDATED_|VALIDATED_[A-Z_]+)') {
    $issues.Add('validated_final_status_missing') | Out-Null
}

if ($evolutionText -notmatch '(?i)(regression|test|assertion|verification|verify)') {
    $issues.Add('regression_or_verification_evidence_missing') | Out-Null
}

$addressed = New-Object System.Collections.Generic.List[string]
$missing = New-Object System.Collections.Generic.List[string]
foreach ($blocker in $repeated) {
    if (Test-TextAddressesBlocker -Text $evolutionText -Blocker $blocker) {
        $addressed.Add($blocker) | Out-Null
    } else {
        $missing.Add($blocker) | Out-Null
    }
}

$requiredAddressed = if ($null -ne $failureAudit -and $repeated.Count -gt 0) {
    $repeated.Count
} else {
    [Math]::Max($MinAddressedBlockers, [Math]::Ceiling([Math]::Max(1, $repeated.Count) / 2))
}
if ($repeated.Count -gt 0 -and $addressed.Count -lt $requiredAddressed) {
    $issues.Add("reflection_does_not_address_repeated_blockers:$($addressed.Count)/$requiredAddressed") | Out-Null
}

if ($repeated -contains 'plan_format_drift' -and $evolutionText -notmatch '(?i)(json|schema|machine[-_ ]?readable|contract[_ -]?json|fail[-_ ]?closed)') {
    $issues.Add('plan_format_drift_requires_machine_contract_strategy') | Out-Null
}

if ($repeated -contains 'low_verification_cap' -and $evolutionText -notmatch '(?i)(verification[_ -]?cap|coverage[_ -]?cap|zero[_ -]?cap|golden[_ -]?slice|first[_ -]?slice|side[_ -]?effect)') {
    $issues.Add('low_verification_cap_requires_coverage_strategy') | Out-Null
}

$goldenRequiredBlockers = @(
    'low_verification_cap',
    'wrong_test_surface',
    'core_entry_unclosed',
    'side_effect_ledger_gap',
    'exact_contract_gap',
    'executable_surface_slice_gap'
)
$goldenRequired = $false
if ($null -ne $failureAudit -and [bool]$failureAudit.golden_first_slice_required) {
    $goldenRequired = $true
}
foreach ($blocker in $repeated) {
    if ($goldenRequiredBlockers -contains $blocker) {
        $goldenRequired = $true
        break
    }
}
if ($goldenRequired) {
    $goldenSlice = Read-JsonIfExists $goldenSlicePath
    if ($null -eq $goldenSlice) {
        $issues.Add('golden_delivery_slice_missing') | Out-Null
    } else {
        $goldenText = (Read-TextIfExists (Join-Path $root 'NEXT_GOLDEN_DELIVERY_SLICE.md')) + "`n" + ($goldenSlice | ConvertTo-Json -Depth 10)
        $bound = $false
        foreach ($blocker in $repeated) {
            if (($goldenRequiredBlockers -contains $blocker) -and $goldenText.ToLowerInvariant().Contains($blocker.ToLowerInvariant())) {
                $bound = $true
                break
            }
        }
        if (-not $bound) {
            $issues.Add('golden_delivery_slice_not_bound_to_repeated_blockers') | Out-Null
        }
    }
}

if ($repeated.Count -eq 0) {
    $warnings.Add('stagnation_triggered_without_repeated_blockers') | Out-Null
}

$pass = $issues.Count -eq 0
Write-GateResult -Root $root -Pass $pass -Result ([ordered]@{
    schema = 'reflection_sufficiency_gate.v1'
    status = if ($pass) { 'PASS' } else { 'FAIL' }
    required = $true
    triggered = $triggered
    repeated_blockers = @($repeated)
    addressed_blockers = @($addressed)
    missing_reflection_for = @($missing)
    failure_audit_pack = if ($null -ne $failureAudit) { $failureAuditPath } else { '' }
    golden_first_slice_required = $goldenRequired
    golden_delivery_slice = if (Test-Path -LiteralPath $goldenSlicePath) { $goldenSlicePath } else { '' }
    min_addressed_blockers = $requiredAddressed
    issues = @($issues)
    warnings = @($warnings)
    generated_at = (Get-Date).ToString('s')
})
