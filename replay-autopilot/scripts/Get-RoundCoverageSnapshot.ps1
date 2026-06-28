param(
    [Parameter(Mandatory = $true)]
    [string]$ReplayRoot,
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
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = Read-TextIfExists $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return $text | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-ExactSliceJsonObjects {
    param(
        [string]$Root,
        [string]$Prefix
    )

    $pattern = "^$([regex]::Escape($Prefix))_\d+\.json$"
    return @(Get-ChildItem -LiteralPath $Root -File -Filter "${Prefix}_*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object Name |
        ForEach-Object { Read-JsonIfExists $_.FullName } |
        Where-Object { $null -ne $_ })
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Array]) { return @($Value | ForEach-Object { [string]$_ }) }
    return @([string]$Value)
}

function Get-IntValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return 0 }
    if ($Object.PSObject.Properties.Name -contains $Name -and "$($Object.$Name)" -match '^-?\d+$') {
        return [int]$Object.$Name
    }
    return 0
}

function Get-FirstNumber {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return [int]$m.Groups[1].Value
        }
    }
    return $null
}

function Get-FirstText {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        $m = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($m.Success) {
            return $m.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Get-MetricNumber {
    param(
        [string]$Text,
        [string[]]$Names
    )

    $bt = [string][char]96
    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $escaped = [regex]::Escape($name)
        $decorated = "(?:\*\*)?${bt}?${escaped}${bt}?(?:\*\*)?"
        $separator = if ($name -match '[_-]') { '[:=]' } else { ':' }
        $patterns.Add("(?m)^\s*-?\s*${decorated}\s*${separator}\s*${bt}?([0-9]+)${bt}?\s*(?:/100)?\s*%?(?:\s+[^\r\n]*)?\s*$")
        $patterns.Add("(?m)^\s*\|\s*${decorated}\s*\|\s*(?:\*\*)?${bt}?([0-9]+)${bt}?(?:\*\*)?\s*(?:/100)?\s*%?\s*\|")
    }
    return Get-FirstNumber $Text $patterns.ToArray()
}

$root = Resolve-AbsolutePath $ReplayRoot
$roundPath = Join-Path $root 'ROUND_RESULT.md'

if ($ValidateOnly) {
    [ordered]@{
        status = 'VALID'
        replay_root = $root
        round_result = $roundPath
    } | ConvertTo-Json -Depth 6
    exit 0
}

$roundText = Read-TextIfExists $roundPath
$roundResultExists = -not [string]::IsNullOrWhiteSpace($roundText)
$blindCoverage = $null
$cappedCoverage = $null
$finalStatus = ''
$coverageSource = 'missing'
$sliceResults = Get-ExactSliceJsonObjects -Root $root -Prefix 'SLICE_RESULT'
$sliceVerifies = Get-ExactSliceJsonObjects -Root $root -Prefix 'SLICE_VERIFY'
$sliceResultCount = @($sliceResults).Count
$sliceVerifyCount = @($sliceVerifies).Count
$coverageCapFromLedger = $null

if ($sliceResultCount -gt 0 -or $sliceVerifyCount -gt 0) {
    $sumBlind = 0
    foreach ($result in $sliceResults) {
        $sumBlind += Get-IntValue $result 'coverage_delta'
    }

    $sumAdjusted = 0
    $allGapFlags = New-Object System.Collections.Generic.List[string]
    foreach ($verify in $sliceVerifies) {
        $sumAdjusted += Get-IntValue $verify 'adjusted_coverage_delta'
        foreach ($flag in Get-StringArray $verify.gap_flags) {
            if (-not $allGapFlags.Contains($flag)) { $allGapFlags.Add($flag) | Out-Null }
        }
        foreach ($blocker in Get-StringArray $verify.authorization_blockers) {
            if (-not [string]::IsNullOrWhiteSpace($blocker) -and -not $allGapFlags.Contains($blocker)) {
                $allGapFlags.Add($blocker) | Out-Null
            }
        }
    }

    $familyLedger = Read-JsonIfExists (Join-Path $root 'REQUIREMENT_FAMILY_LEDGER.json')
    $routerCap = Read-JsonIfExists (Join-Path $root 'FAMILY_ROUTER_AND_CAP.json')
    $ledgerCap = 100
    if ($null -ne $routerCap -and $routerCap.PSObject.Properties.Name -contains 'coverage_cap_from_ledger' -and "$($routerCap.coverage_cap_from_ledger)" -match '^\d+$') {
        $ledgerCap = [int]$routerCap.coverage_cap_from_ledger
    } elseif ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'coverage_cap' -and "$($familyLedger.coverage_cap)" -match '^\d+$') {
        $ledgerCap = [int]$familyLedger.coverage_cap
    }
    $coverageCapFromLedger = $ledgerCap

    $verificationCapped = [Math]::Min($sumAdjusted, $ledgerCap)
    if ($verificationCapped -lt 0) { $verificationCapped = 0 }
    $blindFromSlices = [Math]::Min($sumBlind, 89)
    if ($blindFromSlices -lt 0) { $blindFromSlices = 0 }

    $requiredOpen = @()
    if ($null -ne $familyLedger -and $familyLedger.PSObject.Properties.Name -contains 'families') {
        $requiredOpen = @($familyLedger.families | Where-Object { [bool]$_.required -and @('OPEN', 'PARTIAL') -contains ([string]$_.status) })
    }
    $authorizedStops = @($sliceVerifies | Where-Object {
        ($_.PSObject.Properties.Name -contains 'authorized_for_next_slice' -and -not [bool]$_.authorized_for_next_slice) -or
        ($_.PSObject.Properties.Name -contains 'authorized_for_synthesis' -and -not [bool]$_.authorized_for_synthesis)
    })

    $blindCoverage = $blindFromSlices
    $cappedCoverage = $verificationCapped
    $finalStatus = if ($authorizedStops.Count -gt 0 -or $allGapFlags.Contains('no_progress_slice')) {
        'BLOCKED'
    } elseif ($verificationCapped -ge 90 -and $requiredOpen.Count -eq 0) {
        'PASS'
    } else {
        'PARTIAL'
    }
    $coverageSource = 'slice_artifacts'
} elseif ($roundResultExists) {
    $blindCoverage = Get-MetricNumber $roundText @('blind_self_assessed_coverage', 'blind coverage')
    $cappedCoverage = Get-MetricNumber $roundText @('verification_capped_coverage', 'verification-capped coverage', 'verification capped coverage')
    $finalStatus = Get-FirstText $roundText @(
        '(?m)^\s*-?\s*`?final_status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*`?final status`?\s*[:=]\s*`?([A-Z_]+)`?',
        '(?m)^\s*-?\s*status\s*[:=]\s*`?([A-Z_]+)`?'
    )
    $coverageSource = 'round_result'
}

[ordered]@{
    round_result_exists = $roundResultExists
    round_result = $roundPath
    coverage_source = $coverageSource
    slice_result_count = $sliceResultCount
    slice_verify_count = $sliceVerifyCount
    coverage_cap_from_ledger = $coverageCapFromLedger
    blind_self_assessed_coverage = if ($null -eq $blindCoverage) { 0 } else { [int]$blindCoverage }
    verification_capped_coverage = if ($null -eq $cappedCoverage) { 0 } else { [int]$cappedCoverage }
    final_status = $finalStatus
} | ConvertTo-Json -Depth 6
