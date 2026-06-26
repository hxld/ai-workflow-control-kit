param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$TestCharter,
    [Parameter(Mandatory = $true)]
    [string]$FamilyLedger,
    [string]$Contract = '',
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

function Get-PropertyValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return '' }
    foreach ($name in $Names) {
        if ($Object.PSObject.Properties[$name]) {
            $value = $Object.$name
            if ($value -is [System.Array]) {
                if (@($value).Count -gt 0) { return $value }
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }
    return ''
}

function Test-ForbiddenText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $true }
    return $Text -match '(?i)\b(mock_only|static_only|helper_only|file_presence|dto_field_presence|dto_only|assertion-free|wiring_only|planned_only|synthetic|placeholder|none|n/a|tbd)\b'
}

function Get-FamilyRequiredProofType {
    param($Ledger, [string]$FamilyId)
    foreach ($family in @($Ledger.families)) {
        $id = [string](Get-PropertyValue -Object $family -Names @('id', 'family_id', 'family'))
        if ($id -ne $FamilyId) { continue }
        $proof = [string](Get-PropertyValue -Object $family -Names @('required_proof_type', 'proof_type'))
        if (-not [string]::IsNullOrWhiteSpace($proof)) { return $proof }
    }
    return ''
}

function Test-ProofMatchesFamily {
    param([string]$FamilyId, [string]$ProofType, [string]$RequiredProofType)
    if ([string]::IsNullOrWhiteSpace($ProofType)) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($RequiredProofType)) {
        return $ProofType -eq $RequiredProofType
    }
    switch -Regex ($FamilyId) {
        'core_entry' { return $ProofType -match '(?i)real_entry_behavior' }
        'stateful|side_effect' { return $ProofType -match '(?i)db_state|stateful_side_effect|real_entry_behavior' }
        'wire|payload|api|exact_contract' { return $ProofType -match '(?i)serialized_payload|external_payload_capture|real_entry_behavior' }
        'render|artifact|template|upload|export|page' { return $ProofType -match '(?i)rendered_output|external_payload_capture|real_entry_behavior' }
        'external' { return $ProofType -match '(?i)external_payload_capture|serialized_payload' }
        default { return $ProofType -match '(?i)real_entry_behavior|db_state|serialized_payload|rendered_output|external_payload_capture|must_not_collaborator_invocation' }
    }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$testCharterPath = Resolve-AbsolutePath $TestCharter
$familyLedgerPath = Resolve-AbsolutePath $FamilyLedger
if ([string]::IsNullOrWhiteSpace($Contract)) {
    $Contract = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTION_CONTRACT.json'
    if (-not (Test-Path -LiteralPath $Contract -PathType Leaf)) {
        $Contract = Join-Path $replayRootFull 'FIRST_SLICE_EXECUTABLE_CONTRACT.json'
    }
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $replayRootFull 'PROOF_TYPE_POLICY_GATE.json'
}
$contractPath = Resolve-AbsolutePath $Contract
$outputPathFull = Resolve-AbsolutePath $OutputPath
$issues = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $testCharterPath -PathType Leaf)) {
    $issues.Add('test_charter_missing') | Out-Null
    $testCharterObject = $null
} else {
    $testCharterObject = Read-JsonFile -Path $testCharterPath
}
if (-not (Test-Path -LiteralPath $familyLedgerPath -PathType Leaf)) {
    $issues.Add('family_ledger_missing') | Out-Null
    $familyLedgerObject = $null
} else {
    $familyLedgerObject = Read-JsonFile -Path $familyLedgerPath
}
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $issues.Add('first_slice_execution_contract_missing') | Out-Null
    $contractObject = $null
} else {
    $contractObject = Read-JsonFile -Path $contractPath
}

$familyId = [string](Get-PropertyValue -Object $contractObject -Names @('family_id', 'forced_requirement_family'))
$proofType = [string](Get-PropertyValue -Object $testCharterObject -Names @('proof_type', 'proof_kind', 'required_proof_type'))
if ([string]::IsNullOrWhiteSpace($proofType)) {
    $proofType = [string](Get-PropertyValue -Object $contractObject -Names @('required_proof_type', 'proof_type'))
}
$requiredProofType = if ($null -ne $familyLedgerObject) { Get-FamilyRequiredProofType -Ledger $familyLedgerObject -FamilyId $familyId } else { '' }
$productionEntry = [string](Get-PropertyValue -Object $testCharterObject -Names @('production_entry', 'production_entry_qn', 'real_entry_invoked', 'entry_point'))
$businessAssertion = [string](Get-PropertyValue -Object $testCharterObject -Names @('business_assertion', 'red_phase_business_failure', 'green_phase_business_success', 'must_fail_before_change'))
$stateOrOutput = Get-PropertyValue -Object $testCharterObject -Names @('state_or_output_surface', 'side_effect_target', 'state_or_output', 'side_effect_or_output')
$mustNot = Get-PropertyValue -Object $testCharterObject -Names @('negative_must_not_assertions', 'forbidden_test_surface', 'must_not')

if ([string]::IsNullOrWhiteSpace($familyId)) { $issues.Add('family_id_missing') | Out-Null }
if (Test-ForbiddenText $proofType) { $issues.Add('proof_type_forbidden_or_missing') | Out-Null }
if (-not (Test-ProofMatchesFamily -FamilyId $familyId -ProofType $proofType -RequiredProofType $requiredProofType)) {
    $issues.Add('proof_type_does_not_match_target_family') | Out-Null
}
if (Test-ForbiddenText $productionEntry) { $issues.Add('production_entry_missing_or_forbidden') | Out-Null }
if (Test-ForbiddenText $businessAssertion) { $issues.Add('business_assertion_missing_or_forbidden') | Out-Null }
if (@(Get-StringArray $stateOrOutput | Where-Object { -not (Test-ForbiddenText ([string]$_)) }).Count -eq 0) {
    $issues.Add('state_or_output_observation_missing_or_forbidden') | Out-Null
}
if (@(Get-StringArray $mustNot | Where-Object { -not (Test-ForbiddenText ([string]$_)) }).Count -eq 0) {
    $issues.Add('must_not_assertion_missing_or_forbidden') | Out-Null
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'proof_type_policy_gate.v1'
    status = $status
    authorization = if ($status -eq 'PASS') { 'ALLOW' } else { 'STOP' }
    replay_root = $replayRootFull
    test_charter = $testCharterPath
    family_ledger = $familyLedgerPath
    contract = $contractPath
    family_id = $familyId
    proof_type = $proofType
    required_proof_type = $requiredProofType
    production_entry = $productionEntry
    issues = @($issues.ToArray() | Select-Object -Unique)
    generated_at = (Get-Date).ToString('s')
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPathFull) | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPathFull -Encoding UTF8
Write-Host "Proof-type policy gate ${status}: $outputPathFull"
if ($status -ne 'PASS') { exit 1 }
exit 0
