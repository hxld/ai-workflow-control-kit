param(
    [Parameter(Mandatory = $true)]
    [string]$Contract,
    [Parameter(Mandatory = $true)]
    [string]$CarrierIndex,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-SliceIndexFromPath {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileName($Path)
    $match = [regex]::Match($name, '_(\d{2})\.json$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return [int]$match.Groups[1].Value }
    return 1
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-OptionalJsonFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Read-JsonFile -Path $Path
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return '' }
    return ([string]$Object.$Name).Trim()
}

function Get-PropertyObject {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.$Name
}

function Get-NestedStringValue {
    param($Object, [string[]]$Path)
    $current = $Object
    foreach ($segment in $Path) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$segment]) { return '' }
        $current = $current.$segment
    }
    if ($null -eq $current) { return '' }
    return ([string]$current).Trim()
}

function Get-BoolValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return $false }
    $value = $Object.$Name
    if ($value -is [bool]) { return $value }
    $text = ([string]$value).Trim()
    return $text -match '^(?i:true|1|yes)$'
}

function Test-EmptyJsonArrayLike {
    param($Value)
    if ($null -eq $Value) { return $true }
    if ($Value -is [System.Array]) { return @($Value).Count -eq 0 }
    if ($Value -is [string]) { return [string]::IsNullOrWhiteSpace($Value) }
    return $false
}

function Test-CandidateMatchesEntry {
    param([string]$Candidate, [string]$Entry)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Entry)) { return $false }
    $candidateText = $Candidate.Trim()
    $entryText = $Entry.Trim()
    return ($candidateText -eq $entryText -or $candidateText -like "*$entryText*" -or $entryText -like "*$candidateText*")
}

function Add-ResolutionCandidate {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Source,
        [string]$Value,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    $Candidates.Add([pscustomobject]@{
        source = $Source
        value = $Value.Trim()
        path = $Path
    }) | Out-Null
}

function Add-DryRunResolutionEvidence {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$ReplayRoot,
        [int]$SliceIndex,
        [string]$Entry
    )
    $path = Join-Path $ReplayRoot ('CARRIER_AUTHORIZATION_DRY_RUN_{0:D2}.json' -f $SliceIndex)
    $artifact = Read-OptionalJsonFile -Path $path
    if ($null -eq $artifact) { return }

    $blockers = Get-PropertyObject -Object $artifact -Name 'blockers'
    $chosen = Get-StringValue -Object $artifact -Name 'chosen_replacement_or_blocked'
    $trusted = (Get-BoolValue -Object $artifact -Name 'pre_authorized') `
        -and (Test-EmptyJsonArrayLike -Value $blockers) `
        -and ([string]::IsNullOrWhiteSpace($chosen) -or $chosen -eq 'authorized_original')
    if (-not $trusted) { return }

    $values = @(
        (Get-StringValue -Object $artifact -Name 'selected_symbol'),
        (Get-StringValue -Object $artifact -Name 'signature')
    )
    if (-not ($values | Where-Object { Test-CandidateMatchesEntry -Candidate $_ -Entry $Entry })) { return }
    foreach ($value in $values) {
        Add-ResolutionCandidate -Candidates $Candidates -Source 'carrier_authorization_dry_run' -Value $value -Path $path
    }
}

function Add-CallableResolutionEvidence {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$ReplayRoot,
        [int]$SliceIndex,
        [string]$Entry
    )
    $path = Join-Path $ReplayRoot ('CALLABLE_CARRIER_AUTHORIZATION_{0:D2}.json' -f $SliceIndex)
    $artifact = Read-OptionalJsonFile -Path $path
    if ($null -eq $artifact) { return }

    $blockers = Get-PropertyObject -Object $artifact -Name 'blockers'
    $status = Get-StringValue -Object $artifact -Name 'authorization_status'
    $authorization = Get-StringValue -Object $artifact -Name 'authorization'
    $methodSignatureFound = $true
    if ($artifact.PSObject.Properties['method_signature_found']) {
        $methodSignatureFound = Get-BoolValue -Object $artifact -Name 'method_signature_found'
    }
    $trusted = (Test-EmptyJsonArrayLike -Value $blockers) `
        -and $methodSignatureFound `
        -and ((Get-BoolValue -Object $artifact -Name 'can_proceed') -or $status -eq 'AUTHORIZED' -or $authorization -eq 'ALLOW')
    if (-not $trusted) { return }

    $values = @(
        (Get-StringValue -Object $artifact -Name 'selected_carrier'),
        (Get-StringValue -Object $artifact -Name 'selected_real_entry'),
        (Get-StringValue -Object $artifact -Name 'selected_carrier_fqn'),
        (Get-StringValue -Object $artifact -Name 'existing_entry_fqn'),
        (Get-StringValue -Object $artifact -Name 'existing_entry_signature'),
        (Get-NestedStringValue -Object $artifact -Path @('resolved_signature', 'selected_carrier', 'formatted')),
        (Get-NestedStringValue -Object $artifact -Path @('resolved_signature', 'selected_real_entry', 'formatted'))
    )
    if (-not ($values | Where-Object { Test-CandidateMatchesEntry -Candidate $_ -Entry $Entry })) { return }
    foreach ($value in $values) {
        Add-ResolutionCandidate -Candidates $Candidates -Source 'callable_carrier_authorization' -Value $value -Path $path
    }
}

function Get-CarrierStrings {
    param($Node)
    $values = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node) { return @() }
    if ($Node -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Node)) { $values.Add($Node) | Out-Null }
        return @($values.ToArray())
    }
    if ($Node -is [System.Array]) {
        foreach ($item in @($Node)) {
            foreach ($value in @(Get-CarrierStrings -Node $item)) { $values.Add($value) | Out-Null }
        }
        return @($values.ToArray())
    }
    foreach ($prop in @($Node.PSObject.Properties)) {
        if ($prop.Name -match '(?i)(signature|formatted|carrier|entry|method|production_entry_qn|qualified_name|qn)$') {
            $value = [string]$prop.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) { $values.Add($value.Trim()) | Out-Null }
        }
        if ($prop.Value -isnot [string] -and ($prop.Value -is [System.Array] -or $prop.Value.PSObject.Properties.Count -gt 0)) {
            foreach ($nested in @(Get-CarrierStrings -Node $prop.Value)) { $values.Add($nested) | Out-Null }
        }
    }
    return @($values.ToArray() | Select-Object -Unique)
}

$contractPath = Resolve-AbsolutePath $Contract
$carrierIndexPath = Resolve-AbsolutePath $CarrierIndex
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $contractPath) ('CARRIER_INVOCATION_CONTRACT_{0:D2}.json' -f (Get-SliceIndexFromPath -Path $contractPath))
}
$outputPathFull = Resolve-AbsolutePath $OutputPath
$replayRootFull = Split-Path -Parent $outputPathFull
$sliceIndex = Get-SliceIndexFromPath -Path $outputPathFull

$issues = New-Object System.Collections.Generic.List[string]
$contractObject = $null
$carrierIndexObject = $null
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $issues.Add('slice_execution_contract_missing') | Out-Null
} else {
    $contractObject = Read-JsonFile -Path $contractPath
}
if (-not (Test-Path -LiteralPath $carrierIndexPath -PathType Leaf)) {
    $issues.Add('carrier_index_missing') | Out-Null
} else {
    $carrierIndexObject = Read-JsonFile -Path $carrierIndexPath
}

$entry = Get-StringValue -Object $contractObject -Name 'production_entry_qn'
if ([string]::IsNullOrWhiteSpace($entry)) {
    $entry = Get-StringValue -Object $contractObject -Name 'real_entry_fqn'
}

if ([string]::IsNullOrWhiteSpace($entry)) {
    $issues.Add('production_entry_qn_missing') | Out-Null
}
if ($entry -match '(?i)\b(NEW_PLANNED_CARRIER|planned_only|synthetic|helper_only|dto_only|static_only)\b') {
    $issues.Add('planned_or_synthetic_carrier_forbidden') | Out-Null
}

$indexStrings = @(Get-CarrierStrings -Node $carrierIndexObject)
$resolved = $false
$resolutionSource = ''
$resolutionEvidence = ''
if (-not [string]::IsNullOrWhiteSpace($entry)) {
    foreach ($candidate in $indexStrings) {
        if (Test-CandidateMatchesEntry -Candidate $candidate -Entry $entry) {
            $resolved = $true
            $resolutionSource = 'carrier_index'
            $resolutionEvidence = $candidate
            break
        }
    }
}
if (-not $resolved -and -not [string]::IsNullOrWhiteSpace($entry)) {
    $sameRoundCandidates = New-Object System.Collections.Generic.List[object]
    Add-DryRunResolutionEvidence -Candidates $sameRoundCandidates -ReplayRoot $replayRootFull -SliceIndex $sliceIndex -Entry $entry
    Add-CallableResolutionEvidence -Candidates $sameRoundCandidates -ReplayRoot $replayRootFull -SliceIndex $sliceIndex -Entry $entry
    foreach ($candidate in @($sameRoundCandidates.ToArray())) {
        if (Test-CandidateMatchesEntry -Candidate $candidate.value -Entry $entry) {
            $resolved = $true
            $resolutionSource = $candidate.source
            $resolutionEvidence = $candidate.value
            break
        }
    }
}
if (-not $resolved) {
    $issues.Add('carrier_not_resolved_in_baseline_index') | Out-Null
}

$invocation = Get-StringValue -Object $contractObject -Name 'entry_invocation_method'
if ([string]::IsNullOrWhiteSpace($invocation)) {
    $invocation = Get-StringValue -Object $contractObject -Name 'test_invocation_expression'
}
if ([string]::IsNullOrWhiteSpace($invocation)) {
    $issues.Add('test_invocation_method_missing') | Out-Null
}
if ($invocation -match '(?i)\b(helper_only|mock_only|dto_only|static_only|not invoked|planned)\b') {
    $issues.Add('test_invocation_non_authorizing') | Out-Null
}

$signatureMatch = $resolved -and -not [string]::IsNullOrWhiteSpace($entry)
$testInvokesEntry = -not [string]::IsNullOrWhiteSpace($invocation) -and $invocation -notmatch '(?i)\b(helper_only|mock_only|dto_only|static_only|not invoked|planned)\b'
$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }

$result = [ordered]@{
    schema = 'carrier_invocation_contract.v1'
    status = $status
    resolved = $resolved
    signature_match = $signatureMatch
    test_invokes_entry = $testInvokesEntry
    carrier_origin = if ($resolved) { 'existing_production' } else { 'unresolved' }
    resolution_source = $resolutionSource
    resolution_evidence = $resolutionEvidence
    production_entry_qn = $entry
    test_invocation_method = $invocation
    contract = $contractPath
    carrier_index = $carrierIndexPath
    issues = @($issues.ToArray())
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "Carrier invocation contract verification ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
