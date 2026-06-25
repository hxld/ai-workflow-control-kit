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

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringValue {
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return '' }
    return ([string]$Object.$Name).Trim()
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
    $OutputPath = Join-Path (Split-Path -Parent $contractPath) 'CARRIER_INVOCATION_CONTRACT_01.json'
}
$outputPathFull = Resolve-AbsolutePath $OutputPath

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
if (-not [string]::IsNullOrWhiteSpace($entry)) {
    foreach ($candidate in $indexStrings) {
        if ($candidate -eq $entry -or $candidate -like "*$entry*" -or $entry -like "*$candidate*") {
            $resolved = $true
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
