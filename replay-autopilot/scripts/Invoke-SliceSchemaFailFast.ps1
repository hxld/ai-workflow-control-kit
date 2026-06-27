# Invoke-SliceSchemaFailFast.ps1 — S3 meta-logic de-bloat
# Verifies slice result JSON schema before costly verification.
# If the agent wrapped JSON in markdown fences or omitted required
# fields, this gate rejects fast and prompts an agent re-write,
# rather than normalizing malformed output downstream.
#
# Only-additive: does not replace Read-JsonObject fallbacks (those
# remain as defense-in-depth).  Once this gate has been stable across
# N real replay rounds the fallbacks can be retired separately (S10).

param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,

    [Parameter(Mandatory = $true)]
    [int]$SliceIndex,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Write-Result {
    param(
        [string]$Status,
        [string[]]$Issues = @()
    )
    $outPath = Join-Path $replayRootFull ("SLICE_SCHEMA_FAILFAST_{0:D2}.json" -f $SliceIndex)
    [ordered]@{
        schema = 'slice_schema_fail_fast.v1'
        slice_index = $SliceIndex
        status = $Status
        issues = @($Issues)
        generated_at = (Get-Date).ToString('s')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outPath -Encoding UTF8
    return $outPath
}

$replayRootFull = Resolve-AbsolutePath $ReplayRoot

if ($ValidateOnly) {
    [pscustomobject]@{
        Status = 'VALID'
        Script = $PSCommandPath
        Checks = @(
            'slice_result is valid pure JSON, not markdown-fenced',
            'slice_index matches expected',
            'slice_status is present and one of DONE|PARTIAL|BLOCKED|INVALID_REPLAY',
            'slice_type is present (when slice_status != BLOCKED/INVALID_REPLAY)',
            'proof_kind is present and valid (when slice_status == DONE/PARTIAL)',
            'coverage_delta requires touched_requirement_families + closed_requirement_families'
        )
    } | Write-Output
    exit 0
}

if (-not (Test-Path -LiteralPath $replayRootFull)) {
    throw "Replay root not found: $replayRootFull"
}

$sliceResultPath = Join-Path $replayRootFull ('SLICE_RESULT_{0:D2}.json' -f $SliceIndex)
$raw = Read-TextIfExists $sliceResultPath
if ([string]::IsNullOrWhiteSpace($raw)) {
    $r = Write-Result -Status 'FAIL' -Issues @('slice_result_file_missing_or_empty')
    exit 1
}

# Guard 1: pure JSON – no markdown fence prefix before opening brace
$trimmed = $raw.TrimStart()
if (-not ($trimmed.StartsWith('{') -or $trimmed.StartsWith('['))) {
    $r = Write-Result -Status 'FAIL' -Issues @('slice_result_not_pure_json; agent wrote non-JSON prefix before opening brace')
    exit 1
}
$backtickInsideIndex = $trimmed.IndexOf('```')
$braceIndex = $trimmed.IndexOf('{')
if ($backtickInsideIndex -ge 0 -and $backtickInsideIndex -lt $braceIndex) {
    $r = Write-Result -Status 'FAIL' -Issues @('slice_result_wrapped_in_markdown_fence; agent must write pure JSON without fence')
    exit 1
}

# Parse JSON
$result = $null
try {
    $result = $trimmed | ConvertFrom-Json
} catch {
    $r = Write-Result -Status 'FAIL' -Issues @("slice_result_json_parse_error: $([string]$_.Exception.Message)")
    exit 1
}

$issues = New-Object System.Collections.Generic.List[string]

# Guard 2: slice_index
if ($null -eq $result.slice_index -and $null -eq $result.psobject.Properties['slice_index']) {
    $issues.Add('slice_index_missing')
} elseif ($null -ne $result.slice_index -and [string]$result.slice_index -ne [string]$SliceIndex) {
    $issues.Add("slice_index_mismatch:expected=${SliceIndex}_actual=$($result.slice_index)")
}

# Guard 3: slice_status
$status = if ($null -eq $result.slice_status) { '' } else { [string]$result.slice_status }
$validStatuses = @('DONE', 'PARTIAL', 'BLOCKED', 'INVALID_REPLAY')
if ([string]::IsNullOrWhiteSpace($status)) {
    $issues.Add('slice_status_missing')
} elseif ($validStatuses -notcontains $status) {
    $issues.Add("slice_status_invalid:$status")
}

$isBlocker = @('BLOCKED', 'INVALID_REPLAY') -contains $status

# Guard 4: slice_type (optional for BLOCKED/INVALID_REPLAY)
if ([string]::IsNullOrWhiteSpace([string]$result.slice_type) -and -not $isBlocker) {
    $issues.Add('slice_type_missing_for_non_blocker_result')
}

# Guard 5: proof_kind (required for DONE/PARTIAL)
if ($status -eq 'DONE' -or $status -eq 'PARTIAL') {
    $proofKind = if ($null -eq $result.proof_kind) { '' } else { [string]$result.proof_kind }
    if ([string]::IsNullOrWhiteSpace($proofKind)) {
        $issues.Add('proof_kind_missing_for_executable_result')
    }
}

# Guard 6: coverage_delta needs touched/closed families
$hasDelta = $null -ne $result.coverage_delta
if ($hasDelta -and [int]$result.coverage_delta -gt 0) {
    $touched = $result.touched_requirement_families
    $closed = $result.closed_requirement_families
    if ($null -eq $touched -or @($touched).Count -eq 0) {
        $issues.Add('coverage_delta_without_touched_requirement_families')
    }
    if ($null -eq $closed) {
        $issues.Add('coverage_delta_without_closed_requirement_families')
    }
}

if ($issues.Count -gt 0) {
    $r = Write-Result -Status 'FAIL' -Issues @($issues)
    exit 1
}

$r = Write-Result -Status 'PASS'
exit 0
