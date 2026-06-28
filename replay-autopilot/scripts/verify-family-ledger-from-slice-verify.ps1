param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$Ledger = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($Ledger)) {
    $Ledger = Join-Path $replayRootFull 'REQUIREMENT_FAMILY_LEDGER.json'
}
$ledgerFull = Resolve-AbsolutePath $Ledger
$issues = New-Object System.Collections.Generic.List[object]
$verifiedClosed = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
$verifiedTouched = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

if (-not (Test-Path -LiteralPath $ledgerFull -PathType Leaf)) {
    $issues.Add([ordered]@{ code = 'family_ledger_missing'; path = $ledgerFull }) | Out-Null
    $ledgerObject = $null
} else {
    $ledgerObject = Read-Json -Path $ledgerFull
}

$verifyFiles = @(Get-ChildItem -LiteralPath $replayRootFull -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($file in $verifyFiles) {
    try {
        $verify = Read-Json -Path $file.FullName
    } catch {
        $issues.Add([ordered]@{ code = 'slice_verify_invalid_json'; path = $file.FullName }) | Out-Null
        continue
    }
    foreach ($familyId in @(Get-StringArray $verify.touched_requirement_families)) {
        if (-not [string]::IsNullOrWhiteSpace($familyId)) { [void]$verifiedTouched.Add($familyId) }
    }
    foreach ($familyId in @(Get-StringArray $verify.closed_requirement_families)) {
        if (-not [string]::IsNullOrWhiteSpace($familyId)) {
            [void]$verifiedClosed.Add($familyId)
            [void]$verifiedTouched.Add($familyId)
        }
    }
}

if ($null -ne $ledgerObject -and $null -ne $ledgerObject.families) {
    foreach ($family in @($ledgerObject.families)) {
        $familyId = [string]$family.id
        if ([string]::IsNullOrWhiteSpace($familyId)) { continue }
        $status = [string]$family.status
        $isClosed = @('CLOSED', 'EXECUTABLE_CLOSED') -contains $status
        if ($isClosed -and -not $verifiedClosed.Contains($familyId)) {
            $issues.Add([ordered]@{
                code = 'ledger_closed_without_slice_verify_closure'
                family_id = $familyId
                ledger_status = $status
            }) | Out-Null
        }
        if (-not $isClosed -and $verifiedTouched.Contains($familyId) -and -not $verifiedClosed.Contains($familyId)) {
            Set-ObjectProperty -Object $family -Name 'touched_not_closed' -Value $true
        }
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'family_ledger_from_slice_verify.v1'
    status = $status
    replay_root = $replayRootFull
    ledger = $ledgerFull
    slice_verify_files = @($verifyFiles | ForEach-Object { $_.FullName })
    verified_closed_families = @($verifiedClosed.GetEnumerator() | Sort-Object)
    verified_touched_families = @($verifiedTouched.GetEnumerator() | Sort-Object)
    issues = @($issues.ToArray())
    generated_at = (Get-Date).ToString('s')
}

if ($null -ne $ledgerObject -and $issues.Count -eq 0) {
    $ledgerObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ledgerFull -Encoding UTF8
}
$out = Join-Path $replayRootFull 'FAMILY_LEDGER_FROM_SLICE_VERIFY.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "Family ledger from slice verify ${status}: $out"
if ($status -ne 'PASS') { exit 1 }
exit 0
