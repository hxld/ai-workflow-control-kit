param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [Parameter(Mandatory = $true)]
    [string]$RequirementFamilyLedger,
    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,
    [string]$ForcedRequirementFamily = '',
    [string]$ForcedSliceType = '',
    [string]$ForcedSiblingSurface = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-SafeInt {
    param($Value, [int]$Default = 100)
    if ($null -eq $Value) { return $Default }
    $s = [string]$Value
    $n = 0
    if ([int]::TryParse($s, [ref]$n)) { return $n }
    return $Default
}

$root = Resolve-AbsolutePath $ReplayRoot
$ledgerPath = Resolve-AbsolutePath $RequirementFamilyLedger
$jsonPath = Join-Path $root ('PRE_SLICE_CAP_DISPLAY_{0:D2}.json' -f $SliceIndex)
$mdPath = Join-Path $root ('PRE_SLICE_CAP_DISPLAY_{0:D2}.md' -f $SliceIndex)

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        output_json = $jsonPath
        output_md = $mdPath
    } | ConvertTo-Json -Depth 4
    exit 0
}

$ledger = Read-JsonIfExists $ledgerPath
if ($null -eq $ledger) {
    throw "Requirement family ledger not found or invalid: $ledgerPath"
}

$families = @($ledger.families)
$openFamilies = @($families | Where-Object {
    [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status)
} | Sort-Object @{ Expression = { Get-SafeInt $_.weight 0 }; Descending = $true })

$forcedFamily = $null
if (-not [string]::IsNullOrWhiteSpace($ForcedRequirementFamily)) {
    $forcedFamily = @($families | Where-Object { [string]$_.id -eq $ForcedRequirementFamily } | Select-Object -First 1)
}

$openFamilyCaps = @($openFamilies | ForEach-Object {
    [ordered]@{
        id = [string]$_.id
        status = [string]$_.status
        weight = Get-SafeInt $_.weight 0
        coverage_cap_if_open = Get-SafeInt $_.coverage_cap_if_open 100
        first_executable_carrier = [string]$_.first_executable_carrier
        open_sibling_count = Get-SafeInt $_.open_sibling_count 0
    }
})

$lowestOpenCap = if ($openFamilyCaps.Count -gt 0) {
    (@($openFamilyCaps | ForEach-Object { [int]$_.coverage_cap_if_open }) | Measure-Object -Minimum).Minimum
} else {
    100
}

$sliceCap = if ($null -ne $forcedFamily -and $forcedFamily.Count -gt 0) {
    Get-SafeInt $forcedFamily[0].coverage_cap_if_open 100
} else {
    [int]$lowestOpenCap
}

$mustClose = @()
if ($null -ne $forcedFamily -and $forcedFamily.Count -gt 0) {
    $mustClose += [ordered]@{
        family = [string]$forcedFamily[0].id
        carrier = [string]$forcedFamily[0].first_executable_carrier
        required_proof = @($forcedFamily[0].proof_required)
        forbidden_proof = @($forcedFamily[0].forbidden_proof)
    }
}

$display = [ordered]@{
    schema_version = 1
    replay_root = $root
    slice_index = $SliceIndex
    forced_requirement_family = $ForcedRequirementFamily
    forced_slice_type = $ForcedSliceType
    forced_sibling_surface = $ForcedSiblingSurface
    coverage_cap_before_slice = Get-SafeInt $ledger.coverage_cap 100
    coverage_cap_if_forced_family_remains_open = $sliceCap
    lowest_open_family_cap = [int]$lowestOpenCap
    open_family_count = $openFamilies.Count
    open_family_caps = @($openFamilyCaps)
    must_close_or_report_blocker = @($mustClose)
    enforcement = 'The slice cannot claim coverage above this cap unless executable evidence closes the forced family. Structural existence, TODO placeholders, helper-only tests, and mock-only evidence do not close the family.'
}

$display | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$rows = if ($openFamilyCaps.Count -gt 0) {
    ($openFamilyCaps | ForEach-Object { "| $($_.id) | $($_.status) | $($_.weight) | $($_.coverage_cap_if_open) | $($_.first_executable_carrier) |" }) -join "`n"
} else {
    '| none | EXECUTABLE_CLOSED | 0 | 100 | none |'
}

$md = @"
# Pre-Slice Cap Display

- slice_index: $SliceIndex
- forced_requirement_family: $ForcedRequirementFamily
- forced_slice_type: $ForcedSliceType
- forced_sibling_surface: $ForcedSiblingSurface
- coverage_cap_before_slice: $($display.coverage_cap_before_slice)
- coverage_cap_if_forced_family_remains_open: $sliceCap
- lowest_open_family_cap: $lowestOpenCap
- open_family_count: $($openFamilies.Count)

| family | status | weight | cap_if_open | first executable carrier |
|---|---|---:|---:|---|
$rows

## Enforcement

The slice cannot claim coverage above the displayed cap unless executable evidence closes the forced family. Structural existence, TODO placeholders, helper-only tests, and mock-only evidence do not close the family.
"@
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

Write-Host "Pre-slice cap display written: $jsonPath"
exit 0
