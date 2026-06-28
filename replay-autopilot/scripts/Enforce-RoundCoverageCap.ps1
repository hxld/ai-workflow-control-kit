param(
    [Parameter(Mandatory = $true)]
    [string]$RoundResultPath,

    [Parameter(Mandatory = $true)]
    [string]$RouterCapPath,

    [string]$ReplayRoot = ''
)

$ErrorActionPreference = 'Stop'

function Read-JsonObject {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Get-VerifierAdjustedCoverage {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $total = 0
    $count = 0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^SLICE_VERIFY_\d+\.json$' } |
        Sort-Object Name) {
        try {
            $verify = Read-JsonObject -Path $file.FullName
        } catch {
            continue
        }
        $total += Get-IntValue -Object $verify -Name 'adjusted_coverage_delta'
        $count += 1
    }

    if ($count -eq 0) { return $null }
    if ($total -lt 0) { $total = 0 }
    return $total
}

function Replace-FirstMetricAboveCap {
    param(
        [string]$Text,
        [regex]$Pattern,
        [int]$Cap
    )

    $match = $Pattern.Match($Text)
    if (-not $match.Success) {
        return [ordered]@{ text = $Text; original = $null; changed = $false }
    }

    $original = [int]$match.Groups[2].Value
    if ($original -le $Cap) {
        return [ordered]@{ text = $Text; original = $original; changed = $false }
    }

    $newText = $Pattern.Replace(
        $Text,
        { param($m) $m.Groups[1].Value + $Cap + $m.Groups[3].Value },
        1
    )
    return [ordered]@{ text = $newText; original = $original; changed = $true }
}

function Get-AuthorizationSignals {
    param([string]$Root)

    $signals = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return @($signals)
    }

    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Filter 'SLICE_VERIFY_*.json' -ErrorAction SilentlyContinue) {
        try {
            $verify = Read-JsonObject -Path $file.FullName
        } catch {
            continue
        }

        if ($null -ne $verify.authorized_for_next_slice -and -not [bool]$verify.authorized_for_next_slice) {
            $signals.Add("authorized_for_next_slice=false:$($file.Name)") | Out-Null
        }
        if ($null -ne $verify.authorized_for_synthesis -and -not [bool]$verify.authorized_for_synthesis) {
            $signals.Add("authorized_for_synthesis=false:$($file.Name)") | Out-Null
        }
        foreach ($blocker in Get-StringArray $verify.authorization_blockers) {
            if (-not [string]::IsNullOrWhiteSpace($blocker)) {
                $signals.Add("blocker:$blocker") | Out-Null
            }
        }
    }

    return @($signals | Select-Object -Unique)
}

if (-not (Test-Path -LiteralPath $RoundResultPath) -or -not (Test-Path -LiteralPath $RouterCapPath)) {
    return
}

try {
    $routerCap = Read-JsonObject -Path $RouterCapPath
} catch {
    return
}

if ($null -eq $routerCap.coverage_cap_from_ledger -or "$($routerCap.coverage_cap_from_ledger)" -notmatch '^\d+$') {
    return
}

$ledgerCap = [int]$routerCap.coverage_cap_from_ledger
$finalPassAllowed = if ($null -ne $routerCap.final_pass_allowed) { [bool]$routerCap.final_pass_allowed } else { $true }
$rootForSignals = if (-not [string]::IsNullOrWhiteSpace($ReplayRoot)) { $ReplayRoot } else { Split-Path -Parent $RoundResultPath }
$authorizationSignals = @(Get-AuthorizationSignals -Root $rootForSignals)
$hasNonAuthorizingEvidence = (-not $finalPassAllowed) -or $authorizationSignals.Count -gt 0
$verifierAdjustedCoverage = Get-VerifierAdjustedCoverage -Root $rootForSignals
$verificationCap = $ledgerCap
if ($null -ne $verifierAdjustedCoverage) {
    $verificationCap = [Math]::Min([int]$verifierAdjustedCoverage, $ledgerCap)
}

$text = Get-Content -LiteralPath $RoundResultPath -Raw -Encoding UTF8

$blindResult = Replace-FirstMetricAboveCap `
    -Text $text `
    -Pattern ([regex]'(?m)(blind_self_assessed_coverage\s*[:=]\s*`?)(\d+)(`?)') `
    -Cap $ledgerCap
$text = [string]$blindResult.text

$cappedResult = Replace-FirstMetricAboveCap `
    -Text $text `
    -Pattern ([regex]'(?m)(verification_capped_coverage\s*[:=]\s*`?)(\d+)(`?)') `
    -Cap $verificationCap
$text = [string]$cappedResult.text

$coverageCapResult = Replace-FirstMetricAboveCap `
    -Text $text `
    -Pattern ([regex]'(?m)(coverage_cap\s*[:=]\s*`?)(\d+)(`?)') `
    -Cap $ledgerCap
$text = [string]$coverageCapResult.text

if (-not $finalPassAllowed -or $hasNonAuthorizingEvidence) {
    $statusPattern = [regex]'(?m)(final[_ ]status\s*[:=]\s*`?)(PASS|DONE)(`?)'
    $text = $statusPattern.Replace($text, { param($m) $m.Groups[1].Value + 'BLOCKED' + $m.Groups[3].Value }, 1)
}

$originalBlindText = if ($null -ne $blindResult.original) { [string]$blindResult.original } else { 'N/A' }
$originalCappedText = if ($null -ne $cappedResult.original) { [string]$cappedResult.original } else { 'N/A' }
$signalsText = if ($authorizationSignals.Count -gt 0) { $authorizationSignals -join ', ' } else { 'none' }
$effectiveFinalStatus = if ($hasNonAuthorizingEvidence) { 'BLOCKED' } else { 'PASS' }
$enforcementLines = @(
    '## Runner Cap Enforcement',
    "- family_router_and_cap: $RouterCapPath",
    "- coverage_cap_from_ledger: $ledgerCap",
    "- verifier_adjusted_coverage: $(if ($null -ne $verifierAdjustedCoverage) { [string]$verifierAdjustedCoverage } else { 'N/A' })",
    "- blind_self_assessed_coverage: $ledgerCap",
    "- verification_capped_coverage: $verificationCap",
    "- final_status: $effectiveFinalStatus",
    "- original_blind_self_assessed_coverage: $originalBlindText",
    "- original_verification_capped_coverage: $originalCappedText",
    "- final_pass_allowed_by_ledger: $finalPassAllowed",
    "- non_authorizing_signals: $signalsText",
    "- authorization_enforced: $hasNonAuthorizingEvidence",
    '- enforcement: `blind_self_assessed_coverage` must not exceed ledger cap; `verification_capped_coverage` must not exceed verifier-adjusted coverage or ledger cap; `final_status` must not exceed final-pass authorization'
) -join "`n"

$enforcementPattern = [regex]'(?ms)^## Runner Cap Enforcement\s*.*?(?=^## |\z)'
if ($enforcementPattern.IsMatch($text)) {
    $text = $enforcementPattern.Replace($text, ($enforcementLines + "`n"), 1).TrimEnd()
} else {
    $text = $text.TrimEnd() + "`n`n" + $enforcementLines
}

Set-Content -LiteralPath $RoundResultPath -Value $text -Encoding UTF8
