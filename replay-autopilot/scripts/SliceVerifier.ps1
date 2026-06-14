param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$SliceResult,
    [string]$Worktree = '',
    [int]$SliceIndex = 0,
    [switch]$ValidateOnly,
    [switch]$SkipRemediationMap
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonObject {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $text | ConvertFrom-Json
    } catch {
        $start = $text.IndexOf('{')
        $end = $text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) {
            return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        }
        throw
    }
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-RemediationMap {
    <#
    .SYNOPSIS
    Generates remediation map for gap flags (Experiment 3).

    .DESCRIPTION
    Converts gap flags into actionable fix commands with expected output patterns
    and verification criteria. Helps reduce gap amplification by providing
    concrete remediation paths.
    #>
    param(
        [string[]]$GapFlags,
        [string]$ReplayRoot
    )

    $remediationMap = @{}

    foreach ($flag in $GapFlags) {
        switch ($flag) {
            'wrong_test_surface' {
                $remediationMap['wrong_test_surface'] = @{
                    fix_command = 'Search-BaselineCarrier -Layer Facade,Controller -Family core_entry -Exclude Helpers'
                    expected_output_pattern = 'AiApplyClaimApiTaskProcessor.*handleTaskResponse|ExamineFlowFacade.*autoClose'
                    verification = 'Layer validation output contains layer_class=valid'
                    priority = 'HIGH'
                }
            }
            'side_effect_ledger_gap' {
                $remediationMap['side_effect_ledger_gap'] = @{
                    fix_command = 'Generate-SideEffectRedTest -Family stateful_side_effect -RequiredProof t_compensate_detail,t_case_progress'
                    expected_output_pattern = '@Test.*public.*test.*AutoFlow.*SideEffect'
                    verification = 'SLICE_VERIFY contains side_effect_red_assertion=true'
                    priority = 'HIGH'
                }
            }
            'core_entry_unclosed' {
                $remediationMap['core_entry_unclosed'] = @{
                    fix_command = 'Search-CoreEntryCarrier -TriggerSource AiApplyClaimApiTaskProcessor -Exclude Parsers,Helpers'
                    expected_output_pattern = 'AiAutoClaimFlowService.*executeAutoFlow|AiApplyClaimApiTaskProcessor.*handleTaskResponse'
                    verification = 'Family closure ledger shows core_entry.touched_count > 0'
                    priority = 'CRITICAL'
                }
            }
            'executable_surface_slice_gap' {
                $remediationMap['executable_surface_slice_gap'] = @{
                    fix_command = 'Search-ExecutableSurface -Carrier SelectedCarrier -Layer Facade,Controller'
                    expected_output_pattern = 'public.*handle.*|public.*execute.*|public.*process.*'
                    verification = 'Test charter contains test_surface with public method'
                    priority = 'HIGH'
                }
            }
            'exact_contract_gap' {
                $remediationMap['exact_contract_gap'] = @{
                    fix_command = 'Generate-ExactContractTest -Carrier SelectedCarrier -ExtractSignatureFromProduction'
                    expected_output_pattern = 'exact_contract.*assert.*signature.*parameter.*return'
                    verification = 'SLICE_VERIFY contains exact_contract_assertion=true'
                    priority = 'MEDIUM'
                }
            }
            'behavior_test_charter_gap' {
                $remediationMap['behavior_test_charter_gap'] = @{
                    fix_command = 'Generate-BehaviorTestCharter -Carrier SelectedCarrier -Scenario GivenWhenThen'
                    expected_output_pattern = 'given:.*when:.*then:'
                    verification = 'Test charter contains behavior_scenario with given/when/then'
                    priority = 'MEDIUM'
                }
            }
            'shallow_module' {
                $remediationMap['shallow_module'] = @{
                    fix_command = 'Select-DeepModuleCarrier -RequiredDepth ≥3 -Exclude Parsers,Helpers'
                    expected_output_pattern = '.*Service.*|.*Facade.*|.*Controller.*'
                    verification = 'Carrier module depth ≥ 3 layers'
                    priority = 'MEDIUM'
                }
            }
            'implementation_after_blocked_red' {
                $remediationMap['implementation_after_blocked_red'] = @{
                    fix_command = 'Stop-Implementation -Reason RED phase blocked -RequireRedPassFirst'
                    expected_output_pattern = 'BLOCKED.*red_phase_blocked'
                    verification = 'SLICE_RESULT contains implementation=false and red_result=fail'
                    priority = 'CRITICAL'
                }
            }
            'synthetic_carrier_gap' {
                $remediationMap['synthetic_carrier_gap'] = @{
                    fix_command = 'Select-BaselineCarrier -Exclude TestDouble,Mocks,Fixtures'
                    expected_output_pattern = 'production.*\.java'
                    verification = 'Carrier file exists in production source tree'
                    priority = 'HIGH'
                }
            }
            'tooling_enforcement_stop' {
                $remediationMap['tooling_enforcement_stop'] = @{
                    fix_command = 'Invoke-ToolingEnforcement -ReplayRoot ReplayRoot -RequireAllGatesPass'
                    expected_output_pattern = 'gate.*PASS'
                    verification = 'All gate checks return PASS status'
                    priority = 'CRITICAL'
                }
            }
            'mock_behavior_gap' {
                $remediationMap['mock_behavior_gap'] = @{
                    fix_command = 'Generate-BusinessAssertionTest -UseRealBehavior -RequireProductionCall'
                    expected_output_pattern = 'assert.*business.*rule.*assert'
                    verification = 'Test contains business assertion, not mock verification'
                    priority = 'MEDIUM'
                }
            }
            'carrier_authorization_missing' {
                $remediationMap['carrier_authorization_missing'] = @{
                    fix_command = 'Invoke-CarrierAuthorization -Carrier SelectedCarrier -RequireExplicitAuth'
                    expected_output_pattern = 'authorization_status.*AUTHORIZED'
                    verification = 'CARRIER_AUTHORIZATION contains authorized=true'
                    priority = 'HIGH'
                }
            }
            'carrier_authorization_stop' {
                $remediationMap['carrier_authorization_stop'] = @{
                    fix_command = 'Invoke-CarrierAuthorization -Carrier SelectedCarrier -RequireExplicitAuth'
                    expected_output_pattern = 'authorization_status.*BLOCKED'
                    verification = 'CARRIER_AUTHORIZATION contains authorized=false - must fix before proceeding'
                    priority = 'CRITICAL'
                }
            }
        }
    }

    return $remediationMap
}

function Infer-SliceIndex {
    param([string]$Path, $Result)
    if ($Result -and $null -ne $Result.slice_index -and "$($Result.slice_index)" -match '^\d+$') {
        return [int]$Result.slice_index
    }
    $name = [System.IO.Path]::GetFileName($Path)
    if ($name -match '(\d+)') { return [int]$matches[1] }
    return 1
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$sliceResultFull = Resolve-AbsolutePath $SliceResult
if ([string]::IsNullOrWhiteSpace($Worktree)) {
    $Worktree = Join-Path $replayRootFull 'worktree'
}
$worktreeFull = Resolve-AbsolutePath $Worktree

if (-not (Test-Path -LiteralPath $sliceResultFull)) {
    throw "SliceResult not found: $sliceResultFull"
}
if (-not (Test-Path -LiteralPath $worktreeFull)) {
    throw "Worktree not found: $worktreeFull"
}

$slice = Read-JsonObject -Path $sliceResultFull
if ($SliceIndex -le 0) {
    $SliceIndex = Infer-SliceIndex -Path $sliceResultFull -Result $slice
}

$verifyScript = Join-Path $PSScriptRoot 'Verify-SliceClosure.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript `
    -ReplayRoot $replayRootFull `
    -Worktree $worktreeFull `
    -SliceResult $sliceResultFull `
    -SliceIndex $SliceIndex | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Verify-SliceClosure.ps1 failed with exit code $LASTEXITCODE"
}

$verifyPath = Join-Path $replayRootFull ('SLICE_VERIFY_{0:D2}.json' -f $SliceIndex)
$verify = Read-JsonObject -Path $verifyPath

$tests = @()
if ($null -ne $slice.tests) {
    if ($slice.tests -is [System.Array]) { $tests = @($slice.tests) } else { $tests = @($slice.tests) }
}
$redTests = @($tests | Where-Object { $null -ne $_.phase -and ([string]$_.phase).ToUpperInvariant() -eq 'RED' })
$redFailed = @($redTests | Where-Object { $null -ne $_.result -and ([string]$_.result).ToLowerInvariant() -eq 'fail' }).Count -gt 0
$gapFlags = @(((Get-StringArray $slice.gap_flags) + (Get-StringArray $verify.gap_flags)) | Select-Object -Unique)
$featureExemptedGapFlags = @()
if ($null -ne $verify.verifier_adjustments_applied -and
    $verify.verifier_adjustments_applied.PSObject.Properties.Name -contains 'exempted_gap_flags') {
    $featureExemptedGapFlags = @(Get-StringArray $verify.verifier_adjustments_applied.exempted_gap_flags)
}
if ($featureExemptedGapFlags.Count -gt 0) {
    $gapFlags = @($gapFlags | Where-Object { $featureExemptedGapFlags -notcontains [string]$_ } | Select-Object -Unique)
}
$blockers = @(Get-StringArray $verify.authorization_blockers)
$warnings = @(Get-StringArray $verify.warnings)

$mustFailClosed = $false
$mustFailReasons = New-Object System.Collections.Generic.List[string]
if ($gapFlags -contains 'tdd_red_not_replayed') {
    $mustFailClosed = $true
    $mustFailReasons.Add('tdd_red_not_replayed') | Out-Null
}
if ($redTests.Count -gt 0 -and -not $redFailed -and [string]$slice.slice_status -notmatch 'BLOCKED|INVALID') {
    $mustFailClosed = $true
    $mustFailReasons.Add('red_phase_did_not_fail') | Out-Null
}
foreach ($flag in @(
    'wrong_test_surface',
    'shallow_module',
    'synthetic_carrier_gap',
    'tooling_enforcement_stop',
    'mock_behavior_gap',
    'carrier_authorization_missing',
    'carrier_authorization_stop',
    'exact_contract_assertion_missing',
    'side_effect_evidence_missing',
    'side_effect_red_not_business_assertion',
    'behavior_carrier_gap',
    'facade_direction_gap',
    'facade_direction_facade_class_missing',
    'facade_direction_method_signature_missing',
    'test_contract_mismatch',
    'return_value_vs_exception_mismatch',
    'assertion_surface_mismatch'
)) {
    if ($gapFlags -contains $flag) {
        $mustFailClosed = $true
        $mustFailReasons.Add($flag) | Out-Null
    }
}
foreach ($warning in @('subclass_only_proof', 'empty_or_noop_production_carrier', 'synthetic_production_carrier')) {
    if ($warnings -contains $warning) {
        $mustFailClosed = $true
        $mustFailReasons.Add($warning) | Out-Null
    }
}

$issues = New-Object System.Collections.Generic.List[string]
$requiresCapTen = @($mustFailReasons | Where-Object {
    @(
        'tdd_red_not_replayed',
        'red_phase_did_not_fail',
        'subclass_only_proof',
        'empty_or_noop_production_carrier',
        'tooling_enforcement_stop',
        'carrier_authorization_missing',
        'carrier_authorization_stop',
        'exact_contract_assertion_missing',
        'side_effect_evidence_missing',
        'side_effect_red_not_business_assertion',
        'behavior_carrier_gap',
        'facade_direction_gap',
        'facade_direction_facade_class_missing',
        'facade_direction_method_signature_missing',
        'test_contract_mismatch',
        'return_value_vs_exception_mismatch',
        'assertion_surface_mismatch'
    ) -contains [string]$_
}).Count -gt 0

if ($mustFailClosed) {
    if ([bool]$verify.authorized_for_next_slice) { $issues.Add('must_fail_closed_but_authorized_next_slice') | Out-Null }
    if ([bool]$verify.authorized_for_synthesis) { $issues.Add('must_fail_closed_but_authorized_synthesis') | Out-Null }
    if ($null -eq $verify.adjusted_coverage_delta -or [int]$verify.adjusted_coverage_delta -ne 0) { $issues.Add('must_fail_closed_but_adjusted_delta_nonzero') | Out-Null }
    if ($requiresCapTen -and ($null -eq $verify.coverage_cap -or [int]$verify.coverage_cap -gt 10)) { $issues.Add('must_fail_closed_but_cap_above_10') | Out-Null }
}

# Generate remediation map (Experiment 3)
$remediationMap = @{}
if (-not $SkipRemediationMap) {
    $remediationMap = Get-RemediationMap -GapFlags $gapFlags -ReplayRoot $replayRootFull
    if ($remediationMap.Count -gt 0) {
        Write-Host "INFO: Generated remediation map with $($remediationMap.Count) entries" -ForegroundColor Cyan
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    status = $status
    validation_status = $status
    replay_root = $replayRootFull
    slice_result = $sliceResultFull
    slice_index = $SliceIndex
    verification_status = [string]$verify.verification_status
    authorized_for_next_slice = [bool]$verify.authorized_for_next_slice
    authorized_for_synthesis = [bool]$verify.authorized_for_synthesis
    adjusted_coverage_delta = $verify.adjusted_coverage_delta
    coverage_cap = $verify.coverage_cap
    has_behavior_evidence = [bool]$verify.has_behavior_evidence
    must_fail_closed = $mustFailClosed
    requires_cap_ten = $requiresCapTen
    must_fail_reasons = @($mustFailReasons | Select-Object -Unique)
    feature_exempted_gap_flags = @($featureExemptedGapFlags)
    authorization_blockers = @($blockers)
    warnings = @($warnings)
    validation_issues = @($issues)
    remediation_map = $remediationMap  # Experiment 3: Remediation map output
    gate = 'carrier_and_evidence_authorization_verifier'
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $replayRootFull ('SLICE_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)) -Encoding UTF8
$result | ConvertTo-Json -Depth 10

if ($status -ne 'PASS') { exit 1 }
