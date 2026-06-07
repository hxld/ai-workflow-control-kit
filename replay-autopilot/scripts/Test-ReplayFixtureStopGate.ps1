param(
    [Parameter(Mandatory = $true)]
    [string]$FixtureRoot,
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

function Read-JsonIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Get-Metric {
    param([string]$Text, [string]$Name)
    $m = [regex]::Match($Text, "(?im)\b$([regex]::Escape($Name))\b\s*[:=]\s*`?([0-9]+)`?")
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

$root = Resolve-AbsolutePath $FixtureRoot
$decisionPath = Join-Path $root 'FIXTURE_STOP_GATE_DECISION.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        fixture_root = $root
        decision_path = $decisionPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

if (-not (Test-Path -LiteralPath $root)) { throw "Fixture root not found: $root" }

$summary = Read-TextIfExists (Join-Path $root 'AUTOPILOT_SUMMARY.md')
$round = Read-TextIfExists (Join-Path $root 'ROUND_RESULT.md')
$stopLoss = Read-JsonIfExists (Join-Path $root 'STOP_LOSS_DECISION.json')
$familyLedger = Read-JsonIfExists (Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json')
$sliceVerify = Read-JsonIfExists (Join-Path $root 'SLICE_VERIFY_01.json')
$combined = "$summary`n$round"

$oracle = Get-Metric -Text $combined -Name 'oracle_adjusted_coverage'
$capped = Get-Metric -Text $combined -Name 'verification_capped_coverage'
$blockedPatterns = @(
    'wrong_test_surface',
    'shallow_module',
    'synthetic_carrier_gap',
    'core_entry_unclosed',
    'side_effect_ledger_gap',
    'executable_surface_slice_gap',
    'exact_contract_gap',
    'tooling_enforcement_stop'
)
$presentBlocked = @($blockedPatterns | Where-Object { $combined.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })

$familyPassAllowed = $false
if ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'final_pass_allowed') {
    $familyPassAllowed = [bool]$familyLedger.final_pass_allowed
}
$sliceAuthorized = $false
if ($null -ne $sliceVerify -and $sliceVerify.PSObject.Properties.Name -contains 'authorized_for_next_slice') {
    $sliceAuthorized = [bool]$sliceVerify.authorized_for_next_slice
}
$stopLossSaysStop = $false
if ($null -ne $stopLoss -and $stopLoss.PSObject.Properties.Name -contains 'should_stop') {
    $stopLossSaysStop = [bool]$stopLoss.should_stop
}

$decision = 'CONTINUE_REPLAY'
$reasons = New-Object System.Collections.Generic.List[string]
if ($stopLossSaysStop) { $reasons.Add('stop_loss_should_stop') | Out-Null }
if ($oracle -ne $null -and $oracle -lt 90) { $reasons.Add("oracle_below_target:$oracle") | Out-Null }
if ($capped -ne $null -and $capped -lt 45) { $reasons.Add("low_verification_cap:$capped") | Out-Null }
if ($presentBlocked.Count -gt 0) { $reasons.Add("blocked_patterns:$($presentBlocked -join ',')") | Out-Null }
if (-not $familyPassAllowed) { $reasons.Add('family_ledger_final_pass_not_allowed') | Out-Null }
if (-not $sliceAuthorized) { $reasons.Add('next_slice_not_authorized') | Out-Null }

if ($reasons.Count -gt 0) {
    $decision = 'STOP_AND_EVOLVE'
}

$output = [ordered]@{
    decision = $decision
    fixture_root = $root
    oracle_adjusted_coverage = $oracle
    verification_capped_coverage = $capped
    blocked_patterns = @($presentBlocked)
    reasons = @($reasons)
}
$output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $decisionPath -Encoding UTF8
Get-Content -LiteralPath $decisionPath -Encoding UTF8

if ($decision -ne 'STOP_AND_EVOLVE') {
    exit 1
}
