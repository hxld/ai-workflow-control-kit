param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
    [string]$Ledger = '',
    [string]$FinalReport = '',
    [string]$AssertNextTarget = '',
    [string]$AssertDeployClassification = '',
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

function Read-TextIfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    return ''
}

function Get-Metric {
    param([string]$Text, [string]$Name)
    $m = [regex]::Match($Text, "(?im)\b$([regex]::Escape($Name))\b\s*[:=]\s*`?([0-9]+)`?")
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

$root = Resolve-AbsolutePath $ReplayRoot
if ([string]::IsNullOrWhiteSpace($Ledger)) { $Ledger = Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json' }
if ([string]::IsNullOrWhiteSpace($FinalReport)) { $FinalReport = Join-Path $root 'FINAL_REPLAY_REPORT.md' }
$ledgerFull = Resolve-AbsolutePath $Ledger
$reportFull = Resolve-AbsolutePath $FinalReport
$outPath = Join-Path $root 'ROUTER_CAP_CALIBRATION.json'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        ledger = $ledgerFull
        final_report = $reportFull
        output = $outPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$ledgerObject = Read-JsonIfExists $ledgerFull
$report = Read-TextIfExists $reportFull
$router = Read-JsonIfExists (Join-Path $root 'FAMILY_ROUTER_AND_CAP.json')

if ($null -eq $ledgerObject) { throw "Ledger not found: $ledgerFull" }

$oracleCoverage = Get-Metric -Text $report -Name 'oracle_adjusted_coverage'
$processCap = if ($null -ne $router -and $router.PSObject.Properties.Name -contains 'coverage_cap_from_ledger') { [int]$router.coverage_cap_from_ledger } else { 100 }
$productScopeCap = if ($oracleCoverage -ne $null) { [Math]::Max($oracleCoverage, $processCap) } else { $processCap }

$exactMissing = (
    $report -match '15\s*-?>\s*150|15\s*->\s*150' -and
    $report -match '\bP15\b' -and
    $report -match '\bP29\b'
)
$deploySoft = (
    $report.IndexOf('ORACLE_NOT_REQUIRED_AS_CHANGED_FAMILY', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $report.IndexOf('Oracle did not include the controller', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $report.IndexOf('Oracle did not include a controller', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
)

$familyClassifications = @($ledgerObject.families | ForEach-Object {
    $id = [string]$_.id
    $classification = if (-not [bool]$_.required) {
        'out_of_scope'
    } elseif ($id -eq 'deploy_export_page' -and $deploySoft) {
        'soft_residual'
    } elseif ($report.IndexOf("$id` | ORACLE_NOT_REQUIRED", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        'oracle_not_required'
    } else {
        'hard_required'
    }
    [ordered]@{
        id = $id
        status = [string]$_.status
        classification = $classification
    }
})

$nextTarget = if ($exactMissing) {
    'exact_contract_slice'
} elseif ($null -ne $router) {
    [string]$router.selected_slice_type
} else {
    ''
}

$issues = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($AssertNextTarget) -and $nextTarget -ne $AssertNextTarget) {
    $issues.Add("next_target_mismatch:$AssertNextTarget") | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($AssertDeployClassification)) {
    $deploy = @($familyClassifications | Where-Object { $_.id -eq 'deploy_export_page' } | Select-Object -First 1)
    $actual = if ($deploy.Count -gt 0) { [string]$deploy[0].classification } else { '' }
    if ($actual -ne $AssertDeployClassification) {
        $issues.Add("deploy_classification_mismatch:$AssertDeployClassification") | Out-Null
    }
}

$status = if ($issues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    status = $status
    replay_root = $root
    process_cap = $processCap
    product_scope_cap = $productScopeCap
    oracle_adjusted_coverage = $oracleCoverage
    next_target = $nextTarget
    exact_contract_priority = $exactMissing
    family_classifications = @($familyClassifications)
    issues = @($issues)
    gate = 'router_and_ledger_cap_calibration'
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outPath -Encoding UTF8
$result | ConvertTo-Json -Depth 12

if ($status -ne 'PASS') { exit 1 }
