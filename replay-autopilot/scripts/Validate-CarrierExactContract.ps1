param(
    [Parameter(Mandatory=$true)][string]$ReplayRoot,
    [string]$RequirementSource = '',
    [string]$Mode = 'DryRun'
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

function Read-TextIfExists {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-StatusLikePredicates {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @(
        [regex]::Matches($Text, '\bCaseStatusType\.[A-Za-z0-9_]+\b|\b[A-Z][A-Z0-9_]{2,}\b|\bstatusId\b|\bcaseStatus\b') |
            ForEach-Object { $_.Value } |
            Where-Object {
                $_ -match 'CaseStatusType\.|statusId|caseStatus|DSH|YSH|WAIT|STATUS|TASK_STATUS|CASE_STATUS'
            } |
            Select-Object -Unique
    )
}

$root = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($RequirementSource)) {
    $run = Read-JsonIfExists (Join-Path $root 'AUTOPILOT_RUN.json')
    if ($null -ne $run) { $RequirementSource = [string]$run.requirement_source }
}
$requirementText = if (-not [string]::IsNullOrWhiteSpace($RequirementSource)) { Read-TextIfExists $RequirementSource } else { '' }

$issues = New-Object System.Collections.ArrayList
$checked = 0
foreach ($sliceResult in @(Get-ChildItem -LiteralPath $root -Filter 'SLICE_RESULT_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $result = Read-JsonIfExists $sliceResult.FullName
    if ($null -eq $result -or $null -eq $result.exact_contract_assertions) { continue }
    $slice = [int]$result.slice_index
    foreach ($assertion in @($result.exact_contract_assertions)) {
        $checked++
        $assertionIntent = @(
            [string]$assertion.literal,
            [string]$assertion.test_assertion
        ) -join ' '
        if ($assertionIntent -match '(?i)\b(ordinary|normal|unchanged|preserve|preserves|compatibility|existing)\b') { continue }
        $text = @(
            [string]$assertion.production_predicate,
            [string]$assertion.forbidden_extra_predicate,
            [string]$assertion.test_assertion
        ) -join "`n"
        foreach ($predicate in Get-StatusLikePredicates $text) {
            $p = [string]$predicate
            if ($p -match '^(?i)(TRUE|FALSE|PASS|FAIL|DONE|OPEN|CLOSED|PARTIAL|BLOCKED|RED|GREEN|BUILD|SUCCESS|NULL)$') { continue }
            if ($p -match '^(?i)(SCSCDSH|YBJDSH)$') { continue }
            if (-not [string]::IsNullOrWhiteSpace($requirementText) -and $requirementText -match [regex]::Escape($p)) { continue }
            [void]$issues.Add([pscustomobject][ordered]@{
                slice = $slice
                file = $sliceResult.Name
                literal = [string]$assertion.literal
                predicate = $p
                issue = 'unproven_extra_predicate'
            })
        }
    }
}

$status = if ($issues.Count -eq 0) { 'ALLOW' } else { 'BLOCKED_PLAN_MISMATCH' }
$result = [ordered]@{
    status = $status
    mode = $Mode
    replay_root = $root
    requirement_source = $RequirementSource
    checked_assertions = $checked
    issues = @($issues)
    gate = 'carrier_exact_contract_predicate_dry_run'
}
$outPath = Join-Path $root 'CARRIER_EXACT_CONTRACT_VALIDATION.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
