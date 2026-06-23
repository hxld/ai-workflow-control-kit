param(
    [Parameter(Mandatory = $true)]
    [string]$SliceResultPath,
    [string]$ReplayRoot = '',
    [int]$SliceIndex = 0,
    [switch]$InPlace
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

function Infer-SliceIndex {
    param([string]$Path, $Result)
    $value = Get-SliceResultPropertyValue -Object $Result -Name 'slice_index'
    if ($null -ne $value -and "$value" -match '^\d+$') { return [int]$value }
    $name = [System.IO.Path]::GetFileName($Path)
    if ($name -match '(\d+)') { return [int]$matches[1] }
    return 1
}

. (Join-Path $PSScriptRoot 'SliceResultSchemaNormalizer.ps1')

$sliceResultFull = Resolve-AbsolutePath $SliceResultPath
if (-not (Test-Path -LiteralPath $sliceResultFull)) {
    throw "SliceResultPath not found: $sliceResultFull"
}

if ([string]::IsNullOrWhiteSpace($ReplayRoot)) {
    $ReplayRoot = Split-Path -Parent $sliceResultFull
}
$replayRootFull = Resolve-AbsolutePath $ReplayRoot
$slice = Read-JsonObject -Path $sliceResultFull
if ($SliceIndex -le 0) {
    $SliceIndex = Infer-SliceIndex -Path $sliceResultFull -Result $slice
}

$normalization = Invoke-SliceResultSchemaNormalization -Slice $slice
$backupPath = ''
if ($InPlace -and [bool]$normalization.normalized) {
    $backupPath = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.before_schema_normalization.json' -f $SliceIndex)
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $sliceResultFull -Destination $backupPath -Force
    }
    $slice | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $sliceResultFull -Encoding UTF8
}

$reportPath = Join-Path $replayRootFull ('SLICE_RESULT_SCHEMA_NORMALIZATION_{0:D2}.json' -f $SliceIndex)
$report = [ordered]@{
    schema = 'slice_result_schema_normalization.v1'
    status = 'PASS'
    slice_index = $SliceIndex
    slice_result = $sliceResultFull
    normalized = [bool]$normalization.normalized
    normalized_fields = @($normalization.normalized_fields)
    original_status = [string]$normalization.original_status
    canonical_status = [string]$normalization.canonical_status
    in_place = [bool]$InPlace
    backup_path = $backupPath
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 10
