$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

if ($content -notmatch [regex]::Escape('\bN\s*/\s*A\b')) {
    throw 'placeholderPattern must use bounded N/A matching.'
}
$placeholderLine = (($content -split "\r?\n") | Where-Object { $_ -match '\$placeholderPattern\s*=' } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($placeholderLine)) {
    throw 'placeholderPattern line not found.'
}
if ($placeholderLine -match [regex]::Escape('TBD|unknown|N/A|placeholder')) {
    throw 'phase0 placeholderPattern must not use the old unbounded placeholder alternation.'
}

$placeholderPattern = '(?i)(\bTBD\b|\bunknown\b|\bN\s*/\s*A\b|\bplaceholder\b)'

$entryWithPath = 'TAiClaimModuleConfig (baseline-existing entity at claim-domain/src/main/java/com/huize/claim/domain/ai/TAiClaimModuleConfig.java)'
if ($entryWithPath -match $placeholderPattern) {
    throw 'selected_real_entry path containing domain/ai must not be classified as N/A placeholder.'
}

if ('N/A' -notmatch $placeholderPattern) {
    throw 'literal N/A must still be classified as placeholder.'
}

if ($content -notmatch '\(\?<\!no\\s\)manual\\s\+oracle\\s\+verification\\s\+\(required\|needed\|pending\)') {
    throw 'manualOracleWaitPattern must only block explicit required/needed/pending manual oracle verification.'
}
if ($content -match '\|oracle verification\)') {
    throw 'manualOracleWaitPattern must not contain the old broad oracle verification token.'
}

$manualOracleWaitPattern = '(?is)(waiting for Oracle|(?<!no\s)manual\s+oracle\s+verification\s+(required|needed|pending)|awaiting\s+oracle\s+verification|wait(?:ing)?\s+for\s+oracle\s+verification)'

if ('No manual oracle verification required' -match $manualOracleWaitPattern) {
    throw 'negated oracle verification sentence must not be classified as manual oracle wait.'
}

if ('manual oracle verification required before implementation' -notmatch $manualOracleWaitPattern) {
    throw 'real manual oracle verification requirement must still be blocked.'
}

if ('waiting for Oracle' -notmatch $manualOracleWaitPattern) {
    throw 'real waiting-for-Oracle text must still be blocked.'
}

Write-Host 'Test-v413-Phase0FalseBlockerBoundaries: PASS'
