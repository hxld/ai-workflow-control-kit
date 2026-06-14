$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$tempRoot = Join-Path $env:TEMP ('replay-v260-phase0-test-{0}' -f ([guid]::NewGuid().ToString('N')))

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
}

function Test-HasIssue {
    param(
        [object]$VerifyResult,
        [string]$Pattern
    )
    return (@($VerifyResult.issues | Where-Object { $_ -like $Pattern }).Count -gt 0)
}

function New-MinimalPhase0Fixtures {
    param([string]$Root)
    Set-Content -LiteralPath (Join-Path $Root 'ROUND_CONTRACT.md') -Value '' -Encoding UTF8
    @{families=@(@{id='core_entry';required=$true})} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'FAMILY_CONTRACT.json') -Encoding UTF8
}

$passCount = 0

try {
    # =========================================================================
    # Test 1: EXPLORATION_REPORT has table column but no heading => FAIL
    # =========================================================================
    Write-Host 'Test 1: EXPLORATION_REPORT table column without heading => FAIL'
    $t1Root = Join-Path $tempRoot 'test1-table-only'
    New-Item -ItemType Directory -Force -Path $t1Root | Out-Null
    New-MinimalPhase0Fixtures -Root $t1Root

    @"
# Phase 0 Result

## Phase 0 Status: PROCEED

## Selected Real Entry

Primary Entry: SomeFacade.someMethod()

## First Executable Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
# Exploration Report

| Requirement Literal | Candidate Entries | Evidence |
|---|---|---|

## Source Boundary

Some content.

## Candidate Surface Map

Some content.

## Uncertainty Ledger

confirmed items.
"@ | Set-Content -LiteralPath (Join-Path $t1Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result1 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t1Root -Stage Phase0 2>&1
    $verify1 = $result1 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify1 '*exploration_missing:requirement literal inventory*') 'Table column only should FAIL for requirement literal inventory'
    Write-Host "  PASS (issues=$($verify1.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 2: EXPLORATION_REPORT has exact heading => PASS (no exploration_missing)
    # =========================================================================
    Write-Host 'Test 2: EXPLORATION_REPORT with exact heading => PASS'
    $t2Root = Join-Path $tempRoot 'test2-exact-heading'
    New-Item -ItemType Directory -Force -Path $t2Root | Out-Null
    New-MinimalPhase0Fixtures -Root $t2Root

    @"
# Phase 0 Result

## Phase 0 Status: PROCEED

## Selected Real Entry

Primary Entry: SomeFacade.someMethod()

## First Executable Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
# Exploration Report

## Source Boundary

Content here.

## Requirement Literal Inventory

- literal 1: field A
- literal 2: enum B

## Candidate Surface Map

core path.

## Uncertainty Ledger

confirmed items.
"@ | Set-Content -LiteralPath (Join-Path $t2Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result2 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t2Root -Stage Phase0 2>&1
    $verify2 = $result2 | ConvertFrom-Json
    Assert-True (-not (Test-HasIssue $verify2 '*exploration_missing*')) 'Exact headings should NOT have exploration_missing issues'
    Write-Host "  PASS (issues=$($verify2.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 3: selected_real_entry contains Chinese placeholder => FAIL
    # =========================================================================
    Write-Host 'Test 3: selected_real_entry = Chinese placeholder => selected_real_entry_placeholder'
    $t3Root = Join-Path $tempRoot 'test3-placeholder'
    New-Item -ItemType Directory -Force -Path $t3Root | Out-Null
    New-MinimalPhase0Fixtures -Root $t3Root

    $placeholder3 = [char]0x5F85 + ' Oracle ' + [char]0x5BF9 + [char]0x6BD4 + [char]0x786E + [char]0x8BA4
    @"
# Phase 0 Result

| **selected_real_entry** | $placeholder3 |

## Phase 0 Status: PROCEED

## First Executable Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
## Source Boundary
## Requirement Literal Inventory
Content
## Candidate Surface Map
Content
## Uncertainty Ledger
confirmed
"@ | Set-Content -LiteralPath (Join-Path $t3Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result3 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t3Root -Stage Phase0 2>&1
    $verify3 = $result3 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify3 '*selected_real_entry_placeholder*') 'Chinese placeholder must trigger selected_real_entry_placeholder'
    Write-Host "  PASS (issues=$($verify3.issues.Count))"
    $passCount++

    # =========================================================================
    # Test 4: selected_real_entry = TBD => FAIL
    # =========================================================================
    Write-Host 'Test 4: selected_real_entry = TBD => FAIL'
    $t4Root = Join-Path $tempRoot 'test4-tbd'
    New-Item -ItemType Directory -Force -Path $t4Root | Out-Null
    New-MinimalPhase0Fixtures -Root $t4Root

    @"
# Phase 0 Result

- selected_real_entry: TBD
- phase0_status: PROCEED

## First Executable Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
## Source Boundary
## Requirement Literal Inventory
Content
## Candidate Surface Map
Content
## Uncertainty Ledger
confirmed
"@ | Set-Content -LiteralPath (Join-Path $t4Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result4 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t4Root -Stage Phase0 2>&1
    $verify4 = $result4 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify4 '*selected_real_entry_placeholder*') 'TBD must trigger selected_real_entry_placeholder'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 5: selected_real_entry = real production entry => PASS
    # =========================================================================
    Write-Host 'Test 5: selected_real_entry = real entry => PASS'
    $t5Root = Join-Path $tempRoot 'test5-real-entry'
    New-Item -ItemType Directory -Force -Path $t5Root | Out-Null
    New-MinimalPhase0Fixtures -Root $t5Root

    @"
# Phase 0 Result

- selected_real_entry: ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)
- phase0_status: PROCEED

## First Executable Slice

S1 - Receive return ticket callback
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
## Source Boundary
## Requirement Literal Inventory
Content
## Candidate Surface Map
Content
## Uncertainty Ledger
confirmed
"@ | Set-Content -LiteralPath (Join-Path $t5Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result5 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t5Root -Stage Phase0 2>&1
    $verify5 = $result5 | ConvertFrom-Json
    Assert-True (-not (Test-HasIssue $verify5 '*selected_real_entry_placeholder*')) 'Real entry should NOT trigger placeholder'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Test 6: FAMILY_CONTRACT.json selected_real_entry = Chinese placeholder => FAIL
    # =========================================================================
    Write-Host 'Test 6: FAMILY_CONTRACT.json selected_real_entry placeholder => family_contract_selected_real_entry_missing'
    $t6Root = Join-Path $tempRoot 'test6-family-placeholder'
    New-Item -ItemType Directory -Force -Path $t6Root | Out-Null

    Set-Content -LiteralPath (Join-Path $t6Root 'ROUND_CONTRACT.md') -Value '' -Encoding UTF8
    $placeholder6 = [char]0x5F85 + [char]0x786E + [char]0x8BA4
    @{
        selected_real_entry = $placeholder6
        first_executable_slice = 'S1'
        families = @(@{id='core_entry';required=$true})
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $t6Root 'FAMILY_CONTRACT.json') -Encoding UTF8

    @"
# Phase 0 Result

- selected_real_entry: ExampleReceiveFacade.receiveExampleTicket(ExampleTicketParam)
- phase0_status: PROCEED

## First Executable Slice

S1 - Core path
"@ | Set-Content -LiteralPath (Join-Path $t6Root 'PHASE0_RESULT.md') -Encoding UTF8

    @"
## Source Boundary
## Requirement Literal Inventory
Content
## Candidate Surface Map
Content
## Uncertainty Ledger
confirmed
"@ | Set-Content -LiteralPath (Join-Path $t6Root 'EXPLORATION_REPORT.md') -Encoding UTF8

    $result6 = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot 'Verify-PlanContract.ps1') -ReplayRoot $t6Root -Stage Phase0 2>&1
    $verify6 = $result6 | ConvertFrom-Json
    Assert-True (Test-HasIssue $verify6 '*family_contract_selected_real_entry_missing*') 'FAMILY_CONTRACT placeholder must trigger family_contract_selected_real_entry_missing'
    Write-Host "  PASS"
    $passCount++

    # =========================================================================
    # Summary
    # =========================================================================
    Write-Host ''
    Write-Host "Test-v260-Phase0GateStrength: $passCount passed, all passed"

} catch {
    Write-Host "UNEXPECTED ERROR: $_"
    Write-Host "Test-v260-Phase0GateStrength: $passCount passed, 1 failed"
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
