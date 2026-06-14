$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v253-format-fix-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: Verify-PlanContract Phase0 parses "## Decision: PROCEED"
    # =========================================================================
    Write-Host 'Test 1: Verify-PlanContract Phase0 - ## Decision: PROCEED (no phase0_status issue)'
    $t1Root = Join-Path $tempRoot 'test1-decision-proceed'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null

    @"
# Phase 0 Result - renbao-tuipiao-v253-cross-r01

## Decision: PROCEED

## Selected Real Entry

Primary Entry: InsureCompanyPushFacade.returnTicket(ReturnTicketParam)

## First Executable Slice

S1 - Receive return ticket callback

## First Slice Type

Type: core_path
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'PHASE0_RESULT.md') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $t1Root 'EXPLORATION_REPORT.md') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $t1Root 'ROUND_CONTRACT.md') -Value '' -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t1Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1Root -Stage Phase0 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    $hasPhase0StatusIssue = @($verify1.issues | Where-Object { $_ -like '*phase0_status*' }).Count -gt 0
    Assert-True (-not $hasPhase0StatusIssue) 'Verify-PlanContract should NOT report phase0_status issue for ## Decision: PROCEED'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 2: Verify-PlanContract Phase0 parses "## Decision: PROCEED" with trailing text
    # =========================================================================
    Write-Host 'Test 2: Verify-PlanContract Phase0 - ## Decision: PROCEED with trailing text'
    $t2Root = Join-Path $tempRoot 'test2-decision-trailing'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null

    @"
# Phase 0 Result

## Decision: PROCEED

Phase 0 analysis complete.

## Selected Real Entry

Primary Entry: InsureCompanyPushFacade.returnTicket(ReturnTicketParam)

## First Executable Slice

S1 - Core path

## First Slice Type

Type: core_path
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'PHASE0_RESULT.md') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $t2Root 'EXPLORATION_REPORT.md') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $t2Root 'ROUND_CONTRACT.md') -Value '' -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t2Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2Root -Stage Phase0 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    $hasPhase0StatusIssue = @($verify2.issues | Where-Object { $_ -like '*phase0_status*' }).Count -gt 0
    Assert-True (-not $hasPhase0StatusIssue) 'Verify-PlanContract should NOT report phase0_status issue for ## Decision: PROCEED with trailing text'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 3: Verify-PlanContract Plan accepts "Selected Real Entries" (plural)
    # Uses real fixture from xiebao v253 which had this format
    # =========================================================================
    Write-Host 'Test 3: Verify-PlanContract Plan - Selected Real Entries plural (real fixture)'
    $xiebaoRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\xiebao\claim-codex-replay-v253-cross-20260521-222210-r01"
    if (Test-Path -LiteralPath $xiebaoRoot) {
        $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $xiebaoRoot -Stage Plan 2>&1
        $verify3 = $result3 | ConvertFrom-Json
        $hasSelRealEntry = @($verify3.issues | Where-Object { $_ -like '*implementation_contract_missing:selected real entry*' }).Count -gt 0
        Assert-True (-not $hasSelRealEntry) 'xiebao Plan should NOT report implementation_contract_missing:selected real entry (has Selected Real Entries heading)'
        Write-Host "  PASS (status=$($verify3.verification_status), issues=$($verify3.issues.Count))"
        $passCount++
    } else {
        Write-Host '  SKIP: xiebao fixture not found'
    }

    # =========================================================================
    # Test 4: Parse-ReplayReport parses "Oracle Coverage (Post-Hoc)" format
    # Uses real fixture from skip-task v253 which had 100% coverage
    # =========================================================================
    Write-Host 'Test 4: Parse-ReplayReport - Oracle Coverage (Post-Hoc) real fixture'
    $skipTaskRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\skip-task-transform-case\claim-codex-replay-v253-cross-20260521-213505-r01"
    if (Test-Path -LiteralPath $skipTaskRoot) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $skipTaskRoot | Out-Null
        $summary4 = Get-Content -LiteralPath (Join-Path $skipTaskRoot 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
        # skip-task v253 FINAL_REPLAY_REPORT has "Oracle Coverage (Post-Hoc) | 100%"
        Assert-True ($summary4 -match '(?m)^- oracle_adjusted_coverage:\s*(\d+)') 'Parse-ReplayReport should find oracle_adjusted_coverage'
        $coverage = [int]$matches[1]
        Assert-True ($coverage -gt 0) "oracle_adjusted_coverage should be > 0, got $coverage"
        Write-Host "  PASS (coverage=$coverage)"
        $passCount++
    } else {
        Write-Host '  SKIP: skip-task fixture not found'
    }

    # =========================================================================
    # Test 5: Parse-ReplayReport parses "## Decision: PROCEED ✅" phase0_status
    # =========================================================================
    Write-Host 'Test 5: Parse-ReplayReport - ## Decision: PROCEED phase0_status'
    $t5Root = Join-Path $tempRoot 'test5-decision-parse'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null

    @"
# Phase 0 Result - renbao-tuipiao-v253-cross-r01

## Decision: PROCEED

Phase 0 analysis complete.
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'PHASE0_RESULT.md') -Encoding UTF8

    Set-Content -LiteralPath (Join-Path $t5Root 'ROUND_RESULT.md') -Value '' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $t5Root 'FINAL_REPLAY_REPORT.md') -Value '' -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Parse-ReplayReport.ps1') -ReplayRoot $t5Root | Out-Null
    $summary5 = Get-Content -LiteralPath (Join-Path $t5Root 'AUTOPILOT_SUMMARY.md') -Raw -Encoding UTF8
    Assert-True ($summary5 -match '(?m)^- phase0_status: PROCEED') 'Parse-ReplayReport should parse ## Decision: PROCEED as phase0_status=PROCEED'
    Write-Host '  PASS'
    $passCount++

    # =========================================================================
    # Test 6: Verify-PlanContract Phase0 on real renbao-tuipiao fixture
    # =========================================================================
    Write-Host 'Test 6: Verify-PlanContract Phase0 - real renbao-tuipiao fixture (## Decision: PROCEED)'
    $renbaoRoot = "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\renbao-tuipiao\claim-codex-replay-v253-cross-20260521-222210-r01"
    if (Test-Path -LiteralPath $renbaoRoot) {
        $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $renbaoRoot -Stage Phase0 2>&1
        $verify6 = $result6 | ConvertFrom-Json
        $hasPhase0StatusIssue = @($verify6.issues | Where-Object { $_ -like '*phase0_status*' }).Count -gt 0
        Assert-True (-not $hasPhase0StatusIssue) 'renbao-tuipiao Phase0 should NOT report phase0_status issue (has ## Decision: PROCEED)'
        Write-Host "  PASS (status=$($verify6.verification_status))"
        $passCount++
    } else {
        Write-Host '  SKIP: renbao-tuipiao fixture not found'
    }

    # =========================================================================
    # Test 7: ValidateOnly smoke test
    # =========================================================================
    Write-Host 'Test 7: ValidateOnly for real fixtures'
    $fixtureRoots = @(
        "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\policy-num-extension\claim-codex-replay-v252-cross-20260521-213505-r01",
        "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\skip-task-transform-case\claim-codex-replay-v253-cross-20260521-213505-r01",
        "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\xiebao\claim-codex-replay-v253-cross-20260521-222210-r01",
        "$env:AI_WORKFLOW_REPLAY_EVIDENCE_ROOT\renbao-tuipiao\claim-codex-replay-v253-cross-20260521-222210-r01"
    )
    foreach ($fixture in $fixtureRoots) {
        if (Test-Path -LiteralPath $fixture) {
            $name = Split-Path -Leaf $fixture
            $p0v = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $fixture -Stage Phase0 2>&1
            $p0j = $p0v | ConvertFrom-Json
            $hasPhase0StatusIssue = @($p0j.issues | Where-Object { $_ -like '*phase0_status*' }).Count -gt 0
            Assert-True (-not $hasPhase0StatusIssue) "Phase0 for $name should NOT have phase0_status issue"
            Write-Host "  Phase0 OK: $name"
            $passCount++
        } else {
            Write-Host "  SKIP: $fixture"
        }
    }

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v253-FormatFixes: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v253-FormatFixes: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
