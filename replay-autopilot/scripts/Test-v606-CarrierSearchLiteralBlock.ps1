# v606: Verify YAML | literal block carrier_search parsing
# Tests that YAML | folded block format is correctly parsed and validated
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

if ($ValidateOnly) {
    [ordered]@{ status = 'VALID' } | ConvertTo-Json -Depth 4
    exit 0
}

$verifier = Join-Path $PSScriptRoot 'Verify-PlanContract.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("replay-v605-folded-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$assertions = 0
try {
    # === Test 1: | literal block with enough queries should PASS ===
    $validRoot = Join-Path $tmp 'valid'
    $validWorktree = Join-Path $validRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $validWorktree | Out-Null
    Write-Utf8 (Join-Path $validRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: |
  **Query 1 — Existing flow carriers:**
  - `rg "class GenericFlowService" --type java`
  - `rg "GenericFlowCoordinator" --type java`

  **Query 2 — Feature keyword "AutoFlow":**
  - Glob: `*AutoFlow*.*`, `*autoFlow*.*`

  **Query 3 — Service/Facade/Processor carriers:**
  - Glob: `*Service.java`, `*Facade.java`
  - Grep: `class GenericApplyService`
- existing_production_carriers: GenericTaskProcessor; GenericModuleFacade
- selected_carrier_from_search: NEW_SERVICE_GenericAutoFlowService
- new_service_proposed: true
- new_service_justification: |
  No existing carrier combines all required stateful steps.
  The change requires separate orchestration.
- first_slice: S1 - Source-chain rebuild + auto-flow trigger
- first_red_test: testGenericAutoFlow_WhenConditionsMet
- selected_strategy: core-transaction-first
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $validRoot -Stage Plan -Worktree $validWorktree -ErrorAction SilentlyContinue | Out-Null
    $validVerify = Get-Content -LiteralPath (Join-Path $validRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($validVerify.issues) -notcontains 'carrier_search_queries_too_few') "Folded block with >=3 queries should be accepted, issues=$(@($validVerify.issues) -join ';')"
    $assertions++
    Assert-True (@($validVerify.issues) -notcontains 'carrier_search_new_service_unjustified') "Literal block justification with valid no-existing-carrier evidence should be accepted"
    $assertions++

    # === Test 2: | folded block new_service_justification should work with > continuation pattern too ===
    $foldedJustRoot = Join-Path $tmp 'folded-just'
    $foldedJustWorktree = Join-Path $foldedJustRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $foldedJustWorktree | Out-Null
    Write-Utf8 (Join-Path $foldedJustRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "AutoFlow" app-core; rg "FlowService" app-core; rg "TaskProcessor" app-server
- existing_production_carriers: GenericTaskProcessor; GenericApplyService; GenericTaskService
- selected_carrier_from_search: NEW_SERVICE_GenericAutoFlowService
- new_service_created: true
- new_service_justification: |
  Exhaustive search found no existing carrier handles the complete workflow.
  The change requires separate orchestration.
- first_slice: S1 auto claim flow orchestration
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $foldedJustRoot -Stage Plan -Worktree $foldedJustWorktree -ErrorAction SilentlyContinue | Out-Null
    $foldedJustVerify = Get-Content -LiteralPath (Join-Path $foldedJustRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($foldedJustVerify.issues) -notcontains 'carrier_search_new_service_unjustified') "Folded | block new_service_justification should be accepted with valid keywords, issues=$(@($foldedJustVerify.issues) -join ';')"
    $assertions++

    # === Test 3: weak justification in | folded block should still be rejected ===
    $weakRoot = Join-Path $tmp 'weak'
    $weakWorktree = Join-Path $weakRoot 'worktree'
    New-Item -ItemType Directory -Force -Path $weakWorktree | Out-Null
    Write-Utf8 (Join-Path $weakRoot 'PLAN_RESULT.md') @'
# Plan Result

- plan_status: PROCEED
- carrier_search: performed
- carrier_search_queries: rg "AutoFlow" app-core; rg "FlowService" app-core; rg "TaskProcessor" app-server
- existing_production_carriers: GenericTaskProcessor; GenericApplyService; GenericTaskService
- selected_carrier_from_search: NEW_SERVICE_GenericAutoFlowService
- new_service_created: true
- new_service_justification: |
  Prefer a cleaner service name.
  Keep responsibilities organized.
- first_slice: S1 auto claim flow orchestration
'@

    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifier -ReplayRoot $weakRoot -Stage Plan -Worktree $weakWorktree -ErrorAction SilentlyContinue | Out-Null
    $weakVerify = Get-Content -LiteralPath (Join-Path $weakRoot 'PLAN_CONTRACT_VERIFY.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($weakVerify.issues) -contains 'carrier_search_new_service_unjustified') "Weak folded | justification should still be rejected"
    $assertions++

    Write-Host "PASS: v606 literal block parsing — $assertions assertions"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

[ordered]@{
    status = 'PASS'
    assertions = $assertions
    cases = @(
        'folded_block_carrier_search_queries_accepted',
        'folded_block_new_service_justification_accepted',
        'folded_block_new_service_justification_weak_rejected'
    )
} | ConvertTo-Json -Depth 5

