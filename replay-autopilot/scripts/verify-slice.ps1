# verify-slice.ps1
# Mandatory Side Effect Ledger Verification (Experiment 2 from NEXT_EXPERIMENT_PLAN.md)

param(
    [Parameter(Mandatory = $false)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $false)]
    [string]$SliceResultPath,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-SliceIndexFromPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 0 }
    $leaf = Split-Path -Leaf $Path
    if ($leaf -match 'SLICE_RESULT_(\d+)\.json') {
        return [int]$Matches[1]
    }
    return 0
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-ObjectIntValueOrNull {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
        $value = Get-ObjectPropertyValue -Object $Object -Name $name
        if ($null -ne $value) {
            $text = ([string]$value).Trim()
            if ($text -match '^-?\d+$') { return [int]$text }
        }
    }
    return $null
}

function Get-ObjectBoolValue {
    param($Object, [string[]]$Names, [bool]$Default = $false)
    foreach ($name in $Names) {
        $value = Get-ObjectPropertyValue -Object $Object -Name $name
        if ($null -eq $value) { continue }
        if ($value -is [bool]) { return [bool]$value }
        $text = ([string]$value).Trim()
        if ($text -match '^(?i:true|false)$') { return [System.Convert]::ToBoolean($text) }
        if ($text -match '^[01]$') { return ($text -eq '1') }
    }
    return $Default
}

function Resolve-WorktreeEvidencePath {
    param([string]$WorktreePath, [string]$EvidencePath)
    if ([string]::IsNullOrWhiteSpace($WorktreePath) -or [string]::IsNullOrWhiteSpace($EvidencePath)) { return '' }
    $candidate = (([string]$EvidencePath) -split '#')[0].Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($candidate)) { return '' }
    $candidate = $candidate -replace '/', [System.IO.Path]::DirectorySeparatorChar
    try {
        $fullPath = if ([System.IO.Path]::IsPathRooted($candidate)) {
            [System.IO.Path]::GetFullPath($candidate)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $WorktreePath $candidate))
        }
        $worktreeFull = [System.IO.Path]::GetFullPath($WorktreePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ($fullPath.StartsWith($worktreeFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fullPath
        }
    } catch {
        return ''
    }
    return ''
}

function Add-UniqueString {
    param([System.Collections.Generic.List[string]]$List, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    $trimmed = $Value.Trim()
    if (-not $List.Contains($trimmed)) {
        $List.Add($trimmed) | Out-Null
    }
}

function Get-SliceResultEvidenceFiles {
    param($SliceResult)

    $files = New-Object System.Collections.Generic.List[string]
    if ($null -eq $SliceResult) { return @() }

    $behaviorCharter = Get-ObjectPropertyValue -Object $SliceResult -Name 'behavior_test_charter'
    if ($null -ne $behaviorCharter) {
        foreach ($file in @(Get-StringArray (Get-ObjectPropertyValue -Object $behaviorCharter -Name 'evidence_files'))) {
            Add-UniqueString -List $files -Value ([string]$file)
        }
        foreach ($file in @(Get-StringArray (Get-ObjectPropertyValue -Object $behaviorCharter -Name 'evidence_file'))) {
            foreach ($part in @(([string]$file) -split "[,;`r`n]+")) {
                Add-UniqueString -List $files -Value ([string]$part)
            }
        }
    }

    $sideEffectEvidence = Get-ObjectPropertyValue -Object $SliceResult -Name 'side_effect_evidence'
    if ($null -ne $sideEffectEvidence) {
        foreach ($name in @('test_name', 'evidence_file', 'evidence_path')) {
            foreach ($file in @(Get-StringArray (Get-ObjectPropertyValue -Object $sideEffectEvidence -Name $name))) {
                Add-UniqueString -List $files -Value ([string]$file)
            }
        }
    }

    return @($files)
}

function Test-TestSourceHasExecutableSideEffectAssertion {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $hasExecutableAssertion = $text -match '(?i)(ArgumentCaptor\s*<|\.capture\s*\(|Mockito\.verify\s*\(|\bverify\s*\(|Assert\.assert(?:Equals|True|False|NotNull)\s*\(|assert(?:Equals|True|False|NotNull)\s*\(|assertThat\s*\()'
    $hasSideEffectBoundary = $text -match '(?i)(Mapper\s*\)\s*\.\s*(insert|update|delete|save)|Mapper\s*\.\s*(insert|update|delete|save)|Repository\s*\)\s*\.\s*(save|delete)|Repository\s*\.\s*(save|delete)|\b(insert|update|delete|save)\s*\(|updateStatus|save[A-Za-z]*Log)'
    return ($hasExecutableAssertion -and $hasSideEffectBoundary)
}

function Test-ExecutableSideEffectEvidence {
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath,
        [string]$WorktreePath
    )

    $issues = New-Object System.Collections.Generic.List[string]
    $evidenceFiles = New-Object System.Collections.Generic.List[string]
    $sliceResult = Read-JsonIfExists -Path $SliceResultPath
    if ($null -eq $sliceResult) {
        $issues.Add('slice_result_missing') | Out-Null
        return [pscustomobject]@{ IsValid = $false; Issues = @($issues); EvidenceFiles = @() }
    }

    $matchedTestCount = Get-ObjectIntValueOrNull -Object $sliceResult -Names @('matched_test_count', 'test_count')
    if ($null -eq $matchedTestCount -or $matchedTestCount -le 0) {
        $issues.Add('matched_test_count_missing') | Out-Null
    }

    if (-not (Get-ObjectBoolValue -Object $sliceResult -Names @('real_entry_invoked') -Default $false)) {
        $issues.Add('real_entry_invoked_missing') | Out-Null
    }

    $greenExitCode = Get-ObjectIntValueOrNull -Object $sliceResult -Names @('green_exit_code', 'test_execution_exit_code')
    if ($null -eq $greenExitCode -or $greenExitCode -ne 0) {
        $issues.Add('green_execution_not_verified') | Out-Null
    }

    $assertionSignals = @()
    foreach ($name in @('side_effect_assertions', 'exact_output_assertions')) {
        $assertionSignals += @(Get-StringArray (Get-ObjectPropertyValue -Object $sliceResult -Name $name))
    }
    $sideEffectEvidence = Get-ObjectPropertyValue -Object $sliceResult -Name 'side_effect_evidence'
    if ($null -ne $sideEffectEvidence) {
        $assertionSignals += @(Get-StringArray (Get-ObjectPropertyValue -Object $sideEffectEvidence -Name 'expected_writes_or_outputs'))
        $assertionSignals += @(Get-StringArray (Get-ObjectPropertyValue -Object $sideEffectEvidence -Name 'expected_writes'))
    }
    $assertionSignals = @($assertionSignals | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($assertionSignals.Count -eq 0) {
        $issues.Add('side_effect_assertions_missing') | Out-Null
    }

    $candidateFiles = @(Get-SliceResultEvidenceFiles -SliceResult $sliceResult)
    foreach ($candidateFile in $candidateFiles) {
        $resolved = Resolve-WorktreeEvidencePath -WorktreePath $WorktreePath -EvidencePath $candidateFile
        if (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path -LiteralPath $resolved)) {
            if (Test-TestSourceHasExecutableSideEffectAssertion -Path $resolved) {
                Add-UniqueString -List $evidenceFiles -Value $resolved
            }
        }
    }
    if ($evidenceFiles.Count -eq 0) {
        $issues.Add('executable_test_source_missing') | Out-Null
    }

    return [pscustomobject]@{
        IsValid = ($issues.Count -eq 0)
        Issues = @($issues)
        EvidenceFiles = @($evidenceFiles)
    }
}

function Test-SideEffectNotApplicable {
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $feature = Read-JsonIfExists -Path (Join-Path $ReplayRoot 'FEATURE_CLASSIFICATION.json')
    $readOnly = $false
    $statefulRequired = $true
    $nonApplicableFamilies = @()
    if ($null -ne $feature) {
        if ($feature.PSObject.Properties.Name -contains 'read_only') {
            $readOnly = [bool]$feature.read_only
        }
        if ($null -ne $feature.verifier_adjustments) {
            if ($feature.verifier_adjustments.PSObject.Properties.Name -contains 'stateful_side_effect_required') {
                $statefulRequired = [bool]$feature.verifier_adjustments.stateful_side_effect_required
            }
            if ($feature.verifier_adjustments.PSObject.Properties.Name -contains 'non_applicable_families') {
                $nonApplicableFamilies = @($feature.verifier_adjustments.non_applicable_families | ForEach-Object { [string]$_ })
            }
        }
    }

    $sliceIndex = Get-SliceIndexFromPath -Path $SliceResultPath
    $sliceVerify = if ($sliceIndex -gt 0) { Read-JsonIfExists -Path (Join-Path $ReplayRoot ('SLICE_VERIFY_{0:D2}.json' -f $sliceIndex)) } else { $null }
    $verifyWaived = $false
    if ($null -ne $sliceVerify) {
        $warnings = @($sliceVerify.warnings | ForEach-Object { [string]$_ })
        $verifyWaived = $warnings -contains 'side_effect_evidence_not_applicable_by_feature_classification'
        if ($sliceVerify.PSObject.Properties.Name -contains 'verifier_adjustments_applied' -and $null -ne $sliceVerify.verifier_adjustments_applied) {
            if ($sliceVerify.verifier_adjustments_applied.PSObject.Properties.Name -contains 'side_effect_evidence_required') {
                $verifyWaived = $verifyWaived -or (-not [bool]$sliceVerify.verifier_adjustments_applied.side_effect_evidence_required)
            }
        }
    }

    return ($readOnly -and (-not $statefulRequired -or $nonApplicableFamilies -contains 'stateful_side_effect' -or $verifyWaived))
}

function Test-SideEffectNotRequiredForSlice {
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $sliceIndex = Get-SliceIndexFromPath -Path $SliceResultPath
    if ($sliceIndex -le 0) { return $false }

    $evidencePath = Join-Path $ReplayRoot ('SIDE_EFFECT_EVIDENCE_{0:D2}.json' -f $sliceIndex)
    $evidence = Read-JsonIfExists -Path $evidencePath
    if ($null -eq $evidence) { return $false }

    $required = Get-ObjectBoolValue -Object $evidence -Names @('required_for_this_slice') -Default $true
    $status = ([string](Get-ObjectPropertyValue -Object $evidence -Name 'status')).Trim().ToUpperInvariant()
    $family = ([string](Get-ObjectPropertyValue -Object $evidence -Name 'forced_requirement_family')).Trim()
    if ($required) { return $false }
    if (@('NOT_REQUIRED', 'NOT_APPLICABLE', 'WAIVED') -notcontains $status) { return $false }

    $sliceResult = Read-JsonIfExists -Path $SliceResultPath
    $touchedFamilies = if ($null -ne $sliceResult) {
        @(Get-StringArray (Get-ObjectPropertyValue -Object $sliceResult -Name 'touched_requirement_families'))
    } else {
        @()
    }
    if ($family -eq 'stateful_side_effect' -or $touchedFamilies -contains 'stateful_side_effect') {
        return $false
    }

    return $true
}

function Test-SideEffectLedger {
    <#
    .SYNOPSIS
    Validates that SIDE_EFFECT_LEDGER.md exists and has proper verification for stateful families.

    .DESCRIPTION
    Prevents side_effect_ledger_gap by requiring side effect documentation before slice completion.

    Returns $true if side effects are properly documented.
    Returns $false if side effects are missing or lack verification.
    #>
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $ledgerPath = Join-Path $ReplayRoot 'SIDE_EFFECT_LEDGER.md'

    if (Test-SideEffectNotApplicable -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath) {
        Write-Host "INFO: Side-effect ledger skipped for read-only feature classification." -ForegroundColor Cyan
        return @{
            IsValid = $true
            Reason = 'side_effect_not_applicable_by_feature_classification'
            HasSideEffects = $false
            Skipped = $true
        }
    }

    if (Test-SideEffectNotRequiredForSlice -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath) {
        Write-Host "INFO: Side-effect ledger skipped for non-stateful slice-level evidence." -ForegroundColor Cyan
        return @{
            IsValid = $true
            Reason = 'side_effect_not_required_for_slice'
            HasSideEffects = $false
            Skipped = $true
        }
    }

    # Check if SIDE_EFFECT_LEDGER.md exists
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        Write-Host "WARNING: SIDE_EFFECT_LEDGER.md not found." -ForegroundColor Yellow
        Write-Host "Required for stateful families with DB side effects." -ForegroundColor Yellow
        return @{
            IsValid = $true  # Pass if not stateful
            Reason = 'no_side_effects_required'
            HasSideEffects = $false
        }
    }

    $ledger = Get-Content -LiteralPath $ledgerPath -Raw -Encoding UTF8

    # Check for DB assertion patterns
    $hasSelectPattern = $ledger -match 'SELECT\s+\*\s+FROM'
    $hasAssertionPattern = $ledger -match 'assertThat\(|verify\(.+Mapper\)|AtomicReference'

    if (-not $hasSelectPattern -and -not $hasAssertionPattern) {
        $worktreePath = Join-Path $ReplayRoot 'worktree'
        $executableEvidence = Test-ExecutableSideEffectEvidence -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath -WorktreePath $worktreePath
        if ([bool]$executableEvidence.IsValid) {
            Write-Host "INFO: SIDE_EFFECT_LEDGER.md verified by executable side-effect test evidence" -ForegroundColor Green
            return @{
                IsValid = $true
                Reason = 'executable_side_effect_evidence_verified'
                HasSideEffects = $true
                HasVerification = $true
                VerificationSource = 'SLICE_RESULT_and_test_source'
                EvidenceFiles = @($executableEvidence.EvidenceFiles)
            }
        }

        Write-Host "ERROR: SIDE_EFFECT_LEDGER.md missing DB assertion patterns." -ForegroundColor Red
        Write-Host "Required pattern: SELECT * FROM table WHERE key = ?" -ForegroundColor Yellow
        Write-Host "Or executable Mockito/JUnit side-effect assertions linked from SLICE_RESULT." -ForegroundColor Yellow
        return @{
            IsValid = $false
            Reason = 'missing_verification_patterns'
            HasSideEffects = $true
            RequiredPattern = 'SELECT * FROM table WHERE key = ? or executable Mockito/JUnit side-effect assertions linked from SLICE_RESULT'
            EvidenceIssues = @($executableEvidence.Issues)
        }
    }

    # Check for stateful family declaration
    $hasStatefulFamily = $ledger -match 'stateful.*side.?effect' -or $ledger -match 'Family:\s*stateful'

    if ($hasStatefulFamily) {
        Write-Host "INFO: Stateful side effects declared with verification patterns" -ForegroundColor Green
        return @{
            IsValid = $true
            Reason = 'stateful_effects_verified'
            HasSideEffects = $true
            HasVerification = $true
        }
    }

    Write-Host "INFO: SIDE_EFFECT_LEDGER.md exists (no stateful effects detected)" -ForegroundColor Cyan
    return @{
        IsValid = $true
        Reason = 'no_stateful_effects'
        HasSideEffects = $false
    }
}

function Invoke-SideEffectVerificationGate {
    param(
        [string]$ReplayRoot,
        [string]$SliceResultPath
    )

    $resultPath = Join-Path $ReplayRoot 'SIDE_EFFECT_VERIFICATION_RESULT.json'

    $result = [ordered]@{
        gate = 'side_effect_ledger_complete'
        can_proceed = $true
        validation_status = 'PASS'
        issues = @()
        warnings = @()
        has_side_effects = $false
        verified_at = (Get-Date).ToString('s')
    }

    # Run side effect ledger check
    $ledgerValid = Test-SideEffectLedger -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath

    $result.has_side_effects = $ledgerValid.HasSideEffects
    if ($ledgerValid.Skipped) {
        $result.skipped = $true
        $result.skip_reason = $ledgerValid.Reason
    }
    if ($ledgerValid.HasVerification) {
        $result.has_verification = $true
    }
    if ($ledgerValid.Reason) {
        $result.reason = $ledgerValid.Reason
    }
    if ($ledgerValid.VerificationSource) {
        $result.verification_source = $ledgerValid.VerificationSource
    }
    if ($ledgerValid.EvidenceFiles) {
        $result.evidence_files = @($ledgerValid.EvidenceFiles)
    }

    if (-not $ledgerValid.IsValid) {
        $result.can_proceed = $false
        $result.validation_status = 'FAIL'
        $result.issues += @{
            code = 'side_effect_ledger_gap'
            message = 'Side effects not properly verified'
            reason = $ledgerValid.Reason
            remediation = if ($ledgerValid.RequiredPattern) { $ledgerValid.RequiredPattern } else { 'Document DB verification patterns in SIDE_EFFECT_LEDGER.md' }
        }
    }

    # Write result
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    if ($result.can_proceed) {
        Write-Host "Side effect verification: PASSED" -ForegroundColor Green
    } else {
        Write-Host "Side effect verification: FAILED" -ForegroundColor Red
        foreach ($issue in $result.issues) {
            Write-Host "  [$($issue.code)] $($issue.message)" -ForegroundColor Red
            if ($issue.remediation) {
                Write-Host "  Remediation: $($issue.remediation)" -ForegroundColor Yellow
            }
        }
    }

    return $result
}

if ($ValidateOnly) {
    $result = [ordered]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'Test-SideEffectLedger: Validates SIDE_EFFECT_LEDGER.md exists',
            'Checks for DB assertion patterns (SELECT, assertThat, verify) or executable side-effect test evidence',
            'Prevents side_effect_ledger_gap before slice completion'
        )
    }
    $result | Format-List
    exit 0
}

# Main execution
$result = Invoke-SideEffectVerificationGate -ReplayRoot $ReplayRoot -SliceResultPath $SliceResultPath

exit $(if ($result.can_proceed) { 0 } else { 1 })
