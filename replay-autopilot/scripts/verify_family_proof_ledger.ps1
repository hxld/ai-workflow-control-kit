param(
    [Parameter(Mandatory = $true)]
    [string]$FamilyLedger,
    [Parameter(Mandatory = $true)]
    [string]$SliceContract,
    [Parameter(Mandatory = $true)]
    [string]$SliceResult,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return '' }
    return ([string]$Object.$Name).Trim()
}

function Test-ForbiddenProof {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return $Text -match '(?i)\b(static_only|helper_only|mock_only|dto_only|file_presence_only|planned_only|synthetic|none|n/a|placeholder|todo)\b'
}

function Get-FamilyRecord {
    param($Ledger, [string]$FamilyId)
    if ($null -eq $Ledger -or [string]::IsNullOrWhiteSpace($FamilyId)) { return $null }
    foreach ($family in @($Ledger.families)) {
        if ([string]$family.id -eq $FamilyId -or [string]$family.family_id -eq $FamilyId) { return $family }
    }
    return $null
}

$familyLedgerPath = Resolve-AbsolutePath $FamilyLedger
$sliceContractPath = Resolve-AbsolutePath $SliceContract
$sliceResultPath = Resolve-AbsolutePath $SliceResult
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $sliceResultPath) 'FAMILY_PROOF_LEDGER_01.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath

$issues = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $familyLedgerPath -PathType Leaf)) { $issues.Add('family_ledger_missing') | Out-Null; $ledger = $null } else { $ledger = Read-JsonFile -Path $familyLedgerPath }
if (-not (Test-Path -LiteralPath $sliceContractPath -PathType Leaf)) { $issues.Add('slice_contract_missing') | Out-Null; $contract = $null } else { $contract = Read-JsonFile -Path $sliceContractPath }
if (-not (Test-Path -LiteralPath $sliceResultPath -PathType Leaf)) { $issues.Add('slice_result_missing') | Out-Null; $result = $null } else { $result = Read-JsonFile -Path $sliceResultPath }

$familyId = Get-StringValue -Object $contract -Name 'family_id'
$family = Get-FamilyRecord -Ledger $ledger -FamilyId $familyId
if ([string]::IsNullOrWhiteSpace($familyId)) { $issues.Add('family_id_missing') | Out-Null }
if ($null -eq $family) { $issues.Add('family_not_found_in_ledger') | Out-Null }

$declaredProofKind = Get-StringValue -Object $result -Name 'proof_kind'
if ([string]::IsNullOrWhiteSpace($declaredProofKind) -and $null -ne $result -and $result.PSObject.Properties['behavior_test_charter']) {
    $declaredProofKind = Get-StringValue -Object $result.behavior_test_charter -Name 'proof_kind'
}
$entryCall = ''
if ($null -ne $result -and $result.PSObject.Properties['side_effect_evidence']) {
    $entryCall = Get-StringValue -Object $result.side_effect_evidence -Name 'entry_call'
}
if ([string]::IsNullOrWhiteSpace($entryCall)) {
    $entryCall = Get-StringValue -Object $result -Name 'production_boundary'
}
$expectedOutputs = @()
if ($null -ne $result -and $result.PSObject.Properties['side_effect_evidence']) {
    $expectedOutputs += @(Get-StringArray $result.side_effect_evidence.expected_writes_or_outputs)
}
if ($null -ne $result -and $result.PSObject.Properties['behavior_test_charter']) {
    $expectedOutputs += @(Get-StringArray $result.behavior_test_charter.state_or_output)
}
$expectedOutputs += @(Get-StringArray (Get-StringValue -Object $contract -Name 'side_effect_or_output_probe'))
$mustNot = @()
if ($null -ne $result -and $result.PSObject.Properties['must_not_assertions']) {
    $mustNot += @(Get-StringArray $result.must_not_assertions)
}
if ($null -ne $result -and $result.PSObject.Properties['behavior_test_charter']) {
    $mustNot += @(Get-StringArray $result.behavior_test_charter.must_not)
}
$mustNot += @(Get-StringArray (Get-StringValue -Object $contract -Name 'must_not_assertion'))

$proofFamily = switch -Regex ($familyId) {
    'core_entry' { 'core_entry'; break }
    'stateful' { 'stateful_side_effect'; break }
    'deploy|export|page' { 'deploy_export_page'; break }
    'wire|payload|api' { 'wire_payload_api_contract'; break }
    'generated|artifact|template|upload' { 'generated_artifact_template_upload'; break }
    'external' { 'external_integration'; break }
    'lifecycle|cleanup|retention' { 'lifecycle_cleanup_retention'; break }
    default { $familyId }
}

if (Test-ForbiddenProof -Text $entryCall) { $issues.Add('real_entry_invocation_missing_or_forbidden') | Out-Null }
if (@($expectedOutputs | Where-Object { -not (Test-ForbiddenProof ([string]$_)) }).Count -eq 0) { $issues.Add('side_effect_or_output_evidence_missing') | Out-Null }
if (@($mustNot | Where-Object { -not (Test-ForbiddenProof ([string]$_)) }).Count -eq 0) { $issues.Add('must_not_assertion_missing') | Out-Null }
if (Test-ForbiddenProof -Text $declaredProofKind) { $issues.Add('proof_kind_missing_or_forbidden') | Out-Null }

foreach ($gap in @(Get-StringArray $(if ($null -ne $result -and $result.PSObject.Properties['gap_flags']) { $result.gap_flags } else { @() }))) {
    if ($gap -match '(?i)wrong_test_surface|side_effect_ledger_gap|exact_contract_gap|helper_only|static_only|mock_only|synthetic_carrier_gap|non_authorizing_evidence') {
        $issues.Add("non_authorizing_gap_flag:$gap") | Out-Null
    }
}

$proofMatchesFamily = $false
if (-not [string]::IsNullOrWhiteSpace($declaredProofKind)) {
    $familyProofText = @(
        $declaredProofKind,
        $entryCall,
        (@($expectedOutputs) -join ' '),
        (@(Get-StringArray $(if ($null -ne $family -and $family.PSObject.Properties['proof_required']) { $family.proof_required } else { @() })) -join ' ')
    ) -join ' '
    $proofMatchesFamily = (
        $declaredProofKind -match [regex]::Escape($proofFamily) -or
        ($proofFamily -eq 'core_entry' -and $declaredProofKind -match '(?i)real_entry|entry_behavior') -or
        ($proofFamily -eq 'deploy_export_page' -and $declaredProofKind -match '(?i)export|page|route|output') -or
        ($proofFamily -eq 'stateful_side_effect' -and $declaredProofKind -match '(?i)state|side_effect|transaction|persistence|status|task|log') -or
        ($proofFamily -eq 'config_policy_threshold' -and $declaredProofKind -match '(?i)real_entry|entry_behavior|exact_contract|config|threshold|policy' -and $familyProofText -match '(?i)config|threshold|amount|free_review|auto_flow|clear|reject|persist|save')
    )
}
if (-not $proofMatchesFamily) { $issues.Add('proof_kind_does_not_match_family') | Out-Null }

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$coverageCreditAuthorized = $status -eq 'PASS'
$ledgerResult = [ordered]@{
    schema = 'family_proof_ledger.v1'
    status = $status
    family_id = $familyId
    proof_family = $proofFamily
    proof_kind = $declaredProofKind
    real_entry_invocation = $entryCall
    side_effect_or_output_evidence = @($expectedOutputs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    must_not_assertions = @($mustNot | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    coverage_credit_authorized = $coverageCreditAuthorized
    issues = @($issues.ToArray() | Select-Object -Unique)
    family_ledger = $familyLedgerPath
    slice_contract = $sliceContractPath
    slice_result = $sliceResultPath
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$ledgerResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "Family proof ledger verification ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
