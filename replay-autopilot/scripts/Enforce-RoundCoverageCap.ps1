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

$text = Get-Content -LiteralPath $RoundResultPath -Raw -Encoding UTF8

$blindResult = Replace-FirstMetricAboveCap `
    -Text $text `
    -Pattern ([regex]'(?m)(blind_self_assessed_coverage\s*[:=]\s*`?)(\d+)(`?)') `
    -Cap $ledgerCap
$text = [string]$blindResult.text

$cappedResult = Replace-FirstMetricAboveCap `
    -Text $text `
    -Pattern ([regex]'(?m)(verification_capped_coverage\s*[:=]\s*`?)(\d+)(`?)') `
    -Cap $ledgerCap
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

if ($text -notmatch '(?m)^## Runner Cap Enforcement\s*$') {
    $originalBlindText = if ($null -ne $blindResult.original) { [string]$blindResult.original } else { 'N/A' }
    $originalCappedText = if ($null -ne $cappedResult.original) { [string]$cappedResult.original } else { 'N/A' }
    $signalsText = if ($authorizationSignals.Count -gt 0) { $authorizationSignals -join ', ' } else { 'none' }
    $enforcementLines = @(
        '',
        '## Runner Cap Enforcement',
        "- family_router_and_cap: $RouterCapPath",
        "- coverage_cap_from_ledger: $ledgerCap",
        "- original_blind_self_assessed_coverage: $originalBlindText",
        "- original_verification_capped_coverage: $originalCappedText",
        "- final_pass_allowed_by_ledger: $finalPassAllowed",
        "- non_authorizing_signals: $signalsText",
        '- enforcement: `blind_self_assessed_coverage`, `verification_capped_coverage`, and `final_status` must not exceed ledger cap/final-pass authorization'
    ) -join "`n"
    $text = $text.TrimEnd() + $enforcementLines
}

Set-Content -LiteralPath $RoundResultPath -Value $text -Encoding UTF8
