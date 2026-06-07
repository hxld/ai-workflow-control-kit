param(
    [Parameter(Mandatory=$true)][string]$ReplayRoot,
    [int]$SliceIndex = 0
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Read-JsonIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

$root = Resolve-AbsolutePath $ReplayRoot
$sliceIndexes = if ($SliceIndex -gt 0) {
    @($SliceIndex)
} else {
    @(Get-ChildItem -LiteralPath $root -Filter 'CARRIER_AUTHORIZATION_*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '_(\d+)$' } |
        ForEach-Object { [int]$matches[1] } |
        Sort-Object -Unique)
}

$issues = New-Object System.Collections.ArrayList
foreach ($idx in $sliceIndexes) {
    $carrier = Read-JsonIfExists (Join-Path $root ('CARRIER_AUTHORIZATION_{0:D2}.json' -f $idx))
    $result = Read-JsonIfExists (Join-Path $root ('SLICE_RESULT_{0:D2}.json' -f $idx))
    $verify = Read-JsonIfExists (Join-Path $root ('SLICE_VERIFY_{0:D2}.json' -f $idx))
    if ($null -eq $carrier -or [string]$carrier.forced_requirement_family -ne 'deploy_export_page') { continue }

    $requiredText = @(
        [string]$carrier.selected_carrier,
        [string]$carrier.downstream_side_effect_or_output,
        (Get-StringArray $carrier.proof_required) -join ' '
    ) -join "`n"
    $actualText = if ($null -ne $result) {
        @(
            [string]$result.target_subsurface_or_carrier,
            [string]$result.production_boundary,
            [string]$result.proof_kind,
            (Get-StringArray $result.implemented_files) -join ' ',
            (Get-StringArray $result.closed_assertions) -join ' ',
            (($result.tests | ForEach-Object { [string]$_.command }) -join ' ')
        ) -join "`n"
    } else { '' }

    $routeRequired = $requiredText -match '(?i)\b(controller|route|endpoint|exportMyTask|export|download|workbook|excel)\b'
    $routeProven = $actualText -match '(?i)\b(controller|route|endpoint|exportMyTask|export|download|workbook|excel)\b'
    $verifierStopped = $null -ne $verify -and (-not [bool]$verify.authorized_for_next_slice) -and ((Get-StringArray $verify.gap_flags) -contains 'wrong_test_surface')

    if ($routeRequired -and -not $routeProven -and -not $verifierStopped) {
        [void]$issues.Add([pscustomobject][ordered]@{
            slice = $idx
            issue = 'deploy_route_or_output_not_authorized_or_stopped'
            required = $requiredText
            actual = $actualText
        })
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'STOP' }
$result = [ordered]@{
    status = $status
    replay_root = $root
    slice_index = $SliceIndex
    issues = @($issues)
    gate = 'deploy_surface_route_output_authorization'
}
$outPath = Join-Path $root 'DEPLOY_SURFACE_AUTHORIZATION_VALIDATION.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
