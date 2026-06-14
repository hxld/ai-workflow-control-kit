param(
    [Parameter(Mandatory=$true)][string]$ReplayRoot,
    [int]$TargetCoverage = 90
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

function Get-MetricFromText {
    param([string]$Text, [string]$Name)
    $linePattern = '(?im)^\s*(?:[-*]\s*)?(?:\|\s*)?' + [regex]::Escape($Name) + '\b.*$'
    $line = [regex]::Match($Text, $linePattern)
    if (-not $line.Success) { return $null }
    $directPattern = [regex]::Escape($Name) + '\s*(?:\||:|=|-)\s*([0-9]{1,3})(?:\s*(?:/100|%))?'
    $direct = [regex]::Match($line.Value, $directPattern)
    if ($direct.Success) { return [int]$direct.Groups[1].Value }
    $numbers = @([regex]::Matches($line.Value, '\b([0-9]{1,3})\b') | ForEach-Object { [int]$_.Groups[1].Value } | Where-Object { $_ -le 100 })
    if ($numbers.Count -gt 0) { return [int]$numbers[-1] }
    return $null
}

$root = Resolve-AbsolutePath $ReplayRoot
$roundText = Read-TextIfExists (Join-Path $root 'ROUND_RESULT.md')
$finalText = Read-TextIfExists (Join-Path $root 'FINAL_REPLAY_REPORT.md')
$summaryText = Read-TextIfExists (Join-Path $root 'AUTOPILOT_SUMMARY.md')
$router = Read-JsonIfExists (Join-Path $root 'FAMILY_ROUTER_AND_CAP.json')
$stopLoss = Read-JsonIfExists (Join-Path $root 'STOP_LOSS_DECISION.json')
$ledger = Read-JsonIfExists (Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json')

$blind = Get-MetricFromText -Text $roundText -Name 'blind_self_assessed_coverage'
$capped = Get-MetricFromText -Text $roundText -Name 'verification_capped_coverage'
$oracle = Get-MetricFromText -Text $summaryText -Name 'oracle_adjusted_coverage'
if ($oracle -eq $null) {
    $oracle = Get-MetricFromText -Text $finalText -Name 'oracle_adjusted_coverage'
}

$openFamilies = @()
if ($null -ne $ledger -and $null -ne $ledger.families) {
    $openFamilies = @($ledger.families | Where-Object { [bool]$_.required -and @('OPEN','PARTIAL') -contains ([string]$_.status) })
}
$finalPassAllowed = $false
if ($null -ne $router -and $router.PSObject.Properties.Name -contains 'final_pass_allowed') {
    $finalPassAllowed = [bool]$router.final_pass_allowed
}
if (-not $finalPassAllowed -and $oracle -ne $null -and $capped -ne $null -and [int]$oracle -gt [int]$capped) {
    $oracle = [int]$capped
}

$issues = New-Object System.Collections.Generic.List[string]
if ($blind -eq $null) { $issues.Add('blind_self_assessed_coverage_missing') | Out-Null }
if ($capped -eq $null) { $issues.Add('verification_capped_coverage_missing') | Out-Null }
if ($oracle -eq $null) { $issues.Add('oracle_adjusted_coverage_missing') | Out-Null }
if ($oracle -ne $null -and $oracle -lt $TargetCoverage) { $issues.Add('oracle_adjusted_below_target') | Out-Null }
if ($capped -ne $null -and $capped -lt $TargetCoverage) { $issues.Add('verification_capped_below_target') | Out-Null }
if ($openFamilies.Count -gt 0) { $issues.Add('required_families_open_or_partial') | Out-Null }
if (-not $finalPassAllowed) { $issues.Add('final_pass_not_allowed_by_router') | Out-Null }
if ($null -ne $stopLoss -and [bool]$stopLoss.should_stop) { $issues.Add('stop_loss_requires_deep_review') | Out-Null }

$status = if ($issues.Count -eq 0) { 'CONTINUE_REPLAY' } else { 'STOP_AND_EVOLVE' }
$result = [ordered]@{
    status = $status
    replay_root = $root
    target_coverage = $TargetCoverage
    blind_self_assessed_coverage = $blind
    verification_capped_coverage = $capped
    oracle_adjusted_coverage = $oracle
    final_pass_allowed = $finalPassAllowed
    open_required_family_count = $openFamilies.Count
    issues = @($issues)
    gate = 'stop_loss_synthesis_enforcement'
}
$outPath = Join-Path $root 'STOP_LOSS_SYNTHESIS_VALIDATION.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12
