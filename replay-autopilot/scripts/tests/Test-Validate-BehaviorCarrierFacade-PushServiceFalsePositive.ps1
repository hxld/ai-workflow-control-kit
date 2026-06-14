param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '..\Validate-BehaviorCarrierFacade.ps1')
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0

function Assert-Block {
    param([string]$Name, [string]$ReplayRoot, [string[]]$ExpectedIssueSubstrings)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -ReplayRoot $ReplayRoot -Mode DryRun 2>&1
    $json = $out | ConvertFrom-Json
    if ($json.status -ne 'BLOCKED') {
        Write-Host "FAIL: $Name - expected BLOCKED, got $($json.status)" -ForegroundColor Red
        $script:fail++
        return
    }
    foreach ($expected in $ExpectedIssueSubstrings) {
        $found = $false
        foreach ($issue in $json.issues) {
            if ($issue.issue -like "*$expected*") {
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Host "FAIL: $Name - expected issue containing '$expected', got: $($json.issues | ForEach-Object { $_.issue } | Join-String ', ')" -ForegroundColor Red
            $script:fail++
            return
        }
    }
    Write-Host "PASS: $Name" -ForegroundColor Green
    $script:pass++
}

function Assert-Allow {
    param([string]$Name, [string]$ReplayRoot)
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -ReplayRoot $ReplayRoot -Mode DryRun 2>&1
    $json = $out | ConvertFrom-Json
    if ($json.status -ne 'ALLOW') {
        Write-Host "FAIL: $Name - expected ALLOW, got $($json.status)" -ForegroundColor Red
        Write-Host "  Issues: $($json.issues | ForEach-Object { $_.issue } | Join-String ', ')" -ForegroundColor Yellow
        $script:fail++
        return
    }
    Write-Host "PASS: $Name" -ForegroundColor Green
    $script:pass++
}

$renbaoRoot = 'D:\opt\replay-evidence\renbao-tuipiao\claim-codex-replay-v256-cross-20260525-220853-r01'
$xiebaoRoot = 'D:\opt\replay-evidence\xiebao\claim-codex-replay-v256-cross-20260525-223713-r01'
$fixtureAllow = 'D:\opt\replay-evidence\_test-fixtures\facade-class-and-method-sig-ALLOW'
$fixtureNoSig = 'D:\opt\replay-evidence\_test-fixtures\facade-class-no-method-sig-BLOCKED'
$fixturePushServiceOnly = 'D:\opt\replay-evidence\_test-fixtures\push-service-only-BLOCKED'
$fixtureOppFacadeNameWithSelectedSig = 'D:\opt\replay-evidence\_test-fixtures\opposite-facade-name-with-selected-sig-BLOCKED'
$fixtureOppFacadeNameWithUnrelatedSig = 'D:\opt\replay-evidence\_test-fixtures\opposite-facade-name-with-unrelated-sig-BLOCKED'
$fixtureOppFacadeNoteCellUnbound = 'D:\opt\replay-evidence\_test-fixtures\opposite-facade-note-cell-unbound-BLOCKED'

# Test 1: renbao-tuipiao v256 must be BLOCKED for facade_direction_facade_class_missing
#         (PushService must NOT satisfy PushFacade evidence)
Assert-Block -Name 'renbao-tuipiao v256: PushService NOT satisfying PushFacade (facade_direction_facade_class_missing)' `
    -ReplayRoot $renbaoRoot `
    -ExpectedIssueSubstrings @('facade_direction_facade_class_missing')

# Test 2: xiebao v256 must remain BLOCKED for data-only carrier
Assert-Block -Name 'xiebao v256: data-only carrier remains BLOCKED' `
    -ReplayRoot $xiebaoRoot `
    -ExpectedIssueSubstrings @('data_only_carrier')

# Test 3: Verify the renbao evidence text explicitly mentions PushService but NOT PushFacade in planning docs
$explorationReport = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $renbaoRoot 'EXPLORATION_REPORT.md')
$hasPushService = $explorationReport -match '(?i)PushService'
$hasPushFacade = $explorationReport -match '(?i)InsureCompanyPushFacade'
if ($hasPushService -and -not $hasPushFacade) {
    Write-Host "PASS: renbao exploration has PushService but NOT InsureCompanyPushFacade - confirms the false positive scenario" -ForegroundColor Green
    $script:pass++
} else {
    Write-Host "FAIL: renbao exploration scenario changed - hasPushService=$hasPushService hasPushFacade=$hasPushFacade" -ForegroundColor Red
    $script:fail++
}

# Test 4: Verify renbao surface carrier scan DOES contain InsureCompanyPushFacade (proving it exists but was ignored)
$scan = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $renbaoRoot 'SURFACE_CARRIER_SCAN.md')
$scanHasPushFacade = $scan -match '(?i)InsureCompanyPushFacade'
if ($scanHasPushFacade) {
    Write-Host "PASS: renbao SURFACE_CARRIER_SCAN.md contains InsureCompanyPushFacade - proving the Facade exists but was ignored in planning docs" -ForegroundColor Green
    $script:pass++
} else {
    Write-Host "FAIL: renbao SURFACE_CARRIER_SCAN.md no longer contains InsureCompanyPushFacade" -ForegroundColor Red
    $script:fail++
}

# Test 5: Synthetic fixture - Facade class + method signature evidence => ALLOW (not blocked)
Assert-Allow -Name 'fixture: InsureCompanyPushFacade + method signatures => ALLOW' `
    -ReplayRoot $fixtureAllow

# Test 6: Synthetic fixture - Facade class but NO method signature => BLOCKED with facade_direction_method_signature_missing
Assert-Block -Name 'fixture: InsureCompanyPushFacade without method signatures => BLOCKED (facade_direction_method_signature_missing)' `
    -ReplayRoot $fixtureNoSig `
    -ExpectedIssueSubstrings @('facade_direction_method_signature_missing')

# Test 7: Synthetic fixture - PushService only => BLOCKED with facade_direction_facade_class_missing
Assert-Block -Name 'fixture: PushService only => BLOCKED (facade_direction_facade_class_missing)' `
    -ReplayRoot $fixturePushServiceOnly `
    -ExpectedIssueSubstrings @('facade_direction_facade_class_missing')

# Test 8: Regression - opposite Facade NAME mentioned but method signature belongs to SELECTED carrier
#         This is the P1 false-ALLOW scenario: InsureCompanyPushFacade is mentioned in passing,
#         but the only method signature (ResultModel receiveReturnTicket(...)) is from the selected Receive facade.
#         Expected: BLOCKED with facade_direction_method_signature_missing
Assert-Block -Name 'fixture: opposite Facade name + selected-carrier sig only => BLOCKED (facade_direction_method_signature_missing)' `
    -ReplayRoot $fixtureOppFacadeNameWithSelectedSig `
    -ExpectedIssueSubstrings @('facade_direction_method_signature_missing')

# Test 9: v266 regression - opposite Facade name + unrelated non-direction method on same prose line
#         InsureCompanyPushFacade is mentioned in the same line as ResultModel buildPayload(ReturnTicketParam param)
#         but there is no class-qualified signature, no Markdown table row binding the method to the Facade.
#         Same-line co-occurrence in prose is NOT sufficient evidence.
#         Expected: BLOCKED with facade_direction_method_signature_missing
Assert-Block -Name 'fixture: opposite Facade name + unrelated non-direction sig in prose => BLOCKED (facade_direction_method_signature_missing)' `
    -ReplayRoot $fixtureOppFacadeNameWithUnrelatedSig `
    -ExpectedIssueSubstrings @('facade_direction_method_signature_missing')

# Test 10: v267 regression - opposite Facade name + unrelated method in a single unbound Markdown note cell
#          The note cell is a valid Markdown table row (starts/ends with |) but contains both Facade name
#          and method signature in the SAME cell with no structural binding.
#          Expected: BLOCKED with facade_direction_method_signature_missing
Assert-Block -Name 'fixture: opposite Facade + method sig in single unbound note cell => BLOCKED (facade_direction_method_signature_missing)' `
    -ReplayRoot $fixtureOppFacadeNoteCellUnbound `
    -ExpectedIssueSubstrings @('facade_direction_method_signature_missing')

Write-Host "`n=== Results: $pass passed, $fail failed ===" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
